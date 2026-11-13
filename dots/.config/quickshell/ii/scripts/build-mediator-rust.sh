#!/usr/bin/env bash
# Build the Rust backend into vendor/mediator-rs.
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
root="$(cd -- "$(dirname -- "$self")/.." && pwd)"
source="${1:-$HOME/Projects/mediator}"

if [ ! -f "$source/rust/Cargo.toml" ]; then
    echo "mediator: $source has no rust/ crate" >&2
    exit 2
fi

# -j2: the bundled SQLite and rustls need memory; more jobs have OOM-killed builds before
(cd "$source/rust" && cargo build --release -j"${JOBS:-2}")

mkdir -p "$root/vendor"
new="$root/vendor/mediator-rs.new.$$"
trap 'rm -f "$new"' EXIT
cp "$source/rust/target/release/mediator" "$new"
chmod 755 "$new"
"$new" --help >/dev/null
mv -f "$new" "$root/vendor/mediator-rs"
printf 'built %s (%s bytes)\n' "$root/vendor/mediator-rs" "$(stat -c%s "$root/vendor/mediator-rs")"
