#!/bin/bash
# Monta o rootfs Debian 13 (trixie) armhf do GPS Aquarius em $1 (pasta nova).
# Roda no WSL como root, com qemu-user (binfmt flag F) para executar armhf.
# Nao recebe segredo: Wi-Fi e chave SSH sao injetados depois por configurar-rootfs.sh.
set -euo pipefail

R=${1:?uso: montar-rootfs.sh <pasta-destino>}
MIRROR=http://deb.debian.org/debian

# qemu-user trava (futex) no dpkg-deb com descompressao em varias threads: uma thread so
export DPKG_DEB_THREADS_MAX=1
export GLIBC_TUNABLES=glibc.pthread.rseq=0

# Retomavel: se o debootstrap ja terminou nesta pasta, pula para os pacotes
if [ ! -f "$R/etc/os-release" ]; then
  [ -e "$R" ] && { echo "destino existe sem debootstrap completo: $R" >&2; exit 1; }
  debootstrap --arch=armhf --variant=minbase \
    --components=main,contrib,non-free,non-free-firmware \
    --include=systemd-sysv,udev,dbus,apt,ca-certificates,locales,tzdata,ifupdown \
    trixie "$R" "$MIRROR"
else
  echo "rootfs ja existe, retomando: $R"
  DEBIAN_FRONTEND=noninteractive chroot "$R" dpkg --configure -a
fi

cat > "$R/etc/apt/sources.list" <<EOF
deb $MIRROR trixie main contrib non-free non-free-firmware
deb $MIRROR trixie-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
EOF

# Pacotes que cobrem cada item do mapa (analise/mapa-port.md)
PKGS=(
  linux-image-armmp initramfs-tools u-boot-tools            # kernel + boot
  firmware-realtek wpasupplicant iw wireless-regdb rfkill   # Wi-Fi RTL8188CUS
  systemd-resolved systemd-timesyncd openssh-server         # rede + SSH
  alsa-utils                                                # som (sun4i-codec)
  evtest libinput-tools i2c-tools libiio-utils usbutils     # touch, botoes, I2C, acelerometro
  libgl1-mesa-dri libegl1 libgles2 mesa-utils kmscube       # GPU Mali-400 (lima)
  cage seatd retroarch                                      # interface: RetroArch em tela cheia
  sudo nano less htop iproute2 iputils-ping procps kmod dosfstools e2fsprogs fdisk
)
chroot "$R" apt-get update
DEBIAN_FRONTEND=noninteractive chroot "$R" apt-get install -y --no-install-recommends "${PKGS[@]}"

# Emuladores (libretro) disponiveis no Debian para armhf; o que nao existir e listado, nao some calado
CORES=(libretro-nestopia libretro-snes9x libretro-genesisplusgx libretro-mgba libretro-gambatte libretro-beetle-pce-fast libretro-desmume)
for c in "${CORES[@]}"; do
  if chroot "$R" apt-cache show "$c" >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive chroot "$R" apt-get install -y --no-install-recommends "$c"
  else
    echo "CORE AUSENTE NO DEBIAN ARMHF: $c" | tee -a "$R/root/cores-ausentes.txt"
  fi
done

chroot "$R" apt-get clean
echo "rootfs pronto em $R"
