# AGENTS.md

This repo is a GitHub Codespaces dotfiles repo (see README.md). `install.sh` is the
entry point Codespaces runs automatically — keep it idempotent and safe to re-run.

## Setup status + login banner (shared with project repos)

`install.sh` prints one line per step (`[i/N] label… ✓ 2s` / `✗ FAILED`), then a
totals line; full step output goes to `~/.codespace-setup.d/dotfiles.log`. It
records its state as the `dotfiles` component under `~/.codespace-setup.d/` and
writes the login banner `~/.codespace-setup-login-check.sh`, which project setup
scripts (e.g. `nija-at/strandufer`'s `scripts/setup.sh`) also write. The banner
lists every component that's still running, was interrupted, or errored, or
prints one green "setup complete" line naming them all.

The banner is duplicated rather than shared at runtime, so neither script
depends on the other or on the order they run in. Keep `install_status_banner`
byte-identical with the project repo's copy. `test-setup-banner.sh` is an
identical copy of the project's test; run `bash test-setup-banner.sh` after
changing the banner here or there.
