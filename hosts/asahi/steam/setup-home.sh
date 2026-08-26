#!/bin/sh
# Set up the parts of the Steam distrobox home that the image cannot carry.
#
# Run inside the container:
#   distrobox enter steam -- /etc/nixos/hosts/asahi/steam/setup-home.sh
#
# Idempotent; safe to re-run after recreating the container.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
STEAM_HOME="${HOME}"

# 1. Fonts.
#
# The Steam client is an x86 binary running under FEX, so it reads
# /usr/share/fonts from the FEX rootfs, not from this container. $HOME is
# passed through to the guest, so user fonts are the only ones it can see -
# without this every CJK string in the UI renders as tofu.
fonts_dir="$STEAM_HOME/.local/share/fonts"
mkdir -p "$fonts_dir"
for f in /usr/share/fonts/google-noto-sans-cjk-vf-fonts/*.ttc \
         /usr/share/fonts/google-noto-serif-cjk-vf-fonts/*.ttc; do
    [ -e "$f" ] || continue
    dest="$fonts_dir/$(basename "$f")"
    [ -e "$dest" ] || cp "$f" "$dest"
done
fc-cache -f "$fonts_dir" >/dev/null 2>&1 || true
echo "fonts: $(ls "$fonts_dir" | wc -l) file(s) in $fonts_dir"

# 2. The proton9-nosrt compatibility tool.
#
# See README.md: pressure-vessel hides the FEX i386 Mesa overlay, which breaks
# every 32-bit OpenGL title. This tool runs Proton without that container.
tools_dir="$STEAM_HOME/.local/share/Steam/compatibilitytools.d"
mkdir -p "$tools_dir"
cp -r "$HERE/compatibilitytools.d/proton9-nosrt" "$tools_dir/"
chmod +x "$tools_dir/proton9-nosrt/proton-nosrt"
echo "compat tool: installed to $tools_dir/proton9-nosrt"

echo
echo "Restart Steam, then pick 'Proton 9.0 (no Steam Runtime)' under"
echo "Properties -> Compatibility for OpenGL titles."
