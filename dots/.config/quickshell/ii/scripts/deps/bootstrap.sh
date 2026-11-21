#!/usr/bin/env bash
# bootstrap.sh: builds the shell's one Python environment from deps/requirements.lock.
#
#   bootstrap.sh            create it (or bring it up to the lock if it exists)
#   bootstrap.sh --fresh    delete it first and rebuild from scratch
#
# The environment is ~/.local/state/quickshell/.venv (or $ILLOGICAL_IMPULSE_VIRTUAL_ENV), Python 3.12.
# Nothing the shell runs reads Python packages from the system site-packages; the system interpreter
# is only used for scripts that are not the shell's own (see deps/bin/python3).
#
# Needs: uv, and the headers the compiled packages build against (dbus, glib, cairo,
# gobject-introspection: base-devel pkgconf dbus-glib gobject-introspection cairo).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-$HOME/.local/state/quickshell/.venv}"
VENV="${VENV/#\~/$HOME}"

command -v uv >/dev/null 2>&1 || { echo "ERROR uv is not installed (pacman -S uv)" >&2; exit 1; }

if [ "${1:-}" = "--fresh" ] && [ -d "$VENV" ]; then
    echo "STEP removing $VENV"
    rm -rf "$VENV"
fi

if [ ! -x "$VENV/bin/python" ]; then
    echo "STEP creating $VENV (Python 3.12)"
    mkdir -p "$(dirname "$VENV")"
    uv venv --python 3.12 "$VENV"
fi

echo "STEP installing requirements.lock"
uv pip install --python "$VENV/bin/python" -r "$HERE/requirements.lock"

echo "STEP installing openwakeword (without its unusable tflite-runtime requirement)"
uv pip install --python "$VENV/bin/python" --no-deps -r "$HERE/requirements-nodeps.txt"

# openwakeword's feature models are downloaded into the package folder, not shipped in the wheel.
echo "STEP fetching openwakeword feature models"
"$VENV/bin/python" - <<'PY'
import os, openwakeword
folder = os.path.join(os.path.dirname(openwakeword.__file__), "resources", "models")
need = ("melspectrogram.onnx", "embedding_model.onnx", "silero_vad.onnx")
if all(os.path.exists(os.path.join(folder, n)) for n in need):
    print("already present")
else:
    from openwakeword.utils import download_models
    download_models([])
    print("downloaded")
PY

echo "DONE $("$VENV/bin/python" -V) at $VENV"
"$HERE/check.sh" --quiet || true
