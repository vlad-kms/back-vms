#!/bin/bash
# backup TrueNAS VM's (из Virtualization)
/root/backup/back-vol.sh --config vm_old_arch.json $@
# backup VM's и containers (из Containers)
/root/backup/back-vol.sh --config cont-new-arch.json $@
/root/backup/back-vol.sh --config vm_new_arch.json $@

#/root/backup/back-vol.sh --name dev_deb_001 --dest /mnt/base-pool/vms/backup --dry-run --debug -l ./123.log
#/root/backup/back-vol.sh --name dev_deb_003 --dest /mnt/base-pool/vms/backup --dry-run --debug -l ./123.log

#/root/backup/back-vol-to-ya.sh --name dev_deb_001
#/root/backup/back-vol-to-ya.sh --name dev_deb_003
##/root/backup/back-vol-to-ya.sh --name dev-w11-dsikd --source app