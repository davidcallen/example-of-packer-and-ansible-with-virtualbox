#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail   # preserve exit code when piping e.g. with "tee"

START_PATH=${PWD}
MY_NAME=`basename $0`
START_TIME_SECONDS=$SECONDS

function usage()
{
    echo  "+----------------------------------------------------------------------+"
    echo  "| ${MY_NAME} - build packer image                                      |"
    echo  "+----------------------------------------------------------------------+"
    echo  ""
    echo  "Usage: "
    echo  ""
    echo  "    -debug                     : Enable debug"
    echo  "    -no-yum_update [-ny]       : temporary disable yum update in the AMI for faster dev/debug [DEV DEBUG ONLY USAGE!]"
    echo  ""
    exit 1
}
function err()
{
  echo  "ERROR: occured in $(basename $0)"
  cd "${START_PATH}"
  exit 1
}

ARG_DEBUG=
ARG_YUM_UPDATE_ENABLED="true"
ARGS=$*
while (( "$#" )); do
	ARG_RECOGNISED=FALSE

	if [ "$1" == "-h" ] ; then
		usage
	fi
	if [ "$1" == "-no-yum-update" -o "$1" == "-ny" ]; then
		ARG_YUM_UPDATE_ENABLED="false"
		ARG_RECOGNISED=TRUE
	fi
	if [ "$1" == "-debug" ]; then
		ARG_DEBUG=-debug
		ARG_RECOGNISED=TRUE
	fi
	if [ "${ARG_RECOGNISED}" == "FALSE" ]; then
		echo "Invalid args : Unknown argument \"${1}\"."
		err 1
	fi
	shift
done

echo -e "\nInitialise our environment for Packer..."
export YUM_UPDATE_ENABLED="${ARG_YUM_UPDATE_ENABLED}"
# source ../packer-init.sh

echo -e "\nInstalled Ansible required dependancies..."
export ANSIBLE_FORCE_COLOR=True   # Preserve colours even when piping to "tee"
[ -f ./ansible/requirements.yml ] && ansible-galaxy install --roles-path ./ansible/roles/ -r ./ansible/requirements.yml

echo -e "\nValidate the Ansible playbook..."
ansible-playbook --syntax-check ansible/playbook.yml

# Get filename of our previously created centos-7-from-iso OVF file :
export CENTOS_VBOX_ISO_TO_OVF_FILENAMEPATH="$(ls -1 ../centos-7-from-iso/output/my-centos-7-from-iso.ovf)"
if [ "${CENTOS_VBOX_ISO_TO_OVF_FILENAMEPATH}" == "" ] ; then
  echo "ERROR : OVF source file not found. Check and run ../centos-7-from-iso packer build before this build."
  err
fi

# Clean temporary output files. Will be recreated by Packer from templates.
# But create temporary placeholder files to prevent 'packer validate' from erroring
[ -f cloud-init-floppy/user-data ] && rm -f cloud-init-floppy/user-data
touch cloud-init-floppy/user-data
[ -f cloud-init-floppy/meta-data ] && rm -f cloud-init-floppy/meta-data
touch cloud-init-floppy/meta-data

# VBox packer provisioner requires 'output' directory to not exist
[ -d ./output ] && rm -rf ./output

echo -e "\nValidate the Packer file..."
packer validate packer.pkr.hcl

echo -e "\nBuilding with Packer..."
packer build ${ARG_DEBUG} -on-error=ask packer.pkr.hcl 2>&1 | tee packer.log

ELAPSED_SECONDS=$(($SECONDS - START_TIME_SECONDS))
echo "$(date +'%Y%m%d %H:%M:%S') : Completed in $((ELAPSED_SECONDS/60)) min $((ELAPSED_SECONDS%60)) sec"

