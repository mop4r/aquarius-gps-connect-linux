#!/bin/bash
# 3o passo da imagem (depois de configurar-rootfs.sh e configurar-retroarch.sh): aplica o que o 1o uso
# real do GPS mostrou (04-05/11/2026). Os arquivos vem de novo-so/arquivos-do-aparelho/ (copia fiel do
# aparelho funcionando). Detalhes e motivos: skill aquarius-gps.
# uso: aplicar-ajustes-do-aparelho.sh <rootfs> <pasta arquivos-do-aparelho>
set -euo pipefail
R=${1:?rootfs}; A=${2:?arquivos-do-aparelho}
[ -d "$R/etc" ] && [ -f "$A/usr/local/sbin/aquarius-vbus" ] || { echo "argumento invalido" >&2; exit 1; }
c() { chroot "$R" "$@"; }

# copia fiel (energia, Wi-Fi, botao, RetroArch, touch, som, boot)
cp -a "$A/." "$R/"
chmod 0755 "$R/usr/local/sbin/aquarius-vbus"
c chown -R jogador:jogador /home/jogador

# toque longo = clique direito no X (evdev); ferramentas usadas no diagnostico
DEBIAN_FRONTEND=noninteractive c apt-get install -y --no-install-recommends \
  xserver-xorg-input-evdev i2c-tools gpiod evtest grim x11-apps fio unclutter-xfixes >/dev/null
c glib-compile-schemas /usr/share/glib-2.0/schemas

# energia sem bateria (AXP209 reg 0x30 = 0x43) antes de tudo
c systemctl enable aquarius-vbus.service >/dev/null 2>&1

# servicos que so custam tempo e RAM num GPS (medido: ~20 MB e ~30 s de boot)
c systemctl disable exim4 lm-sensors networking e2scrub_reap avahi-daemon.service avahi-daemon.socket \
  cups.service cups.socket cups.path cups-browsed accounts-daemon udisks2 >/dev/null 2>&1 || true
# 06/11: fwupd (35 MB, 9 s de boot, puxa o udisks2), o gancho de desligamento do unattended-upgrades (21 MB parado;
# a atualizacao segue pelo timer) e timers inuteis. Boot medido: 1 min 34 s -> 51 s.
c systemctl disable unattended-upgrades.service man-db.timer exim4-base.timer e2scrub_all.timer >/dev/null 2>&1 || true
c systemctl mask fwupd.service fwupd-refresh.timer fwupd-refresh.service udisks2.service >/dev/null 2>&1 || true
# kernel calado na tela (a 115200 o console serial atrasava o boot e o texto aparecia por cima do jogo)
sed -i 's/loglevel=[0-9]/quiet loglevel=3/' "$R/etc/default/u-boot"
grep -q 'quiet loglevel=3' "$R/etc/default/u-boot" || { echo "u-boot: loglevel nao trocado" >&2; exit 1; }

# volta automatica (aquarius-vigia + aquarius-tentar) e watchdog de hardware pelo systemd
chmod 0755 "$R/usr/local/sbin/aquarius-vigia" "$R/usr/local/sbin/aquarius-tentar"
c systemctl enable aquarius-vigia.service >/dev/null 2>&1

# atalho "Modo jogos" confiavel: o xfce so aceita marcar com a sessao aberta -> roda no 1o login
install -m 0755 /dev/stdin "$R/usr/local/bin/aquarius-confiar-atalhos" <<'EOF'
#!/bin/sh
# 1o login do XFCE: marca os atalhos da area de trabalho como confiaveis (sem pergunta ao tocar)
for f in "$HOME"/"Área de Trabalho"/*.desktop; do
  [ -f "$f" ] || continue
  chmod +x "$f"
  gio set -t string "$f" metadata::xfce-exe-checksum "$(sha256sum "$f" | cut -d' ' -f1)"
done
rm -f "$HOME/.config/autostart/aquarius-confiar-atalhos.desktop"
EOF
install -d "$R/home/jogador/.config/autostart"
cat > "$R/home/jogador/.config/autostart/aquarius-confiar-atalhos.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Confiar nos atalhos do Aquarius
Exec=/usr/local/bin/aquarius-confiar-atalhos
OnlyShowIn=XFCE;
EOF
sed -i 's/^Icon=retroarch$/Icon=applications-games/' "$R/usr/share/applications/aquarius-modo-jogos.desktop" \
  "$R/home/jogador/Área de Trabalho/aquarius-modo-jogos.desktop" 2>/dev/null || true
c chown -R jogador:jogador /home/jogador

# initramfs com os drivers de video (a tela so funciona assim) e sem diagnostico
rm -f "$R"/etc/initramfs-tools/scripts/init-premount/aquarius-diag "$R"/etc/initramfs-tools/scripts/init-bottom/aquarius-diag
c update-initramfs -u -k all >/dev/null
echo "ajustes do aparelho aplicados"
