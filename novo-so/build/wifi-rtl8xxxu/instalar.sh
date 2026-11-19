#!/bin/bash
# Instala o driver rapido do Wi-Fi interno (rtl8xxxu com o id 0bda:8176 do RTL8188CUS) por DKMS: compila para todo
# kernel instalado agora e, sozinho, para cada kernel novo que a atualizacao trouxer. O rtl8192cu (lento: 0,2 MB/s
# contra 2-2,9 MB/s, medido em 11/11/2026) fica bloqueado pelo /etc/modprobe.d/aquarius-wifi.conf.
# Fonte: drivers/net/wireless/realtek/rtl8xxxu do kernel v6.12.115 (gregkh/linux), copia fiel em fonte/ conferida
# por fontes-v6.12.115.sha256; a unica mudanca e ligar CONFIG_RTL8XXXU_UNTESTED (a tabela com o 0bda:8176).
# uso: instalar.sh [raiz]   sem raiz = este sistema (no GPS, como root); com raiz = rootfs da imagem (chroot, qemu-user)
set -euo pipefail
export LC_ALL=C DPKG_DEB_THREADS_MAX=1 GLIBC_TUNABLES=glibc.pthread.rseq=0   # qemu-user (ver montar-rootfs.sh)
[ "$(id -u)" = 0 ] || { echo "rode como root" >&2; exit 2; }
R=${1:-}; [ -z "$R" ] || [ -d "$R/etc" ] || { echo "raiz invalida: $R" >&2; exit 2; }
c() { if [ -n "$R" ]; then chroot "$R" "$@"; else "$@"; fi; }
AQUI=$(cd "$(dirname "$0")" && pwd)
N=rtl8xxxu-aquarius; V=6.12.115; D=$R/usr/src/$N-$V

(cd "$AQUI/fonte" && sha256sum --strict --quiet -c "$AQUI/fontes-v$V.sha256") || { echo "fonte/ nao bate com fontes-v$V.sha256" >&2; exit 1; }

# kernels instalados (pasta de modulos com o modules.dep do pacote, nao sobra de kernel removido)
mapfile -t KS < <(cd "$R/usr/lib/modules" && for k in *; do [ -f "$k/modules.order" ] && echo "$k"; done)
[ ${#KS[@]} -gt 0 ] || { echo "nenhum kernel instalado em $R/usr/lib/modules" >&2; exit 1; }
HS=(); for k in "${KS[@]}"; do [[ $k =~ ^[0-9][0-9a-z.+~-]*$ ]] || { echo "versao de kernel estranha: $k" >&2; exit 1; }; HS+=("linux-headers-$k"); done
# linux-headers-armmp acompanha o kernel nas atualizacoes: e o que deixa o DKMS compilar o proximo sozinho
DEBIAN_FRONTEND=noninteractive c apt-get install -y --no-install-recommends dkms linux-headers-armmp "${HS[@]}"

rm -rf "$D"; install -d -m 0755 "$D"; install -m 0644 "$AQUI"/fonte/* "$D/"
printf '\n# GPS Aquarius: liga a tabela com o 0bda:8176 (RTL8188CUS interno)\nccflags-y += -DCONFIG_RTL8XXXU_UNTESTED\n' >> "$D/Makefile"
cat > "$D/dkms.conf" <<EOF
PACKAGE_NAME="$N"
PACKAGE_VERSION="$V"
BUILT_MODULE_NAME[0]="rtl8xxxu"
DEST_MODULE_LOCATION[0]="/updates/dkms"
MAKE[0]="make -C \${kernel_source_dir} M=\${dkms_tree}/\${PACKAGE_NAME}/\${PACKAGE_VERSION}/build CONFIG_RTL8XXXU=m modules"
CLEAN="make -C \${kernel_source_dir} M=\${dkms_tree}/\${PACKAGE_NAME}/\${PACKAGE_VERSION}/build clean"
AUTOINSTALL="yes"
EOF
c dkms remove -m "$N" -v "$V" --all >/dev/null 2>&1 || true
c dkms add -m "$N" -v "$V"

# o modulo antigo, compilado a mao (sem DKMS), e o seletor que caia no rtl8192cu saem
rm -f "$R"/usr/lib/modules/*/updates/rtl8xxxu.ko "$R/usr/local/sbin/aquarius-wifi-driver"
for k in "${KS[@]}"; do
  c dkms install -m "$N" -v "$V" -k "$k" --force -j "$(nproc --ignore=1 2>/dev/null | awk '{print ($1>4)?4:$1}')"   # no chroot o nproc e o do PC (32 gcc emulados)
  # saida inteira numa variavel antes de procurar: "modinfo | grep -q" com pipefail da falso mesmo achando (o grep -q
  # fecha o pipe no 1o acerto e o modinfo morre de SIGPIPE), foi o que falhou na 1a montagem em 19/11/2026
  info=$(c modinfo -k "$k" rtl8xxxu)
  grep -qi '^alias:.*v0BDAp8176' <<<"$info" || { echo "kernel $k: rtl8xxxu sem o 0bda:8176" >&2; exit 1; }
  echo "kernel $k: $(c modinfo -k "$k" -n rtl8xxxu)"
done
bloq=$(c modprobe -n -v rtl8192cu 2>&1 || true)
grep -q '/bin/false' <<<"$bloq" || echo "aviso: rtl8192cu ainda nao bloqueado (falta /etc/modprobe.d/aquarius-wifi.conf)" >&2
echo "rtl8xxxu por DKMS instalado (${#KS[@]} kernel(s)); vale no proximo boot"
