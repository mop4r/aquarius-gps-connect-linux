#!/bin/bash
# Gera a imagem do cartao: U-Boot+SPL no setor 16 (8 KiB), p1 FAT32 AQ-BOOT (/boot), p2 ext4 AQ-ROOT (/).
# uso: montar-imagem.sh <rootfs> <u-boot-sunxi-with-spl.bin> <saida.img> [tamanho, padrao 6144M]
set -euo pipefail

R=${1:?rootfs}; UB=${2:?u-boot}; IMG=${3:?saida}; TAM=${4:-6144M}
[ -d "$R/boot" ] && [ -f "$UB" ] || { echo "argumento invalido" >&2; exit 1; }
[ -e "$IMG" ] && { echo "saida ja existe: $IMG" >&2; exit 1; }
[ "$(stat -c %s "$UB")" -lt $((1024*1024 - 8192)) ] || { echo "u-boot nao cabe antes de 1 MiB" >&2; exit 1; }

BOOT_MB=256
truncate -s "$TAM" "$IMG"
# p1 comeca em 1 MiB (o U-Boot ocupa 8 KiB..~600 KiB), bootavel para o distroboot do U-Boot
sfdisk --quiet "$IMG" <<EOF
label: dos
start=2048, size=$((BOOT_MB*2048)), type=c, bootable
start=$((2048 + BOOT_MB*2048)), type=83
EOF
dd if="$UB" of="$IMG" bs=1024 seek=8 conv=notrunc status=none

W=$(mktemp -d)
trap 'umount -q "$W/root/boot" 2>/dev/null || true; umount -q "$W/root" 2>/dev/null || true; losetup -d "$LOOP" 2>/dev/null || true; rm -rf "$W"' EXIT
LOOP=$(losetup --show -fP "$IMG")
mkfs.vfat -F 32 -n AQ-BOOT "${LOOP}p1" >/dev/null
mkfs.ext4 -q -L AQ-ROOT -O ^metadata_csum_seed "${LOOP}p2"
mkdir -p "$W/root"
mount "${LOOP}p2" "$W/root"
mkdir -p "$W/root/boot"
mount "${LOOP}p1" "$W/root/boot"
# /boot vai para a FAT (sem links simbolicos), o resto para o ext4
tar -C "$R" --exclude=./boot --exclude=./proc/* --exclude=./sys/* --exclude=./dev/* -cf - . | tar -C "$W/root" -xpf -
cp -rL "$R/boot/." "$W/root/boot/"
rm -rf "$W/root/boot/extlinux"
# gera o menu com a FAT montada: o u-boot-update so ve o /boot separado com /proc e a montagem reais
for d in proc sys dev; do mount --bind /$d "$W/root/$d"; mount --make-slave "$W/root/$d"; done  # slave: desmontar nao propaga ao WSL
chroot "$W/root" u-boot-update
for d in dev sys proc; do umount "$W/root/$d"; done
grep -q '^	linux /vmlinuz-' "$W/root/boot/extlinux/extlinux.conf" || { echo "extlinux: caminho do kernel errado" >&2; exit 1; }
grep -q '^	fdt /dtbs/.*/aquarius/sun4i-a10-aquarius-mtc4553.dtb' "$W/root/boot/extlinux/extlinux.conf" || { echo "extlinux: sem fdt da placa" >&2; exit 1; }
sync
echo "== conteudo de /boot"; ls -R "$W/root/boot" | head -30
echo "== extlinux.conf"; cat "$W/root/boot/extlinux/extlinux.conf"
umount "$W/root/boot"; umount "$W/root"
echo "imagem pronta: $IMG"
