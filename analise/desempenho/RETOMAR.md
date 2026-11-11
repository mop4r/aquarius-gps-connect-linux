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

## Retomada 10/11/2026 (noite, Pedro dormindo: seguir sozinho ate o fim)
- Bateria 5 refeita, 1008 x 1104 MHz (2 rodadas): SNES 2005_plus 57,0/56,4 x 57,1/58,8; snes9x2010 52,7/53,1 x
  53,5/52,6; mgba 49,3/49,0 x 48,1/34,4 (ponto fora?); gpsp 58,2/56,7 x 58,0/60,7. Turbo SEM ganho medido ate aqui.
- `video_threaded = "true"` TRAVA o RetroArch (4,7 fps, nao sai). Nunca ligar. O jogo travado ficou segurando a tela
  e os testes seguintes deram erro; limpeza: `pkill -9 retroarch; pkill -9 cage`.
- aquarius-bench corrigido NO REPO (unidade com nome fixo + limpa): falta instalar no GPS e testar, depois commit.
- Bateria 6 (/root/bateria6.sh -> /root/bateria6.txt): mgba e snes9x2010 x3 a 1104 e x3 a 1008, frequencia real
  durante o jogo (cpuinfo_cur_freq, time_in_state), depois audio_latency 96 e audio_resampler_quality 1.
  Se a sessao cair: ler /root/bateria6.txt e seguir do passo 2 abaixo (o passo 1 fica feito com ela).

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

## Lista de 10/11 noite (pedido do Pedro: "o maximo de performance"; os que precisam dele perto por ultimo)
Feito em 10/11: turbo 1104 real (performance), trava provada nas duas pontas, estabilidade longa a 1104 OK, tablet a 1104,
log do RetroArch desligado, aquarius-bench derruba jogo travado.
Sem risco (sozinho, medir cada um):
1. Jogos em DRM/KMS direto sem o cage (KMS=1 no aquarius-bench) x cage: fps e CPU.
2. Driver de som do RetroArch (alsa, alsathread, tinyalsa...): fps e CPU.
3. Cartao: ext4 com noatime e commit maior (fstab: coberto pelo vigia? NAO, aquarius-tentar recusa /boot; fstab e raiz).
4. Navegador leve (Netsurf/Dillo) alem do Firefox, com atalho; medir abertura.
5. Rede: RetroArch parado em transferencia, cifra do SSH (chacha20/aes128-ctr), por que rx cai a MCS 2 com -29 dBm.
6. Estabilidade parte 2: OOM x watchdog, queda do Wi-Fi + vigia (com rede de volta agendada por seguranca).
Com o Pedro perto (copia do arquivo antigo, um por vez):
7. mitigations=off na linha do kernel (Spectre v2 no A8).
8. 1152 MHz @ 1,5 V (entre 1104 ok e 1200 que errou).
9. DRAM mais rapida no U-Boot (unico caminho para o mgba); se falhar o GPS nao liga -> regravar o cartao no PC.

## Estado em 11/11/2026 ~00:40 (parte sem risco FEITA)
- Turbo: o schedutil nao usava o 1104; agora aquarius-turbo liga performance. APROVADO e confirmado neste GPS.
  Trava provada (reboot sem confirmar -> 1008 e reprovado; confirmado -> volta 1104). Confirmar exige 9 min de turbo.
- Bateria 7 (clock real): snes9x2010 53 -> 57 fps; 2005_plus ~57 -> ~59; mgba e gpsp sem ganho claro.
- Estabilidade longa a 1104: tudo OK, max 72 C. Tablet a 1104: LibreOffice 21 -> 18 s, terminal ~4 s, area de trabalho 33 s.
- Bateria 8: cage+alsa (atual) e o melhor; KMS direto, alsathread, nearest, 32 kHz: nao.
- Navegador: NetSurf padrao (4-7 s) e Firefox em atalho (41-51 s). Log do RetroArch desligado no GPS.
- Rede: integra; lenta por TX do driver rtl8192cu (CPU ociosa, cifra nao e o gargalo).
- Estabilidade parte 2: OOM -> kernel mata so o guloso, sem reboot; RetroArch caiu (SIGSEGV) e foi ao tablet. Queda de Wi-Fi
  -> vigia reiniciou a rede aos 303 s, sem reboot.
- Nucleos compilados entram na imagem conferidos por sha256 (79d3f86).
- spectre_v2 "Not affected": mitigations=off sai da lista.
Falta (com o Pedro perto, um por vez, com copia):
  a. 1152 MHz @ 1,5 V (entre 1104 ok e 1200 que errou): DTB novo + mesma bateria de estabilidade.
  b. DRAM mais rapida no U-Boot (unico caminho para o mgba); se falhar o GPS nao liga -> regravar o cartao.
  c. Driver rtl8xxxu com o id 0bda:8176 (compilar modulo) para a rede do GPS ao PC.
Opcional: religar o RetroArch se ele cair por sinal (hoje vai ao tablet); volume de volta a 50/63 quando o Pedro pedir.

## 11/11/2026 madrugada, com o Pedro perto (os 3 itens feitos)
- Wi-Fi rtl8xxxu (b42f0c3): GPS -> rede ~10x mais rapido; vigia confirmou. Em observacao: caiu 2x durante memtester
  (uma a 480 MHz de DRAM e outra com um laco meu de SSH sem pausa); na estabilidade longa a 1152, 0 falhas de ping.
- DRAM 480 MHz: REPROVADA (travou sob memtester; nem o watchdog voltou). Volta a 408 pelo leitor do PC (/dev/sdf).
- CPU 1152 MHz: REPROVADO (corrompe dados gravados no cartao em 2 de 3). DTB de volta ao de 1104; fsck forcado: limpo.
- Turbo 1104 reaprovado (a trava tinha desaprovado sozinha depois do boot que travou a 480).
Nao ha mais item de desempenho pendente. Opcional: religar o RetroArch se cair por sinal; volume 50/63 quando pedir.

## 11/11/2026 manhã (fechamento)
- Volume de volta ao normal no GPS (Power Amplifier 50/63, `alsactl store`; igual ao asound.state do repo).
- A imagem nova sai com o turbo 1104 APROVADO (aplicar-ajustes-do-aparelho.sh grava /var/lib/aquarius-turbo/aprovado);
  o 1o boot nao reinicia (o resize2fs e online), entao a trava nao desaprova a toa.
- README da raiz reescrito para o projeto inteiro (SO novo, desempenho, turbo, vigia, Wi-Fi, montagem da imagem).
