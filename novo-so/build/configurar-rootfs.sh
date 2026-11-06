#!/bin/bash
# Configura o rootfs montado por montar-rootfs.sh para o GPS Aquarius.
# uso: configurar-rootfs.sh <rootfs> <dtb> <chave-ssh.pub>  < credenciais (WIFI_SSID=, WIFI_PSK=, ROOT_SENHA=, JOGADOR_SENHA=)
# Os segredos chegam pela entrada padrao: nunca em argumento, nunca impressos.
set -euo pipefail

R=${1:?rootfs}; DTB=${2:?dtb}; PUB=${3:?chave publica}
[ -d "$R/etc" ] && [ -f "$DTB" ] && [ -f "$PUB" ] || { echo "argumento invalido" >&2; exit 1; }

WIFI_SSID=; WIFI_PSK=; ROOT_SENHA=; JOGADOR_SENHA=
while IFS='=' read -r k v; do
  v=${v%$'\r'}
  case "$k" in
    WIFI_SSID) WIFI_SSID=$v ;; WIFI_PSK) WIFI_PSK=$v ;; ROOT_SENHA) ROOT_SENHA=$v ;;
    JOGADOR_SENHA) JOGADOR_SENHA=$v ;;
  esac
done
for n in WIFI_SSID WIFI_PSK ROOT_SENHA JOGADOR_SENHA; do
  v=${!n}
  [ -n "$v" ] || { echo "falta $n na entrada" >&2; exit 1; }
  [ ${#v} -le 63 ] || { echo "$n longo demais" >&2; exit 1; }
  case "$v" in *'"'*|*'\'*) echo "$n tem aspas ou barra invertida" >&2; exit 1 ;; esac
done
[ ${#WIFI_PSK} -ge 8 ] || { echo "WIFI_PSK curta demais" >&2; exit 1; }
grep -qE '^ssh-ed25519 [A-Za-z0-9+/=]+( .*)?$' "$PUB" || { echo "chave publica invalida" >&2; exit 1; }

c() { chroot "$R" "$@"; }

# --- identidade e idioma
echo aquarius > "$R/etc/hostname"
printf '127.0.0.1\tlocalhost\n127.0.1.1\taquarius\n' > "$R/etc/hosts"
sed -i 's/^# *pt_BR.UTF-8/pt_BR.UTF-8/; s/^# *en_US.UTF-8/en_US.UTF-8/' "$R/etc/locale.gen"
c locale-gen >/dev/null
echo 'LANG=pt_BR.UTF-8' > "$R/etc/default/locale"
ln -sf /usr/share/zoneinfo/America/Sao_Paulo "$R/etc/localtime"; echo America/Sao_Paulo > "$R/etc/timezone"

# --- particoes: p1 FAT = /boot (U-Boot le daqui), p2 ext4 = /
cat > "$R/etc/fstab" <<'EOF'
LABEL=AQ-ROOT  /      ext4  defaults,noatime,commit=60  0 1
LABEL=AQ-BOOT  /boot  vfat  defaults,umask=0077         0 2
EOF

# --- boot: u-boot-menu gera /boot/extlinux/extlinux.conf a cada kernel novo
DEBIAN_FRONTEND=noninteractive c apt-get install -y --no-install-recommends u-boot-menu >/dev/null
cat > "$R/etc/default/u-boot" <<'EOF'
U_BOOT_UPDATE="true"
U_BOOT_PROMPT="1"
U_BOOT_TIMEOUT="10"
U_BOOT_ROOT="root=LABEL=AQ-ROOT"
U_BOOT_PARAMETERS="rootfstype=ext4 rootwait rw console=ttyS0,115200 console=tty1 net.ifnames=0 panic=10 loglevel=7"
U_BOOT_FDT="aquarius/sun4i-a10-aquarius-mtc4553.dtb"
U_BOOT_FDT_DIR="/dtbs/"
EOF
# Com /boot em particao propria, o u-boot-update procura /boot/dtbs/<versao>/<U_BOOT_FDT>.
# O DTB da placa fica guardado no rootfs e o hook abaixo o copia para cada kernel instalado.
install -D -m 0644 "$DTB" "$R/usr/local/share/aquarius/sun4i-a10-aquarius-mtc4553.dtb"
install -D -m 0755 /dev/stdin "$R/etc/kernel/postinst.d/zz-aquarius-dtb" <<'EOF'
#!/bin/sh
# $1 = versao do kernel; roda antes do zz-u-boot-menu (ordem alfabetica)
install -D -m 0644 /usr/local/share/aquarius/sun4i-a10-aquarius-mtc4553.dtb \
  "/boot/dtbs/$1/aquarius/sun4i-a10-aquarius-mtc4553.dtb"
EOF
for v in $(ls "$R/usr/lib/modules"); do
  install -D -m 0644 "$DTB" "$R/boot/dtbs/$v/aquarius/sun4i-a10-aquarius-mtc4553.dtb"
done

# modulos que o initramfs precisa para achar o cartao e mostrar a tela cedo
for m in sunxi_mmc axp20x_i2c axp20x_regulator; do
  grep -qx "$m" "$R/etc/initramfs-tools/modules" || echo "$m" >> "$R/etc/initramfs-tools/modules"
done

# --- rede: NetworkManager (o modo tablet escolhe Wi-Fi pela tela); rede da casa ja configurada
DEBIAN_FRONTEND=noninteractive c apt-get install -y --no-install-recommends network-manager >/dev/null
rm -f "$R"/etc/wpa_supplicant/wpa_supplicant-wlan0.conf "$R"/etc/systemd/network/30-wlan0.network
c systemctl disable systemd-networkd wpa_supplicant@wlan0 >/dev/null 2>&1 || true
install -d -m 700 "$R/etc/NetworkManager/system-connections"
umask 077
cat > "$R/etc/NetworkManager/system-connections/casa.nmconnection" <<EOF
[connection]
id=casa
type=wifi
autoconnect=true
autoconnect-priority=10

[wifi]
mode=infrastructure
ssid=$WIFI_SSID

[wifi-security]
key-mgmt=wpa-psk
psk=$WIFI_PSK

[ipv4]
method=auto
dhcp-hostname=aquarius

[ipv6]
method=auto
EOF
umask 022
chmod 600 "$R/etc/NetworkManager/system-connections/casa.nmconnection"
c systemctl enable NetworkManager systemd-resolved systemd-timesyncd >/dev/null 2>&1
ln -sf /run/systemd/resolve/stub-resolv.conf "$R/etc/resolv.conf"

# --- SSH: so a chave-casa; root com senha so no console local
install -d -m 700 "$R/root/.ssh"
install -m 600 "$PUB" "$R/root/.ssh/authorized_keys"
cat > "$R/etc/ssh/sshd_config.d/10-aquarius.conf" <<'EOF'
PermitRootLogin prohibit-password
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF
printf 'root:%s\n' "$ROOT_SENHA" | c chpasswd
# chaves de host novas no primeiro boot (a imagem nao carrega chave de host fixa)
rm -f "$R"/etc/ssh/ssh_host_*
install -m 0644 /dev/stdin "$R/etc/systemd/system/aquarius-sshkeys.service" <<'EOF'
[Unit]
Description=Gera chaves de host do SSH no primeiro boot
Before=ssh.service
ConditionPathExists=!/etc/ssh/ssh_host_ed25519_key

[Service]
Type=oneshot
ExecStart=/usr/bin/ssh-keygen -A

[Install]
WantedBy=multi-user.target
EOF
c systemctl enable aquarius-sshkeys ssh >/dev/null 2>&1

# --- primeiro boot: aumenta a particao raiz ate o fim do cartao
install -m 0755 /dev/stdin "$R/usr/local/sbin/aquarius-expandir" <<'EOF'
#!/bin/sh
set -e
dev=$(findmnt -no SOURCE /)            # ex.: /dev/mmcblk0p2
disk=/dev/$(lsblk -no PKNAME "$dev")
echo ", +" | sfdisk --no-reread --force -N 2 "$disk"
partx -u "$disk"
resize2fs "$dev"
touch /var/lib/aquarius-expandido
EOF
install -m 0644 /dev/stdin "$R/etc/systemd/system/aquarius-expandir.service" <<'EOF'
[Unit]
Description=Expande a particao raiz ate o fim do cartao (uma vez)
ConditionPathExists=!/var/lib/aquarius-expandido
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/aquarius-expandir

[Install]
WantedBy=multi-user.target
EOF
c systemctl enable aquarius-expandir >/dev/null 2>&1

# --- log de cada boot no FAT (/boot/logs), legivel no PC se a rede nao subir
install -m 0755 /dev/stdin "$R/usr/local/sbin/aquarius-relatorio" <<'EOF'
#!/bin/sh
# Relatorio de hardware do boot atual em /boot/logs/boot-<n>.txt (mantem os 10 ultimos)
mkdir -p /boot/logs
n=$(ls /boot/logs 2>/dev/null | sed -n 's/^boot-\([0-9]*\)\.txt$/\1/p' | sort -n | tail -1)
n=$(( ${n:-0} + 1 ))
f=/boot/logs/boot-$n.txt
{
  echo "== $(date -Is) boot $n"; uname -a
  echo "== ip";        ip -br addr; iw dev 2>&1
  echo "== modulos";   lsmod
  echo "== entrada";   cat /proc/bus/input/devices
  echo "== drm";       ls -l /dev/dri 2>&1; cat /sys/class/drm/*/status 2>&1
  echo "== backlight"; for b in /sys/class/backlight/*; do echo "$b $(cat $b/brightness)/$(cat $b/max_brightness)"; done
  echo "== energia";   for p in /sys/class/power_supply/*; do echo "$p: $(cat $p/type) online=$(cat $p/online 2>/dev/null) cap=$(cat $p/capacity 2>/dev/null)"; done
  echo "== som";       cat /proc/asound/cards
  echo "== iio";       for d in /sys/bus/iio/devices/*; do echo "$d $(cat $d/name 2>/dev/null)"; done
  echo "== i2c";       for d in /sys/bus/i2c/devices/*-*; do echo "$d $(cat $d/name 2>/dev/null)"; done
  echo "== usb";       lsusb 2>&1
  echo "== falhas";    systemctl --failed --no-legend
  echo "== dmesg";     dmesg
  echo "== journal";   journalctl -b --no-pager -p warning
} > "$f" 2>&1
ls /boot/logs | sort -t- -k2 -n | head -n -10 | sed 's|^|/boot/logs/|' | xargs -r rm -f
sync
EOF
install -m 0644 /dev/stdin "$R/etc/systemd/system/aquarius-relatorio.service" <<'EOF'
[Unit]
Description=Relatorio de hardware do boot em /boot/logs
After=multi-user.target network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 45
ExecStart=/usr/local/sbin/aquarius-relatorio

[Install]
WantedBy=multi-user.target
EOF
c systemctl enable aquarius-relatorio >/dev/null 2>&1

# --- interface: RetroArch em tela cheia (cage, Wayland) como usuario sem privilegio
c useradd -m -s /bin/bash -G video,render,input,audio jogador 2>/dev/null || true
install -m 0644 /dev/stdin "$R/etc/systemd/system/aquarius-retroarch.service" <<'EOF'
[Unit]
Description=RetroArch em tela cheia no LCD
After=systemd-user-sessions.service seatd.service
Wants=seatd.service
Conflicts=getty@tty1.service

[Service]
User=jogador
PAMName=login
TTYPath=/dev/tty1
StandardInput=tty
Environment=XDG_RUNTIME_DIR=/run/user/1000
Environment=LIBSEAT_BACKEND=seatd
ExecStartPre=+/bin/sh -c 'mkdir -p /run/user/1000 && chown jogador: /run/user/1000 && chmod 700 /run/user/1000'
ExecStart=/usr/bin/cage -s -- /usr/bin/retroarch
Restart=on-failure
RestartSec=5
# parar o modo jogos (troca de modo) termina o cage por SIGTERM: isso nao e falha
SuccessExitStatus=143 SIGTERM

EOF
# sair do RetroArch pelo menu dele = ir para o modo tablet (sem mudar o modo padrao do boot)
install -d "$R/etc/systemd/system/aquarius-retroarch.service.d"
cat > "$R/etc/systemd/system/aquarius-retroarch.service.d/sair-vai-para-tablet.conf" <<'EOF'
[Service]
ExecStopPost=+/bin/sh -c '[ "$SERVICE_RESULT" = success ] && [ ! -e /run/aquarius-trocando ] && systemctl start --no-block lightdm.service || true'
EOF

# --- modo tablet: area de trabalho completa (XFCE, ajustada para toque)
DEBIAN_FRONTEND=noninteractive c apt-get install -y task-xfce-desktop lightdm onboard \
  gnome-software packagekit firefox-esr firefox-esr-l10n-pt-br xserver-xorg-input-libinput \
  zram-tools network-manager-gnome lxpolkit xfce4-goodies >/dev/null
# zram: memoria comprimida (512 MB de RAM e desktop completo)
printf 'ALGO=zstd\nPERCENT=75\nPRIORITY=100\n' > "$R/etc/default/zramswap"
# autologin do jogador na sessao XFCE
install -d "$R/etc/lightdm/lightdm.conf.d"
cat > "$R/etc/lightdm/lightdm.conf.d/50-aquarius.conf" <<'EOF'
[Seat:*]
autologin-user=jogador
autologin-user-timeout=0
user-session=xfce
EOF
c groupadd -f autologin; c usermod -aG autologin,sudo,netdev jogador
printf 'jogador:%s\n' "$JOGADOR_SENHA" | c chpasswd
# Tela de 5" com 800x480: DPI maior, painel e icones grandes para o dedo
J="$R/home/jogador/.config/xfce4/xfconf/xfce-perchannel-xml"; install -d "$J"
cat > "$J/xsettings.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Xft" type="empty"><property name="DPI" type="int" value="120"/></property>
  <property name="Gtk" type="empty"><property name="CursorThemeSize" type="int" value="32"/></property>
</channel>
EOF
# lancadores "Modo jogos" no menu e na area de trabalho
install -m 0644 /dev/stdin "$R/usr/share/applications/aquarius-modo-jogos.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Modo jogos
Comment=Fecha a area de trabalho e abre o RetroArch em tela cheia
Exec=sudo /usr/local/sbin/aquarius-trocar-modo jogos
Icon=retroarch
Categories=Game;
EOF
install -d "$R/home/jogador/Área de Trabalho"
cp "$R/usr/share/applications/aquarius-modo-jogos.desktop" "$R/home/jogador/Área de Trabalho/"
chmod +x "$R/home/jogador/Área de Trabalho/aquarius-modo-jogos.desktop"
# a area de trabalho do XFCE e a pasta XDG_DESKTOP_DIR: fixa em portugues desde o 1o login
install -d "$R/home/jogador/.config"
cat > "$R/home/jogador/.config/user-dirs.dirs" <<'EOF'
XDG_DESKTOP_DIR="$HOME/Área de Trabalho"
XDG_DOWNLOAD_DIR="$HOME/Downloads"
XDG_DOCUMENTS_DIR="$HOME/Documentos"
XDG_PICTURES_DIR="$HOME/Imagens"
XDG_MUSIC_DIR="$HOME/Música"
XDG_VIDEOS_DIR="$HOME/Vídeos"
EOF
echo pt_BR > "$R/home/jogador/.config/user-dirs.locale"
# teclado na tela: comeca escondido e aparece sozinho ao tocar num campo de texto (icone no painel)
cat > "$R/usr/share/glib-2.0/schemas/90-aquarius.gschema.override" <<'EOF'
[org.onboard]
start-minimized=true
show-status-icon=true

[org.onboard.auto-show]
enabled=true

# o auto-show do onboard depende da acessibilidade do GNOME (sem isso ele pergunta a cada login)
[org.gnome.desktop.interface]
toolkit-accessibility=true
EOF
c glib-compile-schemas /usr/share/glib-2.0/schemas
c chown -R jogador:jogador /home/jogador

# --- troca de modo: /boot/modo.txt (padrao do boot), botao MENU segurado no boot inverte, troca ao vivo
install -m 0755 /dev/stdin "$R/usr/local/sbin/aquarius-trocar-modo" <<'EOF'
#!/bin/sh
# uso: aquarius-trocar-modo jogos|tablet [--padrao]   (--padrao tambem grava em /boot/modo.txt)
set -e
case "$1" in jogos|tablet) ;; *) echo "uso: $0 jogos|tablet [--padrao]" >&2; exit 2 ;; esac
[ "$2" = "--padrao" ] && { echo "$1" > /boot/modo.txt; sync; }
touch /run/aquarius-trocando
if [ "$1" = jogos ]; then
  systemctl stop lightdm.service; systemctl start aquarius-retroarch.service
else
  systemctl stop aquarius-retroarch.service; systemctl start lightdm.service
fi
rm -f /run/aquarius-trocando
EOF
echo 'jogador ALL=(root) NOPASSWD: /usr/local/sbin/aquarius-trocar-modo' > "$R/etc/sudoers.d/aquarius-modo"
chmod 440 "$R/etc/sudoers.d/aquarius-modo"
install -m 0755 /dev/stdin "$R/usr/local/sbin/aquarius-modo-boot" <<'EOF'
#!/bin/sh
# Escolhe o modo no boot: /boot/modo.txt (jogos|tablet, padrao jogos); MENU segurado inverte.
modo=$(tr -dc 'a-z' < /boot/modo.txt 2>/dev/null)
case "$modo" in jogos|tablet) ;; *) modo=jogos ;; esac
for ev in /dev/input/by-path/*lradc*-event*; do
  [ -e "$ev" ] || continue
  # evtest --query sai com 10 quando a tecla esta apertada
  evtest --query "$ev" EV_KEY KEY_MENU; [ $? -eq 10 ] && { [ $modo = jogos ] && modo=tablet || modo=jogos; }
done
echo "modo escolhido: $modo"
if [ $modo = tablet ]; then systemctl start --no-block lightdm.service
else systemctl start --no-block aquarius-retroarch.service; fi
EOF
install -m 0644 /dev/stdin "$R/etc/systemd/system/aquarius-modo.service" <<'EOF'
[Unit]
Description=Escolhe o modo (jogos ou tablet) e abre a interface
After=systemd-user-sessions.service systemd-udev-settle.service seatd.service
Wants=seatd.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/aquarius-modo-boot

[Install]
WantedBy=graphical.target
EOF
echo jogos > "$R/boot/modo.txt"
# ninguem sobe a interface sozinho: so o aquarius-modo decide
c systemctl disable lightdm aquarius-retroarch >/dev/null 2>&1 || true
rm -f "$R/etc/systemd/system/display-manager.service"
c usermod -aG video jogador
c systemctl enable seatd aquarius-modo zramswap >/dev/null 2>&1
c systemctl set-default graphical.target >/dev/null 2>&1

# --- atualizacao automatica de tudo (Debian, seguranca, kernel, RetroArch), como no .5 e na TV box
DEBIAN_FRONTEND=noninteractive c apt-get install -y --no-install-recommends unattended-upgrades apt-listchanges >/dev/null
cat > "$R/etc/apt/apt.conf.d/20auto-upgrades" <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
cat > "$R/etc/apt/apt.conf.d/52unattended-aquarius" <<'EOF'
// Tudo do Debian trixie, nao so seguranca
Unattended-Upgrade::Origins-Pattern {
        "origin=Debian,codename=${distro_codename},label=Debian";
        "origin=Debian,codename=${distro_codename}-updates,label=Debian";
        "origin=Debian,codename=${distro_codename}-security,label=Debian-Security";
};
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
// Kernel novo pede reinicio: reinicia de madrugada
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:30";
EOF

# --- gera initramfs e extlinux.conf com o kernel instalado
c update-initramfs -u -k all >/dev/null
# o extlinux.conf definitivo e gerado pelo montar-imagem.sh, com a FAT montada em /boot
echo "configurado: $(ls "$R"/boot/vmlinuz-* | xargs -n1 basename)"
