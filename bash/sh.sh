#!/bin/bash -v
# Make cloud-init output log readable by root.

chmod 600 /var/log/cloud-init-output.log

yum update -y aws-cfn-bootstrap
yum install -y jq

# Set hostname
hostnamectl set-hostname $hostname
printf '%s\t%s\n' `hostname -I` $hostname >> /etc/hosts
hostname $hostname
LOCALIP=`hostname -I | cut -f1 -d " "`

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

sudo -u $SPLUNK_SYSTEM_USER $SPLUNK_HOME/bin/splunk login -auth $SPLUNK_ADMIN_USER:$SPLUNK_ADMIN_PASSWORD

# Connect SH to Indexer
case $splunk_role in
    sh|shc|shc_captain|dmc)
        sudo -u $SPLUNK_SYSTEM_USER $SPLUNK_HOME/bin/splunk edit cluster-config \
            -mode searchhead \
            -site site0 \
            -master_uri https://$ClusterMasterPrivateIp:8089 \
            -secret $SPLUNK_CLUSTER_SECRET
        #sleep 15
    ;;
esac

# Configure SHC parameters
case $splunk_role in
    shc|shc_captain)
        sudo -u $SPLUNK_SYSTEM_USER $SPLUNK_HOME/bin/splunk init shcluster-config \
            -mgmt_uri https://$LOCALIP:8089 \
            -replication_port 8090 \
            -replication_factor 3 \
            -conf_deploy_fetch_url https://$DeployerPrivateIp:8089 \
            -shcluster_label $SEARCH_CLUSTER_LABEL \
            -secret $SPLUNK_CLUSTER_SECRET
        ;;
esac

service splunk restart

# Add Code to Start Captain on last search head
case $splunk_role in
    shc_captain)
# Bootstrap SHC captain
        sudo -u $SPLUNK_SYSTEM_USER $SPLUNK_HOME/bin/splunk login -auth $SPLUNK_ADMIN_USER:$SPLUNK_ADMIN_PASSWORD
        sudo -u $SPLUNK_SYSTEM_USER $SPLUNK_HOME/bin/splunk bootstrap shcluster-captain \
            -servers_list " \
                https://$SHCMember1PrivateIp:8089, \
                https://$SHCMember2PrivateIp:8089, \
                https://$LOCALIP:8089"
        ;;
esac

# Add Code to Start Captain on last search head
case $splunk_role in
    dmc)
# Peer into sites for DMC visibility
        sudo -u $SPLUNK_SYSTEM_USER $SPLUNK_HOME/bin/splunk login -auth $SPLUNK_ADMIN_USER:$SPLUNK_ADMIN_PASSWORD
        sudo -u $SPLUNK_SYSTEM_USER $SPLUNK_HOME/bin/splunk add search-server \
                -host https://$ClusterMasterPrivateIp:8089 \
                -remoteUsername $SPLUNK_ADMIN_USER -remotePassword $SPLUNK_ADMIN_PASSWORD
        sudo -u $SPLUNK_SYSTEM_USER $SPLUNK_HOME/bin/splunk add search-server \
                -host https://$DeployerPrivateIp:8089 \
                -remoteUsername $SPLUNK_ADMIN_USER -remotePassword $SPLUNK_ADMIN_PASSWORD
        sudo -u $SPLUNK_SYSTEM_USER $SPLUNK_HOME/bin/splunk add search-server \
                -host https://$SHCMember1PrivateIp:8089 \
                -remoteUsername $SPLUNK_ADMIN_USER -remotePassword $SPLUNK_ADMIN_PASSWORD
        sudo -u $SPLUNK_SYSTEM_USER $SPLUNK_HOME/bin/splunk add search-server \
                -host https://$SHCMember2PrivateIp:8089 \
                -remoteUsername $SPLUNK_ADMIN_USER -remotePassword $SPLUNK_ADMIN_PASSWORD
        sudo -u $SPLUNK_SYSTEM_USER $SPLUNK_HOME/bin/splunk add search-server \
                -host https://$SHCMember3PrivateIp:8089 \
                -remoteUsername $SPLUNK_ADMIN_USER -remotePassword $SPLUNK_ADMIN_PASSWORD
        sudo -u $SPLUNK_SYSTEM_USER $SPLUNK_HOME/bin/splunk add search-server \
                -host https://$HF1PrivateIp:8089 \
                -remoteUsername $SPLUNK_ADMIN_USER -remotePassword $SPLUNK_ADMIN_PASSWORD
        ;;
esac
