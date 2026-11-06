#!/bin/bash
# Tira prints do sistema do GPS sem o aparelho: tela virtual 800x480 (Xvfb no WSL) e os programas
# ARM do proprio rootfs rodando por qemu-user, numa camada overlay (o rootfs nao e alterado).
# uso: prints.sh <rootfs> <pasta-saida>
set -uo pipefail
R=$(realpath "${1:?rootfs}"); OUT=$(realpath -m "${2:?saida}"); mkdir -p "$OUT"
export GLIBC_TUNABLES=glibc.pthread.rseq=0
W=$(mktemp -d); mkdir -p "$W/up" "$W/work" "$W/m"
mount -t overlay overlay -o lowerdir="$R",upperdir="$W/up",workdir="$W/work" "$W/m"
# --make-rslave: sem isso, desmontar as copias propaga e desmonta o /dev e o /proc do proprio WSL
# (04/11/2026: o WSL inteiro parou de responder e precisou de wsl --shutdown)
for d in proc sys dev; do mount --rbind /$d "$W/m/$d"; mount --make-rslave "$W/m/$d"; done
mkdir -p "$W/m/tmp/.X11-unix"; mount --bind /tmp/.X11-unix "$W/m/tmp/.X11-unix"; mount --make-slave "$W/m/tmp/.X11-unix"
fim() {
  [ -n "${XP:-}" ] && kill "$XP" 2>/dev/null
  for p in /proc/[0-9]*; do [ "$(readlink $p/root 2>/dev/null)" = "$W/m" ] && kill -9 "${p#/proc/}" 2>/dev/null; done
  umount -R "$W/m/tmp/.X11-unix" "$W/m/dev" "$W/m/sys" "$W/m/proc" "$W/m" 2>/dev/null
  rm -rf "$W"
}
trap fim EXIT

Xvfb :77 -screen 0 800x480x24 -dpi 120 -nolisten tcp >/dev/null 2>&1 & XP=$!
sleep 3
print() { DISPLAY=:77 import -window root "$OUT/$1.png" && echo "print: $OUT/$1.png"; }
como() { chroot "$W/m" runuser -u jogador -- env DISPLAY=:77 HOME=/home/jogador LANG=pt_BR.UTF-8 "$@"; }

# so um jogo rodando (SO_JOGO=caminho no rootfs, SO_CORE=nucleo .so): mostra o controle na tela
if [ -n "${SO_JOGO:-}" ]; then
  como retroarch --fullscreen -L "/usr/lib/arm-linux-gnueabihf/libretro/$SO_CORE" "$SO_JOGO" >/dev/null 2>&1 &
  sleep "${ESPERA_RA:-150}"; print "${SO_NOME:-07-jogo}"; exit 0
fi

# 1) modo tablet: sessao XFCE do usuario jogador (com o teclado na tela)
# a sessao completa precisa do logind (lightdm no aparelho); aqui abre as pecas do XFCE uma a uma
chroot "$W/m" install -d -o jogador -g jogador -m 700 /tmp/xdg-jogador
como env XDG_RUNTIME_DIR=/tmp/xdg-jogador dbus-run-session -- sh -c "xfwm4 & xfsettingsd & xfdesktop & xfce4-panel & onboard & sleep 3000" > "$OUT/xfce.log" 2>&1 &
sleep "${ESPERA_XFCE:-240}"
[ -n "${SO_DESKTOP:-}" ] && { print 01-tablet-area-de-trabalho; exit 0; }
print 01-tablet-area-de-trabalho
como xfce4-terminal --geometry=70x16 -e "sh -c 'neofetch 2>/dev/null || (uname -a; free -h; df -h /); sleep 600'" >/dev/null 2>&1 &
sleep 60; print 02-tablet-terminal
como thunar /home/jogador >/dev/null 2>&1 &
sleep 60; print 03-tablet-arquivos
como xfce4-appfinder --collapsed=false >/dev/null 2>&1 &
sleep 60; print 04-tablet-aplicativos
como firefox-esr --new-window about:about >/dev/null 2>&1 &
sleep "${ESPERA_FIREFOX:-180}"; print 05-tablet-firefox
# fecha tudo do tablet
for p in /proc/[0-9]*; do [ "$(readlink $p/root 2>/dev/null)" = "$W/m" ] && kill "${p#/proc/}" 2>/dev/null; done
sleep 5

# 2) modo jogos: RetroArch em tela cheia
como retroarch --fullscreen >/dev/null 2>&1 &
sleep "${ESPERA_RA:-150}"; print 06-jogos-retroarch
