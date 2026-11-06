#!/bin/bash
# Bateria de estabilidade, parte 1 (sem reinicio e sem derrubar a rede). Roda como unidade systemd no GPS.
# Antes: touch /run/aquarius-trocando; systemctl stop aquarius-retroarch lightdm; unidade estab-monitor de pe.
# Saida: /root/estab/estab1.txt (resumo) e /root/estab/*.log
export LC_ALL=C
E=/root/estab; mkdir -p "$E"; R=$E/estab1.txt
J=/home/jogador/Jogos
log() { echo "$(date +%T) $*" >> "$R"; }
erros_kernel() { journalctl -k -b --since "$1" --no-pager -p warning 2>/dev/null | grep -viE "aquarius-vbus" | tail -5; }

log "== inicio; uptime $(cut -d. -f1 /proc/uptime) s"

# T1: jogo pesado (SNES Pink_Wall, snes9x2005_plus) por 30 min, como o modo jogos roda (cage, vsync, som)
t0=$(date '+%F %T'); s0=$(date +%s)
CFG=$(mktemp /tmp/estab.XXXXXX.cfg); cp /home/jogador/.config/retroarch/retroarch.cfg "$CFG"
sed -i -e '/^config_save_on_exit = /d' -e '/^log_verbosity = /d' "$CFG"
printf '%s\n' 'config_save_on_exit = "false"' 'log_verbosity = "false"' >> "$CFG"; chown jogador: "$CFG"; chmod 600 "$CFG"
timeout 2400 systemd-run --quiet --wait --collect -p User=jogador -p PAMName=login -p TTYPath=/dev/tty1 \
  -p StandardInput=tty -p StandardOutput=journal -p StandardError=journal \
  -E XDG_RUNTIME_DIR=/run/user/1000 -E LIBSEAT_BACKEND=seatd -E HOME=/home/jogador \
  /usr/bin/cage -s -- /usr/bin/retroarch -L /usr/local/lib/libretro/snes9x2005_plus_libretro.so \
  --config "$CFG" --max-frames=108000 "$J/SNES/Pink_Wall.sfc" >/dev/null 2>&1
rc=$?; dt=$(( $(date +%s) - s0 )); rm -f "$CFG"
log "T1 jogo 108000 quadros: rc=$rc em ${dt}s (ideal ~1810 s; $(awk -v d=$dt 'BEGIN{printf "%.1f", 108000/(d-12)}') fps medio)"
erros_kernel "$t0" | sed 's/^/   kernel: /' >> "$R"

# T2: CPU com verificacao de resultado, todos os metodos, 20 min
t0=$(date '+%F %T')
stress-ng --cpu 1 --cpu-method all --verify --timeout 20m --metrics-brief > "$E/t2-stress.log" 2>&1
log "T2 stress-ng cpu verify 20 min: rc=$? $(grep -iE 'fail|error|passed|successful' "$E/t2-stress.log" | tail -2 | tr '\n' ' ')"
erros_kernel "$t0" | sed 's/^/   kernel: /' >> "$R"

# T3: memoria (memtester, 2 passadas no que estiver livre menos folga)
livre=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo); tam=$(( livre - 90 ))
[ "$tam" -gt 300 ] && tam=300
t0=$(date '+%F %T')
memtester "${tam}M" 2 > "$E/t3-memtester.log" 2>&1
log "T3 memtester ${tam} MB x2: rc=$? $(grep -ciE 'FAILURE' "$E/t3-memtester.log") falha(s)"
erros_kernel "$t0" | sed 's/^/   kernel: /' >> "$R"

# T4: disco (ext4 do cartao): 400 MB aleatorios, sha256, solta o cache, le de novo
t0=$(date '+%F %T'); s0=$(date +%s)
head -c 400M /dev/urandom > "$E/t4.bin"; sync; a=$(sha256sum "$E/t4.bin" | cut -c1-64)
echo 3 > /proc/sys/vm/drop_caches; b=$(sha256sum "$E/t4.bin" | cut -c1-64); rm -f "$E/t4.bin"
log "T4 disco 400 MB: $([ "$a" = "$b" ] && echo IGUAL || echo DIFERENTE) em $(( $(date +%s) - s0 ))s"
erros_kernel "$t0" | sed 's/^/   kernel: /' >> "$R"

log "== fim; temp max cpu $(awk -F, 'NR>1&&$3!="NA"{if($3>m)m=$3}END{print m/1000}' "$E/monitor.csv") C, usb min $(awk -F, 'NR>1&&$6!="NA"{if(m==""||$6<m)m=$6}END{print m}' "$E/monitor.csv") mV"
