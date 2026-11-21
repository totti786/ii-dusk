#!/usr/bin/env bash
# check.sh: what the shell needs, and what this machine is missing.
#
#   check.sh            report; exit 1 if a REQUIRED item is missing
#   check.sh --quiet    only what is missing
#
# The list itself lives in envcheck.py (one place, shared with Settings > About > Dependencies);
# the reasons are in DEPENDENCIES.md.
exec python3 "$(dirname "$(readlink -f "$0")")/envcheck.py" check "$@"
