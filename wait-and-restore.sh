#!/bin/bash
# Runs in the companion VM: wait for the emulated iPhone's USB to appear, then restore.
# ponytail: poll sysfs for the Apple VID instead of writing udev rules
set -u
IPSW="/mnt/inferno/iPhone11,8,iPhone12,1_14.0_18A5351d_Restore.ipsw"
until grep -qs 05ac /sys/bus/usb/devices/*/idVendor; do sleep 2; done
sleep 3
exec idevicerestore --erase --restore-mode -i 0x1122334455667788 "$IPSW" -T /mnt/inferno/root_ticket.der
