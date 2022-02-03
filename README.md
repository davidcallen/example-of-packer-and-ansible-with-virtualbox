Packer and Ansible with VirtualBox
==================================

This git repository contains an example of using Packer and Ansible to create a CentOS 7 virtual box machine image.

There did not seem to be much information out there on the internet for this so it seemed worthwhile to pass on this knowledge.

[Packer](https://www.packer.io/) from Hashicorp is a tool for creating machine images.  It can be used with plugins, called [Provisioners](https://www.packer.io/docs/provisioners), to extend it.
 
I use the [Ansible Provisioner](https://www.packer.io/plugins/provisioners/ansible/ansible) to execute an [Ansible](https://www.ansible.com/) playbook to configure the internals of the virtual machine.  
  
Packer also includes plugins for building the image under various Hypervisors. One such is the [VirtualBox Builders](https://www.packer.io/plugins/builders/virtualbox) :
- [VirtualBox ISO Builder](https://www.packer.io/plugins/builders/virtualbox/iso) to create an OVF image from the CentOS ISO
- [VirtualBox OVF Builder](https://www.packer.io/plugins/builders/virtualbox/ovf) to create an OVF image based from another OVF image.

This example creates 2 OVF images :
- centos-7-from-iso
- centos-7-base (built upon the centos-7-from-iso image)


centos-7-from-iso image
-----------------------

This image is created from the CentOS 7 CDROM ISO installer.

It uses the [Kickstart](https://docs.centos.org/en-US/centos/install-guide/Kickstart2/) tool to automate the installation of CentOS.

Our Kickstart file is based on a template ```centos-7-from-iso/centos-kickstart.cfg.tpl``` and configures such OS installation details as :
- chosen language
- keyboard layout
- root user settings (no password, no shell)
- selinux settings (enabled and enforcing)
- packages to be installed (just "core")
- install [cloud-init](https://cloudinit.readthedocs.io/) package. This provides us with a convenient way to pass configuration data and commands into a VM on first boot. This is used by the packer builder for centos-7-base.
- configure root SSH authorized_keys to allow Packer to connect via SSH to the VM to run shell commands.
- reboot at end of installation

```shell script
#         centos-7-from-iso/centos-kickstart.cfg.tpl
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
```  

The kickstart file is templated to enable us to pass the root authorized public SSH key into it from the ```packer.pkr.hcl``` as below snippet :

```hcl
source "file" "kickstart-config" {
  content = templatefile("centos-kickstart.cfg.tpl", {
    ssh_public_key = file("~/.ssh/my-ssh-key-packer-builder.pub")
  })
  target                    =  "${path.root}/kickstart-cdrom/ks.cfg"
}
```

The kickstart config file is supplied to the VM via a mounted CDROM, configured in the ```packer.pkr.hcl``` as below snippet :  

```hcl
  # Create and attach a CD containing the centos kickstart config file (kickstart searches for volumes with label "OEMDRV")
  cd_files                  = [
    "${path.root}/kickstart-cdrom/ks.cfg"
  ]
  cd_label                  = "OEMDRV"
  boot_command              = ["<wait><enter>"]   # Send ENTER key to start installation promptly
  boot_wait                 = "5s"
```

The above shows the keystrokes ```"<wait><enter>"``` that are passed to the VM and the CentOS Anaconda Installater to force the installation to start immediately.

After the CentOS installation has completed, then a Shell script is executed by Packer as in ```packer.pkr.hcl``` below :

```hcl
  provisioner "shell" {
    execute_command = "sudo -S sh '{{ .Path }}'"
    inline          = [
      # Configure cloud-init with NoCloud datasource (otherwise cloud-init service wont start on next bootup)
      "echo 'datasource_list: [ NoCloud, None ]' > /etc/cloud/cloud.cfg.d/01_ds-identify.cfg",
    ]
    inline_shebang  = "/bin/sh -e -x"
  }
```  

This configuration to cloud-init will ensure that it is invoked on next bootup. This will occur during the ```centos-7-base``` packer build.  

Note: This shell script is run by Packer via SSH using the root user as defined in ```packer.pkr.hcl``` here :

```hcl
  # Use root and an ssh key (note : the ssh pub key is installed in the Kickstart post-install script)
  ssh_username              = "root"
  ssh_private_key_file      = "~/.ssh/my-ssh-key-packer-builder"
  ssh_clear_authorized_keys = "true"
``` 

Note that the ```ssh_clear_authorized_keys=true``` will ensure that the Packer key is removed and wont be in the output image.  Otherwise this would be a security risk.

The VirtualBox image is then exported as an OVF-format file to the ```centos-7-from-iso/output``` directory.


centos-7-base image
--------------------- 

This image is built upon the centos-7-from-iso OVF image.

It obtains this image from ```centos-7-from-iso/output``` directory.

The ```centos-7-base``` image is intended to be a base image for all our other image builds and so we want to include into it some fundamentals such as :
- an administrative user ```centos``` (seperate and distinct from root user). This is similar as in AWS CentOS AMI images.
- run the ```yum update``` to fully update the system
- install ```yum-cron``` package to update the system nightly 

Many other configurations may be desired in your base image.  I use Ansible to accomplish these since it is more suited to the job than mere shell scripts.

The centos-7-from-iso OVF filename and path is configured in the ```packer.pkr.hcl``` using the ```source_path``` attribute :

```hcl
variable "centos_vbox_iso_to_ovf_filenamepath" {
  type    = string
  default = "${env("CENTOS_VBOX_ISO_TO_OVF_FILENAMEPATH")}"
}
....
source "virtualbox-ovf" "build" {
  vm_name                   = "my-centos-7-base"
  guest_additions_mode      = "attach"
  headless                  = "false"
  source_path               = "${var.centos_vbox_iso_to_ovf_filenamepath}"
```

The filenamepath is found by the ```./packer-build-image.sh``` and exported as an environment variable ```CENTOS_VBOX_ISO_TO_OVF_FILENAMEPATH``` into Packer.

Packer will start the VM using this OVF file. It will pass information into it to cloud-init via an attached floppy disk as defined in ```packer.pkr.hcl``` here :

```hcl
  floppy_files              = [
    "${path.root}/cloud-init-floppy/meta-data",
    "${path.root}/cloud-init-floppy/user-data"
  ]
  floppy_label              = "cidata"
```    

The cloud-init files are created via the packer HCL :

```hcl
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
```    

cloud-init will read and action these files. The ```user-data``` file ensures that a ```centos``` user will be created as below :

```yaml
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
``` 

The ```centos``` user is then used by Packer to connect to the VM via SSH using our SSH Key ```~/.ssh/my-ssh-key-packer-builder```.  Packer can then run the Ansible playbook and shell scripts via this SSH connection. 

```hcl
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
```

Above we can see that the Ansible Provisioner is configured to use the new ```centos``` user. It is passing the ```yum_update_enabled``` variable. Currently no roles are used in the playbook so those lines are commented out.

Finally shell scripts are invoked by Packer over the SSH connection to :
- reboot the VM to ensure the yum updates have been fully applied
- wait for reboot
- clean sensitive information (ssh keys and bash history) e.g. 

```hcl
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
```

The VirtualBox image is then exported as an OVF-format file to the ```centos-7-base/output``` directory.


Scripts
----------
The following scripts help to create, develop and debug the packer images :
- ```packer-build-image.sh``` 
    - this will start the packer build
    - it also installs any required ansible roles from Ansible Galaxy
    - and also validates the ansible playbook and packer hcl file
- ```ansible-debug-run.sh``` 
    - this can be used to re-run a failed ansible playbook during the packer build
    - this is possible because Packer is configured to wait on error via the ```-on-error=ask``` argument:
        ```hcl
        packer build ${ARG_DEBUG} -on-error=ask packer.pkr.hcl 2>&1 | tee packer.log
        ```     
    - this enables fixing and re-running of the ansible and is faster than just re-running ```packer-build-image.sh``` 
- ```ssh-connect-to-packer-builder.sh```
    - provide convenient SSH connection to a running packer build vm, for debugging purposes.    
  

Summary
--------
VirtualBox can be used with Packer and Ansible to create machine images from ISO Installer files and from other VirtualBox OVF image files.

The speed of running the Ansible playbook and the import/export of OVF files was found to be slower than expected.  If it was faster than AWS AMI it could have provided an "on-premise" quick packer/ansible development environment before a final creation of AMI on AWS.  Maybe this could be improved using different network setup on the VirtualBox (host/nat/bridged).

Regardless there are use-cases for rolling your own VirtualBox images and using Packer and Ansible will help to automate the creation of these.

