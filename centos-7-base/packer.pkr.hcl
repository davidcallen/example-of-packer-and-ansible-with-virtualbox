variable "centos_vbox_iso_to_ovf_filenamepath" {
  type    = string
  default = "${env("CENTOS_VBOX_ISO_TO_OVF_FILENAMEPATH")}"
}
variable "yum_update_enabled" {
  type    = string
  default = "${env("YUM_UPDATE_ENABLED")}"
}

locals {
  instance_id = uuidv4()      # Use random instance_id. Otherwise if it does not change then cloud-init "first boot" event will not occur.
}
source "file" "cloud-init-user-data" {
  content                   =  templatefile("cloud-init-user-data.tpl", {
    "centos_user_ssh_public_key" = file("~/.ssh/my-ssh-key-packer-builder.pub")
  })
  target                    =  "${path.root}/cloud-init-floppy/user-data"
}
source "file" "cloud-init-meta-data" {
  content                   =  "instance-id: ${local.instance_id}"
  target                    =  "${path.root}/cloud-init-floppy/meta-data"
}
source "virtualbox-ovf" "build" {
  vm_name                   = "my-centos-7-base"
  guest_additions_mode      = "attach"
  headless                  = "false"
  source_path               = "${var.centos_vbox_iso_to_ovf_filenamepath}"
  ssh_username              = "centos"
  ssh_private_key_file      = "~/.ssh/my-ssh-key-packer-builder"
  ssh_clear_authorized_keys = "true"
  ssh_timeout               = "600s"
  vboxmanage                = [
    ["modifyvm", "{{ .Name }}", "--memory", "2048"],
    ["modifyvm", "{{ .Name }}", "--cpus", "4"],
    ["modifyvm", "{{ .Name }}", "--audio", "none"]
  ]
  floppy_files              = [
    "${path.root}/cloud-init-floppy/meta-data",
    "${path.root}/cloud-init-floppy/user-data"
  ]
  floppy_label              = "cidata"
  shutdown_command          = "echo 'packer' | sudo -S shutdown -P now"
  output_directory          = "${path.root}/output"
}

build {
  sources = [
    "sources.file.cloud-init-user-data",
    "sources.file.cloud-init-meta-data",
    "source.virtualbox-ovf.build"
  ]
  provisioner "ansible" {
    # galaxy_file     = "./ansible/requirements.yml"
    playbook_file   = "./ansible/playbook.yml"
    # roles_path      = "./ansible/roles"
    user            = "centos"
    use_proxy       = false
    extra_arguments = [
      "-e YUM_UPDATE_ENABLED='${var.yum_update_enabled}'",
      "-v"
    ]
  }
  provisioner "shell" {
    expect_disconnect = true
    inline            = [
      "set -x ; date ; uptime ; echo Rebooting to apply yum updates ; sudo reboot"
    ]
    inline_shebang    = "/bin/bash"
  }
  provisioner "shell" {
    inline         = [
      "date ; uptime ; echo ========================  Reboot Succeeded  =================================="
    ]
    inline_shebang = "/bin/bash"
    pause_before   = "1m0s"
  }
  provisioner "shell" {
    execute_command = "sudo -S sh '{{ .Path }}'"
    inline          = [
      "echo '# Shredding sensitive data for user root...'",
      "[ -f /root/.ssh/authorized_keys ] && shred -u /root/.ssh/authorized_keys",
      "[ -f /root/.bash_history ] && shred -u /root/.bash_history",
      "echo '# Shredding sensitive data for user centos...'",
      "[ -d /home/centos ] && [ -f /home/centos/.bash_history ] && shred -u /home/centos/.bash_history",
      "sync; sleep 1; sync"
    ]
    inline_shebang  = "/bin/sh -e -x"
  }
}
