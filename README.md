# homelab-mfe-monorepo

A small micro-frontend demo: a **core shell** that, at runtime, reads an
**import map** from the CDN and loads the **billing** sub-route from whatever
version the map points at. Releasing billing = upload an immutable
`artifacts/billing/v<N>/main.js`, then flip one pointer in `importmap.json`.
Rolling back = point it at an older version. Nothing is rebuilt or redeployed
to change what's live.

```
apps/core-shell         shell page (index.html)
apps/sub-route-billing  billing bundle (main.js)
libs/shared-contracts   shared config, inlined into the bundle at build time
scripts/publish.sh      the one place that uploads to S3 (Jenkins AND make use it)
terraform/              S3 (private) + CloudFront (OAC)
```

## Run it locally

Needs Docker, Node, `aws` CLI, Python 3. Uses LocalStack as a fake AWS — it
cannot reach real AWS (throwaway credentials, every call pinned to localhost).

```sh
make run-local        # build both, release billing, serve on http://localhost:8080
make build-billing    # cut a new billing version + flip the pointer
make test-rollback    # empty the manifest (billing route goes "not found")
make help
```

## Jenkins

| File | Job (via the `dlockamy` GitHub org folders) | Runs on |
|---|---|---|
| `Jenkinsfile` | `dlockamy/homelab-mfe-monorepo` — builds both apps | every branch + PR |
| `Jenkinsfile.cd` | `dlockamy.cd/homelab-mfe-monorepo` — publishes | `main` only |

Both run on label `linux-build` in `node:22-alpine`. New repos appear after the
org folder's next scan (hourly) or a manual "Scan Organization Folder Now".

### Turning on deploys

`Jenkinsfile.cd` ships with `DEPLOY_ENABLED = 'false'`: it builds, then reports
**UNSTABLE** ("built, not deployed"). To go live:

1. `terraform -chdir=terraform apply` (creates the bucket + CloudFront; prints `cdn_domain`).
2. Create an IAM user allowed only `s3:GetObject`, `s3:PutObject`,
   `s3:ListBucket` on that bucket. Add its key to Jenkins as a
   `usernamePassword` credential with id **`aws-homelab-mfe-deploy`**.
3. Flip `DEPLOY_ENABLED` to `'true'` in a PR.
