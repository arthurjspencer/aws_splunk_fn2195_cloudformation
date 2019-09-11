#!/bin/bash -v
# Make cloud-init output log readable by root.

chmod 600 /var/log/cloud-init-output.log

yum update -y aws-cfn-bootstrap
yum install -y jq

# Set hostname
hostnamectl set-hostname $hostname
printf '%s\t%s\n' `hostname -I` $hostname >> /etc/hosts
hostname $hostname

sleep 60

mkfs -t xfs /dev/sdc
mount -a
mkdir /data/

chown -R splunk:splunk /data

sed -i "s/pass4SymmKey.*/pass4SymmKey = $SplunkGeneralSecret/" $SPLUNK_HOME/etc/system/local/server.conf
sed -i "s/serverName.*/serverName = $hostname/" $SPLUNK_HOME/etc/system/local/server.conf
sed -i "s/host.*/host = $hostname/" $SPLUNK_HOME/etc/system/local/inputs.conf

service splunk restart

chown -R $SPLUNK_SYSTEM_USER:$SPLUNK_SYSTEM_USER $SPLUNK_HOME/etc/system/local

sudo -u $SPLUNK_SYSTEM_USER $SPLUNK_HOME/bin/splunk login -auth $SPLUNK_ADMIN_USER:$SPLUNK_ADMIN_PASSWORD
sudo -u $SPLUNK_SYSTEM_USER $SPLUNK_HOME/bin/splunk edit cluster-config \
	-mode slave \
	-site $site \
	-master_uri https://$ClusterMasterPrivateIp:8089 \
        -replication_port 9887 \
	-secret $SPLUNK_CLUSTER_SECRET 


# Configure indexer discovery
cat >>$SPLUNK_HOME/etc/system/local/inputs.conf <<end
[splunktcp://9997]
end

service splunk restart
