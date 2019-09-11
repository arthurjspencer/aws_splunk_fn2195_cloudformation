#!/bin/bash -v
# Make cloud-init output log readable by root.

chmod 600 /var/log/cloud-init-output.log
yum update -y aws-cfn-bootstrap
yum update -y
yum install -y jq

adduser $SPLUNK_SYSTEM_USER --comment "Splunk User" --system --create-home --shell /sbin/nologin
usermod --expiredate 1 $SPLUNK_USER

mkdir $SPLUNK_HOME
mkfs -t xfs /dev/sdb
echo "/dev/sdb    $SPLUNK_HOME        xfs     defaults,nofail 0   2" >> /etc/fstab
mount -a

aws s3 cp s3://${AWS_S3_BUCKET}/code/${SPLUNK_TARBALL} /tmp

tar -xzf /tmp/${SPLUNK_TARBALL} -C $SPLUNK_HOME --strip-components=1
rm -f /tmp/${SPLUNK_TARBALL}

echo "source $SPLUNK_HOME/bin/setSplunkEnv" >> /home/splunk/.bashrc

echo "[user_info]" > $SPLUNK_HOME/etc/system/local/user-seed.conf
echo "USERNAME = $SPLUNK_ADMIN_USER" >> $SPLUNK_HOME/etc/system/local/user-seed.conf
echo "PASSWORD = $SPLUNK_ADMIN_PASSWORD" >> $SPLUNK_HOME/etc/system/local/user-seed.conf

touch $SPLUNK_HOME/etc/.ui_login

chown -R $SPLUNK_SYSTEM_USER:$SPLUNK_SYSTEM_USER $SPLUNK_HOME
sudo -u $SPLUNK_SYSTEM_USER $SPLUNK_HOME/bin/splunk start --accept-license --answer-yes --no-prompt

$SPLUNK_HOME/bin/splunk enable boot-start -user $SPLUNK_SYSTEM_USER

cat << EOF > /tmp/init-thp-ulimits
# Disabling transparent huge pages
disable_thp() {
echo "Disabling transparent huge pages"
if test -f /sys/kernel/mm/transparent_hugepage/enabled; then
    echo never > /sys/kernel/mm/transparent_hugepage/enabled
fi
if test -f /sys/kernel/mm/transparent_hugepage/defrag; then
    echo never > /sys/kernel/mm/transparent_hugepage/defrag
fi
}

# Change ulimits
change_ulimit() {
ulimit -Sn 65535
ulimit -Hn 65535
ulimit -Su 20480
ulimit -Hu 20480
ulimit -Sf unlimited
ulimit -Hf unlimited
}
EOF
sed -i "/init\.d\/functions/r /tmp/init-thp-ulimits" /etc/init.d/splunk
sed -i "/start)$/a \    disable_thp\n    change_ulimit" /etc/init.d/splunk
rm /tmp/init-thp-ulimits

# Create 25-splunk.conf in limits.d to set ulimits when not using systemctl
echo "$SPLUNK_SYSTEM_USER           hard    core            0" >> /etc/security/limits.d/25-splunk.conf
echo "$SPLUNK_SYSTEM_USER           hard    maxlogins       10" >> /etc/security/limits.d/25-splunk.conf
echo "$SPLUNK_SYSTEM_USER           soft    nofile          65535" >> /etc/security/limits.d/25-splunk.conf
echo "$SPLUNK_SYSTEM_USER           hard    nofile          65535" >> /etc/security/limits.d/25-splunk.conf
echo "$SPLUNK_SYSTEM_USER           soft    nproc           20480" >> /etc/security/limits.d/25-splunk.conf
echo "$SPLUNK_SYSTEM_USER           hard    nproc           20480" >> /etc/security/limits.d/25-splunk.conf
echo "$SPLUNK_SYSTEM_USER           soft    fsize           unlimited" >> /etc/security/limits.d/25-splunk.conf
echo "$SPLUNK_SYSTEM_USER           hard    fsize           unlimited"  >> /etc/security/limits.d/25-splunk.conf

$SPLUNK_HOME/bin/splunk stop
$SPLUNK_HOME/bin/splunk clone-prep-clear-config
rm -f $SPLUNK_HOME/var/log

systemctl daemon-reload

