#!/usr/bin/env bash
# Installs the Anki app's engine: a private Python venv holding the official `anki`
# package, so the app does not depend on the system package or on Anki desktop.
#
#   ~/.local/share/ii-anki-engine/venv
#
# The version is PINNED, not "latest": a newer engine than the one in Anki desktop can
# upgrade a collection's format in place, and desktop then cannot open it any more.
# Match this to the Anki desktop you use (`anki --version`), and raise it on purpose:
#
#   II_ANKI_VERSION=26.9.4 bash install_engine.sh
#
# Deliberately not scripts/anki/install.sh: that one is upstream's, installs the newest
# release into upstream's own folder (ii-anki) and would change the version under us.
#
# Safe to re-run. Progress lines start with "STEP"; the last line starts with "DONE".
set -euo pipefail

ANKI_VERSION="${II_ANKI_VERSION:-26.9.4}"
DIR="${II_ANKI_ENGINE:-$HOME/.local/share/ii-anki-engine}"
mkdir -p "$DIR"

echo "STEP 1/2 Creating the Python environment"
# A venv points at the interpreter that made it: after a Python upgrade it stops running.
if [ -x "$DIR/venv/bin/python" ] && ! "$DIR/venv/bin/python" -c "pass" 2>/dev/null; then
    rm -rf "$DIR/venv"
fi
if [ ! -x "$DIR/venv/bin/python" ]; then
    python3 -m venv "$DIR/venv"
fi

echo "STEP 2/2 Installing Anki $ANKI_VERSION"
"$DIR/venv/bin/pip" install --quiet --disable-pip-version-check "anki==$ANKI_VERSION" pillow

"$DIR/venv/bin/python" -c "import PIL; from anki.buildinfo import version; print('DONE anki', version)"
