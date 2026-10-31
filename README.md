# dist-test

A minimal Rust binary for testing new releases of
[`oxidecomputer/cargo-dist`](https://github.com/oxidecomputer/cargo-dist)
before they're adopted by [`oxide.rs`](https://github.com/oxidecomputer/oxide.rs).

The `dist` configuration in `dist-workspace.toml` mirrors the one in `oxide.rs`:
the same targets, runners, manylinux container, signing settings, shell
completions, and versioned Homebrew formulas. Releases publish formulas to
[`oxidecomputer/homebrew-tap-testing`](https://github.com/oxidecomputer/homebrew-tap-testing)
instead of the production tap.

## Test a dist release

After a new `dist` version is released, run:

```sh
scripts/test-dist-release.sh 1.0.20
```

The script does the following:

1. Checks that `main` is clean and matches `origin/main`.
1. Installs the requested `dist` version into a temporary directory. Your
   existing `dist` install isn't changed.
1. Sets `cargo-dist-version`, regenerates `.github/workflows/release.yml`, and
   commits the result as `Update to dist <version>`. This is the same change
   you make in `oxide.rs`, so you can review the workflow diff before you
   update `oxide.rs`.
1. Runs `cargo release patch`, which bumps the version of `dist-test`, commits,
   tags `v<version>`, and pushes to `origin`.
1. Waits for the release workflow and fails if any job fails.
1. Lists the assets of the GitHub release.
1. Checks that the tap's `dist-test.rb` and `dist-test@<major>.<minor>.rb`
   formulas have the new version.
1. Installs or upgrades `oxidecomputer/tap-testing/dist-test` with Homebrew,
   and checks the binary's version and the installed shell completions.

To retest the `dist` version that's already configured, run the script with
that version. It skips the `dist` commit and cuts a new release.

Options:

- `--bump LEVEL`: the `cargo release` level, such as `minor`. Use `minor` to
  test a new versioned formula, such as `dist-test@0.2`. Defaults to `patch`.
- `--no-brew`: skip the Homebrew install, for example on Linux.

## Requirements

- [`cargo-release`](https://github.com/crate-ci/cargo-release)
- The [GitHub CLI](https://cli.github.com/), authenticated with push access to
  this repository
- [Homebrew](https://brew.sh), unless you pass `--no-brew`

## One-time setup

1. Create `oxidecomputer/homebrew-tap-testing` and push its initial commit. The
   release workflow checks out the tap, so the tap can't be empty.
1. Create `oxidecomputer/dist-test` and push this repository.
1. Add a `HOMEBREW_TAP_TOKEN` Actions secret to `dist-test`. The token needs
   write access to the contents of `homebrew-tap-testing`.
1. Optional: to test code signing, add the same signing secrets that `oxide.rs`
   uses: `CODESIGN_*` for macOS and `SSLDOTCOM_*` for Windows. Without them,
   `dist` skips signing and logs a warning.

## Keep in sync with oxide.rs

When the `dist` configuration in `oxide.rs` changes, make the same change here.
The only intended difference is `.github/manylinux.yml`: `dist-test` doesn't
build OpenSSL, so it only marks the checkout as safe for `git`.
