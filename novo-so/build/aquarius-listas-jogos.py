#!/usr/bin/python3 -I
"""Monta as listas de jogos do RetroArch a partir de ~/Jogos/<console>.

Roda antes de cada abertura do modo jogos (ExecStartPre do aquarius-retroarch.service), como o
usuario jogador. Jogo copiado para a pasta do console aparece na lista sem escanear nada no menu.
Cada lista ja vem ligada ao emulador do console (core_path/core_name), entao o jogo abre direto.
"""
import json
import os
import sys
from pathlib import Path

# Nucleos compilados para o Cortex-A8/NEON (build/compilar-nucleos.sh) ficam em /usr/local; os do Debian sao a reserva.
# Medido em 06/11/2026 (skill aquarius-gps, references/desempenho.md): snes9x do Debian dava 36-51 fps no SNES e mgba 49
# no Skyland; snes9x2005_plus e gpsp seguram 58-60 com folga.
PASTAS_NUCLEOS = ("/usr/local/lib/libretro", "/usr/lib/arm-linux-gnueabihf/libretro")
GENESIS = (("picodrive_libretro.so", "PicoDrive"), ("genesis_plus_gx_libretro.so", "Genesis Plus GX"))

# pasta -> (lista do RetroArch, nucleos em ordem de preferencia (arquivo, nome), extensoes)
CONSOLES = {
    "NES": ("Nintendo - Nintendo Entertainment System",
            (("fceumm_libretro.so", "FCEUmm"), ("nestopia_libretro.so", "Nestopia")), {".nes", ".fds", ".unf", ".unif"}),
    "SNES": ("Nintendo - Super Nintendo Entertainment System",
             (("snes9x2005_plus_libretro.so", "Snes9x 2005 Plus"), ("snes9x_libretro.so", "Snes9x")),
             {".sfc", ".smc", ".fig", ".swc", ".bs"}),
    "MegaDrive": ("Sega - Mega Drive - Genesis", GENESIS, {".md", ".gen", ".smd", ".bin"}),
    "MasterSystem": ("Sega - Master System - Mark III", GENESIS, {".sms"}),
    "GameGear": ("Sega - Game Gear", GENESIS, {".gg"}),
    "GB": ("Nintendo - Game Boy", (("gambatte_libretro.so", "Gambatte"),), {".gb"}),
    "GBC": ("Nintendo - Game Boy Color", (("gambatte_libretro.so", "Gambatte"),), {".gbc"}),
    "GBA": ("Nintendo - Game Boy Advance", (("gpsp_libretro.so", "gpSP"), ("mgba_libretro.so", "mGBA")), {".gba"}),
    "NDS": ("Nintendo - Nintendo DS", (("desmume_libretro.so", "DeSmuME"),), {".nds"}),
}


def escolher_nucleo(opcoes):
    """Primeiro nucleo da lista que existe, procurando em /usr/local antes do Debian; None se nenhum existe."""
    for arquivo, nome in opcoes:
        for pasta in PASTAS_NUCLEOS:
            caminho = Path(pasta) / arquivo
            if caminho.is_file():
                return str(caminho), nome
    return None


COMPACTADOS = {".zip", ".7z"}
MAX_JOGOS = 2000          # por console: lista enorme deixa o menu lento no A10
MAX_TAMANHO = 512 << 20   # nada desses consoles passa disso; acima e lixo


def jogos(pasta: Path, extensoes):
    achados = []
    if not pasta.is_dir():
        return achados
    for raiz, dirs, arquivos in os.walk(pasta, followlinks=False):
        if len(Path(raiz).relative_to(pasta).parts) >= 1:  # no maximo 1 nivel de subpasta
            dirs[:] = []
        dirs[:] = sorted(d for d in dirs if not d.startswith("."))
        for nome in sorted(arquivos):
            p = Path(raiz) / nome
            ext = p.suffix.lower()
            if nome.startswith(".") or (ext not in extensoes and ext not in COMPACTADOS):
                continue
            try:
                if not p.is_file() or p.is_symlink() or p.stat().st_size > MAX_TAMANHO:
                    continue
            except OSError:
                continue
            achados.append(p)
            if len(achados) >= MAX_JOGOS:
                return achados
    return achados


def lista(nome_lista, core_path, core_nome, arquivos):
    return {
        "version": "1.5",
        "default_core_path": core_path,
        "default_core_name": core_nome,
        "label_display_mode": 0,
        "right_thumbnail_mode": 0,
        "left_thumbnail_mode": 0,
        "sort_mode": 0,
        "items": [
            {
                "path": str(a),
                "label": a.stem,
                "core_path": core_path,
                "core_name": core_nome,
                "crc32": "DETECT",
                "db_name": f"{nome_lista}.lpl",
            }
            for a in arquivos
        ],
    }


def main():
    casa = Path(os.environ.get("HOME") or Path.home())
    raiz = casa / "Jogos"
    destino = casa / ".config" / "retroarch" / "playlists"
    destino.mkdir(parents=True, exist_ok=True)
    total = 0
    for pasta, (nome_lista, opcoes, extensoes) in CONSOLES.items():
        (raiz / pasta).mkdir(parents=True, exist_ok=True)
        nucleo = escolher_nucleo(opcoes)
        arquivos = jogos(raiz / pasta, extensoes)
        alvo = destino / f"{nome_lista}.lpl"
        if not arquivos or nucleo is None:
            alvo.unlink(missing_ok=True)  # console sem jogo (ou sem emulador) nao aparece no menu
            if arquivos:
                print(f"{pasta}: nenhum emulador instalado, lista omitida", file=sys.stderr)
            continue
        core_path, core_nome = nucleo
        tmp = alvo.with_suffix(".lpl.tmp")
        tmp.write_text(json.dumps(lista(nome_lista, core_path, core_nome, arquivos), ensure_ascii=False, indent=2), encoding="utf-8")
        tmp.replace(alvo)
        total += len(arquivos)
        print(f"{pasta}: {len(arquivos)} jogo(s) -> {core_nome}")
    print(f"listas prontas: {total} jogo(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
