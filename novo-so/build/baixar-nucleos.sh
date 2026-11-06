#!/bin/bash
# Baixa (ou atualiza) o codigo dos nucleos libretro rapidos para o GPS (Cortex-A8) em ~/aquarius-nucleos (WSL)
# e imprime o commit de cada um. Fonte: github.com/libretro (oficial).
set -euo pipefail
D=${1:-$HOME/aquarius-nucleos}; mkdir -p "$D"; cd "$D"
for r in snes9x2005 snes9x2010 gpsp picodrive libretro-fceumm gambatte-libretro mgba; do
  [ -d "$r" ] || git clone -q --depth 1 --recurse-submodules --shallow-submodules "https://github.com/libretro/$r.git"
  echo "$r $(git -C "$r" rev-parse HEAD)"
done
