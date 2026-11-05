---
name: provider-fork-release
description: Fix the Pangolin provider fork (sylvainmetayer/terraform-provider-pangolin), publish a `1.7.0-sylvain.N` prerelease built by hand, and bump the homelab to it (fetch script SHA-256, provider.tf, lock file, AGENTS.md, ADR 0021) with an empty full plan. Use when tofu/pangolin_config hits a provider bug, or when asked to release or bump the fork.
---

# Pangolin provider fork: fix, release, bump

`tofu/pangolin_config` runs a hand-built prerelease of the fork, served from a
local mirror with a pinned SHA-256 (ADR 0021, `tofu/pangolin_config/README.md`
« Provider: a build of the fork »). Source stays `stackopshq/pangolin`, so the
state never changes provider.

## Rules

- **Publishing a release needs Sylvain's explicit OK** in the session.
- **Never delete a fork branch**: each is to be proposed upstream one by one.
  Nothing is proposed upstream without Sylvain.
- The fork's `Release` workflow (GoReleaser, GPG) is **disabled on purpose**:
  the release is built by hand below. Leave it disabled.
- The fork's CI rejects em/en dashes and gofmt drift, and checks `docs/` is
  what `tfplugindocs generate` makes: rerun it when the schema changes.

## 1. Fix on the fork

```bash
: "${SCRATCH:?set SCRATCH to the session scratch dir first}"   # an empty one makes the rm -rf below hit /rel
gh repo clone sylvainmetayer/terraform-provider-pangolin "$SCRATCH/tfp"   # alone (git clone over SSH fails in a sandbox)
cd "$SCRATCH/tfp" && git switch -c fix/<topic>
export GOMODCACHE=$SCRATCH/gomod GOCACHE=$SCRATCH/gocache GOPATH=$SCRATCH/gopath
mise exec go@1.25.14 -- go test -count=1 ./internal/...
```

A Go toolchain at least the `go` line of `go.mod`. Each fix brings a test
reproducing the bug (`internal/client/*_test.go` serve fake API pages with
`writeEnvelope`). Commit in English, push the branch, PR to the fork's `main`
(`gh pr create --repo sylvainmetayer/terraform-provider-pangolin --base main`),
wait for `Test` and `Lint`, merge.

## 2. Build and publish

Next version: `gh release list --repo sylvainmetayer/terraform-provider-pangolin`,
then `.N+1`.

```bash
cd "$SCRATCH/tfp" && git fetch origin && git switch --detach origin/main
V=1.7.0-sylvain.N; R=$SCRATCH/rel; rm -rf $R && mkdir $R
mise exec go@1.25.14 -- go test -count=1 ./internal/...
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 mise exec go@1.25.14 -- \
  go build -trimpath -ldflags "-s -w -X main.version=$V" -o $R/terraform-provider-pangolin_v$V .
cd $R && python3 -I -c "
import zipfile, sys
v = sys.argv[1]; n = f'terraform-provider-pangolin_v{v}'
info = zipfile.ZipInfo(n, (2026, 1, 1, 0, 0, 0)); info.external_attr = 0o755 << 16; info.compress_type = zipfile.ZIP_DEFLATED
with zipfile.ZipFile(f'terraform-provider-pangolin_{v}_linux_amd64.zip', 'w') as z:
    z.writestr(info, open(n, 'rb').read())" "$V"
sha256sum terraform-provider-pangolin_${V}_linux_amd64.zip > terraform-provider-pangolin_${V}_SHA256SUMS
git -C "$SCRATCH/tfp" rev-parse HEAD        # the --target below
```

Fixed zip date and mode: same bytes on a rebuild. Notes (`notes.md`, English,
no dashes): what this release adds over the previous one, by fork PR number,
and « linux_amd64 only, unsigned: consumed through a local mirror with a
pinned SHA-256, not through a registry. »

```bash
gh release create v$V --repo sylvainmetayer/terraform-provider-pangolin --target <sha> --prerelease --title v$V --notes-file $R/notes.md $R/terraform-provider-pangolin_${V}_linux_amd64.zip $R/terraform-provider-pangolin_${V}_SHA256SUMS
```

## 3. Bump the homelab

In a worktree from `origin/main` (never the main checkout), one PR:

| File | Change |
|---|---|
| `.github/scripts/fetch_pangolin_provider.sh` | `version=` and `sha256=` (from `SHA256SUMS`) |
| `tofu/pangolin_config/provider.tf` | `version = "= $V"` |
| `tofu/pangolin_config/.terraform.lock.hcl` | delete the `stackopshq/pangolin` block, `init` writes it back with the new `h1:` |
| `AGENTS.md` | the version in « Current state worth knowing » |
| `docs/adr/0021-provider-pangolin-du-fork.md` | the version in « Décision », and the PR count in « Contexte » when the fix adds one |

```bash
grep -rln 'sylvain\.<N-1>' --exclude-dir=.git .          # nothing left after the edit
git submodule update --init secrets                        # alone
mise trust .                                               # outside the sandbox if any
bash .github/scripts/fetch_pangolin_provider.sh            # downloads and checks the SHA-256
mise exec -- tofu -chdir=tofu/pangolin_config init -input=false -no-color
mise exec -- tofu -chdir=tofu/pangolin_config test -no-color -compact-warnings
```

Then a **full** plan with the `pangolin-config-plan` skill: it must be empty,
or show exactly what the fix is meant to change (e.g. a false recreation that
disappears). A change you cannot explain blocks the PR. Say in the PR body
what the plan showed and that `docs/adr/` makes the merge rebuild the docs
site (`docs_site` tag); nothing else deploys. Review, merge; no apply is
needed for a provider bump with an empty plan.

## 4. After

Every other checkout and worktree reruns `mise run provider-fork` before its
next `tofu init`. When upstream takes the fixes, the way back is in the
module README (remove `terraform.d/` first, check bindings on update).
