# vendor/

Nothing in here is committed. The Mediator backend used to live here as a prebuilt binary; it is
now compiled from `scripts/mediatorRs/mediator-rs_src` by `scripts/rust-helpers.sh` (the shell
builds it on first use, see Settings > About > Compiled components). A leftover `mediator-rs` here
is still used until the new build exists.

`books-rs` is the Books app's backend, an optional extra that ii-dusk does not ship. Build it from
your own books-cli checkout (its `rust/` crate):

```sh
scripts/build-books-rs.sh /path/to/books-cli
```

or point `BOOKS_RS_BIN` at an existing binary. Without it the Books app shows that it is missing.
