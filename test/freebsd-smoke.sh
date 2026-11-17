#!/bin/sh
# Smoke test for the FreeBSD opkssh binary. Run as root on a THROWAWAY FreeBSD host (CI VM):
# it writes /usr/local/etc/opk and creates the group opksshuser.
#
#   sh test/freebsd-smoke.sh dist/opkssh-v0.19.2-freebsd-amd64 v0.19.2
#
# What it proves:
#   1. the binary runs and reports the expected version;
#   2. opkssh reads its config from /usr/local/etc/opk (FreeBSD port convention);
#   3. the owner/group check of policy files works with BSD stat. Unpatched opkssh calls GNU
#      "stat -c", which fails on FreeBSD ("failed to run stat") and breaks every login.
set -eu
BIN=${1:?usage: $0 <opkssh-binary> <expected-version>}
WANT=${2:?usage: $0 <opkssh-binary> <expected-version>}
[ "$(uname -s)" = FreeBSD ] || { echo "FreeBSD only" >&2; exit 2; }
[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq missing (pkg install -y jq)" >&2; exit 2; }

OPK=/usr/local/etc/opk
ISSUER=https://issuer.example.com
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok:   $*"; }

# 1. version
ver=$("$BIN" --version 2>&1) || fail "--version: $ver"
echo "$ver" | grep -qwF -- "$WANT" || fail "version is '$ver', expected $WANT"
ok "$ver"

# 2./3. config in /usr/local/etc/opk with the ownership opkssh expects
pw groupshow opksshuser >/dev/null 2>&1 || pw groupadd -n opksshuser
install -d -o root -g opksshuser -m 0750 "$OPK"
printf '%s smoke-client-id 24h\n' "$ISSUER" > "$OPK/providers"
printf 'root alice@example.com %s\n' "$ISSUER" > "$OPK/auth_id"
chown root:opksshuser "$OPK/providers" "$OPK/auth_id"
chmod 0640 "$OPK/providers" "$OPK/auth_id"

audit() {
    rc=0
    "$BIN" audit --json > /tmp/opkssh-audit.json 2>/tmp/opkssh-audit.err || rc=$?
    [ "$rc" = 0 ] || [ "$rc" = 1 ] || fail "audit exited $rc: $(head -3 /tmp/opkssh-audit.err)"
    jq -e 'type == "object" and has("providers_file") and has("system_policy")' /tmp/opkssh-audit.json >/dev/null \
        || fail "unexpected audit output: $(head -c 400 /tmp/opkssh-audit.json)"
}
errors() { jq -r '[.providers_file.error, .system_policy.error, .system_policy.perms_error] | map(select(. != null and . != "")) | join(" | ")' /tmp/opkssh-audit.json; }

audit
jq -e --arg p "$OPK/providers" '.providers_file.file_path == $p' /tmp/opkssh-audit.json >/dev/null \
    || fail "audit does not read $OPK/providers: $(jq -c .providers_file /tmp/opkssh-audit.json)"
ok "config read from $OPK"
e=$(errors)
[ -z "$e" ] || fail "audit reports errors with correct ownership: $e"
jq -e '.system_policy.file_path' /tmp/opkssh-audit.json >/dev/null || fail "audit did not check the system policy"
ok "ownership check passes (root:opksshuser 0640)"

# Negative: a wrong owner of the system policy (auth_id; opkssh checks owner/group there via stat) must be
# detected by the stat-based check, not fail on running stat itself
chown nobody "$OPK/auth_id"
audit
e=$(errors)
case $e in
    *"failed to run stat"*) fail "stat call fails on FreeBSD (unpatched?): $e" ;;
    *"expected owner (root), got (nobody)"*) ok "wrong owner detected: $e" ;;
    *) fail "wrong owner not detected as expected: '${e:-no error}'" ;;
esac
chown root "$OPK/auth_id"
echo "PASS"
