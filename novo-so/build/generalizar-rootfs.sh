#!/bin/bash
# Ultimo passo antes do montar-imagem.sh para a imagem PUBLICAVEL: tira tudo o que e de uma casa (Wi-Fi, chave SSH,
# senhas) e liga o aquarius-config-inicial, que no boot aplica /boot/aquarius.txt (o usuario escreve no Windows) e
# apaga o arquivo. Sem o aquarius.txt o GPS liga no modo jogos normalmente, sem rede.
# uso: generalizar-rootfs.sh <rootfs>
set -euo pipefail
export DPKG_DEB_THREADS_MAX=1 GLIBC_TUNABLES=glibc.pthread.rseq=0   # qemu-user (ver montar-rootfs.sh)
R=${1:?rootfs}
[ -x "$R/usr/local/sbin/aquarius-config-inicial" ] && [ -f "$R/etc/systemd/system/aquarius-config-inicial.service" ] \
  || { echo "rode antes o aplicar-ajustes-do-aparelho.sh (falta o aquarius-config-inicial)" >&2; exit 1; }
c() { chroot "$R" "$@"; }

# Wi-Fi e chave SSH de quem montou
rm -f "$R"/etc/NetworkManager/system-connections/*
rm -f "$R/root/.ssh/authorized_keys" "$R"/root/.bash_history "$R"/home/jogador/.bash_history
# root sem senha de console (so entra pela chave do aquarius.txt; "*" e nao "!", que o sshd trata como conta travada)
c usermod -p '*' root
# jogador: senha padrao "aquarius" (documentada no README; o SSH nao aceita senha) ate o aquarius.txt trocar
h=$(printf '%s' aquarius | openssl passwd -6 -stdin); [[ $h == '$6$'* ]] || { echo "hash falhou" >&2; exit 1; }
printf 'jogador:%s\n' "$h" | c chpasswd -e

c systemctl enable aquarius-config-inicial.service >/dev/null 2>&1
# modelo na particao de boot (FAT, aparece no Windows); CRLF para o Bloco de Notas
sed 's/$/\r/' > "$R/boot/aquarius-exemplo.txt" <<'EOF'
# Configuracao do GPS Aquarius. Copie este arquivo para "aquarius.txt" (nesta mesma pasta), preencha e ligue o GPS:
# no boot ele aplica e APAGA o aquarius.txt. Campo vazio = nao mexe. Para trocar o Wi-Fi depois, crie outro.
#
# Rede Wi-Fi de 2,4 GHz (o GPS nao enxerga 5 GHz). Nome ate 32 caracteres, sem ; e sem \
WIFI_NOME=
WIFI_SENHA=
# Senha nova do usuario "jogador" (modo tablet, sudo). A padrao da imagem e: aquarius
SENHA=
# Chave publica SSH (uma linha "ssh-ed25519 AAAA..."), para entrar como root pela rede
CHAVE_SSH=
EOF

# conferencia: nada de casa ficou
[ -z "$(ls -A "$R/etc/NetworkManager/system-connections" 2>/dev/null)" ] || { echo "sobrou conexao de rede" >&2; exit 1; }
[ ! -e "$R/root/.ssh/authorized_keys" ] || { echo "sobrou authorized_keys" >&2; exit 1; }
grep -q '^root:\*:' "$R/etc/shadow" || { echo "root ainda com senha" >&2; exit 1; }
[ -L "$R/etc/systemd/system/multi-user.target.wants/aquarius-config-inicial.service" ] || { echo "servico nao ligado" >&2; exit 1; }
echo "rootfs generalizado (sem Wi-Fi, sem chave SSH; jogador com a senha padrao)"
