#!/bin/bash

yum install -y httpd
systemctl enable httpd
systemctl start httpd

groupadd -f webteam

id asha || useradd -m asha
id ravi || useradd -m ravi

usermod -aG webteam asha
usermod -aG webteam ravi

mkdir -p /data/www/status
chown -R root:webteam /data/www
chmod -R g+rwX /data/www

ln -sfn /data/www/status /var/www/html/status

