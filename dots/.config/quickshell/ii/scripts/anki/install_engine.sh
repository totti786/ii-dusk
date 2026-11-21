#!/usr/bin/env bash
# Installs the Anki app's engine: the official `anki` package, pinned, inside the shell's one
# Python environment ($ILLOGICAL_IMPULSE_VIRTUAL_ENV, default ~/.local/state/quickshell/.venv).
#
# The version is PINNED, not "latest": a newer engine than the one in Anki desktop can
# upgrade a collection's format in place, and desktop then cannot open it any more.
# Match this to the Anki desktop you use (`anki --version`), and raise it on purpose:
#
#   II_ANKI_VERSION=26.9.4 bash install_engine.sh
#
# The same pin lives in scripts/deps/requirements.txt, so a rebuilt environment gets the same engine.
# Deliberately not scripts/anki/install.sh: that one is upstream's and installs the newest release.
#
# Safe to re-run. Progress lines start with "STEP"; the last line starts with "DONE".
set -euo pipefail

ANKI_VERSION="${II_ANKI_VERSION:-26.9.4}"
VENV="${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-$HOME/.local/state/quickshell/.venv}"
VENV="${VENV/#\~/$HOME}"

if [ ! -x "$VENV/bin/python" ]; then
    echo "ERROR The shell's Python environment is missing: run scripts/deps/bootstrap.sh first" >&2
    exit 1
fi

echo "STEP 1/1 Installing Anki $ANKI_VERSION into the shell's Python environment"
if command -v uv >/dev/null 2>&1; then
    uv pip install --quiet --python "$VENV/bin/python" "anki==$ANKI_VERSION"
else
    "$VENV/bin/python" -m pip install --quiet --disable-pip-version-check "anki==$ANKI_VERSION"
fi

"$VENV/bin/python" -c "from anki.buildinfo import version; print('DONE anki', version)"
