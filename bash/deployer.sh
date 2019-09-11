#!/bin/bash -v
# Make cloud-init output log readable by root.

chmod 600 /var/log/cloud-init-output.log

yum update -y aws-cfn-bootstrap
yum install -y jq

# Set hostname
hostnamectl set-hostname $hostname
printf '%s\t%s\n' `hostname -I` $hostname >> /etc/hosts
hostname $hostname

#sleep 60

sed -i "s/pass4SymmKey.*/pass4SymmKey = $SPLUNK_GENERAL_SECRET/" $SPLUNK_HOME/etc/system/local/server.conf
sed -i "s/serverName.*/serverName = $hostname/" $SPLUNK_HOME/etc/system/local/server.conf
sed -i "s/host.*/host = $hostname/" $SPLUNK_HOME/etc/system/local/inputs.conf

service splunk restart
# sleep 15


cat >>$SPLUNK_HOME/etc/system/local/outputs.conf <<end
# Turn off indexing on the search head
[indexAndForward]
index = false

[indexer_discovery:cluster_master]
pass4SymmKey = $SPLUNK_INDEX_DISCOVERY_SECRET

master_uri = https://$ClusterMasterPrivateIp:8089

[tcpout]
defaultGroup = indexers

[tcpout:indexers]
indexerDiscovery = cluster_master
useACK = true

end

# Configure somd SHC parameters
cat >>$SPLUNK_HOME/etc/system/local/server.conf <<end
[shclustering]
pass4SymmKey = $SPLUNK_CLUSTER_SECRET

shcluster_label = $SEARCH_CLUSTER_LABEL
end

chown -R $SPLUNK_SYSTEM_USER:$SPLUNK_SYSTEM_USER $SPLUNK_HOME/etc/system/local

sudo -u $SPLUNK_SYSTEM_USER $SPLUNK_HOME/bin/splunk login -auth $SPLUNK_ADMIN_USER:$SPLUNK_ADMIN_PASSWORD


sudo -u $SPLUNK_SYSTEM_USER $SPLUNK_HOME/bin/splunk apply shcluster-bundle \
	-action stage \
	--answer-yes

sudo -u $SPLUNK_SYSTEM_USER $SPLUNK_HOME/bin/splunk edit cluster-config \
	-mode searchhead \
	-site site0 \
	-master_uri https://$ClusterMasterPrivateIp:8089 \
	-secret $SPLUNK_CLUSTER_SECRET

service splunk restart
#sleep 15
