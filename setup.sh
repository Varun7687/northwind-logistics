#!/bin/bash

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Run with: sudo bash setup.sh"
    exit 1
fi

yum install -y httpd git
systemctl enable --now httpd

if ! mountpoint -q /data/www; then
    echo "ERROR: EBS is not mounted at /data/www"
    exit 1
fi

groupadd -f webteam

id asha || useradd -m -s /bin/bash asha
id ravi || useradd -m -s /bin/bash ravi

usermod -aG webteam asha
usermod -aG webteam ravi

cat > /etc/ssh/sshd_config.d/99-no-password-login.conf <<EOF
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF

sshd -t
systemctl reload sshd

mkdir -p /data/www/status

ln -sfn /data/www/status /var/www/html/status

chown -R root:webteam /data/www

find /data/www -type d -exec chmod 2775 {} \;
find /data/www -type f -exec chmod 0664 {} \;

if [ ! -f /data/www/status/index.html ]; then
cat > /data/www/status/index.html <<HTML
<!DOCTYPE html>
<html>
<head>
    <title>Server Status</title>
</head>
<body>
    <h1>Northwind Logistics</h1>
    <p><strong>Hostname:</strong> $(hostname)</p>
    <p><strong>Last updated:</strong> $(date +%F)</p>

    <table border="1">
        <tr>
            <th>Service</th>
            <th>Status</th>
        </tr>
        <tr>
            <td>Website</td>
            <td>Operational</td>
        </tr>
        <tr>
            <td>Database</td>
            <td>Operational</td>
        </tr>
        <tr>
            <td>API</td>
            <td>Degraded</td>
        </tr>
    </table>
</body>
</html>
HTML
fi

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

echo "Complete setup finished successfully."
