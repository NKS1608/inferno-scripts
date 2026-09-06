#!/bin/bash
# Inferno launcher. Sobe a companion antes da VM do iPhone (ordem obrigatória).
#   ./inferno.sh boot     iniciar o iPhone emulado
#   ./inferno.sh restore   restaurar do zero (apaga o disco root)
#   ./inferno.sh patch     aplicar os filesystem patches no disco restaurado (pede sudo)
#   ./inferno.sh shell     shell na companion
#   ./inferno.sh log       acompanhar o log do restore
#   ./inferno.sh status | stop
set -euo pipefail
cd "$(dirname "$0")"

ERASE_RAMDISK="./Restore/038-44135-124.dmg"
SSH=(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -p 32222 inferno@127.0.0.1)

companion_up() {
  if nc -z 127.0.0.1 32222 2>/dev/null; then echo "companion: já rodando"; return; fi
  echo "companion: subindo (log em companion.log)"
  nohup ./run-companion.sh > companion.log 2>&1 &
  until nc -z 127.0.0.1 32222 2>/dev/null; do sleep 3; done
  echo "companion: pronta"
}

case "${1:-boot}" in
  boot)
    companion_up
    exec ./run-iphone.sh
    ;;
  restore)
    [ -f "$ERASE_RAMDISK" ] || { echo "!! ramdisk de erase não encontrado: $ERASE_RAMDISK"; exit 1; }
    companion_up
    # o watcher espera o USB do iPhone aparecer antes de disparar o idevicerestore;
    # começar antes disso dá "Unable to discover device mode"
    "${SSH[@]}" 'sudo pkill -f "idevicerestore|wait-and-restore" || true' >/dev/null 2>&1 || true
    "${SSH[@]}" 'cat > wait-and-restore.sh && chmod +x wait-and-restore.sh' < wait-and-restore.sh
    "${SSH[@]}" 'sudo bash -c "nohup /home/inferno/wait-and-restore.sh > /home/inferno/restore.log 2>&1 &"'
    echo "restore: armado. subindo o iPhone com o ramdisk de erase."
    exec ./run-iphone.sh -initrd "$ERASE_RAMDISK"
    ;;
  patch)
    if ! [ -d /Volumes/System/System/Library/xpc ]; then
      hdiutil attach -imagekey diskimage-class=CRawDiskImage -blocksize 4096 -noverify -noautofsck root
    fi
    exec sudo ./patch-fs.sh
    ;;
  shell)  exec "${SSH[@]}" ;;
  log)    exec "${SSH[@]}" 'tail -f /home/inferno/restore.log' ;;
  status)
    nc -z 127.0.0.1 32222 2>/dev/null && echo "companion: up" || echo "companion: down"
    pgrep -qf "qemu-system-aarch64 -M t8030" && echo "iphone:    up" || echo "iphone:    down"
    [ -d /Volumes/System ] && echo "disco root: montado em /Volumes/System" || echo "disco root: desmontado"
    ;;
  stop)
    pkill -f "qemu-system-aarch64 -M t8030" || true
    pkill -f "qemu-system-aarch64 -M virt" || true
    echo "parado"
    ;;
  *) sed -n '2,9p' "$0"; exit 1 ;;
esac
