This folder only holds `shell.nix`, the nix shell the `--via-nix` install runs the Python bootstrap in.

The shell's Python packages are not listed here. They live with the shell, in
`dots/.config/quickshell/ii/scripts/deps/` (`requirements.in`, `requirements.lock`, `bootstrap.sh`, see
`DEPENDENCIES.md` there), and are installed into `~/.local/state/quickshell/.venv`, never into the system.
