# Algoritmo do receptor: o que roda onde

Descrição por comportamento, para reimplementação limpa (clean-room). **[O]** observado (função
@endereço no `gps.ko` ou símbolo da HAL), **[I]** inferido, **[?]** desconhecido.

## 1. Divisão de trabalho

| Etapa | Onde | Evidência |
|---|---|---|
| Amostragem do sinal (sinal + magnitude, 2 bits) e anel de amostras | hardware (bloco 0x01C30000) | [O] PI0–PI2; ponteiros 0x404/0x420 |
| Geração do código C/A, mistura com NCO de portadora, 64 correlatores por canal em 1 ms, DMA para a DRAM | hardware, 32 canais | [O] registradores de canal; 0x100 B/ms/canal |
| FFT sobre as saídas dos correlatores (bins de Doppler), acumulação, pico e vizinhos | hardware (acelerador +0x8000), comandado pelo kernel | [O] `_FFTMainProcessing` @0x4310, `GetEpdMax*` |
| Rearranjo/decimação das saídas antes da FFT, ruído | kernel, a cada 5 ms | [O] `_FFTDSProcessing` @0x2e44, `rao_test` @0x2d08 |
| Aquisição (busca grossa, fina, confirmação) | kernel | [O] `GpsAcquire.c`: `CoarseSearchAcqPro`, `FineSearchAcqPro`, `FineSearchAcqCodeCmf`, `TangSearch*`, `GpsFirstAcqSignal` |
| Rastreio de portadora (FLL → PLL) e de código (DLL) | kernel; correções aplicadas aos NCOs no IRQ de 1 ms | [O] `GpsCarrier.c`, `GpsDllProcess` @0x55c4, `_ISRBBIntrPro` @0xbec |
| Sincronismo de bit (bordas de 20 ms) | kernel | [O] `BitEdgeCheck` @0x3b70, `EpochNo` mod 20 |
| Demodulação dos bits de navegação (diferencial) | kernel, no IRQ | [O] `DataDecode` @0x17bc, `_ISRBBDataDecode` |
| Medições por canal 1×/s (fase de código, portadora, épocas, energia) | kernel → `read()` | [O] `GpsISRPro` @0x1ad8 |
| Escolha de satélites, partida fria/morna/quente, alocação de canais, ajuste de modo | **HAL** (manda comandos 1–8) | [O] HAL: `InitColdStateMachine`, `MultiChannelAllocate`, `GetStartSeq`, `SetAcqMode`, `UpdateGroupSearchMode` |
| Sincronismo de quadro, paridade, subframes, efemérides, almanaque, SBAS (Viterbi) | **HAL** | [O] `CStreamBuffer::GetSubframe`, `hec_check`, `crc24`, `FrameProcess`, `CViterbiStream`, `WaasFrameProcess` |
| Tempo de trânsito, pseudodistância, Doppler, correções (ionosfera, troposfera, relógio do satélite, rotação da Terra) | **HAL** | [O] `GetTravelTime`, `IonoDelay`, `TropoDelay`, `SatClckOffset`, `EarthRotateCorr` |
| PVT: mínimos quadrados + filtro de Kalman, detecção de outliers e multipercurso | **HAL** | [O] `RcvrPosSolution4xn`, `LSQUpdate`, `KalmanFilter`, `CLargeOutlierDetection`, `MultiPathDetection` |
| Efemérides preditas/sintéticas, salvar estado | **HAL** | [O] `SPGOD*`, `EphPredictor*`, `ParamData.bin` |
| NMEA | **HAL** | [O] `NMEAGSV`, `NMEARMC`, `NMEAZDA`, strings `$GPGGA`, `$GPRMC` |

## 2. Hardware: anel de amostras e correlatores

- [O] O anel de amostras tem **0x6000 posições**; o ponteiro avança **0x1550 = 5456 posições por
  ms** (`_ISRBBIntrPro` calcula `WriteAddrErr += (Δptr mod 0x6000) − 0x1550`). O anel cobre
  ≈ 4,5 ms: o IRQ tem esse folga antes de perder amostras.
- [I] 5456 × 3 = **16368** e o registrador 0x41C usa `0xBFD0 = 49104 = 3 × 16368`: amostragem de
  **16,368 MHz** (16 × 1,023 MHz), 3 amostras por posição do anel.
- [I] NCOs com acumulador de **26 bits** (máscara 0x83FFFFFF). Com f = palavra × 16,368 MHz / 2²⁶:
  portadora nominal 0xF9FC01 → **≈ 3,996 MHz** (FI do front-end); código nominal 0x1800200 →
  **6,138 MHz = 6 × 1,023 MHz** (código a 6× a taxa de chip; em rastreio 0x2400300 = 9×). [?]
  Confirmar com o sinal real: é a hipótese mais coerente com os números, não está escrita em
  lugar nenhum.
- [O] Relação portadora → código na aquisição: `code = 0x1800200 − ((carr×85 − 0x5300AC55) >> 16)`;
  no rastreio: `code = 0x2400300 − ((carr − 0xF9FC01) >> 9)` (`GetAcqCodeFreq` @0x4c28). [I] É o
  "Doppler de código" = Doppler de portadora / 1540 na escala de cada NCO.
- [O] O PRN de cada canal é escolhido pelo **estado inicial do registrador G2** (10 bits em
  ReadPoint[25:16]), não por número de PRN. O canal 0 usa G2 = 0x108 com id 33.
- [O] Por canal e por ms o hardware grava **0x100 B = 64 pares I/Q Int16** (`ISRCorNum = 0x40`,
  `CorNum = 0x40`) num anel de 40 ms (0x2800 B), lido em metades de 20 ms (ping-pong:
  `BBDMAStatus & 1` escolhe a metade). [I] 64 correlatores espaçados em atraso de código, cobrindo
  a janela de busca de código do canal.
- [O] O IRQ de 1 ms aplica os deltas de frequência/fase que a tasklet calculou (soma com
  máscara de 26 bits e reescreve CarFreq, CarNco, CodeNco, CodeFreq, ReadPoint, MemAddr) e conta
  `EpochNo` módulo 20 (bit de navegação de 20 ms).
- [O] Se o IRQ atrasar mais de 1 ms (medido com `do_gettimeofday`), `_ISRBBConfigWritePtrTh`
  avança épocas e ponteiros em múltiplos de 0x1550 para não perder o sincronismo.

## 3. Aquisição (kernel + acelerador)

Fluxo por canal, a cada rodada de 5 ms (`baseband_process` → `GpsMainProcessing` @0x59fc):
1. `_FFTDSProcessing`: copia as saídas de 20 ms dos correlatores para a área de entrada do
   acelerador, decimando por `ModeDsFactor` e removendo bits conhecidos quando há ajuda de dados
   (`Ch_DA_Buf`, flag 0x8000: "data aided").
2. `_FFTMainProcessing`: programa o acelerador (`AccCtrl` com o tamanho de FFT do modo,
   `FFTValid`, `FFTLoop`), DMA de entrada, inicia, espera o bit 1 de 0x410 por varredura
   (`_WaitAccBlockDone`, até 100000 voltas; enquanto espera adianta outros canais).
3. `_FFT_Get_Result` / `_FFTPickupMaxEnergy`: pico (energia, correlator, bin de frequência),
   vizinhos esquerda/direita e as 10 maiores energias.
4. `GpsAcqProcess` @0x6520: compara com os limiares do modo e decide
   - busca grossa (`CoarseSearchAcqPro`): varre faixas de código/frequência (`CodeSearchRange`,
     `FreqSearchRange`, `AcqFreqStart`, `AcqFreqBin`);
   - busca fina (`FineSearchAcqPro`) e confirmação (`FineSearchAcqCodeCmf`, `CfmLoopCnt`);
   - "TangSearch" (`TangSearchAlg`/`TangSearchUpdate`/`TangSearchFreqUpdate`): refino de
     frequência em torno do pico [I];
   - perda: `AcqLostSignalTime_Para` tentativas sem pico → recomeça.
5. Achado o sinal, o canal passa para rastreio (`ChStatus` bits 0..2, `ChIntgModeUpdate` troca o
   modo de integração).

Parâmetros por modo (13 modos; `ModeParaTalbe`, `.rodata+0xD0`, 21 Int16 cada) [O]:

| Modo | IntgM | IntgN | IntgL | FFT | Ds | ValidDs | MIPS | FreqInt | PllC1/C2 |
|---|---|---|---|---|---|---|---|---|---|
| 0 | 0 | 0 | 0 | — | 0 | 0 | 0 | 6500 | — |
| 1 | 5 | 1 | 4 | 4 | 1 | 4 | 1 | 6500 | — |
| 2 | 15 | 1 | 4 | 4 | 1 | 4 | 2 | 6500 | — |
| 3 | 3 | 1 | 20 | 32 | 1 | 20 | 1 | 6500 | — |
| 4 | 30 | 1 | 4 | 4 | 1 | 4 | 4 | 6500 | — |
| 5 | 120 | 1 | 8 | 4 | 2 | 4 | 6 | 3075 | — |
| 6 | 1 | 3 | 20 | 64 | 1 | 20 | 4 | 6500 | 288/192 |
| 7 | 1 | 6 | 20 | 64 | 2 | 10 | 8 | 3075 | 144/96 |
| 8 | 1 | 16 | 20 | 64 | 5 | 4 | 24 | 1230 | 57/38 |
| 9 | 1 | 32 | 20 | 128 | 5 | 4 | 44 | 1230 | 19/19 |
| 10 | 1 | 64 | 20 | 128 | 10 | 2 | 64 | 615 | 9/9 |
| 11 | 1 | 128 | 20 | 256 | 10 | 2 | 48 | 615 | 4/4 |
| 12 | 1 | 32 | 20 | 128 | 5 | 4 | 22 | 1230 | 19/19 |

(FFT = `_Hw_FFT_Len[ModeFFTPoint]`.) [I] Modos 1–5: integração curta com muitas acumulações não
coerentes (sinal forte, partida). Modos 6–12: integração coerente cada vez mais longa (3 a 128 ms)
com FFT maior e banda de laço menor: sensibilidade crescente para sinal fraco/ambiente interno
(`GbcEnableInDoor` na HAL). Os demais campos (`EnergyShift*`, `LP3RD_C1`, `CodeCmf_Loop`,
`DllUnUpdate`, `Dll_Tune_Step`, `AcqLostSignalTime`, `Df_Scale`, `AcqTrueTime`,
`DeltaFreqOffset`, `FreqBinOffset`) estão na tabela completa em
`decompilado/tabelas-rodata.txt` (com as tabelas auxiliares `C.*`).

Limiares (`ModeThresholdParaTable`, `.rodata+0x2F2`, 8 Int16 por modo: Acq, Tracking, CFM,
LowPower e as mesmas 4 com ajuda de dados) multiplicados por `escala/2`, com a escala vinda do
buffer de inicialização (500000..1000000) [O] `GpsChannelInit`.

## 4. Rastreio

- **FLL** (`CoarseFllProcess` @0x6d04) [O]: `DDFS_Freq += Df_Scale_Para × (CarDf/8) / 1024`; com
  |CarDf| < 0x2000 por 5 rodadas seguidas marca `ChStatus |= 2` e passa para o PLL.
- **PLL** (`CoarsePllProcess` @0x6ea8) [O]: discriminador = `atan2(Q, I)` em ponto fixo (CORDIC de
  16 passos, `fixed_atan2` @0x6e08, tabela `atan_tab` com 16384 = 45°, ou seja 65536 = 180°);
  zera o erro se `I² + Q² < 250000`; nos primeiros 20 passos mistura erro de fase
  (`Dfai × 157 / 65536`) e de frequência; depois laço com integradores (`Dfai_D2`,
  `Pll_Dfai_Temp`) e ganho `LP3RD_C1_PARA` [I: laço de 2ª/3ª ordem]; perde o travamento após
  10 (sem bit sync) ou 50 (com) rodadas com erro grande → limpa `ChStatus` bits 0..1.
- **DLL** (`GpsDllProcess` @0x55c4) [O por nome/parâmetros]: usa energia do pico e dos vizinhos
  (esquerda/direita) para corrigir a fase de código; `Dll_Tune_Step_Para`, `DllUnUpdate_Para`.
- **Sincronismo de bit** (`BitEdgeCheck` @0x3b70) [O]: acumula I/Q e potência por 20 posições de
  borda candidatas (`BitEdgeCheck_I/Q/Power/Cnt[20]`) e escolhe a de maior energia.
- **Bits de navegação** (`DataDecode` @0x17bc) [O]: demodulação **diferencial**: compara o
  somatório I/Q do bit atual com o anterior (produto escalar); sinal negativo inverte o bit.
  Empacota em `DataMessage[0..3]` (até ~56 bits/s) com o contador no byte alto de
  `DataMessage[3]` e flags de erro em `DataMessage[4..7]`. A ambiguidade de polaridade fica para
  a HAL (preâmbulo/paridade).
- **Qualidade do sinal** (`GpsSignalQualityCheck` @0x35d0) [O]: contadores de oscilação de
  frequência e de correlator; reset de canal por falsa aquisição (`FaseAcqCheckAndReset`).

## 5. Medições entregues (1×/s) e o que a HAL faz com elas

[O] Por canal: `CodeNco` (fase fina de código), `ReadPtr` (posição no anel = fase grossa),
`EpochNo` (ms dentro do bit), `DDFS_Freq` e `Delta_DDFS_Freq` (portadora), `PartPhaseAcc`
(fase de portadora acumulada no segundo), `Delta_Add_Sum` (deslizamento de código acumulado),
`ChInfo1/2` (id do satélite, modos, estado), `SignalPower`, `NoisePower`, 16 B de bits de
navegação e 10 energias de correlação. Mais, em canais fixos: ponteiro de escrita do RF,
segundos do ISR e tempo do sistema (s, µs).

[I] Com isso a HAL forma o tempo de transmissão (TOW do subframe + bits + épocas + fase de
código), a pseudodistância (diferença para o tempo do receptor × c) e o Doppler (portadora −
FI nominal), e resolve a posição. Os detalhes de escala dessas grandezas estão na HAL
(`GetTravelTime`, `GetIQDataFromDSP`, `PackupDataBitsOneSecond`) e não foram desmontados nesta
rodada.

## 6. Custo de CPU

[O] Tudo do kernel roda em contexto de interrupção (1 kHz) e de tasklet (200 Hz), com
`SystemTotalProCap = 0x180` e `ModeMipsPerCor` por modo: o próprio código orça processamento
por canal. [I] No A10 a 1 GHz isso deve ocupar uma fração grande de um núcleo com 12+ canais em
modos de alta sensibilidade. No Linux 6.12 o equivalente deve ser IRQ com thread + kthread
SCHED_FIFO, não tasklet.

## 7. Desconhecido

- [?] Escala exata de cada campo de medição (unidades de fase de código e de portadora).
- [?] O que faz `_CmdSetInoutModePro`/`_CmdSetFineTrackingPro`/`_CmdSetChInfoPro` em detalhe
  (estão decompilados em `decompilado/gps.ko.c`, não descritos aqui).
- [?] Toda a lógica da HAL (≈ 390 KB de código Thumb sem símbolos internos de dados), só mapeada
  pelos nomes exportados.
