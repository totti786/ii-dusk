#!/usr/bin/env bash
# Build vendor/books.pyz from the books-cli checkout, with its pure-Python dependencies bundled.
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
root="$(cd -- "$(dirname -- "$self")/.." && pwd)"
source="${1:-$HOME/Projects/books-cli}"
python="${PYTHON:-python3}"
out="$root/vendor/books.pyz"

if [ ! -f "$source/books.py" ]; then
    echo "books: $source is not a books-cli checkout" >&2
    exit 2
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
for f in "$source"/*.py; do
    case "$(basename "$f")" in test_*|conftest.py) continue ;; esac
    cp "$f" "$tmp/"
done
printf 'import sys\nfrom books import main\nsys.exit(main())\n' > "$tmp/__main__.py"
# requests, beautifulsoup4 and websocket-client are pure Python; the optional compiled
# charset_normalizer speedups cannot load from a zip, so drop them and let it fall back.
"$python" -m pip install -q --disable-pip-version-check --no-compile --target "$tmp" \
    requests beautifulsoup4 websocket-client
find "$tmp" -name '*.so' -delete
find "$tmp" -type d \( -name __pycache__ -o -name '*.dist-info' \) -prune -exec rm -rf {} +

mkdir -p "$root/vendor"
"$python" -m zipapp "$tmp" -p "/usr/bin/env python3" --compress -o "$out"
chmod 755 "$out"
"$python" -I "$out" --help >/dev/null
printf 'built %s (%s bytes)\n' "$out" "$(stat -c%s "$out")"
