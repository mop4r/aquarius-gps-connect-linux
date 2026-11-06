# Aquarius Connect 5.0 (Guia Quatro Rodas) — extração do cartão SD

Conteúdo do cartão SD de 2 GB (FAT16) que estava no GPS **Aquarius Connect 5.0 / Guia
Quatro Rodas**, extraído em **2026-11-03** no PC de casa (`Pedro`).

## Por que o cartão "não aparecia"
O cartão estava saudável, mas o Windows **não atribuiu letra de unidade** a ele
(partição FAT16 "MS-DOS V4 Huge", Disco 4 / `/dev/sde`, ~1,99 GB). Bastou dar uma letra
(`Set-Partition -NewDriveLetter G`) para montar e ler.

## O que tinha no cartão
Software de navegação **iGO My Way 8.4.3 (motor "Amigo", build Android)** com mapa do
Brasil — exatamente o software do GPS.

- `iGO/` — instalação completa (266 arquivos, 414,28 MB)
  - `content/map/Brazil.fbl` (114,9 MB) + `Basemap.fbl` (9,1 MB) — **mapa Brasil, 2013-09-04**
  - `content/dem/` (199,6 MB) — relevo 3D
  - `content/poi/` (55,8 MB) — pontos de interesse
  - `content/speedcam/speedcam.txt` + `SpeedcamUpdates.spud` — radares (2013-09-02); +
    pedágios, quebra-molas, túneis (2009)
  - `content/lang/Lang_Portuguese-ptbr.gro` — idioma PT-BR
  - `content/voice/`, `audio/EN`, `audio/RU` — vozes
  - `license/` — **licenças travadas ao aparelho**: `device.nng`,
    `Android_Amigo_WW@1001_JM-PPCW.lic`, `Android_Amigo_Engine_Multilang.lyc`,
    `Full_Europe_NQ_Subscription_2009_Q3.lic`, `LCP_43J_FEU@0807_(NNG+TA_HUN_TMC).lic`
  - `data.gro` (6,33 MB), `branding.gro`, `sys.txt` (config — `type="android"`),
    `iGO My Way v8.4.3.179971 ...apk` (3,63 MB)
- `LOST.DIR` — vazia (resíduo de fsck FAT); não copiada
- `System Volume Information` — criada pelo Windows ao montar; não é do GPS

## Arquivos desta pasta
- `arquivos/iGO/` — cópia dos arquivos pelo sistema de arquivos (robocopy, **0 falhas**)
- `sd-card-dump/aquarius-connect-5pol-full.img` — **imagem bruta** do cartão inteiro
  (1.992.294.400 bytes). Feita ANTES de montar, então não contém `System Volume Information`.
  - `*.img.sha256` — `ABCFED9C3B0E9BA3B813E98E0E7D7281B4BDE39E0EFABFE5DB7E95C9DED6F8FC`
- `robocopy.log`, `indice-arquivos.txt`

## Nota sobre a imagem bruta
O `dd` (bs=4M, `conv=noerror,sync`) acusou poucos **erros de leitura** (~184 MB e
~480–492 MB) preenchidos com zero. Esses setores caíam em **espaço livre**: a cópia pelo
sistema de arquivos leu os 266 arquivos **sem nenhuma falha**, então nenhum arquivo foi
afetado. Para uma imagem 100% byte-a-byte (se um dia precisar), reimagear com `ddrescue`.

## Restaurar em outro cartão
Imagem é do disco inteiro (MBR + partição). Para recriar o cartão:
`dd if=aquarius-connect-5pol-full.img of=/dev/sdX bs=4M` (gravar no cartão vazio). As
licenças em `license/` são travadas ao aparelho original — podem não validar em outro device.

## Como atualizar mapa/radares
**Não é pelo menu do GPS.** O aparelho é offline (iGO Amigo 8.4.3; `sys.txt` com
`location_net=0`, `tmc-http=0`, servidor comentado) — ele não baixa mapa sozinho. Toda
atualização é **no PC**, por dois caminhos:

1. **Oficial — Naviextras Toolbox** (naviextras.com/toolbox, grátis da NNG): conecta o
   cartão/aparelho em modo armazenamento em massa; o Toolbox lê `license/device.nng` e, se o
   device estiver na lista de suportados, mostra os updates. Ressalvas: (a) rebrands BR como
   este normalmente **não** estão na lista (licença OEM) → Toolbox não reconhece; (b) a janela
   de update grátis (~2 anos) expirou — só update **pago**; (c) portal da Aquarius morto.
2. **Manual (o que funciona na prática):** trocar os arquivos no cartão —
   `content/map/Brazil.fbl` (+`Basemap.fbl`) por um mapa Brasil mais novo **compatível com o
   motor Amigo 8.4.3** (mapa de iGO Primo/NextGen NÃO roda no Amigo), e atualizar
   `content/speedcam/speedcam.txt` (radares — esse é fácil, é só texto). Mapa novo vem de
   fórum BR (gpsclube/gpsinfo, cadastro) ou pacote pago pronto (gpsaquarius.com.br,
   rotacertagps). Mapa tem que casar com a licença `.lic`/`device.nng`.

Como há backup completo, dá pra testar à vontade: se quebrar, regravar o cartão pela imagem.
