#!/usr/bin/env bash
# Build vendor/books-rs from a books-cli checkout's rust/ crate. Optional: ii-dusk does not ship
# books-cli, so this is for someone who has their own checkout.
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
root="$(cd -- "$(dirname -- "$self")/.." && pwd)"
source="${1:-$HOME/Projects/books-cli}"

if [ ! -f "$source/rust/Cargo.toml" ]; then
    echo "books: $source has no rust/ crate" >&2
    exit 2
fi

# -j2: more jobs have OOM-killed builds on this machine before
(cd "$source/rust" && cargo build --release -j"${JOBS:-2}")

mkdir -p "$root/vendor"
new="$root/vendor/books-rs.new.$$"
trap 'rm -f "$new"' EXIT
cp "$source/rust/target/release/books-rs" "$new"
chmod 755 "$new"
"$new" --help >/dev/null
mv -f "$new" "$root/vendor/books-rs"
printf 'built %s (%s bytes)\n' "$root/vendor/books-rs" "$(stat -c%s "$root/vendor/books-rs")"
