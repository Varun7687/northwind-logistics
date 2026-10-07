# Northwind Logistics — Internal Team Status Page

**Assignment:** Assignment 1 — Internal Team Status Page  
**Platform:** AWS EC2, Amazon Linux 2023, Apache httpd  
**Website data:** `/data/www/status`  
**Shared Linux group:** `webteam`

## 1. Project overview

This project hosts a Northwind Logistics service-status page on an Amazon Linux 2023 EC2 instance. It uses a separate EBS volume for website data, gives `asha` and `ravi` individual SSH-key access, and configures shared website editing through the `webteam` group. The setup script and build log document the configuration and security choices.

## 2. Architecture and AWS resources

Apache serves the page from the EBS-backed directory. `/var/www/html/status` links to `/data/www/status`.

![Northwind Logistics AWS architecture](diagrams/architecture-demo.jpg)

| Resource | Configuration / value to record |
|---|---|
| EC2 instance | Amazon Linux 2023; `t3.micro` or `t2.micro` |
| VPC / subnet | Default VPC, public subnet |
| Public IPv4 / instance ID | `<EC2_PUBLIC_IP>` / `<EC2_INSTANCE_ID>` |
| Security group | `<SECURITY_GROUP_ID>` |
| Data EBS volume | gp3, 1–2 GiB; `<EBS_VOLUME_ID>` |
| Filesystem / mount | ext4 at `/data/www` |

Security-group inbound rules:

| Protocol | Port | Source | Purpose |
|---|---:|---|---|
| SSH | 22 | `<YOUR_PUBLIC_IP>/32` | Administrative SSH from the current trusted public IP only |
| HTTP | 80 | `0.0.0.0/0` | Browser access to the demonstration page |

Do not expose SSH to `0.0.0.0/0`. Update the SSH rule if the administrator’s public IP changes. For multiple administrators, allow only trusted source addresses or use a VPN/bastion. Restrict HTTP too if the page is not intended to be publicly reachable.

## 3. Prerequisites

* An AWS account with permission to create EC2, security-group, and EBS resources.
* An Amazon Linux 2023 EC2 instance and a newly attached data volume. Confirm its device name with `lsblk`; do not assume it is always `/dev/nvme1n1`.
* Separate public SSH keys for `asha` and `ravi`. Keep private keys off the instance and out of GitHub.
* Git and SSH on the workstation, plus a GitHub repository for the assignment.

The script expects `ASHA_PUBLIC_KEY` and `RAVI_PUBLIC_KEY` to be set before it runs. Review `setup.sh` and verify that the selected data disk is not the root disk before using it.

## 4. Build and deployment

Run `setup.sh` as root after attaching the new EBS data volume, confirming its Linux device name, and preparing both public keys. It installs Apache and Git, creates `webteam` and the user accounts, configures key-only SSH, prepares the fresh EBS filesystem, adds a UUID-based mount to `/etc/fstab`, verifies the mount, and only then creates the page. Do not use this setup on a volume containing data you need to preserve.

For launch-time automation, include the bootstrap commands (or the `setup.sh` contents) in EC2 **User Data**. Attach the EBS volume at launch, confirm `DATA_DISK` identifies the data disk rather than the root disk, and provide the public-key values required by the script. User Data runs as root on first boot; if the EBS volume is attached later, run the setup after attaching it rather than expecting first-boot User Data to run again.

Example from the project folder (replace the device path with the one confirmed by `lsblk`):

```bash
sudo env \
  DATA_DISK=/dev/nvme1n1 \
  ASHA_PUBLIC_KEY="$(cat asha.pub)" \
  RAVI_PUBLIC_KEY="$(cat ravi.pub)" \
  bash ./setup.sh
```

**Safety:** the script can create a partition and format a new filesystem when the selected partition has no filesystem. Never point it at the root disk or a volume containing data that must be preserved. It backs up `/etc/fstab`, mounts by filesystem UUID, and verifies the mount before writing the website.

Permission choices and the reason SSH is IP-restricted are explained in [`build_log.md`](build_log.md).

## 5. Security, users, and permissions

`asha` and `ravi` use separate public keys, belong to `webteam`, and have no password-based SSH access. The script also disables root SSH login. Website files are owned by `root:webteam` so team members can update them without making them owned by a login account.

| Path / object | Mode | Intended access |
|---|---:|---|
| `/home/asha/.ssh`, `/home/ravi/.ssh` | `0700` | Each user alone can access their SSH configuration directory. |
| Each `authorized_keys` file | `0600` | Only the account owner can read or change accepted public keys. |
| Website directories | `2775` | Owner and `webteam` can manage content; setgid makes new entries inherit the shared group; others can read/traverse but not write. |
| Website files | `0664` | Owner and `webteam` can edit; Apache and other readers can read, but users outside the group cannot change files. |

Useful checks:

```bash
getent group webteam
id asha
id ravi
ls -ld /data/www /data/www/status
ls -l /data/www/status
```

## 6. EBS storage and Apache

The setup script obtains the EBS filesystem UUID with `blkid`, backs up `/etc/fstab`, and adds the persistent mount entry below if it is not already present. It then mounts the volume and verifies `/data/www` before writing website files. Because the entry uses the filesystem UUID rather than a changing device name, Linux can remount the EBS volume after reboot.

```text
UUID=<EBS_FILESYSTEM_UUID> /data/www ext4 defaults,nofail 0 2
```

The website is stored at `/data/www/status`. Apache serves it through `/var/www/html/status` and the configuration created by `setup.sh`. The expected URL is:

```text
http://<EC2_PUBLIC_IP>/status/
```

Check the storage and web service with:

```bash
lsblk -f
findmnt /data/www
df -h /data/www
systemctl is-enabled httpd
systemctl is-active httpd
curl -f http://localhost/status/
```

## 7. Git and GitHub workflow

The repository is `assignment-1-status-page`. Develop the assignment on `assignment-1`, review it, and merge it into `main`.

1. Add the README, setup script, build log, diagrams, and any demonstration evidence to the repository.
2. Commit and push the assignment branch, then review and merge it into `main`.
3. Clone the repository on EC2. Push a page change from the workstation, pull it on EC2, and verify the update in the browser.

```bash
git status
git branch --show-current
git pull
```

Never commit private keys, passwords, or GitHub tokens.

Files included in this project folder:

```text
README.md
build_log.md
setup.sh
diagrams/
├── architecture-demo.jpg
└── architecture.png
```

## 8. Validation and assessment reports

Capture actual output from the EC2 instance and replace the placeholders below. No live instance output is included in this README.

### Files modified in the last day

```bash
find /data/www -type f -mtime -1 -print
```

```text
<PASTE THE ACTUAL COMMAND OUTPUT HERE>
```

### Files owned by the `webteam` group

```bash
find /data/www -type f -group webteam -print
```

```text
<PASTE THE ACTUAL COMMAND OUTPUT HERE>
```

Before the demo, verify the page from a browser and with `curl`, confirm the EBS mount and Apache service after reboot, test SSH as `asha` with her key, and show that a user outside `webteam` cannot edit site files. Save screenshots of the page, mount, permissions, and Git pull if required by the assignment.

## 9. Troubleshooting and completion

* **SSH reports “unprotected private key file” on Windows:** this concerns the local private-key file’s Windows ACL, not the EC2 security group. Restrict it to the current account, for example:

  ```powershell
  icacls .\northwind-ec2-key.pem /inheritance:r
  icacls .\northwind-ec2-key.pem /grant:r "$env:USERNAME:R"
  ```

* **SSH is unreachable:** confirm the client’s current public IP matches the security-group `/32`, port 22 is allowed, and the correct username/private key is used.
* **Apache returns 404:** check the symlink, Apache configuration, and service status with `ls -l /var/www/html/status`, `apachectl configtest`, and `systemctl status httpd`.
* **The website is not on the data volume:** check `mountpoint /data/www` and `findmnt /data/www` before writing files.
* **Package-manager conflict for curl:** Amazon Linux may provide `curl` through `curl-minimal`; avoid installing a conflicting package.

Record these values before submission:

* GitHub repository URL: `<REPOSITORY_URL>`
* EC2 public IP: `<EC2_PUBLIC_IP>`
* EBS volume ID: `<EBS_VOLUME_ID>`
* Demo date: `<DATE>`
