# opkssh for FreeBSD / OPNsense

Reproducible FreeBSD/amd64 builds of [opkssh](https://github.com/openpubkey/opkssh) with a small patch that
makes it work on FreeBSD-based systems such as OPNsense. Not affiliated with the opkssh project.

## Why a patch?

Upstream opkssh (v0.19.2) does not work on FreeBSD as is:

1. **Ownership check uses GNU `stat`.** opkssh checks the owner and group of its policy file with
   `stat -c "%U %G"`. FreeBSD's `stat` has no `-c`, so the check fails with `failed to run stat` and
   **every login is rejected**. The patch uses `/usr/bin/stat -f "%Su %Sg"` on FreeBSD (same output).
2. **Build tag.** The `readhome` code is not built for `freebsd`, so the code does not compile for FreeBSD.
3. **Paths.** Configuration lives in `/usr/local/etc/opk` (as in the FreeBSD port `security/opkssh`)
   instead of `/etc/opk`.

The patch is [`patches/opkssh-freebsd.patch`](patches/opkssh-freebsd.patch). Everything else is upstream
code at the tag and commit pinned in [`versions.env`](versions.env).

## Download and verify

Releases are named `<opkssh version>-freebsd.<revision>`, e.g. `v0.19.2-freebsd.1`. Each release has the
binary `opkssh-<version>-freebsd-amd64`, `SHA256SUMS` and a signed build provenance attestation.

```sh
sha256sum -c SHA256SUMS
gh attestation verify opkssh-v0.19.2-freebsd-amd64 --repo mod242/opkssh-opnsense-build
```

The build is reproducible. To check a release independently of GitHub Actions:

```sh
git checkout v0.19.2-freebsd.1
./build.sh          # needs git, file and any Go >= 1.21 as bootstrap
cat dist/SHA256SUMS # must match the release
```

`build.sh` clones the upstream tag, checks the pinned commit, applies the patch, builds with exactly the Go
toolchain requested by opkssh's `go.mod` (downloaded and verified by Go), builds twice and requires both
results to be bit-identical.

## Tests

CI runs on every push and pull request:

- the reproducible build on Linux;
- on a FreeBSD 15.1 VM: [`test/freebsd-smoke.sh`](test/freebsd-smoke.sh) (version, config path, the
  owner/group check via `opkssh audit`, and a negative test with a wrong owner) and
  [`test/freebsd-gotest.sh`](test/freebsd-gotest.sh) (opkssh's own `policy` tests, natively on FreeBSD).

The smoke test fails with `failed to run stat` against a build that still uses GNU `stat`.

## Updates

[Renovate](https://docs.renovatebot.com/) watches the upstream tags and opens a pull request that bumps
`OPKSSH_VERSION` and `OPKSSH_COMMIT`. A human reviews the upstream changes, adapts the patch if CI fails,
resets `RELEASE_REVISION=1`, merges and pushes the tag; the release workflow then publishes the binary.
Nothing is deployed automatically.

## Using it

Install the binary as `/usr/local/bin/opkssh`, put `providers`, `auth_id` and optionally `config.yml` into
`/usr/local/etc/opk` (owner `root`, group of the `AuthorizedKeysCommandUser`, mode `0640`) and point sshd to it:

```
AuthorizedKeysCommand /usr/local/bin/opkssh verify %u %k %t
AuthorizedKeysCommandUser opksshuser
```

See the [opkssh documentation](https://github.com/openpubkey/opkssh) for the policy format.
On OPNsense, put the sshd lines into a file in `/usr/local/etc/ssh/sshd_config.d/`, which the generated
`sshd_config` includes first, so they survive configuration changes.

## License

Apache License 2.0, like opkssh. See [LICENSE](LICENSE).
