# Mediator backend payload

`mediator-rs` is the backend: one Rust binary built from the mediator checkout's `rust/` crate.
`scripts/mediator` launches it, so the shell needs no Python backend, no pip install and no
separate mediator installation. (`books.pyz` here is the Books app's own bundle.)

Rebuild after backend changes:

```sh
scripts/build-mediator-rust.sh          # needs cargo; about 2-4 minutes with -j2
```

User data stays in `~/.config/mediator`, `~/.local/state/mediator` and `~/.cache/mediator`.
