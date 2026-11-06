# Mapa do port: Android de fábrica → Debian 13 (armhf)

Fontes: `analise/script.fex` (config da placa), módulos de `/system/vendor/modules`,
`init.sun4i.rc` do ramdisk, `lsmod` e `/proc/bus/input/devices` lidos ao vivo (03/11).
DTS: `novo-so/dts/sun4i-a10-aquarius-mtc4553.dts`. U-Boot: `novo-so/u-boot/Aquarius_MTC4553_defconfig`.

Status: **mapeado** = pinos e driver definidos · **testado QEMU** · **testado no aparelho** · **sem driver**.

| Item | Android (driver / fonte) | Debian (driver mainline) | Pinos / parâmetros | Status |
|---|---|---|---|---|
| SoC / CPU | sun4i, dvfs 60–1056 MHz | `cpufreq-dt`, OPPs do `sun4i-a10.dtsi` | cpu-supply = AXP DCDC2 | mapeado |
| RAM | 512 MB DDR3, 408 MHz | SPL do U-Boot (`dram_sun4i`) | `DRAM_CLK=408`, ZQ 123 | mapeado |
| PMU | AXP209 (`axp20-supplyer`) | `axp20x` mfd + regulators + `axp20x_battery`/`ac`/`usb` + `axp20x-pek` | twi0 0x34; DCDC2 1,40 V, DCDC3 1,25 V, LDO2 3,0 V, LDO3/4 2,8 V | mapeado |
| Botão liga | AXP PEK (`axp20-supplyer.kl`) | `axp20x-pek` → KEY_POWER | — | mapeado |
| Botões MENU/VOLTAR | `sun4i-keyboard.ko`, tabela `_113` | `sun4i-lradc-keys` | LRADC0: MENU ~0,1 V, BACK ~0,35 V | mapeado (níveis vindos do `keypad_mapindex`) |
| Tela | LCD RGB 24 bits, `disp` Allwinner | `sun4i-drm` (DE1 + TCON0) + `panel-dpi` | PD0–PD27; 800x480, 33 MHz, hbp 79, ht 928, vbp 29, vt 525 | mapeado |
| Luz de fundo | PWM0 | `pwm-sun4i` + `pwm-backlight` | PB2, 12 kHz, invertido; enable PH7 | mapeado (polaridade a confirmar) |
| Energia do LCD | — | `regulator-fixed` | PH8 | mapeado |
| Touch | `ft5x_ts.ko` | `edt-ft5x06` | twi2 0x38, INT PH21, wake PB13, X/Y trocados | mapeado (orientação a confirmar com `evtest`) |
| Wi-Fi | `8192cu.ko` (RTL8188CUS, `0bda:8176`) | `rtl8xxxu` + `firmware-realtek` | USB porta 2 (EHCI1), VBUS PH3 | mapeado |
| Som | codec interno + PA | `sun4i-codec` | `allwinner,pa-gpios` PH15 | mapeado |
| Microfone | `capture_used = 1` | `sun4i-codec` captura | — | mapeado |
| MicroSD | mmc0 | `sunxi-mmc` | PF0–PF5, CD PH1 | mapeado |
| USB OTG | `sw_usb`, Master/Slave | `musb-sunxi` + `phy-sun4i-usb` | ID PH4, VBUS det PH5, VBUS PB9 | mapeado |
| USB host 1 | usbc1 | EHCI0/OHCI0 | VBUS PH6 | mapeado |
| Acelerômetro | `mma7660.ko` / `mma8452.ko` ("gsensor") | `mma7660` / `mma8452` (IIO) | twi1 0x4c / 0x1c | mapeado (qual chip existe: confirmar) |
| GPU | Mali-400 (`mali.ko`, `ump.ko`) | `lima` + Mesa | — | mapeado |
| Console serial | UART0 | `8250_dw` | PB22/PB23, 115200 | mapeado |
| **GPS** | `gps.ko` (baseband do A10 em 0x01C30000, IRQ 57, 32 canais, resultados por DMA em 16 MiB em 0x49000000; aquisição/rastreio no kernel) + `gps.exDroid.so` (motor "GBC 2.3": efemérides, PVT, NMEA) | nenhum ainda: plano em `analise/gps/plano-de-port.md` (driver 6.12 com a mesma interface `/dev/gps` + HAL original via libhybris; 4–7 semanas até o 1º fix) | PC22 vcc, PI15 rx, PI14 osc, PI0–PI2 clk/sign/mag | **REA feito (04/11)**, port não iniciado |
| Rádio FM | `RDA_FM.ko` / `fm_kta0806.ko` | não há driver mainline para RDA5807/KTA0806 | twi1 | **sem driver** (e o Android também tinha `fm_used = 0`) |
| Câmera | módulos carregados, `csi_used = 0` | — | — | não existe na placa |
| Vibração | `motor_used = 0` | — | — | não existe na placa |

## Testado no aparelho (04-05/11/2026)
Funcionando: tela (sun4i-drm, drivers forçados no initramfs), touch (PB13 ACTIVE_HIGH), Wi-Fi RTL8188CUS,
SSH, botões LRADC e PEK (toque curto ignorado, segurar desliga), energia sem bateria (AXP209 reg 0x30 = 0x43,
como o Android), acelerômetro MMA7660, GPU lima, cpufreq 624–1008 MHz, RetroArch (Wayland) com 35 jogos
livres e overlay de toque, modo tablet XFCE com ajustes de toque (evdev, clique único, Firefox XInput2).
Som: placa ok e mixer ligado e salvo; **falta o Pedro confirmar que ouviu**.
Cartão: leitura seq. 22 MB/s (teto do A10), escrita seq. 9,9 MB/s, 4K aleatório 843/199 IOPS.
Boot até a interface: ~42 s (13 s kernel + 29 s sistema); RAM em uso no modo jogos: 198 de 455 MB.

## Validações já feitas (04/11)
- DTS compila sem aviso (`dtc`) e passa no `dt-validate` (dtschema 2025.8, bindings do kernel
  v6.12). Só dois avisos esperados: o compatible da placa não está na lista oficial e o
  `panel-dpi` pede um compatible de fabricante na frente; o `panel-simple` aceita `panel-dpi` sozinho.
- U-Boot v2025.10 com este DTS boota no QEMU `-M cubieboard`: SPL, DRAM, CPU 1008 MHz, console
  LCD 800x480, leitura do cartão.

## GPS: por que não tem driver
O fex declara o GPS em `gps_spi_id = 2` com `gps_clk/sign/mag` em PI0–PI2: são as saídas de um
front-end RF que entregam o sinal bruto ao **baseband interno do A10**. O cálculo (aquisição,
rastreio de portadora, DLL, navegação) está no módulo fechado `gps.ko` (strings `GpsAcquire.c`,
`GpsCarrier.c`, `gps_baseband_pro.c`) e na HAL `gps.exDroid.so`. Não existe documentação desse
bloco nem driver fora do kernel 3.0 do Android.
Alternativas: (1) um GPS USB (u-blox) na porta OTG + `gpsd`; (2) projeto à parte de REA do
`gps.ko` para reimplementar o baseband (meses, sem garantia).
