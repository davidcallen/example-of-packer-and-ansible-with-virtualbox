#!/bin/bash
# For re-running a failed ansible playbook whilst Packer VM still alive.
#
# Pass "-v" for verbose ansible logging
set -o errexit
set -o pipefail   # preserve exit code when piping e.g. with "tee"


# Installed required dependancies
[-f ./ansible/requirements.yml ] && ansible-galaxy install --roles-path ./ansible/roles/ -r ./ansible/requirements.yml
echo

ansible-playbook --syntax-check ansible/playbook.yml
echo

# NOTE : check that the correct target IP address (packer build instance) is in file : ansible/group_vars/static
export ANSIBLE_FORCE_COLOR=True   # Preserve colours even when piping to "tee"
ansible-playbook ansible/playbook.yml \
  -i ansible/group_vars/static \
  --private-key=~/.ssh/my-ssh-key-packer-builder $* 2>&1 | tee ansible.log
