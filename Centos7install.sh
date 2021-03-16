#!/bin/bash

##########################################################
# Automated Centos 7 server installation and configuration
##########################################################

# Set FQDN hostname
hostnamectl set-hostname Server

# Add alias for root and update alias database 
echo "root:      user" >>/etc/aliases
newaliases

# Set SELINUX into permissive mode
setenforce 0
sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config

# Firstly, update yum
yum uqpdate -y

# REMI Repository initialization
yum install -y epel-release
wget https://rpms.remirepo.net/enterprise/remi-release-7.rpm
rpm -Uvh remi-release-7.rpm
yum update -y

# Apache web server and security packages
yum install -y httpd mod_evasive mod_ssl openssl
systemctl start httpd

# Mariadb install
yum install -y mariadb mariadb-server
systemctl start mariadb

# Mariadb 10 install
#yum install wget
#wget https://downloads.mariadb.com/MariaDB/mariadb_repo_setup
#chmod +x mariadb_repo_setup
#./mariadb_repo_setup
#yum install MariaDB-server

# Extra packages
yum install -y lnav lm_sensors logwatch wget fail2ban fail2ban-systemd whois yum-utils bash-completion bash-completion-extras NetworkManager-wifi NetworkManager-tui

# Cockpit and related packages
yum install -y cockpit cockpit-packagekit cockpit-dashboard cockpit-storaged cockpit-pcp

# PHP 7.3 install
yum-config-manager --enable remi-php73
yum install -y php

# PHPMYAdmin install and configure
yum install -y phpmyadmin

# Postfix and Dovecot
yum install -y postfix dovecot
mkdir /home/user/mail
chown user.user -R /home/user/mail
chmod 700 -R /home/user/mail
chmod 600 /var/mail/user

# UPS battery backup software


# Firewalld setup
firewall-cmd --permanent --add-service=imap
firewall-cmd --permanent --add-service=imaps
firewall-cmd --permanent --add-service=pop3
firewall-cmd --permanent --add-service=pop3s
firewall-cmd --permanent --add-service=smtp
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --permanent --add-service=cockpit
firewall-cmd --permanent --add-port=10000/tcp
firewall-cmd --permanent --add-port=19999/tcp
firewall-cmd --permanent --add-port=2020/tcp
firewall-cmd --permanent --add-port=587/tcp
firewall-cmd --permanent --add-port=465/tcp
firewall-cmd --reload


# make backup directory and mount backup drive
mkdir /mnt/backup
echo "UUID=01da53cb-76c1-4817-8b1a-8811763b0d6f  /mnt/backup auto nosuid,nodev,nofail 0 0" >>/etc/fstab

echo "Connect backup media at this time..."
read -p "Backup media connected (y/n)?" CONT
if [ "$CONT" = "y" ]; then
  echo "Great! Let's continue";
else
  echo "Sorry, no dice.";
  exit 1;
fi

mount -a

MNTPNT='/mnt/backup'
if ! mountpoint -q ${MNTPNT}/; then
	echo "Drive not mounted! Cannot continue without backup volume mounted!"
	exit 1
fi


# Apache server configuration/restoration

echo "Begin Apache server configuration"
echo

if [ ! -d /etc/ssl/private ]; then
  mkdir /etc/ssl/private
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout /etc/ssl/private/localhost.key -out /etc/ssl/certs/localhost.crt

else
  echo "Key pair already exists."

fi

# restore config/dir files from backup or master server
rsync -arv /mnt/backup/Server/2020/etc/httpd/conf/ /etc/httpd/conf
rsync -arv /mnt/backup/Server/2020/etc/httpd/conf.d/ /etc/httpd/conf.d
rsync -arv /mnt/backup/Server/2020/etc/httpd/conf.modules.d/ /etc/httpd/conf.modules.d
rsync -arv /mnt/backup/Server/2020/var/www/ /var/www

echo

# Mariadb config

echo "Begin Mariadb configuration"
echo


mysql --user=root <<_EOF_
GRANT ALL PRIVILEGES ON *.* TO 'admin'@'localhost' IDENTIFIED BY 'your password';
CREATE DATABASE roundcubemail DEFAULT CHARACTER SET utf8;
CREATE DATABASE suitecrm DEFAULT CHARACTER SET utf8;
CREATE DATABASE suitecrm2 DEFAULT CHARACTER SET utf8;
_EOF_

# Gunzip latest database backup sql.gz file for each databse and restore the database

DIR="/mnt/backup/sql/${dbase}/"
NEWEST=`ls -tr1d "${DIR}/"*.gz 2>/dev/null | tail -1`
TODAY=$(date +"%a")

echo "Name of databases seperated by spaces to restore?"
read -p 'databases: ' dbases

for dbase in $dbases
 do
  if [ ! -f "*.sql" ] ; then
   gunzip ${NEWEST}
   mysql --user=admin -p "$dbase" < $DIR/$TODAY.sql
else
    echo "The .sql file already exists for this $dbase"

fi
done

echo "Securing SQL installation"

mysql_secure_installation

echo 


# Postfix and Dovecot configuration

echo "Begin Postfix/Dovecot configuration"
echo

# import config files for mail server
rsync -arv /mnt/backup/Server/2020/etc/dovecot/ /etc/dovecot
rsync -arv /mnt/backup/Server/2020/etc/postfix/ /etc/postfix

echo


echo "Perform file restoration"
echo
rsync -arv /mnt/backup/Server/2020/etc/logwatch/ /etc/logwatch
rsync -arv /mnt/backup/Server/2020/etc/fail2ban/ /etc/fail2ban
rsync -arv /mnt/backup/Server/2020/etc/php.ini /etc/

# Webmin installation
#{
#  echo '[Webmin]'
#  echo 'name=Webmin Distribution Neutral'
#  echo '#baseurl=https://download.webmin.com/download/yum'
#  echo 'mirrorlist=https://download.webmin.com/download/yum/mirrorlist'
#  echo 'enabled=1'
#} >/etc/yum.repos.d/webmin.repo

#rpm --import http://www.webmin.com/jcameron-key.asc
#yum install -y webmin


# Start and enable services
systemctl start httpd
systemctl enable httpd
systemctl start mariadb
systemctl enable mariadb
systemctl start postfix
systemctl enable postfix
systemctl start dovecot
systemctl enable dovecot
systemctl start  cockpit.socket
systemctl enable cockpit.socket

# Install NetData
#bash <(curl -Ss https://my-netdata.io/kickstart.sh)

# Cronjobs
mkdir /etc/cron.custom

# drop in custom cron jobs
rsync -arv /mnt/backup/Server/2020/etc/cron.custom/ /etc/cron.custom


# RKHunter
yum install -y rkhunter
rkhunter --update
rkhunter --propupd

echo "All Finished!  The computer will now reboot."

# reboot computer
reboot
