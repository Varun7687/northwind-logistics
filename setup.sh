#!/bin/bash

# Northwind Logistics status page - EC2 User Data
# Target: Amazon Linux 2023 with a separate, NEW empty EBS data volume attached.
# Verify DATA_DISK before launch. On many Nitro instances, the root disk is
# /dev/nvme0n1 and the second EBS volume is /dev/nvme1n1.

exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1
set -Eeuo pipefail

DATA_DISK="/dev/nvme1n1"  # CHANGE this if your data disk has another device name
MOUNT_POINT="/data/www"
SITE_DIR="${MOUNT_POINT}/status"
WEB_ROOT="/var/www/html"
FORMAT_BLANK_VOLUME="yes"  # Keep yes only for a NEW, EMPTY EBS volume

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: EC2 User Data should run this as root."
    exit 1
fi

echo "Installing Apache, Git, and EBS filesystem tools..."
yum install -y httpd git util-linux e2fsprogs parted
systemctl enable --now httpd

groupadd -f webteam
id asha >/dev/null 2>&1 || useradd -m -s /bin/bash asha
id ravi >/dev/null 2>&1 || useradd -m -s /bin/bash ravi
usermod -aG webteam asha
usermod -aG webteam ravi

# Wait for the separately attached EBS disk to appear.
for attempt in {1..30}; do
    if [ -b "$DATA_DISK" ]; then
        break
    fi
    sleep 2
done

if [ ! -b "$DATA_DISK" ]; then
    echo "ERROR: Data disk $DATA_DISK was not found. Check the EBS attachment/device name."
    lsblk
    exit 1
fi

# Refuse to modify the root disk.
ROOT_SOURCE=$(findmnt -n -o SOURCE /)
ROOT_DEVICE=$(readlink -f "$ROOT_SOURCE" 2>/dev/null || true)
ROOT_DISK=$(lsblk -no PKNAME "$ROOT_DEVICE" 2>/dev/null | head -n 1 || true)
DATA_DISK_NAME=$(basename "$DATA_DISK")

if [ "$DATA_DISK" = "$ROOT_SOURCE" ] || \
   [ "$DATA_DISK" = "$ROOT_DEVICE" ] || \
   [ "$DATA_DISK_NAME" = "$ROOT_DISK" ]; then
    echo "ERROR: DATA_DISK points to the root disk. Stopping to protect the instance."
    exit 1
fi

# Find an existing partition. For a new blank disk, create partition 1.
DATA_PART=$(lsblk -nrpo NAME,TYPE "$DATA_DISK" | awk '$2 == "part" {print $1; exit}')
if [ -z "$DATA_PART" ]; then
    WHOLE_DISK_FS=$(blkid -s TYPE -o value "$DATA_DISK" 2>/dev/null || true)
    if [ -n "$WHOLE_DISK_FS" ]; then
        # A filesystem is already on the whole disk; do not repartition it.
        DATA_PART="$DATA_DISK"
    else
        echo "No partition/filesystem found on $DATA_DISK; creating a GPT partition."
        printf 'g\nn\n1\n\n\nw\n' | fdisk "$DATA_DISK"
        partprobe "$DATA_DISK"
        udevadm settle

        for attempt in {1..30}; do
            DATA_PART=$(lsblk -nrpo NAME,TYPE "$DATA_DISK" | awk '$2 == "part" {print $1; exit}')
            if [ -n "$DATA_PART" ]; then
                break
            fi
            sleep 1
        done
    fi
fi

if [ -z "$DATA_PART" ] || [ ! -b "$DATA_PART" ]; then
    echo "ERROR: Could not find or create a data partition."
    lsblk
    exit 1
fi

# Format only if no filesystem is detected. Intended only for a new empty volume.
DATA_FS=$(blkid -s TYPE -o value "$DATA_PART" 2>/dev/null || true)
if [ -z "$DATA_FS" ]; then
    if [ "$FORMAT_BLANK_VOLUME" != "yes" ]; then
        echo "ERROR: No filesystem found on $DATA_PART and formatting is disabled."
        exit 1
    fi
    echo "Creating ext4 filesystem on $DATA_PART (new empty volume)."
    mkfs.ext4 "$DATA_PART"
    DATA_FS=$(blkid -s TYPE -o value "$DATA_PART" 2>/dev/null || true)
fi

if [ "$DATA_FS" != "ext4" ]; then
    echo "ERROR: Expected ext4 on $DATA_PART; found '${DATA_FS:-no filesystem}'."
    exit 1
fi

DATA_UUID=$(blkid -s UUID -o value "$DATA_PART" 2>/dev/null || true)
if [ -z "$DATA_UUID" ]; then
    echo "ERROR: Could not determine filesystem UUID for $DATA_PART."
    exit 1
fi

# ----- FSTAB SETUP: persistently mount this EBS filesystem at /data/www -----
mkdir -p "$MOUNT_POINT"

if awk -v mp="$MOUNT_POINT" '$2 == mp { found=1 } END { exit !found }' /etc/fstab; then
    if ! awk -v uuid="UUID=$DATA_UUID" -v mp="$MOUNT_POINT" \
        '$1 == uuid && $2 == mp && $3 == "ext4" { found=1 } END { exit !found }' /etc/fstab; then
        echo "ERROR: /etc/fstab already has a conflicting entry for $MOUNT_POINT."
        exit 1
    fi
else
    cp -a /etc/fstab "/etc/fstab.backup.$(date +%Y%m%d%H%M%S)"
    printf 'UUID=%s %s ext4 defaults,nofail 0 2\n' \
        "$DATA_UUID" "$MOUNT_POINT" >> /etc/fstab
fi

# Mount and verify the EBS volume before writing website files.
if ! mountpoint -q "$MOUNT_POINT"; then
    mount "$MOUNT_POINT"
fi

MOUNTED_UUID=$(findmnt -n -o UUID --target "$MOUNT_POINT" 2>/dev/null || true)
if [ "$MOUNTED_UUID" != "$DATA_UUID" ]; then
    echo "ERROR: Expected EBS UUID $DATA_UUID is not mounted at $MOUNT_POINT. Stopping."
    exit 1
fi

echo "$MOUNT_POINT is mounted from EBS UUID $DATA_UUID."
df -h "$MOUNT_POINT"

# Website directory is created only after the EBS mount is confirmed.
mkdir -p "$SITE_DIR"
ln -sfnT "$SITE_DIR" "$WEB_ROOT/status"

cat > "$SITE_DIR/index.html" <<HTML
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
    find "$MOUNT_POINT" -type f -mtime -1 -print
    echo
    echo "## Files owned by webteam"
    echo 'find /data/www -type f -group webteam -print'
    find "$MOUNT_POINT" -type f -group webteam -print
} > "$SITE_DIR/README.md"

# Explicitly allow Apache to serve the EBS-backed directory.
cat > /etc/httpd/conf.d/northwind-status.conf <<APACHE
<Directory "$SITE_DIR">
    Options FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>
APACHE

chown -R root:webteam "$MOUNT_POINT"
find "$MOUNT_POINT" -type d -exec chmod 2775 {} \;
find "$MOUNT_POINT" -type f -exec chmod 0664 {} \;

cd "$SITE_DIR"
if [ ! -d ".git" ]; then
    git init
fi
git branch -M main
git config user.name "asha"
git config user.email "asha@localhost"
git add .

if ! git diff --cached --quiet; then
    git commit -m "Complete server setup"
fi

httpd -t
systemctl restart httpd
systemctl is-active --quiet httpd
mountpoint -q "$MOUNT_POINT"
test -L "$WEB_ROOT/status"

echo "Setup completed successfully."
echo "Users: asha and ravi"
echo "Group: webteam"
echo "Data partition: $DATA_PART"
echo "Mount point: $MOUNT_POINT"
echo "Website: http://localhost/status/"
/"
