# vendor/

Nothing in here is committed. The Mediator backend used to live here as a prebuilt binary; it is
now compiled from `scripts/mediatorRs/mediator-rs_src` by `scripts/rust-helpers.sh` (the shell
builds it on first use, see Settings > About > Compiled components). A leftover `mediator-rs` here
is still used until the new build exists.

`books.pyz` is the Books app's own bundle, an optional extra that ii-dusk does not ship. Build it
from your own books-cli checkout:

```sh
scripts/build-books-zipapp.sh /path/to/books-cli
```

or point `BOOKS_CLI_PYZ` at an existing bundle. Without it the Books app shows that it is missing.
