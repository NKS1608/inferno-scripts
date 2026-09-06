#!/bin/bash
# Main VM (emulated iPhone 11 / t8030). Start the companion FIRST.
# Pass -initrd ./Restore/<ramdisk>.dmg for restore/upgrade (erase ramdisk = smaller of the two).
set -euo pipefail
cd "$(dirname "$0")"
exec ./Inferno/build/qemu-system-aarch64 \
  -M t8030,trustcache=./Restore/Firmware/038-44135-124.dmg.trustcache,ticket=root_ticket.der,sep-fw=sep-firmware.n104.RELEASE.new.img4,sep-rom=AppleSEPROM-Cebu-B1,kaslr-off=true \
  -kernel ./Restore/kernelcache.research.iphone12b \
  -dtb ./Restore/Firmware/all_flash/DeviceTree.n104ap.im4p \
  -append "tlto_us=-1 mtxspin=-1 agm-genuine=1 agm-authentic=1 agm-trusted=1 serial=3 wdt=-1 -vm_compressor_wk_sw" \
  -accel tcg,tb-size=1024 \
  -smp 7 -m 4G -serial "${SERIAL:-mon:stdio}" \
  -display cocoa,zoom-to-fit=on,zoom-interpolation=on,show-cursor=on \
  -drive file=sep_nvram,if=pflash,format=raw \
  -drive file=sep_ssc,if=pflash,format=raw \
  -drive file=root,format=raw,if=none,id=root -device nvme-ns,drive=root,bus=nvme-bus.0,nsid=1,nstype=1,logical_block_size=4096,physical_block_size=4096 \
  -drive file=firmware,format=raw,if=none,id=firmware -device nvme-ns,drive=firmware,bus=nvme-bus.0,nsid=2,nstype=2,logical_block_size=4096,physical_block_size=4096 \
  -drive file=syscfg,format=raw,if=none,id=syscfg -device nvme-ns,drive=syscfg,bus=nvme-bus.0,nsid=3,nstype=3,logical_block_size=4096,physical_block_size=4096 \
  -drive file=ctrl_bits,format=raw,if=none,id=ctrl_bits -device nvme-ns,drive=ctrl_bits,bus=nvme-bus.0,nsid=4,nstype=4,logical_block_size=4096,physical_block_size=4096 \
  -drive file=nvram,if=none,format=raw,id=nvram -device apple-nvram,drive=nvram,bus=nvme-bus.0,nsid=5,nstype=5,id=nvram,logical_block_size=4096,physical_block_size=4096 \
  -drive file=effaceable,format=raw,if=none,id=effaceable -device nvme-ns,drive=effaceable,bus=nvme-bus.0,nsid=6,nstype=6,logical_block_size=4096,physical_block_size=4096 \
  -drive file=panic_log,format=raw,if=none,id=panic_log -device nvme-ns,drive=panic_log,bus=nvme-bus.0,nsid=7,nstype=8,logical_block_size=4096,physical_block_size=4096 \
  "$@"
