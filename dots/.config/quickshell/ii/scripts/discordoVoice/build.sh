#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
data_dir="${DISCORDO_VOICE_DATA_DIR:-${HOME}/.local/share/quickshell-ii}"
source_dir="${data_dir}/discordo-voice-src"
binary_dir="${data_dir}/bin"
binary_path="${binary_dir}/discordo-voice"
binary_tmp="${binary_path}.tmp.$$"
repository="${DISCORDO_VOICE_REPOSITORY:-https://github.com/ayn2op/discordo.git}"
# This is the inspected upstream fork source pin. Live applet Connect/Join
# remains an explicit user-level check; the offline tests never authenticate.
pinned_commit="${DISCORDO_VOICE_COMMIT:-5089044cd699c01110090db4cf3ed6b65cb44565}"
seed_dir="${DISCORDO_VOICE_SOURCE_SEED:-/tmp/discordo-inspect-20261025}"

mkdir -p "${data_dir}" "${binary_dir}"

if [[ ! -d "${source_dir}/.git" ]]; then
    if [[ -d "${seed_dir}/.git" ]]; then
        git clone --local "${seed_dir}" "${source_dir}" >/dev/null
    else
        git clone "${repository}" "${source_dir}" >/dev/null
    fi
fi
git -C "${source_dir}" remote set-url origin "${repository}" 2>/dev/null ||
    git -C "${source_dir}" remote add origin "${repository}"

if ! git -C "${source_dir}" cat-file -e "${pinned_commit}^{commit}" 2>/dev/null; then
    git -C "${source_dir}" fetch --depth=1 origin "${pinned_commit}"
fi
git -C "${source_dir}" checkout --detach --quiet "${pinned_commit}"

# Discordo's follow handler and public voice methods share this mutex. The
# upstream TryLock silently reports success when follow owns it, which would
# let the NDJSON adapter publish a false mute/join state. Apply the small,
# reproducible helper-only patch before copying the adapter into the module.
git -C "${source_dir}" restore --source="${pinned_commit}" -- internal/voice/session.go internal/voice/speaker.go
rm -f "${source_dir}/internal/voice/engine.go" "${source_dir}/internal/voice/speaker_conceal_test.go"
git -C "${source_dir}" apply --check "${script_dir}/backend/voice_session_blocking.patch"
git -C "${source_dir}" apply "${script_dir}/backend/voice_session_blocking.patch"
# Playback jitter buffer, fades and 32-bit mixing, for crackle-free incoming audio.
git -C "${source_dir}" apply --check "${script_dir}/backend/playback_buffer.patch"
git -C "${source_dir}" apply "${script_dir}/backend/playback_buffer.patch"
# Optional Rust audio engine hooks (engine.go). They only act when discordo-audio is installed.
git -C "${source_dir}" apply --check "${script_dir}/backend/rust_engine.patch"
git -C "${source_dir}" apply "${script_dir}/backend/rust_engine.patch"

mkdir -p "${source_dir}/cmd/ii-voice"
cp "${script_dir}"/backend/*.go "${source_dir}/cmd/ii-voice/"

cd "${source_dir}"
go test "./cmd/ii-voice"
trap 'rm -f "${binary_tmp}"' EXIT
go build -trimpath -ldflags="-s -w" -o "${binary_tmp}" "./cmd/ii-voice"
chmod 0755 "${binary_tmp}"
mv -f "${binary_tmp}" "${binary_path}"
printf 'Built %s from %s at %s\n' "${binary_path}" "${repository}" "${pinned_commit}"

# The Rust audio engine (~/Projects/discordo-audio). Without it the helper keeps using the built-in audio.
engine_src="${DISCORDO_AUDIO_SRC:-${HOME}/Projects/discordo-audio}"
if [[ -f "${engine_src}/Cargo.toml" ]] && command -v cargo >/dev/null 2>&1; then
    (cd "${engine_src}" && cargo build --release --bin discordo-audio)
    install -m 0755 "${engine_src}/target/release/discordo-audio" "${binary_dir}/discordo-audio"
    printf 'Installed %s/discordo-audio\n' "${binary_dir}"
fi
