#!/bin/bash
# Filesystem patches for the restored Inferno root disk. Run as root.
# Assumes `hdiutil attach ... root` already mounted /Volumes/System.
set -euo pipefail
cd "$(dirname "$0")"
V=/Volumes/System
[ -d "$V/System/Library/xpc" ] || { echo "!! $V is not mounted"; exit 1; }

echo "== enabling write access"
diskutil enableownership "$V"
mount -urw "$V"

echo "== patching dyld shared cache (software rendering)"
./InfernoFSPatcher/build/inferno_fs_patcher "$V/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64e"

echo "== backing up launch service cache"
cp -n "$V/System/Library/xpc/launchd.plist" ./launchd.plist

echo "== disabling problematic launch daemons"
python3 - <<'PY'
import plistlib
p = "/Volumes/System/System/Library/xpc/launchd.plist"
want = {"com.apple.voicemail.vmd", "com.apple.CommCenter",
        "com.apple.CommCenterMobileHelper", "com.apple.CommCenterRootHelper",
        "com.apple.locationd"}
with open(p, "rb") as f:
    d = plistlib.load(f)
hit = 0
for k, v in d["LaunchDaemons"].items():
    if isinstance(v, dict) and v.get("Label") in want:
        v["Disabled"] = True
        hit += 1
        print("  disabled", v["Label"])
assert hit == len(want), f"only found {hit} of {len(want)} services"
with open(p, "wb") as f:
    plistlib.dump(d, f, fmt=plistlib.FMT_BINARY)
PY

sync
echo "== ejecting"
diskutil eject "$V"
echo "== done"
