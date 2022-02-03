
# Create the centos kickstart config file (will be copied into a CD ISO - kickstart searches for volumes with label "OEMDRV")
source "file" "kickstart-config" {
  content = templatefile("centos-kickstart.cfg.tpl", {
    ssh_public_key = file("~/.ssh/my-ssh-key-packer-builder.pub")
  })
  target                    =  "${path.root}/kickstart-cdrom/ks.cfg"
}
source "virtualbox-iso" "from_iso" {
  vm_name                   = "my-centos-7-from-iso"
  guest_os_type             = "RedHat_64"
  headless                  = "false"
  # Will need to periodically check for availability of later CentOS 7 images :
  iso_checksum              = "sha256:07b94e6b1a0b0260b94c83d6bb76b26bf7a310dc78d7a9c7432809fb9bc6194a"
  iso_url                   = "http://mirrors.ukfast.co.uk/sites/ftp.centos.org/7.9.2009/isos/x86_64/CentOS-7-x86_64-Minimal-2009.iso"
  # Uploads guest additions files to /root  (currently haven't added installation of this in our packer shell scripts)
  guest_additions_mode      = "upload"
  # Use root and an ssh key (note : the ssh pub key is installed in the Kickstart post-install script)
  ssh_username              = "root"
  ssh_private_key_file      = "~/.ssh/my-ssh-key-packer-builder"
  ssh_clear_authorized_keys = "true"
  ssh_timeout               = "1200s"
  vboxmanage                = [
    ["modifyvm", "{{ .Name }}", "--memory", "2048"],
    ["modifyvm", "{{ .Name }}", "--cpus", "4"],
    ["modifyvm", "{{ .Name }}", "--audio", "none"]
  ]
  disk_size                 = "10240"
  # Create and attach a CD containing the centos kickstart config file (kickstart searches for volumes with label "OEMDRV")
  cd_files                  = [
    "${path.root}/kickstart-cdrom/ks.cfg"
  ]
  cd_label                  = "OEMDRV"
  boot_command              = ["<wait><enter>"]   # Send ENTER key to start installation promptly
  boot_wait                 = "5s"
  shutdown_command          = "echo 'packer' | sudo -S shutdown -P now"
  output_directory          = "${path.root}/output"
}

build {
  sources = [
    "sources.file.kickstart-config",
    "source.virtualbox-iso.from_iso"
  ]
  provisioner "shell" {
    execute_command = "sudo -S sh '{{ .Path }}'"
    inline          = [
      # Configure cloud-init with NoCloud datasource (otherwise cloud-init service wont start on next bootup)
      "echo 'datasource_list: [ NoCloud, None ]' > /etc/cloud/cloud.cfg.d/01_ds-identify.cfg",
    ]
    inline_shebang  = "/bin/sh -e -x"
  }
  provisioner "shell" {
    execute_command = "sudo -S sh '{{ .Path }}'"
    inline          = [
      "echo '# Shredding sensitive data for user root...'",
      "[ -f /root/.bash_history ] && shred -u /root/.bash_history",
      "sync; sleep 1; sync"
    ]
    inline_shebang  = "/bin/sh -e -x"
  }
}
