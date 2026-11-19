#!/bin/bash
# Testa a imagem do GPS no QEMU (-M cubieboard = Allwinner A10, 512 MB como o aparelho).
# A copia de teste ganha a EMAC (rede que o QEMU emula; o GPS real nao tem) e o sun4i_ss desligado
# (o QEMU nao emula o motor de cripto e o autoteste trava). A imagem original nao e alterada.
# uso: testar-qemu.sh <imagem.img> <dtb-base.dts-dir> <saida-log>   < chave privada ssh (stdin)
set -euo pipefail
IMG=${1:?imagem}; DTSDIR=${2:?pasta com dts/ e src/linux}; LOG=${3:?log}
T=$(mktemp -d); trap 'kill "$(cat "$T/qemu.pid" 2>/dev/null)" 2>/dev/null || true; rm -rf "$T"' EXIT
umask 077; cat > "$T/chave"; umask 022
grep -q "PRIVATE KEY" "$T/chave" || { echo "chave invalida na entrada" >&2; exit 1; }

cp --sparse=always "$IMG" "$T/teste.img"; truncate -s 8G "$T/teste.img"
L=$DTSDIR/src/linux
cat "$DTSDIR/dts/sun4i-a10-aquarius-mtc4553.dts" - > "$T/teste.dts" <<'EOF'
&emac { phy-handle = <&phy1>; status = "okay"; };
&emac_sram { status = "okay"; };
&mdio { status = "okay"; phy1: ethernet-phy@1 { reg = <1>; }; };
EOF
cpp -nostdinc -undef -D__DTS__ -x assembler-with-cpp -I "$L/include" -I "$L/arch/arm/boot/dts/allwinner" \
  -I "$L/scripts/dtc/include-prefixes" -I "$DTSDIR/dts" "$T/teste.dts" -o "$T/teste.pre"
dtc -q -I dts -O dtb -o "$T/teste.dtb" "$T/teste.pre"
export MTOOLS_SKIP_CHECK=1; P="$T/teste.img@@1048576"
DTBP=$(mtype -i "$P" ::/extlinux/extlinux.conf | sed -n 's/^\tfdt //p' | head -1)
mcopy -o -i "$P" "$T/teste.dtb" "::$DTBP"
# qualquer loglevel (a imagem sai com "quiet loglevel=3": o "s/loglevel=7/" antigo nao casava, o sun4i_ss ficava ligado
# e o kernel reiniciava em laco sem mensagem, 13/11/2026); kernel falante na serial do teste
mtype -i "$P" ::/extlinux/extlinux.conf | sed -E 's/ quiet / /; s/loglevel=[0-9]/loglevel=7 modprobe.blacklist=sun4i_ss,sunxi_wdt/' > "$T/ext.conf"
# sunxi_wdt: o watchdog (systemd, 12 s; no GPS real provado) estourava no QEMU lento do 1o boot e reiniciava a VM
grep -q 'modprobe.blacklist=sun4i_ss' "$T/ext.conf" || { echo "FALHA: nao consegui desligar o sun4i_ss no extlinux" >&2; exit 1; }
mcopy -o -i "$P" "$T/ext.conf" ::/extlinux/extlinux.conf

qemu-system-arm -M cubieboard -m 512 -display none -daemonize -pidfile "$T/qemu.pid" \
  -drive if=sd,format=raw,file="$T/teste.img" -serial file:"$LOG" \
  -nic user,hostfwd=tcp:127.0.0.1:2222-:22
S="ssh -i $T/chave -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes root@127.0.0.1"
for i in $(seq 1 90); do $S true 2>/dev/null && break; sleep 10; done
$S true 2>/dev/null || { echo "FALHA: SSH nao respondeu em 15 min"; exit 1; }
echo "== SSH ok (chave-casa) apos ~$((i*10)) s"
$S 'echo "== kernel"; uname -r; echo "== modelo"; tr -d "\0" < /proc/device-tree/model; echo
    echo "== falhas"; systemctl --failed --no-legend
    for u in aquarius-modo aquarius-expandir aquarius-relatorio aquarius-sshkeys NetworkManager zramswap unattended-upgrades.service ssh seatd; do printf "%-24s %s\n" $u "$(systemctl is-active $u)"; done
    echo "== modo"; journalctl -b -u aquarius-modo --no-pager | grep -E "modo escolhido" ; systemctl is-active aquarius-retroarch lightdm
    echo "== disco"; df -h / /boot | tail -2; ls /var/lib/aquarius-expandido
    echo "== zram"; swapon --show
    echo "== senha ssh desligada"; sshd -T 2>/dev/null | grep -E "^(passwordauthentication|permitrootlogin)"
    echo "== nm"; nmcli -t -f NAME,TYPE con show
    echo "== atualizacao"; apt-config dump | grep -c "Unattended-Upgrade::Origins-Pattern::"; apt-config dump | grep Automatic-Reboot
    echo "== drivers"; lsmod | grep -E -c "sun4i_drm|edt_ft5x06|axp20x|sun4i_codec|rtl8xxxu|sun4i_lradc|lima|pwm_sun4i"
    echo "== troca de modo"; aquarius-trocar-modo tablet; sleep 20; systemctl is-active lightdm aquarius-retroarch
    aquarius-trocar-modo jogos; sleep 10; systemctl is-active lightdm aquarius-retroarch
    echo "== relatorio"; ls /boot/logs/ 2>&1
    echo "== aquarius.txt (imagem generica: tem de ter sido aplicado e apagado)"; ls /boot/aquarius*.txt 2>&1
    journalctl -b -u aquarius-config-inicial --no-pager -o cat | grep config-inicial
    echo "== vigia"; journalctl -b -u aquarius-vigia --no-pager -o cat | tail -3
    echo "== turbo"; aquarius-turbo estado
    echo "== wi-fi: rtl8xxxu por dkms com o 0bda:8176 (espera 1) e rtl8192cu bloqueado (espera install /bin/false)"
    modinfo rtl8xxxu | grep -ci "^alias:.*v0BDAp8176"; modinfo -n rtl8xxxu; modprobe -n -v rtl8192cu 2>&1 | tail -1; dkms status
    echo "== certificado snakeoil refeito no 1o boot (espera o arquivo)"; ls /etc/ssl/private/ssl-cert-snakeoil.key 2>&1
    echo "== atualizacao ociosa (espera 5 = idle)"; systemctl show apt-daily-upgrade.service -p CPUSchedulingPolicy
    echo "== sistema gravavel por outros ou do uid 1000 fora do /home (espera 0)"
    find / -xdev \( -path /home -o -path /tmp -o -path /var/tmp \) -prune -o \( -perm -o+w ! -type l ! \( -type d -perm -1000 \) -print \) -o \( -uid 1000 -print \) 2>/dev/null | wc -l'
