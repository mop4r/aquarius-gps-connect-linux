#!/bin/bash
# Testes do aquarius-config-inicial (raiz falsa, valores ficticios). Rodar como root no Linux/WSL:
#   bash novo-so/build/testes/testar-config-inicial.sh   -> "falhas=0"
X=$(cd "$(dirname "$0")/../../arquivos-do-aparelho" && pwd)/usr/local/sbin/aquarius-config-inicial
falhas=0; ok() { echo "ok   $1"; }; ruim() { echo "FALHA $1"; falhas=$((falhas+1)); }
novo() { T=$(mktemp -d); mkdir -p $T/etc $T/boot; echo 'jogador:x:1000:1000::/home/jogador:/bin/bash' > $T/etc/passwd; echo 'jogador:*:1::::::' > $T/etc/shadow; chmod 600 $T/etc/shadow; }
roda() { AQ_RAIZ=$T AQ_ARQUIVO=$T/boot/aquarius.txt bash $X; }
C=$T/etc/NetworkManager/system-connections/aquarius.nmconnection
# 1 completo, Bloco de Notas (BOM + CRLF)
novo; printf '\xef\xbb\xbfWIFI_NOME=Rede Teste 2G\r\nWIFI_SENHA=senha-ficticia-123\r\nSENHA=jogo1234\r\nCHAVE_SSH=ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeFakeFakeFakeFakeFakeFakeFakeFakeFake1 pc\r\n' > $T/boot/aquarius.txt
o=$(roda); C=$T/etc/NetworkManager/system-connections/aquarius.nmconnection
grep -qx 'ssid=Rede Teste 2G' $C && grep -qx 'psk=senha-ficticia-123' $C && ok "wifi com BOM/CRLF" || ruim "wifi com BOM/CRLF"
[ "$(stat -c %a $C)" = 600 ] && ok "permissao 600" || ruim "permissao $(stat -c %a $C)"
grep -q '^jogador:\$' $T/etc/shadow && ok "senha trocada" || ruim "senha nao trocada"
grep -q '^ssh-ed25519 AAAA' $T/root/.ssh/authorized_keys && ok "chave ssh" || ruim "chave ssh"
[ ! -e $T/boot/aquarius.txt ] && ok "arquivo apagado" || ruim "arquivo ficou"
echo "$o" | grep -q 'senha-ficticia\|jogo1234' && ruim "segredo no log" || ok "log sem segredo"
roda >/dev/null; [ "$(grep -c ssh-ed25519 $T/root/.ssh/authorized_keys 2>/dev/null)" = 1 ] && ok "sem arquivo: nada muda" || ruim "sem arquivo"
# 2 invalidos: ssid com ; e senha wifi curta, senha curta, chave lixo
novo; printf 'WIFI_NOME=a;b\nWIFI_SENHA=12345678\nSENHA=12\nCHAVE_SSH=lixo $(id)\n' > $T/boot/aquarius.txt
o=$(roda); C=$T/etc/NetworkManager/system-connections/aquarius.nmconnection
[ ! -e $C ] && ok "ssid com ; recusado" || ruim "ssid com ; gravado"
grep -q '^jogador:\*' $T/etc/shadow && ok "senha curta recusada" || ruim "senha curta aceita"
[ ! -e $T/root/.ssh/authorized_keys ] && ok "chave lixo recusada" || ruim "chave lixo aceita"
[ ! -e $T/boot/aquarius.txt ] && ok "invalido tambem apagado" || ruim "invalido ficou"
echo "$o" | grep -q 'aplicado em parte' && ok "avisa o que falhou" || ruim "nao avisou"
novo; printf 'WIFI_NOME=CasaX\nWIFI_SENHA=1234567\n' > $T/boot/aquarius.txt; roda >/dev/null
[ ! -e $T/etc/NetworkManager/system-connections/aquarius.nmconnection ] && ok "psk de 7 recusada" || ruim "psk de 7 aceita"
# 3 falha no meio (sem /etc/shadow): o arquivo com senha sai do cartao mesmo assim
novo; rm $T/etc/shadow; printf 'SENHA=abcd1234\n' > $T/boot/aquarius.txt; roda >/dev/null 2>&1
[ ! -e $T/boot/aquarius.txt ] && ok "falha no meio: arquivo apagado" || ruim "falha no meio: arquivo ficou"
echo "falhas=$falhas"
[ "$falhas" = 0 ]
