#!/bin/sh
# Set up the parts of the Steam distrobox home that the image cannot carry.
#
# Run inside the container:
#   distrobox enter steam -- /run/host/etc/nixos/hosts/asahi/steam/setup-home.sh
#
# Idempotent; safe to re-run after recreating the container.
set -eu

STEAM_HOME="${HOME}"

# Fonts.
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
