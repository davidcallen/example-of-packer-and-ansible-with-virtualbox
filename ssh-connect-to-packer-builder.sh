#!/bin/bash
# For easy SSH connection to a running packer build vm, for debugging purposes
set -o errexit
set -o pipefail   # preserve exit code when piping e.g. with "tee"

# Get the random ssh port assigned to our vbox packer vm
GET_SSH_PORT_LINE=$(cat packer.log | grep 'Creating forwarded port mapping for communicator (SSH, WinRM, etc) (host port ')
GET_SSH_PORT=`echo "${GET_SSH_PORT_LINE}" | cut -d ')' -f 2 | cut -d ' ' -f 4`


echo "Connecting to ansible target ${SSH_USER_AND_IP} on port ${GET_SSH_PORT} ..."
ssh -i ~/.ssh/my-ssh-key-packer-builder centos@127.0.0.1 -p ${GET_SSH_PORT}