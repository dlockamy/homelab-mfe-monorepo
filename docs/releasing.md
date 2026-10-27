# Releasing, tagging and rollback

Related: [Architecture](architecture.md) · [CI and CD](ci-cd.md)

A release happens by merging to `main`. There is no manual release step. This
page covers what that produces, how each component is tagged, and how to go
back.

## What "a release" is

Merging to `main` runs `Jenkinsfile.cd`, which deploys **whichever components
changed** in that merge:

| Component changed | Deployed as | Tagged as |
|---|---|---|
| `apps/core-shell/` | overwrites `s3://<bucket>/index.html` | `apps-core-shell-v<N>` |
| `apps/sub-route-billing/` | new `s3://<bucket>/artifacts/billing/v<N>/main.js`, then manifest flip | `apps-sub-route-billing-v<N>` |
| anything else (docs, Terraform, scripts, pipelines) | nothing | nothing |

`<N>` is the Jenkins build number of the `main` CD job. If both components
change in one merge they share the same `<N>` and each gets its own tag.

## Tagging

**One tag per deployed component, per release**, named
`apps-<component-directory>-v<N>`.

```
apps-core-shell-v12
apps-sub-route-billing-v12
```

Rules:

- **Created by Jenkins, only after a successful deploy.** If the build is
  UNSTABLE because `DEPLOY_ENABLED` is `false`, or the deploy failed, **no tag
  is made**. A tag therefore means "this commit was actually published".
- **Only for components that were deployed in that build.** A billing-only
  change creates only a billing tag. Because `<N>` is shared across the whole
  job, each component's sequence has gaps. That is expected.
  Example:

  | CD build | Changed | Tags created | New S3 artifact |
  |---|---|---|---|
  | 7 | shell + billing | `apps-core-shell-v7`, `apps-sub-route-billing-v7` | `billing/v7` |
  | 8 | billing | `apps-sub-route-billing-v8` | `billing/v8` |
  | 9 | shell | `apps-core-shell-v9` | none |

- **For billing, the tag number is the S3 version**, so
  `apps-sub-route-billing-v8` is the exact source of
  `/artifacts/billing/v8/main.js`.
- **Lightweight tags**, pushed with the `github-token` credential. They are
  never moved or deleted.
- **Why per component, not one repo-wide version:** the apps release
  independently. A repo-wide tag couldn't say which of them a commit shipped.
- **`libs/shared-contracts` is not tagged**, because nothing deploys it. If it
  becomes a real dependency of the apps, give it its own tag
  (`libs-shared-contracts-v<N>`) and add `libs/` to change detection in
  `Jenkinsfile.cd`. See the first item under
  [known gaps](architecture.md#known-gaps).

> **Status:** the tagging step is written and its shell logic was run against a
> scratch git remote, and both Jenkinsfiles lint clean. It has **not** run on
> Jenkins, because deploys are off. Verify the first real tags after enabling
> deploys.

## Finding things

```sh
# What billing version is live right now?
curl -s https://<cdn_domain>/importmap.json
#  -> {"imports":{"@mfe/sub-route-billing":"/artifacts/billing/v8/main.js"}}

# What commit is that?
git rev-list -n1 apps-sub-route-billing-v8

# All releases of one component, newest last
git tag -l 'apps-sub-route-billing-v*' --sort=v:refname
git tag -l 'apps-core-shell-v*'        --sort=v:refname

# What changed in billing between two releases?
git diff apps-sub-route-billing-v7 apps-sub-route-billing-v8 -- apps/sub-route-billing
```

## Rolling back billing

Fast, safe, no build, no redeploy. Every past `artifacts/billing/v<N>/` is
still in the bucket and is never modified, so any of them can be made live
again by changing the manifest pointer.

```sh
# needs: aws CLI v2, node, and credentials that can read/write the bucket
export S3_BUCKET=homelab-mfe-delivery-bucket
scripts/publish.sh rollback v7
```

The script confirms `artifacts/billing/v7/main.js` exists **before** touching
the manifest and aborts otherwise. Browsers pick the change up on the next
page load (the manifest is `no-cache` and fetched with a cache-buster).

Afterwards, **fix forward in git too**: `main` still contains the bad change,
and the next billing merge will publish it again. Revert the offending commit
on `main` (a normal PR); its merge ships a new version that supersedes the
rollback.

To switch billing off entirely (the shell shows "mapping path not found"),
that is the manifest with no billing entry; locally it's `make test-rollback`.
There is no production command for it yet; use a rollback to a known-good
version instead.

## Rolling back the shell

The shell has no history in S3 (bucket versioning is off), so there is no
pointer to flip. Two options:

1. **Preferred:** revert the change on `main` via PR. CD redeploys the shell
   from the reverted source and tags it.
2. **Emergency, out-of-band:** rebuild the last good release from its tag and
   publish it by hand.

   ```sh
   git checkout apps-core-shell-v9
   (cd apps/core-shell && npm run build)
   S3_BUCKET=homelab-mfe-delivery-bucket scripts/publish.sh shell
   git checkout -         # then follow with option 1 so main matches reality
   ```

Enabling S3 bucket versioning in `terraform/main.tf` would make shell rollback
a one-step restore. Not done.

## When something goes wrong

| Situation | What to do |
|---|---|
| Deploy succeeded but the build is red at **Tag release** | The site is fine; only the tag is missing. Find the commit on the Jenkins build page, then `git tag <name> <commit> && git push origin <name>` using the numbers from that build. |
| Deploy failed halfway (billing artifact uploaded, manifest not flipped) | Live site is unchanged (the manifest decides). Re-running the build will refuse to reuse that `v<N>`; it uses the next build number. The orphaned artifact is harmless. |
| `Refusing to overwrite already-published artifact` | The version number is already in the bucket. See [ci-cd.md](ci-cd.md#troubleshooting). |
| Need to know what shipped when | Tags plus `importmap.json`'s history in the Jenkins build logs; there is no other deploy log. |

## Retention

Tags and billing artifacts are kept forever; there is no lifecycle rule. The
bundles are about 1 KB each, so storage is not a concern.
