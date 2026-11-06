# Registradores do bloco de GPS do A10 (como o `gps.ko` usa)

Base física **0x01C30000** (virtual 0xF1C30000 no kernel 3.0 do aparelho). Todos os acessos são
de 32 bits. Nomes vêm das funções de acesso do próprio módulo (`RegAccess.c`, com DWARF); o que
está entre parênteses é dedução. **[O]** observado, **[I]** inferido, **[?]** desconhecido.
Endereços de função são do `.text` do `gps.ko` (ver `decompilado/gps.ko.asm`).

Fórmulas de endereço [O]:
- canal: `0x01C30000 + ch*0x20 + reg*4`, ch 0..31 (`BBChRegWrite/Read` @0x1e50/0x1e6c)
- controle: `0x01C30400 + id*4` (`BBCtrlRegWrite/Read` @0x1e84/0x1ea0)
- "Sec": `0x01C30800 + id*4` (`BBSecRegRead` @0x1ed0, sem chamadas)
- "ConfigDS": `0x01C32000 + id*4` (`BBConfigDSRegRead` @0x1eb8)
- acelerador: `0x01C38000 + id*4` (`HWAccCtrlRegWrite/Read` @0x1ee8/0x1f04)
- diagnóstico: 0x460, 0x464, 0x468, 0x46C (só lidos no IRQ, para `printk`)

## Registradores por canal (32 canais × 0x20)

| Offset | Nome (do código) | Bits | Escrito / lido | Funções |
|---|---|---|---|---|
| ch*0x20+0x00 | ReadPoint | [14:0] posição de leitura no anel de amostras (0..0x5FFF); [25:16] **estado inicial do G2** (10 bits, escolhe o PRN C/A); [26] liga quando `ChStatus & 4` [I: modo de rastreio fino/integração longa] | W: `G2pn | ptr` (bit 26 conforme o estado); R: só [14:0] (`<<17>>17`) | `SetChReadPoint` @0x1fbc, `GetChReadPoint` @0x1f24; `_ISRBBIntrPro`, `GpsBasebandInit` |
| +0x04 | CarNco | fase do NCO de portadora, 26 bits (máscara 0x83FFFFFF, extensão de sinal pelo bit 31) | W: fase + delta da tasklet, a cada ms | `SetChCarNco`/`GetChCarNco` |
| +0x08 | CodeNco | fase do NCO de código, 26 bits | idem | `SetChCodeNco`/`GetChCodeNco` |
| +0x0C | MemAddr | endereço **físico** de destino do DMA das saídas do correlator | W: `base + ch*0x2800 + n*0x100` (n = ms no anel de 40) | `SetChMemAddr`/`GetChMemAddr` |
| +0x10 | CarFreq | palavra de frequência do NCO de portadora; nominal **0xF9FC01** | W | `SetChCarFreq`/`GetChCarFreq` |
| +0x14 | CodeFreq | palavra de frequência do NCO de código; nominal **0x1800200** (aquisição) ou **0x2400300** (rastreio) | W | `SetChCodeFreq`/`GetChCodeFreq` |
| +0x18, +0x1C | — | não usados | — | — |

## Registradores de controle (0x400..0x420)

| Endereço | Nome | Bits / valores | Funções |
|---|---|---|---|
| 0x01C30400 | BBCtr | bit 1 = **próximo bloco** (setado a cada IRQ e no fim da init); bits 4:2 (0x1C) = **reset** do baseband (liga, 5 ms, desliga) | `SetNextBlock` @0x21d8, `SetBBReset` @0x2004, `ClearBBReset` @0x2020 |
| 0x01C30404 | RFStartAddr | posição inicial no anel: (mínimo dos ReadPoint + 0x34E0) mod 0x6000 | `SetRFStartAddr` @0x1f80 (em `GpsBasebandInit`) |
| 0x01C30408 | BBDS (config. de "down-sampling"/formato [I]) | 0x70000 durante a checagem do RF; depois **0x81317** se a checagem bateu, **0x80007** se não; bit 16 (0x10000) = **liga o RF** (`SetRFEnableFlag`) | `SetBBDSReg` @0x1f98, `ConfigDsReg` @0x1fa4, `SetRFEnableFlag` @0x2218 |
| 0x01C3040C | IntrEna | **0xFFF9** para ligar; **0** para parar | `SetIntrEna` @0x2204 (`GpsBasebandInit`, `Gps_Stop`, `GPSDrv_Deinit`) |
| 0x01C30410 | IntrStatus | bit 0 = bloco de 1 ms pronto (IRQ; limpa escrevendo 1); bit 1 = **acelerador terminou** (lido por varredura; limpa escrevendo 2); bits ≥3 = erro [I] (o IRQ imprime 0x460–0x46C) | `gps_int_handler` @0x3b4, `_WaitAccBlockDone` @0x3dd0 |
| 0x01C30414 | ChannelStatus | lido e descartado a cada ms | `GetChannelStatus` @0x1f64 |
| 0x01C30418 | ChValid | máscara de canais ativos: `(1<<n)-1` (0xFFFFFFFF com 32) | `SetChannelValid`/`SetChValidFlag` |
| 0x01C3041C | TimeValue | `nCanais * 0xBFD0 / 0xA0` (≈ 306,9 por canal) [I: orçamento de tempo do sequenciador de canais, em ciclos] | `SetTimeValueReg` @0x21ec |
| 0x01C30420 | RFWritePoint | [14:0] e [30:16]: ponteiro de escrita do anel de amostras (o ISR usa [30:16], a checagem do RF e o diagnóstico usam [14:0]) [I: dois contadores, um deles amostrado no IRQ] | `GetRFWritePoint` @0x1f1c |
| 0x01C30460..0x46C | — | só lidos e impressos quando o status tem erro | `gps_int_handler` |

## Área "ConfigDS" (0x01C32000)

| Endereço | Uso |
|---|---|
| 0x01C32000..0x01C321F8 (127 palavras) | lidas depois de ligar o RX, com o OSC desligado, e comparadas com o padrão fixo 0xEC46EC46 (`mem_data`, 128 palavras em `.data+0x3c`). [I] São as primeiras amostras capturadas (janela de captura); o padrão identifica o front-end/formato do sinal. `CheckRFSec` @0x203c |

## Acelerador "Acc" (0x01C38000): FFT e detecção de pico

| Endereço | id | Nome | Bits / valores | Funções |
|---|---|---|---|---|
| 0x01C38000 | 0 | AccCtrl | bit 0 = **inicia DMA do canal 1** (entrada); bit 9 (0x200) = reset do detector de pico (EPD); 0x400 escrito sozinho = reset da lógica; bits [15:12] = índice do tamanho de FFT (`_Hw_FFT_Len` = 4, 8, 16, 32, 64, 128, 256, 512); bits baixos de modo: **0x88** (sem ajuda de dados, IntgM≠1), **0x98** (sem ajuda, IntgM=1), **0xB4** (com ajuda de dados), **0x100B4** (IntgN=1) [I: coerente/não coerente, remoção de bits] | `SetAccCtrlReg`, `_HwStartDMA_Ch1Pro` @0x2298, `_EpdRegisterReset` @0x2270, `_AccLogicReset` @0x228c, `_FFT_NoDAInit`/`_FFT_DAInit`/`_FFTProInitialize` |
| 0x01C3800C | 3 | DMA1 endereço | físico da entrada (área de pós-processamento do canal + deslocamento dos correlatores já feitos) | `AccCh1DMAConfig` @0x24e0 |
| 0x01C38010 | 4 | DMA1 tamanho − 1 | `(loop+1) * correlatoresAgora * ValidAfDs` palavras [I] | idem |
| 0x01C38014 | 5 | DMA2 endereço | **nunca escrito** (`AccCh2DMAConfig` não tem chamadas) | — |
| 0x01C38018 | 6 | DMA2 tamanho − 1 | idem | — |
| 0x01C3801C | 7 | FFTValid | `(ValidAfDs − 1) << 16` ou `(IntgN*ValidAfDs − 1) << 16` | `SetAccFFTValidReg` |
| 0x01C38020 | 8 | FFTLoop | [8:0] = laços de acumulação − 1 (IntgN−1 ou IntgM−1); [21:16] = correlatores por rodada − 1 | `SetAccFFTLoopReg`, `_FFTDSProcessing` |
| 0x01C38024 | 9 | EpdMaxCorID | correlator (atraso de código) do pico | `GetEpdMaxCorID` @0x24d8 |
| 0x01C38028 | 10 | EpdMaxEnergy | energia do pico (mantissa) | `GetEpdMaxEnergy` @0x24a8 |
| 0x01C3802C | 11 | EpdMaxExp | expoente da energia do pico | `GetEpdMaxExp` |
| 0x01C38030/34 | 12/13 | EpdMaxRight energia/exp | vizinho à direita (interpolação de código) | `GetEpdMaxRight*` |
| 0x01C38038/3C | 14/15 | EpdMaxLeft energia/exp | vizinho à esquerda | `GetEpdMaxLeft*` |
| 0x01C38040..0x8C | 0x10..0x23 | 10 pares (energia, expoente) | as 10 maiores energias [I: uma por bin de frequência ou correlator] | `GetEpdMaxTenResult` @0x230c |

`NormalizeEnergy` @0x22b4 converte (mantissa, expoente) para uma escala comum.

## GPIO e relógio (fora do bloco)

| Recurso | Valor | Quando |
|---|---|---|
| PI0, PI1, PI2 | função 2 (gps_clk, gps_sign, gps_mag) | mux aplicado no `insmod` e na partida (`gpio_request_ex("gps_para")`) |
| PC22 `gps_vcc_en` | 0 no `insmod`; **1** na partida; 0 na parada | `GPSDrv_Init`, `gps_soc_init`, `gps_soc_deinit` |
| PI15 `gps_rx_en` | 0; **1** durante a checagem do RF (antes do OSC); 0 na parada | `CheckRFSec`, `gps_soc_deinit` |
| PI14 `gps_osc_en` | 0; **1** no fim da checagem do RF; 0 na parada | idem |
| PB14–16 / PC19–21 (`spi2_para`) | cs0, sclk, mosi = 0 no `insmod` | `GPSDrv_Init` |
| CCU 0x01C20060 bit 26 | gate AHB do GPS (`ahb_com` no 3.0; `CLK_AHB_GPS` no mainline) | ligado na partida (nunca desligado: bug do original) |
| CCU 0x01C200D0 bit 0 | reset do GPS (`com` no 3.0; `RST_GPS` no mainline) | pulso de 10 ms na partida |
| CCU 0x01C200D0 (resto) | relógio de módulo do GPS: **não usado** pelo driver (`CLK_GPS` "unimplemented" no mainline) | — |

## Memória

| Faixa física | Uso |
|---|---|
| 0x49000000 + ch*0x2800 (ch 0..31; total 0x50000) | destino do DMA dos correlatores: 40 ms × 0x100 B por canal (64 pares I/Q Int16 por ms), em duas metades de 20 ms (ping-pong) |
| 0x49050000 + ch*0x28000 (até 0x49550000) | entrada do acelerador: amostras rearranjadas/decimadas por `_FFTDSProcessing` (160 KiB por canal) |
| até 0x4A000000 | resto dos 16 MiB reservados (sem uso visto) |
