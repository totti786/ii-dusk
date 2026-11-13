#!/usr/bin/env bash
# Prints the image the colour previews should read for a wallpaper path.
# Pillow cannot open JPEG XL, so a .jxl is decoded to a PNG copy in the same cache switchwall.sh
# uses (same key, so the two share it); anything else is printed as it is.
src="$1"
case "${src,,}" in
*.jxl)
    key="$(printf '%s %s' "$src" "$(stat -c %Y -- "$src" 2>/dev/null)" | md5sum | cut -c1-16)"
    out="${XDG_CACHE_HOME:-$HOME/.cache}/switchwall/decoded/$key.png"
    if [[ ! -s "$out" ]]; then
        mkdir -p "$(dirname "$out")"
        tmp="$out.$$.tmp.png"
        if { command -v magick >/dev/null && magick "$src[0]" -resize '2560x2560>' "$tmp" 2>/dev/null; } \
            || { command -v djxl >/dev/null && djxl "$src" "$tmp" --quiet 2>/dev/null; }; then
            mv -f -- "$tmp" "$out"
        else
            rm -f -- "$tmp"
            printf '%s' "$src"
            exit 0
        fi
    fi
    printf '%s' "$out"
    ;;
*) printf '%s' "$src" ;;
esac
