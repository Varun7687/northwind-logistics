#!/bin/bash

exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

set -e

yum install -y httpd git
systemctl enable --now httpd

groupadd -f webteam

id asha >/dev/null 2>&1 || useradd -m -s /bin/bash asha
id ravi >/dev/null 2>&1 || useradd -m -s /bin/bash ravi

usermod -aG webteam asha
usermod -aG webteam ravi

mkdir -p /data/www/status

if mountpoint -q /data/www; then
    echo "/data/www is mounted."
else
    echo "WARNING: /data/www is not mounted. Using the root volume."
fi

ln -sfn /data/www/status /var/www/html/status

cat > /data/www/status/index.html <<HTML
<!DOCTYPE html>
<html>
<head>
    <title>Server Status</title>
</head>
<body>
    <h1>Northwind Logistics</h1>
    <p>Hostname: $(hostname)</p>
    <p>Last updated: $(date)</p>

    <table border="1">
        <tr><th>Service</th><th>Status</th></tr>
        <tr><td>Website</td><td>Operational</td></tr>
        <tr><td>Database</td><td>Operational</td></tr>
        <tr><td>API</td><td>Degraded</td></tr>
    </table>
</body>
</html>
HTML

{
    echo "# Website File Report"
    echo
    echo "## Files modified in the last day"
    echo 'find /data/www -type f -mtime -1 -print'
    find /data/www -type f -mtime -1 -print
    echo
    echo "## Files owned by webteam"
    echo 'find /data/www -type f -group webteam -print'
    find /data/www -type f -group webteam -print
} > /data/www/status/README.md

chown -R root:webteam /data/www

find /data/www -type d -exec chmod 2775 {} \;
find /data/www -type f -exec chmod 0664 {} \;

cd /data/www/status

if [ ! -d ".git" ]; then
    git init
fi

git branch -M main
git config user.name "asha"
git config user.email "asha@localhost"

git add .
git diff --cached --quiet || git commit -m "Complete server setup"

systemctl restart httpd
systemctl is-active --quiet httpd

echo "Setup completed successfully."
echo "Users: asha and ravi"
echo "Group: webteam"
echo "Website: http://localhost/status/"
