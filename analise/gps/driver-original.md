# Driver de GPS original: `gps.ko` + HAL `gps.exDroid.so`

Análise para interoperabilidade (porte da função de GPS do aparelho do dono para o Debian 13
mainline). Só leitura dos binários do backup da NAND. Data: 04/11/2026.

Legenda: **[O]** observado (com função/endereço de origem), **[I]** inferido, **[?]** desconhecido.

Fontes da análise (todas em `decompilado/`):
- `gps.ko.asm`: `objdump -dr` (com relocações) do módulo.
- `gps.ko.c`, `gps.ko.funcoes.tsv`, `gps.ko.strings.tsv`: Ghidra headless (198 funções, 0 falhas).
- `tipos-dwarf.txt`: o `gps.ko` **veio com DWARF completo** (nomes de funções, parâmetros,
  structs e globais); extraído com pyelftools. `lines.txt`: tabela endereço → arquivo:linha.
- `gps.exDroid.so.c` (+ `.funcoes.tsv`, `.strings.tsv`), `hal-simbolos.txt` (1755 símbolos
  exportados da HAL), `hal-strings.txt`.
- Kernel do aparelho (`binarios/boot/zImage`, que na verdade é a `Image` sem compressão do
  3.0.8): kallsyms extraídos com `kallsyms-finder` (não guardados aqui, ver "Kernel" abaixo).

## 1. Visão geral

```
 antena → front-end RF externo (chip "Hivision"? [I]) ──PI0 clk / PI1 sign / PI2 mag──┐
                                                                                       ▼
 ┌──────────────────────────── A10: bloco "GPS" @ 0x01C30000, IRQ 57 ─────────────────────────┐
 │ anel de amostras RF (0x6000 posições) → 32 canais de correlação (NCO de portadora e de    │
 │ código, gerador C/A pelo estado G2) → 64 correlatores por canal, 1 ms → DMA p/ a DRAM      │
 │ acelerador "Acc" (+0x8000): FFT 4..512 pontos sobre as saídas, acumula, acha o pico       │
 └────────────────────────────────────────────────────────────────────────────────────────────┘
        │ IRQ a cada 1 ms                      ▲ NCOs, ponteiros, comandos do acelerador
        ▼                                      │
 gps.ko (kernel): ISR 1 ms  + tasklet a cada 5 ms = aquisição (FFT), rastreio (FLL/PLL/DLL),
                  sincronismo de bit, extração dos bits de navegação, medições
        │ read() 1 vez por segundo: 0xD40 bytes        ▲ ioctl 0x82: buffers de comando A/B
        ▼                                              │
 gps.exDroid.so (HAL, motor "GBC" v2.3): escolhe satélites, manda comandos de canal, decodifica
                  subframes (efemérides, almanaque), pseudodistâncias, Kalman/LSQ → posição,
                  NMEA ($GPGGA, $GPRMC, $GPGSV…) → callbacks do Android
```

**Quem calcula a posição: a HAL (espaço do usuário).** O kernel entrega medições brutas por canal
(fase de código, frequência e fase de portadora, contagem de épocas, bits de navegação, energia
de correlação) e nunca vê efeméride nem coordenada. [O] `GpsISRPro` @0x11ad8 monta
`GPS_INFO_DATA`; a HAL exporta `KalmanFilter`, `RcvrPosSolution4xn…`, `XYZ2LLA`,
`FrameProcess…`, `NMEAGSV`, `NMEARMC` etc. (`hal-simbolos.txt`).

## 2. Origem do código

- [O] Caminhos no DWARF: `…/hardware/libhardware/modules/a23port/drv/lnxdrv/` (`gpsdriver.c`,
  `PALAPI.c`, `lnxdrv_F30.c`, `gpsdrv.h`, `../inc/gpsbb.h`) e `/media/KINGSTON/Driver_soc/algpro/`
  (`GpsIsr.c`, `RegAccess.c`, `gps_baseband_pro.c`, `Alg_Platform.c`, `GpsAcquire.c`,
  `GpsCarrier.c`, `GpsCommandParse.c`, `GpsVarType.h`). Compilado em "Mar 28 2012 02:19:18".
- [O] `.modinfo`: `license=GPL`, `vermagic=3.0.8+ preempt mod_unload modversions ARMv7`.
- [O] A HAL tem `SONAME gps.default.so`, versão interna "GBCV 2.3, Mar 28 2012 19:35:28", e uma
  entrada JNI de teste `Java_com_hv_gpstest_GPSLib_Start` (prefixo `hv`). A função de checagem do
  RF no kernel chama-se `HivisionGpsRfCheck`. [I] O baseband/firmware veio de um fornecedor
  ("Hivision"/"HV") integrado pela Allwinner; o "F30" do nome do arquivo e "a23port" são da
  árvore deles.
- [I] Como o módulo se declara GPL, o código-fonte dele deveria poder ser pedido ao fabricante.
  [?] Não achamos o fonte publicado.

## 3. Recursos de hardware que o driver usa

| Recurso | Valor | Onde |
|---|---|---|
| Registradores do baseband | físico **0x01C30000**, acessado pelo mapa estático virtual 0xF1C30000; usa até +0x808C | [O] `GPSDrv_Init` @0xa88 grava `g_dwGPS_BASE = 0xf1c30000`; `RegAccess.c` calcula `(id + 0x3c70c100) << 2` etc. |
| IRQ | **57** (numeração do kernel 3.0 sun4i = número da fonte no INTC do A10 [I]) | [O] `GPSDrv_Init`: `request_irq(57, gps_int_handler, IRQF_DISABLED(0x20), "gps")`; `GPSDrv_Deinit`: `free_irq(57)` |
| Relógio | gate AHB `"ahb_com"` (clk_enable) | [O] `gps_soc_init` @0x834 |
| Reset | `"com"`: `clk_reset(1)`, espera 10 ms, `clk_reset(0)`; nunca `clk_enable` | [O] `gps_soc_init` |
| Mapeamento no mainline | `CLK_AHB_GPS` (gate 0x060 bit 26) e `RST_GPS` (0x0D0 bit 0) já existem em `ccu-sun4i-a10.c`; `CLK_GPS` (0x0D0, módulo) está "unimplemented" | [O] fonte do Linux 6.18.58 no WSL; [I] "ahb_com" = AHB GPS e "com" = reset do GPS_CLK_REG |
| Memória de amostras/DMA | **16 MiB em 0x49000000** reservados pelo kernel do aparelho (`gps_start`/`gps_size`, `memblock_reserve` em `sw_core_reserve`); o driver usa `virt = phys + 0x80000000` (mapa linear) | [O] kallsyms `gps_start`=0x49000000, `gps_size`=0x01000000; `AccPhysicalAddrSpace` @0x2f8 |
| Pinos do sinal | PI0 gps_clk, PI1 gps_sign, PI2 gps_mag, função **2** | [O] fex `[gps_para]`; `gpio_request_ex("gps_para")` aplica o mux do fex |
| Energia do RF | `gps_vcc_en` PC22, `gps_osc_en` PI14, `gps_rx_en` PI15 (saídas) | [O] fex; `GPSDrv_Init`, `gps_soc_init`, `CheckRFSec` |
| SPI2 | **não é usado para dados**: no `insmod` o driver pega `spi2_para` e põe `spi_cs0`, `spi_sclk`, `spi_mosi` em 0 e solta | [O] `GPSDrv_Init` @0xb50–0xb98. [I] Só estaciona as linhas (o fex tem `spi_used = 0` e pinos repetidos em PB14–17 e PC19–22; PC22 é também o `gps_vcc_en`) |
| LRADC | `gps_lradc = 1` no fex, **nenhum acesso** no `gps.ko` | [O] nenhuma string/registrador do LRADC no módulo. [?] Uso, se houver, seria na HAL (não achado) |
| DMA do sistema | **não usa** o controlador DMA do A10; o bloco de GPS tem DMA próprio (escreve direto na DRAM) | [O] nenhum import de DMA; endereço físico gravado em registrador de canal (`SetChMemAddr`) |
| Cache | invalida 0x50000 bytes a cada 1 ms (`isr_dma_cache_inv`) e faz write-back no acelerador | [O] `GpsISRPro`; `bb_dma_cache_wback_inv` |
| Tempo | `do_gettimeofday` para medir atraso de IRQ e marcar medições | [O] `PAL_GetCurTimer_US` @0x78 |

Funções vazias (stubs) no módulo: `cpm_power_ctrl` (só `bx lr`), `bb_dma_cache_inv`,
`BB_Val_Check` (sempre 1), `MemoryCheck` (sempre 1). `newPLLProcess` e `_NoiseFloorCal` também são
de 4 bytes. [O] `gps.ko.asm`.

## 4. Interface com o espaço do usuário

- [O] `misc_register` com minor dinâmico (255) e nome **`gps`** → **`/dev/gps`**.
  `gps_fops`: `open`/`release` não fazem nada, `read`, `unlocked_ioctl`.
- [O] **ioctl** (números crus, sem `_IOW`), `gps_ioctl` @0x9f0:

| cmd | Argumento | O que faz |
|---|---|---|
| `0x80` START | ponteiro p/ `BB_COMMAND_BUFFER {int bufA; int bufB; int navBuf}` (ponteiros de usuário) | `gps_soc_init()` (pinos, `gps_vcc_en=1`, clock, reset) e `Gps_Init()`: copia 3000 B de A (buffer de inicialização), 3000 B de B, 512 B de ajuda (`GPS_AIDED_DATA`); `HivisionGpsRfCheck`; `GpsBasebandInit`. No fim **escreve direto no struct do usuário** `[0]=phys` e `[1]=virt` da área de amostras (sem `copy_to_user`) |
| `0x81` STOP | — | `Gps_Stop`: IntrEna (0x40C) = 0, solta o leitor; `gps_soc_deinit`: `gps_osc_en=0`, `gps_rx_en=0`, `gps_vcc_en=0`, solta GPIO, desliga e libera o clock |
| `0x82` UPDATE | mesmo `BB_COMMAND_BUFFER` | copia A (3000 B), B (3000 B) e ajuda (512 B) e liga `bCommandProtect` |
| `0x83` VERSION | ponteiro p/ `BB_DRV_VERSION {u32 major; u32 minor; char[32]}` | grava `1`, `8`, `"Mar 28 2012,02:19:18"` |
| outro | — | `printk("gpsdrv: ioctl number is worng %d")`, retorna 0 |

- [O] **read**: `gps_read` @0x6ac → `GpsDrv_Read`: bloqueia num semáforo (`down`) que a tasklet
  solta **uma vez por segundo**; copia `GPS_INFO_DATA` (0x840 B) e logo depois
  `s_GPS_CorrpowerData` (`Int32[32][10]`, 0x500 B). A HAL sempre lê **0xD40 bytes**. Retorna o
  tamanho pedido (ou `-EFAULT` se `GpsDrv_Read` devolver 0).
- [O] Não há sysfs, poll nem mmap. O endereço da área de amostras sai pelo ioctl 0x80, mas a HAL
  não usa (zera os buffers logo depois).

### Formatos (do DWARF, `gpsbb.h`/`gpsdrv.h`; detalhe em `tipos-dwarf.txt`)

`GPS_INFO_DATA` (0x840 B):
- `+0x000 UInt16 waas_info[32]`
- `+0x040 UInt16 gps_info[32][8]`: 16 bytes por canal = **bits de navegação** do último segundo
  (`DataMessage`, 8×Int16) [O] `GpsISRPro` copia `sChUpdate[ch].DataMessage` (0x10 B) por canal.
- `+0x240 GPS_NAV_MEASURE gps_measure[32]` (48 B cada): `code_phase` (CodeNco), `part_phase_acc`
  (fase de portadora acumulada), `ddfs_freq` (frequência de portadora/NCO), `read_address`
  (ponteiro no anel = fase de código grossa), `epoch_no` (ms dentro do bit, 0..19),
  `trace_state` (ChStatus), `delta_ddfs`, `delta_address`, `power2_sum`/`power4_sum`
  (ChInfo1/ChInfo2 no kernel), 2 reservados (DebugVar1/2 = segundos/µs do relógio do kernel
  no canal 5), `power4` (SignalPower), `power9` (NoisePower).
- [O] Campos "contrabandeados" em `Reserved` de canais fixos: canal 0 = ponteiro de escrita do
  RF, canal 2 = contador de segundos do ISR, canal 3 = erro do ponteiro de escrita;
  `ChInfo2 |= 0x80` no último canal marca fim.

`s_GPS_CorrpowerData` (0x500 B): 10 energias de correlação por canal (`ISRCorEnergy`).

Buffers de comando A e B (3000 B = 1500 Int16 cada), lidos por `GpsCommandParsePro` @0x186bc:
sequência de `[código][parâmetros…]`, termina em 0. Códigos [O]:

| Código | Handler | Tamanho (Int16 após o código) |
|---|---|---|
| 1 | `_CmdAddChannelPro` (põe um satélite num canal) | 15 |
| 2 | `_CmdDelChannelPro` | ver função |
| 3 | `_CmdSwapChannelPro` | ver função |
| 4 | `_CmdSetFineTrackingPro` | ver função |
| 5 | `_CmdSetInoutModePro` (modo de operação do canal) | ver função |
| 6 | `_CmdSetThresholdPro` | ver função |
| 7 | `_CmdSetWaasPro` (só zera o tamanho) | — |
| 8 | `_CmdSetChInfoPro` | ver função |

Layout do comando 1 (Int16, a partir do primeiro parâmetro) [O] `_CmdAddChannelPro` @0x174e8:
`[0]` id do satélite (vai para `ChInfo2` bits 15:8), `[1..2]` Int32 frequência inicial do NCO
de portadora, `[3]` estado inicial do G2 (10 bits → seleciona o PRN C/A), `[5]` flags
(bits 3:0 → ChInfo1, bits 9:8 → ChInfo2), `[6]` modo de partida (≠0 = quente), `[7]` faixa de
busca de código, `[8]` início da busca de frequência, `[9]` faixa de frequência, `[10]` posição
no anel (−1 = a atual), `[11]` época (bit 15 = automática), `[13]` modo de rastreio,
`[14]` modo de operação (índice 0..12 da `ModeParaTalbe`). Comprimento total 15.

A HAL também filtra/repacota esses comandos (`BBDev_UpdateBBData` @0x50b78) com tamanhos por
código: 1→16, 4→4, 5/6/8→5, 3/10→3, 2/7/9/0xd→2 Int16 (contando o código).

Buffer de inicialização (A no ioctl 0x80) [O] `GpsChannelInit` @0x14c88: `[0]` número de canais
(≤32), `[4..5]` escala dos limiares (entre 500000 e 1000000), depois 15 Int16 por canal com o
mesmo layout do comando 1. **O canal 0 é fixo**: id 0x21 (33), G2 = 0x108, portadora 0xF9FC01,
código 0x1800200, modo 1. [I] Canal de referência/ruído: o ponteiro de leitura do canal 0
define o mínimo do anel (`ISRRfReadPtrMin`) usado por todos.

## 5. Sequências

### Carga do módulo (`insmod`, `init.sun4i.rc` linha 70) — `GPSDrv_Init` @0xa88
1. `g_dwGPS_BASE = 0xF1C30000`; `request_irq(57)`; `misc_register("gps")`.
2. `AccPhysicalAddrSpace`: guarda `phys = gps_start` (0x49000000) e `virt = phys + 0x80000000`.
3. `gpio_request_ex("gps_para")` (aplica o mux PI0–PI2 = 2 e as saídas) e põe
   `gps_osc_en = 0`, `gps_rx_en = 0`, `gps_vcc_en = 0`; solta o handle.
4. `gpio_request_ex("spi2_para")`: `spi_cs0 = spi_sclk = spi_mosi = 0`; solta.

### Partida (ioctl 0x80)
1. `gps_soc_init`: pega `gps_para`, **`gps_vcc_en = 1`**, `clk_get("ahb_com")`, `clk_get("com")`,
   `clk_enable(ahb_com)`, `clk_reset(com, 1)`, 10 ms, `clk_reset(com, 0)`.
2. `Gps_Init`: cria o semáforo, copia A/B/ajuda, monta `_sGpsGlobalMem` (ponteiros para os
   buffers de saída).
3. `HivisionGpsRfCheck` → `CheckRFSec(1, 2)` @0x203c:
   `gps_osc_en = 0`, `gps_rx_en = 0`; reset do baseband (0x400 |= 0x1C, 5 ms, limpa, 5 ms);
   lê o ponteiro de escrita (0x420); DS (0x408) = 0x70000; **`gps_rx_en = 1`**; espera o ponteiro
   mudar e passar de 0x800; lê 127 palavras de +0x2000 e compara com um padrão fixo
   (`mem_data`, 0xEC46EC46…, `.data+0x3c`). Se diferente, repete uma vez com 50 ms. Por fim
   **`gps_osc_en = 1`**. Resultado (1 = bateu) vai em `bRfSecCheck`.
   [I] Detecta a variante do front-end/formato do sinal; decide o valor do registrador 0x408.
4. `GpsBasebandInit` @0x14fac: `GpsChannelInit`; reset do baseband; para cada canal monta a área
   de DMA (`phys + ch*0x2800`, 2 metades de 0x1400 B) e a área de pós-processamento
   (`phys + 0x50000 + ch*0x28000`); tira o reset; programa os 6 registradores de cada canal;
   0x408 = 0x81317 (RF ok) ou 0x80007; 0x41C = `nCanais * 49104 / 160`; 0x404 = ponteiro inicial
   (mínimo dos canais + 0x34E0, módulo 0x6000); 0x418 = máscara de canais válidos;
   **0x40C = 0xFFF9** (habilita IRQ); 0x408 |= 0x10000 (liga o RF); 0x400 |= 2 (próximo bloco).

### Regime (a cada 1 ms) — `gps_int_handler` @0x3b4
1. Lê 0x410 (status). Se tiver bit além de 0..2, imprime 0x460–0x46C (diagnóstico).
2. Se bit 0: escreve 1 em 0x410 (limpa) e chama `GpsISRPro`:
   lê o ponteiro de escrita do RF; sincroniza variáveis com a tasklet; `_ISRBBIntrPro` (lê os
   registradores de cada canal, aplica os deltas de NCO calculados pela tasklet, avança o
   ponteiro de DMA de 0x100 B por ms num anel de 40 ms, conta épocas de 20 ms, acumula fase de
   portadora); `_ISRBBConfigWritePtrTh` (se o IRQ atrasou mais de 1 ms, mede pelo relógio do
   sistema e compensa em múltiplos de 0x1550 posições); invalida o cache de 0x50000 B;
   0x400 |= 2; `_ISRBBDataDecode` (bits de navegação).
3. A cada 1000 ms monta o pacote para o `read()` (retorno bit 0); a cada 5 ms pede o
   processamento pesado (bit 1). Agenda a tasklet.

`gps_do_tasklet` @0x298: bit 1 → `baseband_process` (= `GpsMainProcessing` +
`GpsPostProcessing` + `GpsCommandParsePro`); bit 0 → `up()` do semáforo (acorda o `read`).

### Parada (ioctl 0x81) e descarga
`Gps_Stop`: 0x40C = 0, `up()`. `gps_soc_deinit`: osc/rx/vcc = 0, `gpio_release`,
`clk_disable` + `clk_put`. `rmmod` (`GPSDrv_Deinit`): 0x40C = 0, `free_irq(57)`,
`misc_deregister`, imprime "GPS exit ok!". [O] Observação: `gps_soc_deinit` chama
`clk_disable` no handle do reset (`com`), não no `ahb_com`: o gate AHB fica ligado. Bug do
original; o driver novo deve desligar o gate certo.

## 6. HAL `gps.exDroid.so` (motor GBC)

- [O] ARM Thumb-2, Bionic; depende só de `liblog`, `libc`, `libcutils` (sem `property_get`),
  `libm`, `libstdc++`. Exporta `HMI` (hw_module_t) e `gps_get_hardware_interface` (HAL legado do
  Android 4.0).
- [O] `BBDev_Init` @0x509f8: `open("/dev/gps", O_RDWR)`; ioctl 0x80 com {A, B, ajuda}; zera A e B
  e põe 0xFF na ajuda; ioctl 0x83 (versão); cria a thread de leitura (prioridade 10).
- [O] Thread `FUN_00050ab4`: laço `read(fd, buf, 0xD40)`; copia 0x840 para um de 4 buffers
  circulares e 0x500 para o buffer de energia; sinaliza um evento para o motor; registra
  `$GPVER,GBCV:2.0003…;DRIVER:1.0008…`.
- [O] `BBDev_UpdateBBData` @0x50b78: copia os comandos para um buffer limpo e manda ioctl 0x82.
  `BBDev_Deinit` @0x509b8: ioctl 0x81, espera a thread, `close`.
- [O] Dentro da HAL (pelos nomes exportados): máquina de estados de busca
  (`InitColdStateMachine`, `MultiChannelAllocate`, `GetStartSeq`), decodificação de navegação
  (`CStreamBuffer`, `CViterbiStream` para SBAS, `hec_check`, `crc24`, `FrameProcess`,
  `NavDataBitDec`), efemérides e almanaque, efemérides sintéticas/preditas (`SPGOD`,
  `EphPredictor`), partida rápida (`CFastWarmStart`), solução (`LSQ…`, `KalmanFilter`,
  `RcvrPosSolution4xn`), correções (ionosfera, troposfera, rotação da Terra), conversões
  (`XYZ2LLA`, `GpsTime2UTC`), saída NMEA e mensagens proprietárias `$PPLM*` (diagnóstico).
- [O] Arquivos que ela usa: `/data/gpsdata` ou `/sdcard/gpsdata` (`ParamData.bin`, logs
  `GpsDebug_*.log`, `NMEA_*.log`), `packedEphemeris*.bin`, `/fs/etfs/*/BRDC.bin`.
- [O] `gps.conf` é o padrão do Android (NTP, XTRA da Qualcomm, SUPL do Google). [I] A HAL não
  usa (não há XTRA/SUPL nos símbolos dela).

## 7. Kernel do aparelho (o que ele faz pelo GPS)

- [O] Só reserva a memória (`gps_start`/`gps_size` = 0x49000000 / 16 MiB, em `sw_core_reserve`,
  junto com LCD, VE e G2D) e exporta os dois símbolos. Nada mais: pinos, clock e IRQ são do
  módulo. Não há mensagem de boot para a reserva do GPS.
- [O] O arquivo `boot/zImage` é a imagem **sem compressão** (o gzip encontrado nele é o
  `ikconfig`). kallsyms extraíveis com `kallsyms-finder` (vmlinux-to-elf).

## 8. O que não sabemos

- [?] O chip do front-end RF (nome, registradores). O driver não o configura por SPI/I2C: só
  liga energia, oscilador e RX. [I] É um front-end de configuração fixa (por pinos), como os
  de 2 bits sinal/magnitude.
- [?] Significado dos bits de 0x408 (0x70000, 0x80007, 0x81317, 0x10000) e de 0x41C.
- [?] Frequência de amostragem e FI exatas. [I] 16,368 MHz de amostragem (0x1550 posições por
  ms × 3 = 16368; `0xBFD0 = 3 × 16368`) e FI ≈ 4 MHz (ver `algoritmo.md`).
- [?] Conteúdo do bloco +0x800 (`BBSecRegRead`, sem chamadas) e +0x2000 além das 127 palavras.
