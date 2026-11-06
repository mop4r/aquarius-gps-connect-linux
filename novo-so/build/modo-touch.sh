#!/bin/bash
# Modo tablet mais "de toque" no XFCE (X11) do GPS: rolagem com o dedo, toque longo = clique direito,
# clique unico, elementos maiores. Roda como root no aparelho; a parte do usuario usa a sessao viva
# do jogador se houver, senao grava os XML do xfconf. Idempotente.
set -euo pipefail
U=jogador; H=/home/$U

# 1) Toque longo = clique direito: touchscreen pelo driver evdev com emulacao do 3o botao
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq xserver-xorg-input-evdev >/dev/null
install -d /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/40-aquarius-touch.conf <<'EOF'
# Touch FocalTech do GPS: evdev com toque longo (0,7 s parado) = clique direito
Section "InputClass"
    Identifier      "aquarius-touch"
    MatchIsTouchscreen "on"
    MatchProduct    "ft5x06"
    Driver          "evdev"
    Option          "EmulateThirdButton" "on"
    Option          "EmulateThirdButtonTimeout" "700"
    Option          "EmulateThirdButtonMoveThreshold" "30"
EndSection
EOF

# 2) Firefox com eventos de toque reais (rolagem com o dedo, pinca para zoom)
cat > /etc/X11/Xsession.d/90aquarius-touch <<'EOF'
# Firefox: XInput2 = toque de verdade (rolagem e zoom com os dedos)
export MOZ_USE_XINPUT2=1
EOF
install -d /usr/lib/firefox-esr/defaults/pref
cat > /usr/lib/firefox-esr/defaults/pref/aquarius-touch.js <<'EOF'
pref("dom.w3c_touch_events.enabled", 1);
pref("apz.allow_zooming", true);
pref("layout.css.devPixelsPerPx", "1.2");
EOF

# 3) Preferencias do usuario (clique unico, tamanhos). Com a sessao viva usa xfconf-query.
P=$(pgrep -u $U -x xfce4-session | head -1 || true)
if [ -n "$P" ]; then
  BUS=$(tr '\0' '\n' < /proc/$P/environ | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p')
  xq() { runuser -u $U -- env DBUS_SESSION_BUS_ADDRESS="$BUS" DISPLAY=:0 xfconf-query "$@"; }
  xq -c xfce4-desktop -p /desktop-icons/single-click -n -t bool -s true
  xq -c xfce4-desktop -p /desktop-icons/icon-size -n -t int -s 48
  xq -c thunar -p /misc-single-click -n -t bool -s true
  xq -c xfwm4 -p /general/theme -n -t string -s "Default"
  xq -c xfwm4 -p /general/title_font -n -t string -s "Sans Bold 9"
  xq -c xsettings -p /Gtk/CursorThemeSize -n -t int -s 24
  xq -c xsettings -p /Net/DoubleClickTime -n -t int -s 500
  xq -c xsettings -p /Net/DndDragThreshold -n -t int -s 24
  for p in $(xq -c xfce4-panel -l | grep -E '^/panels/panel-[0-9]+/size$'); do xq -c xfce4-panel -p "$p" -s 30; done
  for p in $(xq -c xfce4-panel -l | grep -E '^/panels/panel-[0-9]+/icon-size$'); do xq -c xfce4-panel -p "$p" -s 0; done
  echo "preferencias aplicadas na sessao viva"
else
  echo "sem sessao XFCE viva: preferencias ficam para o proximo login (rode de novo com o tablet aberto)"
fi
echo "touch: reinicie o modo tablet (aquarius-trocar-modo tablet) para o evdev valer"
