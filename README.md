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

## Docs

- [Architecture](docs/architecture.md): how the service works, hosting, known gaps
- [CI and CD](docs/ci-cd.md): the Jenkins pipelines, enabling deploys, troubleshooting
- [Releasing, tagging and rollback](docs/releasing.md): per-component tags, finding what's live, going back
- [Monorepo vs split repos](docs/monorepo-vs-split-repos.md): the trade-offs of keeping this one repo vs a shared npm package, for Jenkins and Harness.io

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

`Jenkinsfile` (CI, every branch and PR) and `Jenkinsfile.cd` (CD, `main` only)
are discovered automatically by the `dlockamy` org folders. Deploys ship
**disabled** (`DEPLOY_ENABLED = 'false'`); see [docs/ci-cd.md](docs/ci-cd.md)
for how to turn them on.
