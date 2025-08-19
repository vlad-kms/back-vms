#!/bin/bash

#./back-vol.sh --debug --name vm1 -s "test/ds2" -d "/mnt/test/ds1/back" $@

./back-vol.sh --config ./cron-vm-deb.json $@

# удалить все снапшоты для Dataset's
#ds=( "test/ds2/.sys/cnt/vol_1" "test/ds2/.sys/cnt/vol_2" "test/ds2/.sys/vm/vol_3" "test/ds2/.sys/vm/dev-deb-003" ); for n in ${ds[*]}; do zfs list -t snapshot "$n" -r | tail +2 | awk '{print $1}' | xargs -I {} zfs destroy {}; done
