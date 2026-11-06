"""Testes do gerador de listas (escolha do nucleo). Rodar: python -I -m unittest novo-so/build/test_aquarius_listas_jogos.py"""
import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

AQUI = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("listas", AQUI / "aquarius-listas-jogos.py")
listas = importlib.util.module_from_spec(spec)
spec.loader.exec_module(listas)


class EscolhaDoNucleo(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.local = base / "local"; self.debian = base / "debian"
        self.local.mkdir(); self.debian.mkdir()
        self.casa = base / "casa"
        self.p = mock.patch.object(listas, "PASTAS_NUCLEOS", (str(self.local), str(self.debian)))
        self.p.start()

    def tearDown(self):
        self.p.stop(); self.tmp.cleanup()

    def toca(self, pasta, nome):
        (pasta / nome).write_bytes(b"\x7fELF")

    def test_prefere_o_otimizado_em_local(self):
        self.toca(self.local, "gpsp_libretro.so"); self.toca(self.debian, "mgba_libretro.so")
        self.assertEqual(listas.escolher_nucleo(listas.CONSOLES["GBA"][1]),
                         (str(self.local / "gpsp_libretro.so"), "gpSP"))

    def test_mesmo_nucleo_nas_duas_pastas_usa_o_de_local(self):
        self.toca(self.local, "gambatte_libretro.so"); self.toca(self.debian, "gambatte_libretro.so")
        self.assertEqual(listas.escolher_nucleo(listas.CONSOLES["GB"][1])[0], str(self.local / "gambatte_libretro.so"))

    def test_volta_para_o_do_debian_sem_o_otimizado(self):
        self.toca(self.debian, "mgba_libretro.so")
        self.assertEqual(listas.escolher_nucleo(listas.CONSOLES["GBA"][1]),
                         (str(self.debian / "mgba_libretro.so"), "mGBA"))

    def test_sem_nenhum_nucleo_devolve_none(self):
        self.assertIsNone(listas.escolher_nucleo(listas.CONSOLES["SNES"][1]))

    def test_lista_gerada_aponta_para_o_nucleo_escolhido_e_omite_console_sem_emulador(self):
        self.toca(self.local, "snes9x2005_plus_libretro.so")
        (self.casa / "Jogos" / "SNES").mkdir(parents=True)
        (self.casa / "Jogos" / "SNES" / "a.sfc").write_bytes(b"x")
        (self.casa / "Jogos" / "NES").mkdir(parents=True)
        (self.casa / "Jogos" / "NES" / "b.nes").write_bytes(b"x")   # sem emulador de NES instalado
        with mock.patch.dict(os.environ, {"HOME": str(self.casa)}):
            self.assertEqual(listas.main(), 0)
        pl = self.casa / ".config" / "retroarch" / "playlists"
        snes = json.loads((pl / "Nintendo - Super Nintendo Entertainment System.lpl").read_text(encoding="utf-8"))
        self.assertEqual(snes["default_core_path"], str(self.local / "snes9x2005_plus_libretro.so"))
        self.assertEqual(snes["items"][0]["core_name"], "Snes9x 2005 Plus")
        self.assertFalse((pl / "Nintendo - Nintendo Entertainment System.lpl").exists())


if __name__ == "__main__":
    unittest.main()
