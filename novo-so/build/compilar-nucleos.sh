#!/bin/bash
# Compila (cruzado, no WSL) os nucleos libretro para o GPS: Cortex-A8, NEON, hard-float.
# Antes: baixar-nucleos.sh. Saida: <destino>/<nucleo>_libretro.so (sem simbolos).
# uso: compilar-nucleos.sh <destino> [nucleo...]
set -euo pipefail
OUT=${1:?destino}; shift; mkdir -p "$OUT"
D=${NUCLEOS_SRC:-$HOME/aquarius-nucleos}
X=arm-linux-gnueabihf-
P=armv-cortexa8-neon-hardfloat
J=$(nproc)
mk() {  # mk <pasta> <makefile> [args extra]
  local r=$1 m=$2; shift 2
  make -C "$D/$r" -f "$m" clean >/dev/null 2>&1 || true
  make -C "$D/$r" -f "$m" -j"$J" platform="$P" CC=${X}gcc CXX=${X}g++ AR=${X}ar LD=${X}g++ "$@" >"$OUT/$r.log" 2>&1 \
    || { echo "FALHOU $r (veja $OUT/$r.log)"; return 0; }
  local so; so=$(ls -t "$D/$r"/*_libretro.so 2>/dev/null | head -1)
  [ -n "$so" ] || { echo "FALHOU $r: sem .so"; return 0; }
  ${X}strip -o "$OUT/$(basename "$so")" "$so"
  echo "ok $r -> $(basename "$so") $(stat -c %s "$OUT/$(basename "$so")") bytes"
}
LISTA=${*:-snes9x2005 snes9x2010 gpsp picodrive libretro-fceumm gambatte-libretro}
for n in $LISTA; do
  case $n in
    snes9x2005) mk snes9x2005 Makefile USE_BLARGG_APU=1 ;;   # "plus": APU mais fiel
    snes9x2010) mk snes9x2010 Makefile.libretro ;;
    gpsp)       mk gpsp Makefile HAVE_DYNAREC=1 CPU_ARCH=arm ;;
    picodrive)  mk picodrive Makefile.libretro ;;
    libretro-fceumm) mk libretro-fceumm Makefile.libretro ;;
    gambatte-libretro) mk gambatte-libretro Makefile.libretro ;;
    *) echo "nucleo desconhecido: $n" ;;
  esac
done
