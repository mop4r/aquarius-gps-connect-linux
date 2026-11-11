#!/bin/bash
# Compila no proprio GPS o rtl8xxxu do kernel 6.12.115 com o id 0bda:8176 (Wi-Fi interno RTL8188CUS) e instala em
# /lib/modules/<kernel>/updates. Quem escolhe o driver no boot e o /usr/local/sbin/aquarius-wifi-driver: sem este
# modulo (kernel novo ainda nao compilado) ele carrega o rtl8192cu de sempre.
# Medido em 11/11/2026: GPS -> rede 0,2 -> 2 MB/s (rtl8192cu -> rtl8xxxu); rx 19-39 -> 65 Mbit/s.
# uso (root, no GPS): compilar.sh [pasta-de-trabalho]   precisa de linux-headers-$(uname -r), gcc, make, wget e rede.
# Kernel diferente do 6.12.x: troque TAG e refaca fontes-<TAG>.sha256 conferindo o diff do driver.
set -euo pipefail
export LC_ALL=C
[ "$(id -u)" = 0 ] || { echo "rode como root" >&2; exit 2; }
TAG=v6.12.115
AQUI=$(cd "$(dirname "$0")" && pwd); LISTA="$AQUI/fontes-$TAG.sha256"
V=$(uname -r); KB=/lib/modules/$V/build
[ -f "$LISTA" ] || { echo "falta $LISTA" >&2; exit 2; }
[ -d "$KB" ] || { echo "falta linux-headers-$V (apt-get install linux-headers-$V)" >&2; exit 2; }
W=${1:-/root/rtl8xxxu}; rm -rf "$W"; mkdir -p "$W"
URL=https://raw.githubusercontent.com/gregkh/linux/$TAG/drivers/net/wireless/realtek/rtl8xxxu
while read -r _ f; do
  [[ $f =~ ^[A-Za-z0-9_.]+$ ]] || { echo "nome invalido na lista: $f" >&2; exit 2; }
  # wget: o Debian do GPS nao traz curl (11/11/2026). O conteudo e conferido pelo sha256 logo abaixo.
  wget -q --https-only --timeout=60 --tries=3 -O "$W/$f" "$URL/$f" || { echo "falhou baixar $f" >&2; exit 1; }
done < "$LISTA"
(cd "$W" && sha256sum --strict --quiet -c "$LISTA") || { echo "fontes nao batem com $LISTA" >&2; exit 1; }
printf '\n# GPS Aquarius: liga a tabela com o 0bda:8176, que o probe ja considera testado\nccflags-y += -DCONFIG_RTL8XXXU_UNTESTED\n' >> "$W/Makefile"
make -C "$KB" M="$W" CONFIG_RTL8XXXU=m modules >"$W/compilar.log" 2>&1 || { echo "falhou a compilacao (veja $W/compilar.log)" >&2; exit 1; }
modinfo "$W/rtl8xxxu.ko" | grep -qi '^alias:.*v0BDAp8176' || { echo "modulo sem o id 0bda:8176" >&2; exit 1; }
install -d "/lib/modules/$V/updates"; install -m 0644 "$W/rtl8xxxu.ko" "/lib/modules/$V/updates/rtl8xxxu.ko"; depmod -a "$V"
echo "instalado: $(modinfo -n -k "$V" rtl8xxxu) (vale no proximo boot)"
