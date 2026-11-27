#!/bin/bash
# 3o passo da imagem (depois de configurar-rootfs.sh e configurar-retroarch.sh): aplica o que o 1o uso
# real do GPS mostrou (04-05/11/2026). Os arquivos vem de novo-so/arquivos-do-aparelho/ (copia fiel do
# aparelho funcionando). Detalhes e motivos: skill aquarius-gps.
# uso: aplicar-ajustes-do-aparelho.sh <rootfs> <pasta arquivos-do-aparelho>
set -euo pipefail
# qemu-user trava (futex) no dpkg-deb e em programas com rseq: as mesmas protecoes do montar-rootfs.sh valem em
# toda etapa que roda apt/dpkg no chroot (sem elas o configurar travou duas vezes em 12/11/2026)
export DPKG_DEB_THREADS_MAX=1
export GLIBC_TUNABLES=glibc.pthread.rseq=0
R=${1:?rootfs}; A=${2:?arquivos-do-aparelho}
[ -d "$R/etc" ] && [ -f "$A/usr/local/sbin/aquarius-vbus" ] || { echo "argumento invalido" >&2; exit 1; }
c() { chroot "$R" "$@"; }

# copia fiel (energia, Wi-Fi, botao, RetroArch, touch, som, boot) SEM as permissoes de origem: vinda do Windows
# (/mnt/c) cada arquivo e pasta e 777 com dono uid 1000 = jogador, e o "cp -a" antigo deixava /, /etc, /usr, /var e os
# scripts que rodam como root graváveis pelo jogador (13/11/2026). Agora: dono root, pastas 755, arquivos 644 e 755 so
# para script (#!); o /home/jogador e do jogador. O laco tambem conserta uma raiz ja estragada por uma rodada antiga.
tar -C "$A" -cf - . | tar -C "$R" -xf - --no-same-owner --no-same-permissions
(cd "$A" && find . -mindepth 0) | while IFS= read -r p; do
  d="$R/${p#./}"; [ "$p" = . ] && d=$R
  if [ -d "$d" ] && [ ! -L "$d" ]; then m=0755
  elif [ "$(head -c2 "$d" 2>/dev/null)" = '#!' ]; then m=0755
  else m=0644; fi
  chown -h 0:0 "$d"; [ -L "$d" ] || chmod "$m" "$d"
done
c chown -R jogador:jogador /home/jogador
# conferencia: nada do sistema gravavel por outros nem de dono comum
ruim=$(find "$R" -xdev \( -path "$R/home" -o -path "$R/tmp" -o -path "$R/var/tmp" -o -path "$R/proc" -o -path "$R/sys" -o -path "$R/dev" -o -path "$R/run" \) -prune -o \
  \( -perm -o+w ! -type l ! \( -type d -perm -1000 \) -print \) -o \( -uid 1000 -print \) | head -5)
[ -z "$ruim" ] || { echo "permissao errada na raiz: $ruim" >&2; exit 1; }

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
  # -L tambem: o link aponta para um caminho do aparelho, que visto do host nao existe ([ -e ] da falso e a 2a rodada falhava)
  [ -e "$LR/${n}_libretro.so" ] || [ -L "$LR/${n}_libretro.so" ] || ln -s "/usr/lib/arm-linux-gnueabihf/libretro/${n}_libretro.so" "$LR/${n}_libretro.so"
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
# lightdm.postinst recria display-manager.service a cada upgrade do pacote (27/11/2026);
# 99aquarius-sem-display-manager remove apos cada apt, e garantimos aqui tambem.
rm -f "$R/etc/systemd/system/display-manager.service"
# kernel calado na tela (a 115200 o console serial atrasava o boot e o texto aparecia por cima do jogo)
sed -i -E 's/(quiet )?loglevel=[0-9]/quiet loglevel=3/' "$R/etc/default/u-boot"
grep -q 'quiet loglevel=3' "$R/etc/default/u-boot" || { echo "u-boot: loglevel nao trocado" >&2; exit 1; }

# volta automatica (aquarius-vigia + aquarius-tentar) e watchdog de hardware pelo systemd
chmod 0755 "$R/usr/local/sbin/aquarius-vigia" "$R/usr/local/sbin/aquarius-tentar" "$R/usr/local/sbin/aquarius-config-inicial"
c systemctl enable aquarius-vigia.service >/dev/null 2>&1

# CPU vai ate 1056 MHz @ 1,45 V como OPP nativo do DTB (120/120 OK mesmo em 1,40 V e 75/75 em 1,45 V sob
# GPU 100%, 27/11/2026); 1104 corrompeu >72,7 C, 1152 corrompeu disco e 1200 errou conta. O servico aquarius-turbo
# (antigo toggle de boost 1104) fica desabilitado.
chmod 0755 "$R/usr/local/sbin/aquarius-turbo"
c systemctl disable aquarius-turbo.service aquarius-turbo-confirmar.timer >/dev/null 2>&1 || true
rm -f "$R/var/lib/aquarius-turbo/aprovado" "$R/var/lib/aquarius-turbo/sem-confirmar"

# Wi-Fi: so o rtl8xxxu com o 0bda:8176 (~10x mais rapido que o rtl8192cu, que fica bloqueado), compilado aqui por DKMS
# para o kernel da imagem e, sozinho, para cada kernel novo; sem ele o kernel novo nao vira o padrao do boot
# (etc/kernel/postinst.d/zz-aquarius-wifi). Desde 19/11/2026 (antes a imagem saia com o rtl8192cu).
bash "$(dirname "$0")/wifi-rtl8xxxu/instalar.sh" "$R"

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
