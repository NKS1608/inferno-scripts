# Inferno on Apple Silicon macOS

*[Português](README.md) · English*

Scripts and a manual for running ChefKiss'
[Inferno](https://chefkiss.dev/guides/inferno/) — an emulated iPhone 11 (t8030) —
on an Apple Silicon Mac.

The official guide is the source of truth. This is what was left after running it
end to end: the deviations macOS demanded, the ordering that actually works, and a
launcher that keeps you from getting the sequence wrong.

Tested on macOS 15.7, M4, 16 GB. Restored with iOS 14.0 beta 5 (`18A5351d`) on
`iPhone12,1`.

## What you must supply

These scripts do **not** download any of it, and they shouldn't:

- the `.ipsw` for a supported version of your device;
- the matching SEP ROM (for t8030, `Cebu B1`);
- the SEP firmware IV and key for that exact build, from
  [The Apple Wiki](https://theapplewiki.com/).

The guide is explicit: do not share ipsws, images, decrypted firmware, tickets,
IVs or keys, and do not automate downloading or patching any of them. That
violates Apple's EULA and may be a crime in your jurisdiction. This repo's
`.gitignore` is a whitelist precisely so none of it lands here by accident.

## Requirements

- macOS on Apple Silicon, Homebrew, `cmake`, `python3`.
- ~40 GB free: 5 GB ipsw, 0.5 GB extracted `Restore/`, ~8 GB `root` disk after the
  restore, ~6 GB companion VM.
- Patience. The restore takes over an hour, and the UI afterwards runs on software
  rendering.

## Setup from scratch

Keep everything in one directory, called `InfernoData` here. The scripts assume
they sit at its root.

### 1. Host

```sh
brew install libtool meson ninja pkgconf dtc glib gnutls jpeg-turbo libpng \
  libslirp libssh libusb lzo ncurses pixman snappy vde zstd libtasn1 lzfse

git clone https://github.com/ChefKissInc/Inferno && cd Inferno
git submodule update --init
mkdir build && cd build
LIBTOOL="glibtool" ../configure --target-list=aarch64-softmmu,x86_64-softmmu \
  --disable-guest-agent --enable-lzfse --enable-slirp --enable-curses \
  --enable-libssh --enable-virtfs --enable-zstd --extra-cflags=-DNCURSES_WIDECHAR=1 \
  --disable-sdl --disable-gtk --enable-cocoa --enable-nettle --enable-gnutls \
  --extra-cflags="-I/opt/homebrew/include" --extra-ldflags="-L/opt/homebrew/lib" \
  --disable-werror --disable-qom-cast-debug --disable-debug-info --disable-fuse
ninja
```

`--disable-fuse` is not in the guide and is mandatory on macOS:
`block/export/fuse.c` does not compile against the macFUSE headers.

The build only produces `qemu-system-*-unsigned`. Sign them so HVF works for the
companion:

```sh
cd Inferno/build
for b in qemu-system-aarch64 qemu-system-x86_64; do
  codesign --entitlements ../accel/hvf/entitlements.plist --force -s - ./$b-unsigned
  cp ./$b-unsigned ./$b
done
```

### 2. Files

```sh
python3 -m venv venv && ./venv/bin/pip install pyasn1 pyasn1-modules

for d in "root 32G" "firmware 8M" "syscfg 128K" "ctrl_bits 8K" "nvram 8K" \
         "effaceable 4K" "panic_log 1M" "sep_nvram 64K" "sep_ssc 128K"; do
  set -- $d; Inferno/build/qemu-img create -f raw "$1" "$2"
done
```

In `zsh`, `set -- $d` does not word-split — run the nine `qemu-img create` calls by
hand, or use `bash`.

Drop the ipsw in the directory, extract it without the large `.dmg` (that's the OS
image; `idevicerestore` reads it straight from the ipsw), then grab the ticket
scripts and `img4lib`:

```sh
mkdir Restore
unzip -q "YOUR.ipsw" -x "038-44337-083.dmg" -d Restore     # adjust the dmg name

for f in create_apticket.py create_septicket.py ticket.shsh2 idevicerestore.patch; do
  curl -LO "https://chefkiss.dev/Extras/Inferno/$f"
done

git clone https://github.com/xerub/img4lib && cd img4lib
git submodule update --init
make LDFLAGS="-L/opt/homebrew/opt/openssl/lib -L/opt/homebrew/opt/lzfse/lib" \
     CFLAGS='-I/opt/homebrew/opt/openssl/include -I/opt/homebrew/opt/lzfse/include -O2 -I. -g -DiOS10 -DDER_MULTIBYTE_TAGS=1 -DDER_TAG_SIZE=8 -D__unused="__attribute__((unused))"'
```

Tickets and SEP firmware (`n104ap` is the iPhone 11 — adjust for your device):

```sh
./venv/bin/python3 create_apticket.py  n104ap Restore/BuildManifest.plist ticket.shsh2 root_ticket.der
./venv/bin/python3 create_septicket.py n104ap Restore/BuildManifest.plist ticket.shsh2 sep_root_ticket.der

KEY=<IV><KEY>    # concatenated, no space, from The Apple Wiki, for YOUR build
V=$(img4lib/img4 -v -i Restore/Firmware/all_flash/sep-firmware.n104.RELEASE.im4p \
      -o sep-firmware.n104.RELEASE -k $KEY)
img4lib/img4 -A -F -o sep-firmware.n104.RELEASE.new.img4 -i sep-firmware.n104.RELEASE \
      -M sep_root_ticket.der -T rsep -V "$V"
```

That last command should print nothing but `none`. The IV and key differ per build
**and** per device — triple-check them. Getting this wrong produces a `dart-sep`
panic much later, not an error here.

### 3. Companion

The guide suggests an emulated x86_64 VM. This setup uses **arm64 Debian with
HVF** instead — `usb-tcp-remote` exists on the `aarch64` target too, so the
companion runs accelerated rather than emulated.

```sh
mkdir companion && cd companion
bzcat ../Inferno/pc-bios/edk2-aarch64-code.fd.bz2 > edk2-aarch64-code.fd
dd if=/dev/zero of=edk2-arm-vars.fd bs=1m count=64
curl -LO https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-arm64.qcow2
../Inferno/build/qemu-img resize debian-13-generic-arm64.qcow2 12G
hdiutil makehybrid -iso -joliet -iso-volume-name CIDATA -joliet-volume-name CIDATA -o seed.iso seed
```

This repo's `companion/seed/user-data` already installs the dependencies, mounts
`InfernoData` at `/mnt/inferno` over 9p, and builds the libimobiledevice stack
(`libplist`, `libimobiledevice-glue`, `libusbmuxd`, `libtatsu`, `libimobiledevice`,
`libirecovery`, `usbmuxd`, `idevicerestore`) with ChefKiss' patch applied.

Two things cloud-init won't sort out on its own:

- `libplist` needs `--without-cython` — the Python bindings don't build without
  `python-is-python3`, and nothing here uses them.
- `usbmuxd` built from source installs neither a unit nor a udev rule unless you
  pass the directories:

  ```sh
  ./configure --with-udevrulesdir=/lib/udev/rules.d \
              --with-systemdsystemunitdir=/lib/systemd/system
  ```

  Without that, `idevicerestore` never sees the device. The service shows as
  `inactive` when no device is attached — that's normal, it is udev-activated.

## Daily use

```sh
./inferno.sh boot     # brings the companion up if needed, then the iPhone
./inferno.sh status
./inferno.sh stop
```

The companion **must** come up before the iPhone VM: the iPhone's USB is the
client connecting to the `/tmp/InfernoUSBRemote` socket the companion opens.
`inferno.sh` handles that.

## Restoring

Wipes the `root` disk. Only worth doing the first time, or if the install broke.

```sh
./inferno.sh restore   # the VM closes itself when stage 1 finishes
./inferno.sh patch     # filesystem patches (asks for sudo)
./inferno.sh boot      # data migration + setup screen
```

`restore` arms a watcher on the companion that only fires `idevicerestore` once
the iPhone's USB shows up in sysfs. Firing earlier yields
`Unable to discover device mode`. Follow along with `./inferno.sh log`.

`patch` mounts `root`, runs
[InfernoFSPatcher](https://git.chefkiss.dev/AppleHax/InfernoFSPatcher) on
`dyld_shared_cache_arm64e` (this is what enables software rendering — there is no
GPU emulation), disables five launch daemons that break boot (`voicemail.vmd`, the
three `CommCenter*`, `locationd`), and ejects. It aborts if it can't find all five
rather than writing a half-patched plist. The original `launchd.plist` is saved
alongside.

Clone and build the patcher before your first `patch`:

```sh
git clone https://git.chefkiss.dev/AppleHax/InfernoFSPatcher && cd InfernoFSPatcher
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build
```

## Device buttons

| Key | Action           | Key    | Action            |
|-----|------------------|--------|-------------------|
| F1  | Force shutdown   | F5     | Power/side        |
| F2  | Toggle ringer    | F6     | Home              |
| F3  | Volume −         | F7/F8  | Help / Help double |
| F4  | Volume +         | F9/F10 | Hall effect       |

Home screen: F6 once. App switcher: F6 twice.
SOS/slide-to-power-off: hold F4, then hold F5 about half a second later — not
simultaneously.

## Never do

- **Don't** set a passcode — it doesn't work.
- **Don't** enable location services.
- **Don't** use "Erase All Content and Settings" — it bricks the install.
- **Don't** modify the tickets after the restore. They're required at every boot
  stage, not just during installation.

## On performance

The iPhone VM is pure TCG, and will stay that way. The A13 is emulated with
Apple's proprietary system registers (GXF/APRR) hand-registered in
`hw/arm/apple-silicon/a13_gxf.c`; Hypervisor.framework exposes the host with a
fixed feature set and won't let you register or trap those. There isn't a single
line of `hvf` under `hw/arm/apple-silicon/`.

What you can do: `-accel tcg,tb-size=1024` (already in `run-iphone.sh`), MTTCG is
on by default, and the companion is accelerated. On an M4 (4 P-cores + 6 E-cores)
the 7 vCPUs spread out and most land on E-cores; macOS offers no thread affinity.

For games the bottleneck isn't the emulated CPU, it's having no GPU at all.

## Files

| File | What |
|---|---|
| `inferno.sh` | launcher: `boot`, `restore`, `patch`, `shell`, `log`, `status`, `stop` |
| `run-iphone.sh` | raw QEMU command for the device (`SERIAL=file:x.log` redirects the serial) |
| `run-companion.sh` | raw QEMU command for the companion |
| `patch-fs.sh` | filesystem patches, runs as root |
| `wait-and-restore.sh` | runs **inside** the companion; waits for USB, then calls `idevicerestore` |
| `companion/seed/user-data` | companion cloud-init |

Companion: `./inferno.sh shell` (or `ssh -p 32222 inferno@127.0.0.1`, password
`inferno`). `InfernoData` shows up there at `/mnt/inferno`, read-only.

The filenames in `run-iphone.sh` and `wait-and-restore.sh` are specific to iOS
14.0 beta 5 on the iPhone 11. Changing version or device means adjusting the
ramdisk, trustcache, kernelcache, device tree and SEP firmware.

## When things break

| Symptom | Cause |
|---|---|
| Stuck at "skipping unencrypted volume" or "SEP accepted IMG4" | Known instability. Restart until it gets through. |
| `Unable to discover device mode` | Companion started after the iPhone, or `usbmuxd` isn't active. Use `./inferno.sh restore`. |
| `at24c-eeprom: Backing file size ...` | `truncate -c -s 64K ./sep_nvram` |
| `dart-sep ... TTBR invalid` panic | Wrong SEP ROM or SEP firmware. |
| `cannot find IOAESAccelerator` panic | Booted without the ramdisk, or corrupted disk. |
| Can't mount `root` read-write | macOS too old. |

The iPhone serial log is only written when you start with `SERIAL=file:...`.
Full list: <https://chefkiss.dev/guides/inferno/troubleshooting/>
