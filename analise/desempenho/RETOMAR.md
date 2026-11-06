# Onde paramos (06/11/2026, 21:00) — otimizacao parte 2

Pausado a pedido do Pedro (GPS ia ser desligado). Estado deixado no GPS: modo jogos, turbo DESLIGADO
(boost=0, max 1008 MHz, nada aprovado em /var/lib/aquarius-turbo).

## Ja feito e provado
- Modo tablet (aquarius-bench-tablet): area de trabalho 45 -> 35 s, usavel 78 -> 57 s, RAM livre 243 -> 281 MB
  (autostart enxuto, compositor do xfwm4 desligado, zram swappiness 150 / page-cluster 0).
- Programas (quente / frio): terminal ~4-6 / 6-9 s, editor ~7-8 / 8-11 s, arquivos ~1 s (Thunar residente),
  Firefox ~46 / 55 s, LibreOffice Writer ~21 / 27 s. GTK3 e Firefox sao limitados pela CPU (perf/strace):
  nao ha espera de disco ou rede para cortar. Prefs leves do Firefox nao mudaram a abertura.
- DTB com 1104 MHz turbo-mode instalado no GPS (sha do arquivo em /boot muda; copia sem turbo em
  /usr/local/share/aquarius/sem-turbo-60hz.dtb). 1104 @ 1,45 V: stress-ng --verify 5 min e memtester 120 MB OK.
  1200 @ 1,5 V errou conta (tirado do DTB e do aquarius-turbo).
- aquarius-turbo + aquarius-turbo.service + aquarius-turbo-confirmar.timer instalados e habilitados no GPS.

## Bateria 5 (parcial, 1008 MHz; /root/bateria5-parcial.txt no GPS)
| nucleo | jogo | fps | CPU |
|---|---|---|---|
| snes9x2005_plus | Pink_Wall | 58,3 / 57,3 | 94 / 90 % |
| snes9x2010 | Pink_Wall | 52,6 / 54,1 | 98 / 97 % |
| mgba | Skyland | 47,5 / 48,4 | 96 / 97 % |
| gpsp | Skyland | 57,9 | 74 % |

## Retomar daqui (nessa ordem)
1. `touch /run/aquarius-trocando; systemctl stop aquarius-retroarch lightdm` e rodar de novo
   `systemd-run --unit=bateria5 --collect bash /root/bateria5.sh` (1008 x 1104 + video_threaded,
   audio_latency 96, audio_resampler_quality 1). Esperar numa sessao SSH so (SSH novo da ruido).
2. Prova da trava do turbo: `aquarius-turbo aprovar 1104000` e reiniciar ANTES de 10 min -> no boot
   seguinte tem que ficar boost=0 e "reprovado-*" em /var/lib/aquarius-turbo. Depois aprovar, esperar
   o confirmar (10 min), reiniciar -> tem que voltar boost=1 em 1104.
3. Estabilidade longa em 1104 (estab1.sh: jogo 30 min, stress-ng 20 min, memtester, disco).
4. Modo tablet em 1104: aquarius-bench-tablet sessao + apps (comparar com os numeros acima).
5. Aplicar os ajustes do RetroArch que provarem ganho; decidir se a imagem sai com turbo aprovado.
6. Pendentes antigos: estabilidade parte 2 (rede, Wi-Fi/vigia, OOM, servicos), volume de volta a 50/63,
   log_verbosity do RetroArch, nucleos proprios na imagem.
