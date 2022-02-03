#cloud-config
users:
  - name: centos
    gecos: administrative user
    lock_passwd: true
    ssh_authorized_keys:
      - ${centos_user_ssh_public_key}
    sudo: "ALL=(ALL) NOPASSWD: ALL"

# Avoid it messing with network
network:
  config: disabled

# Avoid it trashing the host keys
ssh_deletekeys: false