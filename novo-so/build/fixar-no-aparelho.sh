#!/bin/bash
# Deixa permanentes no GPS (rodando) as correcoes achadas no 1o boot real (04/11/2026).
# Roda como root no aparelho. Idempotente.
set -euo pipefail
V=$(uname -r)

# 1) Energia: sem bateria, tirar o limite de corrente da VBUS (AXP209 reg 0x30 bits 1:0 = 11)
install -m 0755 /dev/stdin /usr/local/sbin/aquarius-vbus <<'EOF'
#!/bin/sh
# Sem bateria, o limite padrao da VBUS derruba o GPS quando o Wi-Fi liga o radio.
# O Android de fabrica usava pmu_usbcur_limit=0 (sem limite). O AXP so aparece no I2C ~37 s.
diz() { echo "aquarius-vbus: $*" > /dev/kmsg; }
i=0; a=
while [ $i -lt 90 ]; do
  modprobe i2c-dev 2>/dev/null
  a=$(i2cget -f -y 0 0x34 0x30 2>/dev/null) && break
  i=$((i + 1)); sleep 1
done
[ -n "$a" ] || { diz "reg 0x30 nao leu em 90 s"; exit 0; }
i2cset -f -y 0 0x34 0x30 $(( (a & 0xC4) | 0x03 ))  # sem limite + V_HOLD 4,0 V (Android: pmu_usbvol=4000)
diz "reg 0x30 antes=$a depois=$(i2cget -f -y 0 0x34 0x30) (espera ${i}s)"
EOF
cat > /etc/systemd/system/aquarius-vbus.service <<'EOF'
[Unit]
Description=AXP209: tira o limite de corrente da USB (como o Android de fabrica)
DefaultDependencies=no
After=systemd-modules-load.service
Before=sysinit.target NetworkManager.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/aquarius-vbus

[Install]
WantedBy=sysinit.target
EOF
install -d /etc/systemd/system/NetworkManager.service.d
printf '[Unit]\nAfter=aquarius-vbus.service\nWants=aquarius-vbus.service\n' > /etc/systemd/system/NetworkManager.service.d/vbus.conf

# 2) Wi-Fi com potencia menor (10 dBm): menos pico de corrente
cat > /etc/udev/rules.d/90-aquarius-wifi.rules <<'EOF'
ACTION=="add", SUBSYSTEM=="net", KERNEL=="wlan*", RUN+="/bin/sh -c 'sleep 2; iw dev %k set txpower fixed 1000'"
EOF

# 3) Sair do RetroArch = modo tablet (qualquer saida que nao seja troca pedida); fechar rapido
install -d /etc/systemd/system/aquarius-retroarch.service.d
cat > /etc/systemd/system/aquarius-retroarch.service.d/sair-vai-para-tablet.conf <<'EOF'
[Service]
# o cage sai com codigo diferente de 0 ao fechar o RetroArch: nao depender do resultado
Restart=no
TimeoutStopSec=8
ExecStopPost=+/bin/sh -c '[ -e /run/aquarius-trocando ] || systemctl start --no-block lightdm.service'
EOF

# 4) Som: liga o amplificador e a saida do DAC e guarda (alsa-restore aplica a cada boot)
amixer -c 0 -q sset 'Power Amplifier DAC' on
amixer -c 0 -q sset 'Power Amplifier Mute' on
amixer -c 0 -q sset 'Power Amplifier' 80%
amixer -c 0 -q sset 'Left Mixer Left DAC' on 2>/dev/null || true
amixer -c 0 -q sset 'Right Mixer Right DAC' on 2>/dev/null || true
alsactl store 0

# 5) Boot: sem AppArmor (2,5 min a menos no A10); sem o diagnostico do initramfs
sed -i 's/^U_BOOT_PARAMETERS="\(.*\)loglevel=7"$/U_BOOT_PARAMETERS="\1loglevel=4 apparmor=0"/' /etc/default/u-boot
rm -f /etc/initramfs-tools/scripts/init-premount/aquarius-diag /etc/initramfs-tools/scripts/init-bottom/aquarius-diag
grep -qx sun4i_drm /etc/initramfs-tools/modules || printf '%s\n' sun4i_drm sun4i_backend sun4i_tcon pwm_sun4i pwm_bl panel_simple >> /etc/initramfs-tools/modules
update-initramfs -u -k "$V"
u-boot-update

systemctl daemon-reload
systemctl enable aquarius-vbus.service
echo "== conferencia"
grep append /boot/extlinux/extlinux.conf | head -1
systemctl is-enabled aquarius-vbus
amixer -c 0 sget 'Power Amplifier' | tail -1
