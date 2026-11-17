#!/bin/sh
# Runs opkssh's own tests for the patched packages natively on FreeBSD.
# Needs git and a bootstrap Go (pkg install -y git go); the exact toolchain from go.mod is downloaded.
#
#   sh test/freebsd-gotest.sh
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd)
val() { sed -n "s/^$1=\([^[:space:]]*\).*/\1/p" "$HERE/versions.env" | head -1; }
VERSION=$(val OPKSSH_VERSION)
COMMIT=$(val OPKSSH_COMMIT)
[ "$(uname -s)" = FreeBSD ] || { echo "FreeBSD only" >&2; exit 2; }

WORK=$(mktemp -d /tmp/opkssh-gotest.XXXXXX)
trap 'rm -rf -- "$WORK"' EXIT
git -c advice.detachedHead=false clone -q --depth 1 --branch "$VERSION" https://github.com/openpubkey/opkssh.git "$WORK/src"
[ "$(git -C "$WORK/src" rev-parse HEAD)" = "$COMMIT" ] || { echo "unexpected commit for $VERSION" >&2; exit 1; }
git -C "$WORK/src" apply "$HERE/patches/opkssh-freebsd.patch"
cd "$WORK/src"
tc=$(awk '$1 == "toolchain" { print $2; exit }' go.mod)
[ -n "$tc" ] || tc=go$(awk '$1 == "go" { print $2; exit }' go.mod)
export GOTOOLCHAIN=$tc GOFLAGS=-mod=readonly CGO_ENABLED=0
echo "opkssh $VERSION, $(go env GOVERSION), $(uname -sr)"
go vet ./policy/... ./commands/...
go test -count=1 ./policy/...
