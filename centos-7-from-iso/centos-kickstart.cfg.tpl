install
cdrom
lang en_GB.UTF-8
keyboard uk
timezone UTC
network --bootproto=dhcp
rootpw --lock
auth --enableshadow --passalgo=sha512 --kickstart
firewall --disabled
selinux --enforcing
bootloader --location=mbr

text
skipx
zerombr

clearpart --all --initlabel
autopart

firstboot --disable
reboot

%packages --instLangs=en_GB.utf8 --nobase --ignoremissing --excludedocs
@core
%end

# ------------------ anaconda post installation script ----------------------------
# Will do the yum update in the centos-7-base build instead
%post --log=/root/ks.log
set -x
echo "Start Anaconda Kickstart post-install script"

# Install cloud-init (will be configured at end of packer shell)
yum install -y cloud-init

# Save below ssh key to /root/.ssh to avoid using a password
[ ! -d /root/.ssh ] && mkdir /root/.ssh
chmod 700 /root/.ssh
PACKER_SSH_PUBLIC_KEY='${ssh_public_key}'
echo "PACKER_SSH_PUBLIC_KEY=$${PACKER_SSH_PUBLIC_KEY}"
echo "$${PACKER_SSH_PUBLIC_KEY}" > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
restorecon -R /root/.ssh

echo "Finished Anaconda Kickstart post-install script"
%end