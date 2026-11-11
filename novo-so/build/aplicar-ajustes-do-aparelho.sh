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

# toque longo = clique direito no X (evdev); ferramentas usadas no diagnostico; netsurf-gtk = navegador padrao do
# tablet (abre em ~5 s; o Firefox leva ~45 s e fica num atalho "sites completos"), medido em 10/11/2026
DEBIAN_FRONTEND=noninteractive c apt-get install -y --no-install-recommends \
  xserver-xorg-input-evdev i2c-tools gpiod evtest grim x11-apps fio unclutter-xfixes netsurf-gtk >/dev/null
c glib-compile-schemas /usr/share/glib-2.0/schemas

# nucleos compilados para o Cortex-A8 (compilar-nucleos.sh / no GPS), os mesmos medidos no aparelho: vem de
# novo-so/nucleos-compilados/ (fora do git) e tem de bater com novo-so/nucleos-compilados.sha256. Os outros sao
# atalhos para os do Debian. O RetroArch e o aquarius-listas-jogos procuram primeiro em /usr/local/lib/libretro.
NC=$(cd "$A/.." && pwd)/nucleos-compilados
[ -f "$NC.sha256" ] && [ -d "$NC" ] || { echo "faltam os nucleos compilados em $NC (veja $NC.sha256)" >&2; exit 1; }
(cd "$NC" && sha256sum --strict --quiet -c "$NC.sha256") || { echo "nucleos compilados nao batem com $NC.sha256" >&2; exit 1; }
LR="$R/usr/local/lib/libretro"; install -d -m 0755 "$LR"
while read -r _ so; do
  [[ $so =~ ^[a-z0-9_]+_libretro\.so$ ]] || { echo "nome de nucleo invalido em $NC.sha256" >&2; exit 1; }
  install -m 0644 "$NC/$so" "$LR/$so"
done < "$NC.sha256"
for n in desmume gambatte genesis_plus_gx mgba nestopia snes9x; do
  [ -e "$LR/${n}_libretro.so" ] || ln -s "/usr/lib/arm-linux-gnueabihf/libretro/${n}_libretro.so" "$LR/${n}_libretro.so"
done

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

# turbo 1104 MHz (turbo-mode no DTB) com governador performance: so liga com /var/lib/aquarius-turbo/aprovado, e
# desaprova sozinho se um boot com turbo nao confirmar (9 min de turbo; timer em 11 min). Desde 11/11/2026 a imagem
# sai APROVADA (1104 provado: estabilidade longa, disco, trava nas duas pontas; o 1o boot nao reinicia).
# 1152 e 1200 NAO: corrompem dados / erram conta. Para sair sem turbo: aquarius-turbo desligar.
chmod 0755 "$R/usr/local/sbin/aquarius-turbo"
c systemctl enable aquarius-turbo.service aquarius-turbo-confirmar.timer >/dev/null 2>&1
install -d -m 0755 "$R/var/lib/aquarius-turbo"
echo 1104000 > "$R/var/lib/aquarius-turbo/aprovado"; rm -f "$R/var/lib/aquarius-turbo/sem-confirmar"

# Wi-Fi: o modprobe chama o aquarius-wifi-driver no lugar do rtl8192cu; ele usa o rtl8xxxu com o id 0bda:8176 se o
# kernel tiver o modulo (novo-so/build/wifi-rtl8xxxu/compilar.sh, no GPS) e senao o rtl8192cu: a imagem sai funcionando
# com o driver antigo e fica ~10x mais rapida de enviar depois de compilar.
chmod 0755 "$R/usr/local/sbin/aquarius-wifi-driver"
install -d "$R/usr/local/share/aquarius/wifi-rtl8xxxu"
install -m 0755 "$(dirname "$0")/wifi-rtl8xxxu/compilar.sh" "$R/usr/local/share/aquarius/wifi-rtl8xxxu/compilar.sh"
install -m 0644 "$(dirname "$0")"/wifi-rtl8xxxu/fontes-*.sha256 "$R/usr/local/share/aquarius/wifi-rtl8xxxu/"

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
