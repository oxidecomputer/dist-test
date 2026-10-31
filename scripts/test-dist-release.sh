#!/usr/bin/env bash
#
# Cuts a release of dist-test built by a given dist version, waits for the
# release workflow, and checks the GitHub release, the tap, and a Homebrew
# install.
#
# Usage: scripts/test-dist-release.sh [--bump LEVEL] [--no-brew] DIST_VERSION
#
#   DIST_VERSION  A published oxidecomputer/cargo-dist release, such as 1.0.20.
#   --bump LEVEL  The `cargo release` level for dist-test. Defaults to patch.
#   --no-brew     Skip installing dist-test from the tap.

set -euo pipefail

REPO=oxidecomputer/dist-test
TAP_REPO=oxidecomputer/homebrew-tap-testing
TAP=oxidecomputer/tap-testing
FORMULA="dist-test"

bump="patch"
brew=1
dist_version=

usage() {
    sed -n '7,11s/^# \{0,1\}//p' "$0" >&2
    exit 2
}

while [ $# -gt 0 ]; do
    case "$1" in
        --bump) bump="${2:?--bump needs a level}"; shift 2 ;;
        --no-brew) brew=0; shift ;;
        -h|--help) usage ;;
        -*) echo "unknown option: $1" >&2; usage ;;
        *) [ -z "$dist_version" ] || usage; dist_version="${1#v}"; shift ;;
    esac
done
[ -n "$dist_version" ] || usage

step() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

cd "$(git rev-parse --show-toplevel)"

step "Checking the working tree"
[ "$(git branch --show-current)" = main ] || die "not on main"
[ -z "$(git status --porcelain)" ] || die "the working tree has uncommitted changes"
git fetch --quiet origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] ||
    die "main differs from origin/main"

step "Installing dist $dist_version"
dist_dir="$(mktemp -d)"
trap 'rm -rf "$dist_dir"' EXIT
installer_url="https://github.com/oxidecomputer/cargo-dist/releases/download/v${dist_version}/dist-installer.sh"
curl --proto '=https' --tlsv1.2 -LsSf "$installer_url" |
    DIST_UNMANAGED_INSTALL="$dist_dir" INSTALLER_PRINT_QUIET=1 sh
dist="$dist_dir/dist"
"$dist" --version

step "Updating dist-test to dist $dist_version"
# Change only the version and regenerate CI, as oxide.rs does. `dist init`
# would also rewrite unrelated parts of dist-workspace.toml.
config="dist-workspace.toml"
sed "s/^cargo-dist-version = \".*\"$/cargo-dist-version = \"$dist_version\"/" \
    "$config" >"$dist_dir/$config"
mv "$dist_dir/$config" "$config"
grep -q "^cargo-dist-version = \"$dist_version\"$" "$config" ||
    die "couldn't set cargo-dist-version in $config"
"$dist" generate
git add --all
if git diff --cached --quiet; then
    echo "dist-test already uses dist $dist_version"
else
    git commit --quiet -m "Update to dist $dist_version"
    git show --stat --format='%h %s' HEAD
fi

step "Releasing dist-test (cargo release $bump)"
cargo release "$bump" --execute --no-confirm
tag="$(git describe --tags --exact-match HEAD)"
version="${tag#v}"
commit="$(git rev-parse HEAD)"

step "Waiting for the release workflow for $tag"
run_id=
for _ in $(seq 1 30); do
    run_id="$(gh run list -R "$REPO" --workflow release.yml --event push \
        --commit "$commit" --json databaseId --jq '.[0].databaseId')"
    [ -n "$run_id" ] && break
    sleep 5
done
[ -n "$run_id" ] || die "no release workflow run started for $tag"
gh run watch -R "$REPO" "$run_id" --exit-status --interval 30 ||
    die "the release workflow failed: $(gh run view -R "$REPO" "$run_id" --json url --jq .url)"

step "Checking the GitHub release"
gh release view -R "$REPO" "$tag" --json assets --jq '.assets[].name'

step "Checking the tap's formulas"
formula_version() {
    gh api "repos/$TAP_REPO/contents/Formula/$1.rb" --jq .content |
        base64 --decode | sed -n 's/^ *version "\([^"]*\)"$/\1/p'
}
major_minor="$(echo "$version" | cut -d. -f1-2)"
for name in "$FORMULA" "$FORMULA@$major_minor"; do
    published="$(formula_version "$name")"
    [ "$published" = "$version" ] ||
        die "$name.rb in $TAP_REPO has version '$published', expected $version"
    echo "$name.rb: $published"
done

if [ "$brew" = 1 ]; then
    step "Installing $TAP/$FORMULA with Homebrew"
    brew tap "$TAP" >/dev/null
    git -C "$(brew --repository "$TAP")" pull --quiet --ff-only
    if brew list --formula "$TAP/$FORMULA" >/dev/null 2>&1; then
        HOMEBREW_NO_AUTO_UPDATE=1 brew upgrade "$TAP/$FORMULA"
    else
        HOMEBREW_NO_AUTO_UPDATE=1 brew install "$TAP/$FORMULA"
    fi

    keg="$(brew --prefix "$TAP/$FORMULA")"
    installed="$("$keg/bin/dist-test" --version)"
    [ "$installed" = "dist-test $version" ] ||
        die "the installed binary reports '$installed', expected 'dist-test $version'"
    echo "$installed"
    for completion in \
        etc/bash_completion.d/dist-test \
        share/fish/vendor_completions.d/dist-test.fish \
        share/zsh/site-functions/_dist-test; do
        [ -s "$keg/$completion" ] || die "the formula didn't install $completion"
        echo "installed $completion"
    done
fi

step "dist $dist_version released dist-test $version"
