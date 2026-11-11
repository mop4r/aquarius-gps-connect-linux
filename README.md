# Aquarius Connect 5.0 (Guia Quatro Rodas) → console retrô e tablet com Debian

O GPS **Aquarius Connect 5.0** (placa MTC4553, Allwinner **A10** Cortex-A8 a 1 GHz, Mali-400, **512 MB**, tela
800×480 com toque, Wi-Fi RTL8188CUS) vinha com Android 4.0.3 e o iGO 8.4.3. Este repositório tem:

1. **O SO novo** (`novo-so/`): Debian 13 (trixie) armhf rodando de um **microSD separado**, sem tocar na NAND
   do aparelho (tirou o cartão, volta a ser o GPS original). Kernel do Debian com DTS próprio, U-Boot mainline.
2. **A análise do aparelho** (`analise/`): mapa do hardware, porte item a item, desempenho e o receptor GPS.
3. **O backup do cartão original** do iGO (fora do git; descrito no fim).

## O que o GPS faz com o SO novo

| Modo | O que é | Como entra |
|---|---|---|
| **Jogos** (padrão no boot) | RetroArch em tela cheia (cage/Wayland), controle na tela, listas por console | liga o aparelho; ou `aquarius-trocar-modo jogos`; ou o atalho "Modo jogos" no tablet |
| **Tablet** | XFCE com toque (rolagem com o dedo, toque longo = clique direito), NetSurf, arquivos, terminal, editor | sair do RetroArch; ou `aquarius-trocar-modo tablet` |

Jogos: só homebrew de licença livre (`novo-so/jogos-livres/CATALOGO.md`); nenhum ROM comercial no repo.
Acesso: SSH por chave (root) pelo Wi-Fi de casa, configurado na montagem da imagem.

## Desempenho (medido no aparelho, 06–11/11/2026)

| O quê | Antes | Agora |
|---|---|---|
| Processador | 1008 MHz, `schedutil` | **1104 MHz turbo** com `performance` (aprovado por padrão, com trava) |
| SNES pesado (snes9x2010) | 53 fps | **57–60 fps** |
| Área de trabalho do tablet / usável | 45 s / 78 s | **33 s / 54 s** |
| Navegador | Firefox ~45 s para abrir | **NetSurf 4–7 s** (Firefox fica num atalho para sites pesados) |
| LibreOffice Writer (quente) | 21 s | **18 s** |
| Envio do GPS pela rede | 0,2 MB/s | **2–2,9 MB/s** (driver `rtl8xxxu`) |
| Boot | 1 min 34 s | 51 s |

Testado e **reprovado** (não usar): 1152 MHz (corrompe dados gravados no cartão), 1200 MHz (erra conta),
RAM a 480 MHz (trava com a memória cheia; fica 408, o valor de fábrica), `video_threaded` do RetroArch
(trava o jogo), RetroArch direto no DRM sem o cage (perde quadros). Detalhes e números:
`analise/desempenho/RETOMAR.md`.

### Turbo (1104 MHz) e a trava

- O DTB lista 1104 MHz como `turbo-mode`. O kernel só usa com `boost=1`, e todo boot **começa em até 1008**.
- O serviço `aquarius-turbo` liga o turbo no boot (com governador `performance`: o `schedutil` ignora o turbo)
  **só se aprovado** em `/var/lib/aquarius-turbo/aprovado`. A imagem sai aprovada em 1104.
- **Trava:** cada boot com turbo precisa ficar 9 min de pé para confirmar (timer de 11 min). Se o GPS travar ou
  reiniciar antes, o boot seguinte desaprova sozinho e fica em 1008.
- Comandos: `aquarius-turbo estado | aprovar 1104000 | desligar`.

### Volta automática (`aquarius-vigia`)

- Sem roteador por 5 min → reinicia a rede; por 15 min → reinicia o aparelho (no máximo 3 seguidos).
- Mudança arriscada: `aquarius-tentar inicio "<descrição>" <arquivos>` antes de mexer. Se rede ou SSH ficarem
  5 min fora (antes ou depois de reiniciar), o vigia devolve os arquivos e reinicia; 10 min saudável confirma.
- Watchdog de hardware pelo systemd (12 s). Não cobre `/boot`, kernel, DTB nem U-Boot: esses só com cópia guardada.

### Wi-Fi

O `aquarius-wifi-driver` (chamado pelo modprobe no lugar do `rtl8192cu`) usa o `rtl8xxxu` compilado com o id
`0bda:8176` quando o kernel em uso tem esse módulo, e senão o `rtl8192cu`: atualização de kernel nunca deixa o GPS
sem Wi-Fi. Recompilar para um kernel novo, no próprio GPS: `novo-so/build/wifi-rtl8xxxu/compilar.sh`.

## Montar a imagem do cartão

No WSL (Ubuntu), como root, com `qemu-user-static` (binfmt) e o toolchain `arm-linux-gnueabihf`:

1. `novo-so/build/montar-rootfs.sh <pasta>`: Debian 13 armhf mínimo.
2. `novo-so/build/configurar-rootfs.sh <pasta> <dtb> <chave-ssh.pub> < credenciais`: rede, usuários, boot. Os
   segredos (`WIFI_SSID=`, `WIFI_PSK=`, `ROOT_SENHA=`, `JOGADOR_SENHA=`) entram pela entrada padrão, nunca em argumento.
3. `novo-so/build/configurar-retroarch.sh <pasta> novo-so/build [novo-so/jogos-livres]`: modo jogos.
4. `novo-so/build/aplicar-ajustes-do-aparelho.sh <pasta> novo-so/arquivos-do-aparelho`: tudo o que o uso real
   provou (energia, toque, som, vigia, turbo, Wi-Fi, NetSurf, núcleos). Exige os núcleos compilados em
   `novo-so/nucleos-compilados/` (fora do git; `compilar-nucleos.sh`), conferidos contra
   `novo-so/nucleos-compilados.sha256`.
5. `novo-so/build/montar-imagem.sh <pasta> <u-boot-sunxi-with-spl.bin> <saida.img>`: U-Boot no setor 16,
   `AQ-BOOT` (FAT32, `/boot`) e `AQ-ROOT` (ext4, `/`, cresce até o fim do cartão no 1º boot).

U-Boot: mainline v2025.10 com `novo-so/u-boot/Aquarius_MTC4553_defconfig` (DRAM do fex: 408 MHz) e o DTS de
`novo-so/dts/`. Testar antes no QEMU: `novo-so/build/testar-qemu.sh`.

**Gravar:** gravar primeiro o corpo da imagem e por último o 1º MiB (MBR + U-Boot), e conferir lendo de volta.
O Windows monta as partições no meio da gravação: tirar as letras antes (`mountvol`).

## Pastas

| Pasta | Conteúdo |
|---|---|
| `novo-so/build/` | scripts da imagem, `bench/` (medidores `aquarius-bench` e `aquarius-bench-tablet`), `estabilidade/`, `wifi-rtl8xxxu/` |
| `novo-so/arquivos-do-aparelho/` | cópia fiel dos arquivos ajustados no GPS funcionando (entram na imagem) |
| `novo-so/dts/`, `novo-so/u-boot/` | device tree da placa e configuração do U-Boot |
| `novo-so/jogos-livres/` | catálogo dos jogos homebrew livres (os arquivos de jogo ficam fora do git) |
| `analise/` | hardware (`hardware.md`), porte (`mapa-port.md`), `desempenho/`, receptor `gps/`, `script.fex` de fábrica, logs |

## O cartão original do iGO (backup de 2026-11-03)

O cartão de 2 GB (FAT16) que estava no GPS tinha o **iGO My Way 8.4.3** (motor Amigo, Android) com o mapa do
Brasil de 2013-09, radares de 2013, relevo 3D, POIs, voz PT-BR e as **licenças travadas ao aparelho**
(`license/device.nng` e `.lic`). Imagem bruta (`sd-card-dump/`, sha256 `ABCFED9C…F8FC`) e cópia dos arquivos
(`arquivos/iGO/`, 266 arquivos, 0 falhas) ficam **fora do git**. O Windows só não dava letra à partição; o cartão
estava bom. O `dd` teve alguns erros de leitura em espaço livre, sem afetar arquivo nenhum.

**Restaurar:** `dd if=aquarius-connect-5pol-full.img of=/dev/sdX bs=4M` num cartão vazio.

**Atualizar mapa/radares (no modo GPS original):** o aparelho é offline. O Naviextras Toolbox oficial
normalmente não reconhece este rebrand e o update grátis expirou. Na prática: trocar `content/map/Brazil.fbl`
por um mapa compatível com o motor **Amigo 8.4.3** (mapa de iGO Primo/NextGen não roda) e atualizar
`content/speedcam/speedcam.txt` (radares em texto). Com o backup, dá para testar à vontade.
