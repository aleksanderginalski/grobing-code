# age test vectors (C2SP/CCTV)

Official test vectors for the age v1 format, used by `test/backup/age_testkit_test.dart` to check our
own module (`lib/backup/age/`, ISSUE-008).

- **Source:** https://github.com/C2SP/CCTV/tree/main/age/testdata
- **Commit:** `50a8ecf2a220f4c8bdc4f085789b8e85c26829e7` (fetched 2026-10-06)
- **Licence:** Zero-Clause BSD, CC0 1.0 or Unlicense, at your choice — copying is allowed without
  attribution (`age/README.md` → *License*).
- **Subset:** every vector except `armor_*` and `hybrid_*` (92 files). Grobing writes binary age files
  to X25519 and scrypt recipients only, so ASCII armor and the post-quantum hybrid type are not
  implemented.
- **Format of a vector:** a text header (`expect`, `payload`, `identity`, `passphrase`, `compressed`, …),
  an empty line, then the age file, zlib-compressed when `compressed: zlib`. See the source README.

To update: fetch a newer commit, copy the same subset, change the commit above and run `flutter test`.
The files are binary for git (`.gitattributes`): line endings must not change.
