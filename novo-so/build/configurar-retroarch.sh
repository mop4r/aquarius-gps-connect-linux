#!/bin/bash
# Configura o modo jogos (RetroArch) no rootfs do GPS: controle na tela, listas por console,
# ajustes para o A10 (Cortex-A8 + Mali-400, 800x480), controles USB e saida para o modo tablet.
# uso: configurar-retroarch.sh <rootfs> <pasta-com-aquarius-listas-jogos.py> [pasta-jogos-livres]
set -euo pipefail
R=${1:?rootfs}; B=${2:?pasta do build}; JL=${3:-}
[ -d "$R/etc" ] && [ -f "$B/aquarius-listas-jogos.py" ] || { echo "argumento invalido" >&2; exit 1; }

# Versoes fixas dos dois projetos do libretro que o Debian nao empacota
OVERLAYS_COMMIT=84250057ec476554aed8145c61811d824a0f08fd   # libretro/common-overlays (CC-BY-4.0)
AUTOCONF_COMMIT=2e3b8a2728d5efd00fa0207d07ba2488b89e87b2   # libretro/retroarch-joypad-autoconfig (MIT)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
baixar() {  # repo commit destino
  curl -fsSL --proto '=https' --max-filesize 200000000 -o "$T/$1.tgz" "https://codeload.github.com/libretro/$1/tar.gz/$2"
  mkdir -p "$T/$1"; tar -xzf "$T/$1.tgz" -C "$T/$1" --strip-components=1 --no-same-owner
}
baixar common-overlays "$OVERLAYS_COMMIT"
baixar retroarch-joypad-autoconfig "$AUTOCONF_COMMIT"

L="$R/usr/local/share/libretro"
rm -rf "$L/overlays" "$L/autoconfig"; mkdir -p "$L/overlays" "$L/autoconfig"
cp -r "$T/common-overlays/gamepads" "$L/overlays/"
cp "$T/common-overlays/COPYING" "$L/overlays/COPYING-CC-BY-4.0"
# cage/Wayland usa o driver de controle udev
cp -r "$T/retroarch-joypad-autoconfig/udev" "$L/autoconfig/"
cp "$T/retroarch-joypad-autoconfig/COPYING" "$L/autoconfig/COPYING-MIT"
printf 'Overlays: libretro/common-overlays @ %s (CC-BY-4.0, The RetroArch team)\nAutoconfig: libretro/retroarch-joypad-autoconfig @ %s (MIT)\n' \
  "$OVERLAYS_COMMIT" "$AUTOCONF_COMMIT" > "$L/CREDITOS.txt"

# Gerador das listas (roda antes de cada abertura do modo jogos)
install -m 0755 "$B/aquarius-listas-jogos.py" "$R/usr/local/bin/aquarius-listas-jogos"
install -d "$R/etc/systemd/system/aquarius-retroarch.service.d"
cat > "$R/etc/systemd/system/aquarius-retroarch.service.d/listas.conf" <<'EOF'
[Service]
Environment=HOME=/home/jogador
ExecStartPre=/usr/local/bin/aquarius-listas-jogos
EOF

# Pastas de jogos por console (+ jogos livres, se vieram)
J="$R/home/jogador/Jogos"
for c in NES SNES MegaDrive MasterSystem GameGear GB GBC GBA NDS; do install -d "$J/$c"; done
cat > "$J/LEIA-ME.txt" <<'EOF'
Copie os jogos para a pasta do console (NES, SNES, MegaDrive, MasterSystem, GameGear, GB, GBC,
GBA, NDS). Pode ser o arquivo do jogo ou .zip, direto na pasta ou numa subpasta.
Na proxima vez que o modo jogos abrir, eles aparecem no menu do console.
EOF
if [ -n "$JL" ] && [ -d "$JL" ]; then
  for c in NES SNES MegaDrive MasterSystem GB GBC GBA; do
    [ -d "$JL/$c" ] && find "$JL/$c" -maxdepth 1 -type f -exec cp -n {} "$J/$c/" \;
  done
  [ -f "$JL/CATALOGO.md" ] && cp "$JL/CATALOGO.md" "$J/JOGOS-LIVRES-CATALOGO.md"
fi

# Configuracao do RetroArch do jogador
C="$R/home/jogador/.config/retroarch"; install -d "$C" "$C/saves" "$C/states" "$C/screenshots" "$C/system"
cat > "$C/retroarch.cfg" <<'EOF'
# --- Aquarius (A10 Cortex-A8 + Mali-400, LCD 800x480) ---
libretro_directory = "/usr/lib/arm-linux-gnueabihf/libretro/"
libretro_info_path = "/usr/share/libretro/info/"
assets_directory = "/usr/share/libretro/assets/"
overlay_directory = "/usr/local/share/libretro/overlays/"
joypad_autoconfig_dir = "/usr/local/share/libretro/autoconfig/"
playlist_directory = "~/.config/retroarch/playlists/"
rgui_browser_directory = "~/Jogos/"
savefile_directory = "~/.config/retroarch/saves/"
savestate_directory = "~/.config/retroarch/states/"
screenshot_directory = "~/.config/retroarch/screenshots/"
system_directory = "~/.config/retroarch/system/"

# Wayland direto (dentro do cage): pelo XWayland o toque nao chega ao RetroArch (04/11)
video_context_driver = "wayland"
input_driver = "wayland"
menu_pointer_enable = "true"
menu_mouse_enable = "true"

# Video leve: tela cheia nativa, sem shader, sem filtro, vsync
video_driver = "gl"
video_fullscreen = "true"
video_windowed_fullscreen = "true"
video_vsync = "true"
video_threaded = "false"
video_smooth = "false"
video_shader_enable = "false"
video_scale_integer = "false"
video_aspect_ratio_auto = "true"
video_font_enable = "true"
video_frame_delay = "0"
video_max_swapchain_images = "2"

# Audio direto no ALSA, pouco atraso
audio_driver = "alsa"
audio_device = "plughw:CARD=sun4icodec,DEV=0"
audio_latency = "64"
audio_sync = "true"
audio_out_rate = "44100"

# Desliga o que pesa no Cortex-A8
rewind_enable = "false"
run_ahead_enabled = "false"
preemptive_frames_enable = "false"
fps_show = "false"

# Menu: XMB sem o fundo animado (shader)
menu_driver = "xmb"
xmb_shader_pipeline = "0"
menu_show_quit_retroarch = "true"
quit_press_twice = "false"
pause_nonactive = "false"

# Toque: controle virtual na tela (o GPS nao tem botoes de jogo)
input_overlay_enable = "true"
input_overlay = "/usr/local/share/libretro/overlays/gamepads/neo-retropad/neo-retropad.cfg"
input_overlay_opacity = "0.55"
input_overlay_scale = "1.000000"
input_overlay_hide_in_menu = "true"
input_overlay_hide_when_gamepad_connected = "true"
input_overlay_show_mouse_cursor = "false"
input_overlay_auto_rotate = "false"

# Controle USB: reconhecimento automatico; Start+Select abre o menu
input_joypad_driver = "udev"
input_autodetect_enable = "true"
input_menu_toggle_gamepad_combo = "4"
input_max_users = "2"

# Teclado USB/bluetooth tambem funciona; F1 = menu
input_menu_toggle = "f1"
EOF
chroot "$R" chown -R jogador:jogador /home/jogador
echo "retroarch configurado"
