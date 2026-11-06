# Plano de port do GPS para o Debian 13 (Linux 6.12 mainline)

Base: `driver-original.md`, `registradores.md`, `algoritmo.md`. Data: 04/11/2026.
Mesmo método do porte do GTMedia: copiar o mecanismo original (mesma sequência de registradores,
mesma divisão IRQ/processamento), provar cada camada isoladamente, aparelho só no fim.

## 1. Veredito

**Viável, mas não é "escrever um driver".** O hardware é simples de ligar (o mainline já tem o
gate AHB e o reset do GPS; falta só a função 2 dos pinos PI0–PI2), e o protocolo entre kernel e
HAL está todo mapeado. O trabalho grande são duas peças de software fechadas:
1. o **algoritmo de baseband do `gps.ko`** (≈ 200 funções, 7,6 mil linhas decompiladas, em ponto
   fixo, com DWARF): reimplementável em clean-room em semanas, com teste diferencial contra o
   código original sem precisar do aparelho;
2. a **HAL/motor GBC** (≈ 390 KB de Thumb, navegação e PVT): substituível por motor aberto em
   meses, ou reaproveitável como está (só no aparelho do dono) via libhybris.

Caminho recomendado: **kernel novo + HAL original via libhybris primeiro** (fix rápido e oráculo),
depois trocar a HAL se valer a pena. Se o objetivo for só "ter GPS no Debian", um receptor USB
(u-blox) + `gpsd` resolve em um dia; este plano é para usar o GPS embutido.

## 2. Arquitetura proposta

```
 DT: gps@1c30000 (reg, IRQ 57, CLK_AHB_GPS, RST_GPS, pinos PI0-2 fn2, PC22/PI14/PI15, memória)
        │
 kernel: sun4i-gps.ko (platform driver)
   ├─ probe: ioremap, clock, reset, pinctrl, regulador/GPIOs, memória de DMA, IRQ, misc /dev/gps
   ├─ IRQ 1 ms (hardirq): o equivalente de GpsISRPro (_ISRBBIntrPro, ConfigWritePtrTh, DataDecode)
   ├─ kthread SCHED_FIFO acordada a cada 5 ms: baseband_process (aquisição, rastreio, comandos)
   └─ /dev/gps: ioctl 0x80..0x83 e read() de 0xD40 B/s  (mesma ABI do original)
        │
 espaço do usuário:
   Fase A/B: gps-a10d = carregador libhybris + gps.exDroid.so original → callback NMEA → pty
   Fase C:   gps-a10d aberto (gerência de canais + decodificação + PVT com RTKLIB) → NMEA
        │
 /dev/gps-nmea (pty) → gpsd (DEVICES="/dev/gps-nmea") → clientes; chrony pelo SHM do gpsd
```

Por que o algoritmo fica no kernel (como no original): o IRQ de 1 ms reescreve os NCOs de cada
canal antes do próximo bloco e o anel de amostras só segura ≈ 4,5 ms; a tasklet de 5 ms troca
estado com o IRQ por funções de sincronismo (`GpsVarBBSyncISR`/`GpsVarISRSyncBB`). Separar isso
entre kernel e usuário (UIO) muda o mecanismo e põe latência de escalonamento no caminho
crítico. O código do algoritmo fica numa biblioteca C pura (sem dependência de kernel), que
compila tanto no módulo quanto num harness de teste no PC.

### 2.1 Device tree (binding novo, local)

```dts
reserved-memory {
	#address-cells = <1>; #size-cells = <1>; ranges;
	gps_mem: gps@49000000 { reg = <0x49000000 0x1000000>; no-map; };  /* mesmo lugar do original */
};

reg_gps_vcc: regulator-gps-vcc {
	compatible = "regulator-fixed"; regulator-name = "gps-vcc";
	gpio = <&pio 2 22 GPIO_ACTIVE_HIGH>; enable-active-high;            /* PC22 */
};

&pio {
	gps_pins: gps-pins { pins = "PI0", "PI1", "PI2"; function = "gps"; };
};

gps: gps@1c30000 {
	compatible = "allwinner,sun4i-a10-gps";
	reg = <0x01c30000 0x10000>;
	interrupts = <57>;
	clocks = <&ccu CLK_AHB_GPS>;
	resets = <&ccu RST_GPS>;
	pinctrl-names = "default"; pinctrl-0 = <&gps_pins>;
	memory-region = <&gps_mem>;
	vcc-supply = <&reg_gps_vcc>;
	osc-enable-gpios = <&pio 8 14 GPIO_ACTIVE_HIGH>;                        /* PI14 */
	rx-enable-gpios  = <&pio 8 15 GPIO_ACTIVE_HIGH>;                        /* PI15 */
};
```
- Schema YAML do binding (`allwinner,sun4i-a10-gps.yaml`) para passar no `dt-validate`.
- O `spi2_para` do original não entra: o fex tem `spi_used = 0` e o driver só zerava as linhas.
  Conferir no DTS que nada usa PB14–17/PC19–21; se quiser o mesmo estado, `gpio-hog` em 0.
- Começar com a memória no **mesmo endereço do original** (copiar o mecanismo). Depois, testar
  `shared-dma-pool`/CMA com `dma_alloc_coherent` (só precisa de ≈ 5,4 MiB: 0x550000).

### 2.2 Patch de pinctrl (único patch fora do driver)
`drivers/pinctrl/sunxi/pinctrl-sun4i-a10.c`, pinos PI0, PI1, PI2: acrescentar
`SUNXI_FUNCTION_VARIANT(0x2, "gps", PINCTRL_SUN4I_A10)`. Hoje só existem `gpio_in`, `gpio_out` e
i2c3/i2c4 (A20/R40). [O] fonte do 6.18.58; conferir igual no 6.12.

### 2.3 Driver `sun4i-gps` (API moderna)
- `platform_driver` + `of_match_table`; `devm_platform_ioremap_resource`.
- Clock: `devm_clk_get_enabled(dev, NULL)` (AHB). Reset: `devm_reset_control_get_exclusive` e, na
  partida, `assert` → `msleep(10)` → `deassert` (igual ao `clk_reset` do original).
- Energia: `devm_regulator_get(dev, "vcc")`, `devm_gpiod_get(dev, "osc-enable", GPIOD_OUT_LOW)`,
  `devm_gpiod_get(dev, "rx-enable", GPIOD_OUT_LOW)`. Sequência da partida idêntica a
  `CheckRFSec` (ver `driver-original.md` §5), inclusive o retry de 50 ms.
- Memória: `of_reserved_mem_lookup` + `memremap(..., MEMREMAP_WB)` com
  `dma_sync_single_for_cpu` só na metade de 20 ms que acabou (o original invalidava 320 KiB a
  cada ms), ou `dma_alloc_noncoherent`. Endereço físico vai para `MemAddr` dos canais e DMA1.
- Registradores: `readl_relaxed/writel_relaxed` em acessores próprios (caminho quente no IRQ);
  `regmap` só para o dump em debugfs, se quiser.
- IRQ: `devm_request_irq` em hardirq (trabalho curto e com prazo). Processamento de 5 ms:
  `kthread` com `sched_set_fifo()`, acordada por `complete()` do IRQ. Leitura: `wait_queue` +
  sinalização 1×/s (em vez do semáforo do original).
- `/dev/gps`: `miscdevice` com a mesma ABI (0x80 START, 0x81 STOP, 0x82 UPDATE, 0x83 VERSION,
  `read` de 0xD40). Diferenças obrigatórias:
  - `copy_from_user`/`copy_to_user` sempre (o original escreve direto no ponteiro do usuário no
    0x80, o que falha com PAN no 6.12);
  - **validar tudo que vem do usuário**: número de canais (o original aceita qualquer valor de
    `InitBuf[0]` e `BB_Val_Check` é um stub, o que estoura vetores do kernel), índices de canal
    dos comandos, tamanhos; recusar `read` com tamanho diferente de 0xD40;
  - um só aberto por vez; `release` faz o STOP.
- debugfs: registradores, contadores de IRQ atrasado (`WriteAddrErr`), energias por canal.
- Desligar o gate AHB no STOP (o original esquecia).

## 3. Fases, testes que provam cada uma e esforço

Esforço em semanas de trabalho focado (uma pessoa + Claude), com faixa honesta.

### Fase 0: tudo que dá sem o aparelho (2–3 semanas)
| Entrega | Teste que prova |
|---|---|
| Binding YAML + nó no DTS + patch de pinctrl | `dtc` sem aviso, `dt-validate` com o schema novo, kernel 6.12 compila |
| Esqueleto do `sun4i-gps` (probe, energia, ABI, validação) | compila com `W=1` e `sparse`; boot no QEMU `-M cubieboard` com o nó: o probe roda, falha de forma limpa sem o hardware (o QEMU não emula o bloco) e não deixa nada ligado; teste da ABI com um backend falso de registradores |
| **Harness diferencial**: o código original do `gps.ko` rodando em espaço do usuário | ver §4; roda no WSL com `qemu-arm-static` |
| Gravação do diálogo da HAL: libhybris + `gps.exDroid.so` + `/dev/gps` falso (CUSE) | a HAL carrega, chama 0x80/0x83 e manda os comandos de partida fria; o log mostra o buffer de inicialização e os comandos reais (complementa o que a análise estática deu) |

### Fase A: prova de hardware com o algoritmo original (2–4 semanas, inclui aparelho)
Para uso **só no aparelho do dono** (não redistribuível): religar o código objeto original do
algoritmo (`algpro/*`) num módulo 6.12, trocando toda a camada de plataforma.
- Viável porque [O] todas as chamadas do `gps.ko` passam por relocação de símbolo (até as
  internas, `R_ARM_CALL`/`R_ARM_JUMP24`) e os registradores só são tocados em `RegAccess.c`
  (endereços fixos 0xF1C3xxxx; nenhum outro acesso direto). Basta `objcopy` tirar
  `.modinfo/__versions/.gnu.linkonce.this_module`, enfraquecer (`--weaken-symbol`) as funções de
  `PALAPI.c`, `lnxdrv_F30.c`, `gpsdriver.c`, `RegAccess.c` e `Alg_Platform.c`, e fornecer versões
  novas delas (ioremap, `copy_*_user`, GPIO descriptors, reset). Os imports antigos que sobrarem
  nos corpos substituídos (`gpio_request_ex`, `clk_reset`, `cpu_cache`…) recebem stubs locais.
- Userspace: `gps-a10d` com libhybris carregando a HAL original; NMEA para pty; `gpsd`.
- Testes no aparelho, em ordem: (1) depois do reset, IntrEna lê 0xFFF9 e o IRQ 57 conta
  1000/s em `/proc/interrupts`; (2) `RFWritePoint` avança 0x1550 por ms; (3) `CheckRFSec` bate o
  padrão (registra qual valor de 0x408 foi usado); (4) as áreas de DMA recebem I/Q diferentes
  de zero; (5) ao ar livre, picos de energia acima do limiar em PRNs que o celular vê;
  (6) bits de navegação com o preâmbulo 10001011 a cada 6 s; (7) fix com erro < 30 m contra o
  celular e `gpsmon` mostrando o NMEA.

### Fase B: algoritmo reimplementado (clean-room) (6–10 semanas)
- Reescrever `algpro` a partir de `algoritmo.md`/`registradores.md` e do comportamento medido no
  harness (não copiar o pseudocódigo do Ghidra para o fonte novo).
- Prova sem aparelho: **equivalência diferencial** função a função e de ponta a ponta contra o
  original (§4), em entradas sintéticas e nas gravadas na Fase A.
- Prova no aparelho: troca a versão relinkada pela nova, mesma HAL, mesmo resultado (tempo até o
  primeiro fix, número de satélites, C/N0) em 3 sessões ao ar livre.

### Fase C (opcional): HAL aberta (8–16 semanas)
- Gerência de canais e busca (fria: 32 PRNs × faixa de Doppler; morna/quente com almanaque),
  decodificação LNAV (preâmbulo, paridade, subframes) e PVT com **RTKLIB** (BSD-2), saída NMEA.
- Prova sem aparelho: alimentar com as medições e bits gravados na Fase A e comparar posição e
  tempo com o que a HAL original deu nos mesmos dados.
- Tira a dependência de libhybris e de binário da Android.

### Estágio extra (opcional, 2–4 semanas): modelo de software do bloco de GPS
Gerar amostras de FI de 2 bits a 16,368 MHz com `gps-sdr-sim` e passar por um modelo em C do
correlator (anel, NCOs de 26 bits, G2, 64 correlatores, DMA de 0x100 B/ms). Se o algoritmo
original + HAL original derem fix no modelo, o entendimento do hardware está certo antes de ligar
o aparelho; depois o modelo vira teste de regressão das Fases B e C.

### Totais
| Caminho | Esforço | Risco |
|---|---|---|
| USB u-blox + gpsd (alternativa) | 1 dia | baixo |
| Fases 0 + A (kernel novo, algoritmo e HAL originais, uso pessoal) | 4–7 semanas | médio |
| + Fase B (algoritmo aberto, HAL original) | +6–10 semanas (≈ 3–4 meses no total) | médio |
| + Fase C (tudo aberto) | +8–16 semanas (≈ 5–8 meses no total) | médio-alto |

## 4. Harness diferencial (o teste principal sem aparelho)

- O `gps.ko` é um ELF relocável ARM com DWARF. No WSL: `objcopy` como na Fase A, ligar com
  stubs de PAL e um **banco de registradores falso** (vetor em memória que registra cada
  leitura/escrita), compilar com a toolchain `arm-linux-gnueabi` (soft-float, a mesma ABI do
  kernel) e rodar com `qemu-arm-static`.
- Casos: funções puras (`GetAcqCodeFreq`, `fixed_atan2`, `norm_l`, `Gps_Div64`, `NormalizeEnergy`,
  `DataDecode`, `CoarseFllProcess`, `CoarsePllProcess`), o parser de comandos
  (`GpsChannelInit`, `GpsCommandParsePro`: estado depois de cada comando) e o laço inteiro
  (`GpsISRPro` + `baseband_process`) com saídas de correlator sintéticas (pico de autocorrelação
  C/A com Doppler, fase e ruído conhecidos).
- Critério: mesma sequência de escritas nos registradores e mesmos 0xD40 bytes de saída, bit a
  bit, para a mesma entrada. Também serve de teste de propriedade (entradas aleatórias).

## 5. O que dá para reaproveitar do original

| Item | Como |
|---|---|
| Sequência de energia, reset, checagem do RF e init do baseband | reimplementar igual (documentada) |
| Mapa de registradores e formato das áreas de DMA | igual |
| ABI `/dev/gps` (ioctl e read) e formatos (`GPS_INFO_DATA`, comandos 1–8) | igual, com validação |
| Tabelas de parâmetros (modos, limiares, CORDIC) | são dados de ajuste numérico; usar como parâmetros de partida |
| Código objeto do algoritmo | só na Fase A e no harness (aparelho do dono, sem redistribuir) |
| HAL `gps.exDroid.so` | via libhybris no aparelho do dono (Fases A/B) |
| Fonte do `gps.ko` | o módulo se declara GPL: vale pedir o fonte ao fabricante/Allwinner; se vier, encurta a Fase B |

## 6. Riscos e desconhecidos

1. **Hardware do aparelho**: bateria inchada. Precisa rodar sem bateria (AXP209 aceita só ACIN/
   VBUS) e a antena/front-end precisam estar bons. Sem isso, as Fases A–C param na Fase 0.
2. **Front-end RF desconhecido** (nome e frequências). A FI ≈ 4 MHz e a amostragem de
   16,368 MHz são inferidas; confirmar na Fase A pelo Doppler dos satélites achados.
3. **Relógio de módulo do GPS (CCU 0x0D0)**: o original nunca o liga (só reset) e o mainline o
   marca como não implementado. [I] O bloco provavelmente usa o relógio que chega do RF (PI0). Se
   não andar, conferir o valor desse registrador no Android (dump salvo, se houver) e no boot.
4. **Valores de 0x408 e 0x41C**: copiados do original; significado em aberto.
5. **libhybris com Bionic do Android 4.0** em Debian 13 armhf: o libhybris mira Androids mais
   novos; pode exigir as `libc.so`/`libstdc++.so` do próprio aparelho (estão no backup) e
   ajustes (a HAL usa `sem_open`, pthread com prioridade). Risco médio; não está empacotado no
   Debian, compilar do fonte.
6. **Tempo real**: IRQ a 1 kHz e kthread de 200 Hz em kernel 6.12 `PREEMPT_DYNAMIC`. O anel
   de 4,5 ms e a compensação de IRQ atrasado do próprio algoritmo dão folga; medir `WriteAddrErr`.
7. **CPU**: em modos de alta sensibilidade o algoritmo é pesado; pode competir com a interface
   gráfica. Medir na Fase A.
8. **Licença**: binários originais só no aparelho do dono; o que for publicado é o código novo.
