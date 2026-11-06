# Hardware — Aquarius Connect 5.0 / Guia Quatro Rodas

Fontes: fotos do "Sobre" (2026-11-03) e **recon por ADB pela rede** (2026-11-03,
`analise/recon-adb.txt`, `analise/script.fex` decodificado do `script.bin` da partição `nanda`).
Legenda: **[obs]** visto no aparelho · **[inf]** inferência.

| Item | Valor | |
|---|---|---|
| Modelo | **MTC4553** (fabricante "Aquarius", marca `softwinners`) | [obs] |
| SoC | **Allwinner A10 (sun4i)**, Cortex-A8 ARMv7, NEON/VFPv3, ~1 GHz | [obs] `/proc/cpuinfo` |
| GPU | Mali-400 (`mali_used = 1`) | [obs] |
| RAM | **512 MB**, DRAM a 408 MHz | [obs] |
| Armazenamento | NAND ~8 GB (partições `nanda`…`nandi`, ver abaixo) + slot microSD (`mmc0`) | [obs] |
| Tela | **800x480**, LCD RGB paralelo (`lcd_if = 0`), DCLK 33 MHz, backlight por PWM | [obs] |
| Touch | **capacitivo FocalTech `ft5x_ts`**, I2C `twi2` endereço `0x38`, INT em `PH21`, wake `PB13`, eixos X/Y trocados | [obs] |
| Wi-Fi | **Realtek RTL8188CUS** por USB (`0bda:8176`, driver `8192cu`), na porta USB 2 | [obs] |
| PMU | **AXP209** | [obs] |
| Outros | GPS (UART, módulo `gps`), rádio FM (RDA / KTA0806), acelerômetro MMA7660/MMA8452, câmera (sensores vários, provavelmente sem câmera montada), áudio do codec interno | [obs] |
| USB | uma porta OTG (`usb_port_type = 2`) com troca Master/Slave | [obs] |
| Android | 4.0.3, kernel 3.0.8, build `crane_11x-eng`, `ro.secure = 0` | [obs] |
| Root | **sim**: `adbd` roda como root (uid 0) e existe `/system/xbin/su` | [obs] |
| Console serial | `console=ttyS0,115200` (UART0) | [obs] |

## Partições NAND
| Partição | Tamanho | Uso |
|---|---|---|
| nanda | 16 MB | boot FAT: `script.bin` (config da placa), `boot.axf`, logo |
| nandb | 2 MB | env |
| nandc | 32 MB | boot (kernel + ramdisk) |
| nandd | 512 MB | `/system` |
| nande | 1 GB | `/data` |
| nandf | 1 MB | misc |
| nandg | 32 MB | recovery |
| nandh | 256 MB | `/cache` |
| nandi | ~5,6 GB | armazenamento interno (`/mnt/flash`, FAT) |

Cópia dos arquivos da `nanda` em `firmware-estoque/nanda-arquivos/na/` (só leitura, montada `ro`).

## Acesso remoto (como foi feito)
Uma linha no Terminal Emulator: `su -c "setprop service.adb.tcp.port 5555; stop adbd; start adbd"`.
Do PC: `adb connect 192.168.0.187:5555`. Não sobrevive a reboot (repetir a linha). O aparelho
não tem busybox (sem `grep`, `cut`, `telnetd`).

## Go/no-go: **GO**
Tudo o que importa tem suporte no Linux mainline (linux-sunxi): A10, Mali-400 (driver `lima`
para GLES2 em mesa), LCD RGB, touch FocalTech (`edt-ft5x06`), RTL8188CUS (`rtl8xxxu`), AXP209,
codec de áudio interno. Pontos de atenção:
- Boot ROM do A10 tenta o **microSD antes da NAND** → Linux roda de um **segundo cartão**, sem
  gravar nada na NAND. Tirou o cartão, volta o Android.
- 512 MB de RAM e Cortex-A8 single-core: dá para **emulação até 16 bits** (NES, SNES, Mega
  Drive, Game Boy/GBA, Master System). PS1 só leve. Nada de desktop pesado.
- O único controle é a tela: precisa de **controle USB** (pela porta OTG em modo host) ou de
  controle virtual na tela. Bateria viciada: ele vive na tomada; para usar controle USB e carga
  juntos, precisa de um cabo/hub OTG com alimentação.
- O `.dts` da placa precisa ser escrito a partir do `script.fex` (pinos de LCD, touch, backlight).

## Rota escolhida
1. **Backup da NAND** pela rede (só leitura) para `firmware-estoque/` antes de qualquer outra
   coisa. A rede é lenta (~0,1 MB/s por `adb pull`): fazer as partições pequenas primeiro
   (`nanda`, `nandb`, `nandc`, `nandg`), depois `nandd`.
2. **Linux em microSD separado**: U-Boot mainline (alvo A10 genérico) + kernel mainline + DTS
   próprio da placa + Buildroot ou Armbian mínimo + RetroArch (ou EmulationStation) em
   framebuffer/KMS.
3. Alternativa sem trocar de SO: ficar no Android rooteado e instalar um RetroArch antigo
   compatível com Android 4.0 (rápido, mas preso a Android 4).
