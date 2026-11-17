#!/usr/bin/env bash
# Reproducible build of opkssh for FreeBSD/amd64 (e.g. OPNsense) with patches/opkssh-freebsd.patch.
#
# - Source: the upstream tag from versions.env; its commit must match OPKSSH_COMMIT.
# - Go toolchain: exactly the one requested by opkssh's go.mod ("toolchain", else "go"), downloaded via
#   GOTOOLCHAIN and verified against the Go checksum database. Any Go >= 1.21 works as bootstrap.
# - Two independent builds must be bit-identical.
#
# Output: dist/opkssh-<version>-freebsd-amd64 and dist/SHA256SUMS
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=https://github.com/openpubkey/opkssh.git
PATCH=$HERE/patches/opkssh-freebsd.patch
DIST=$HERE/dist

# versions.env is parsed, not sourced
val() { sed -n "s/^$1=\([^[:space:]]*\).*/\1/p" "$HERE/versions.env" | head -1; }
VERSION=$(val OPKSSH_VERSION)
COMMIT=$(val OPKSSH_COMMIT)
[[ $VERSION =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "invalid OPKSSH_VERSION: '$VERSION'" >&2; exit 1; }
[[ $COMMIT =~ ^[0-9a-f]{40}$ ]] || { echo "invalid OPKSSH_COMMIT: '$COMMIT'" >&2; exit 1; }
OUT_NAME=opkssh-$VERSION-freebsd-amd64

command -v go >/dev/null || { echo "go not found (only needed to bootstrap the pinned toolchain)" >&2; exit 1; }
[ -f "$PATCH" ] || { echo "patch missing: $PATCH" >&2; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/opkssh-build.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT

toolchain_of() {
    local t
    t=$(awk '$1 == "toolchain" { print $2; exit }' "$1/go.mod")
    [ -n "$t" ] || t=go$(awk '$1 == "go" { print $2; exit }' "$1/go.mod")
    [[ $t =~ ^go[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || { echo "cannot determine toolchain from go.mod: '$t'" >&2; exit 1; }
    echo "$t"
}

build_once() {
    local dir=$1 head toolchain
    git -c advice.detachedHead=false clone -q --depth 1 --branch "$VERSION" "$REPO" "$dir"
    head=$(git -C "$dir" rev-parse HEAD)
    [ "$head" = "$COMMIT" ] || { echo "tag $VERSION points to $head, expected $COMMIT" >&2; exit 1; }
    git -C "$dir" apply --check "$PATCH"
    git -C "$dir" apply "$PATCH"
    toolchain=$(toolchain_of "$dir")
    (
        cd "$dir"
        export GOTOOLCHAIN=$toolchain GOFLAGS=-mod=readonly CGO_ENABLED=0 GOOS=freebsd GOARCH=amd64
        [ "$(go env GOVERSION)" = "$toolchain" ] || { echo "toolchain is $(go env GOVERSION), expected $toolchain" >&2; exit 1; }
        go build -trimpath -buildvcs=false -ldflags "-s -w -X main.Version=$VERSION" -o opkssh .
    )
    echo "$toolchain" > "$dir/.toolchain"
}

build_once "$WORK/a"
build_once "$WORK/b"
sum_a=$(sha256sum "$WORK/a/opkssh" | cut -d' ' -f1)
sum_b=$(sha256sum "$WORK/b/opkssh" | cut -d' ' -f1)
[ "$sum_a" = "$sum_b" ] || { echo "builds differ: $sum_a / $sum_b" >&2; exit 1; }

# Plausibility: FreeBSD binary, patched config path present
file "$WORK/a/opkssh" | grep -q 'FreeBSD' || { echo "not a FreeBSD binary" >&2; exit 1; }
grep -aq '/usr/local/etc/opk' "$WORK/a/opkssh" || { echo "patched config path missing in binary" >&2; exit 1; }

mkdir -p "$DIST"
install -m 0755 "$WORK/a/opkssh" "$DIST/$OUT_NAME"
(cd "$DIST" && sha256sum "$OUT_NAME" > SHA256SUMS)
echo "opkssh $VERSION, commit $COMMIT, $(cat "$WORK/a/.toolchain"), patch $(sha256sum "$PATCH" | cut -c1-16)"
cat "$DIST/SHA256SUMS"
