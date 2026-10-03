#!/bin/sh
# Faux zramswap (Molecule, cf. prepare.yml) : même configuration que le vrai
# (/etc/default/zramswap : SIZE en Mio, sinon PERCENT de la RAM, 50 par défaut),
# mais la taille atterrit dans le /sys/block/zram0 factice au lieu d'un device.
set -eu
ALGO=lz4
PERCENT=
SIZE=
PRIORITY=100
if [ -r /etc/default/zramswap ]; then
  . /etc/default/zramswap
fi

case "${1:-}" in
  start)
    if [ -n "$SIZE" ]; then
      bytes=$((SIZE * 1024 * 1024))
    else
      mem_kib=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)
      bytes=$((mem_kib * 1024 * ${PERCENT:-50} / 100))
    fi
    mkdir -p /sys/block/zram0
    echo "$bytes" > /sys/block/zram0/disksize
    echo "$ALGO" > /sys/block/zram0/comp_algorithm
    echo "$PRIORITY" > /sys/block/zram0/molecule_priority
    ;;
  stop)
    # Le vrai fait swapoff puis `modprobe -r zram` (qui échoue, device en
    # usage) : le device reste, avec sa taille.
    ;;
  *)
    echo "usage: $0 start|stop" >&2
    exit 1
    ;;
esac
