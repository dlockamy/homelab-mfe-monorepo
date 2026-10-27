#!/bin/sh
# Publish built output to the delivery bucket. Used by BOTH Jenkinsfile.cd and
# the Makefile, so what you rehearse against LocalStack is what Jenkins runs.
#
#   publish.sh shell              upload the core shell (index.html)
#   publish.sh billing <version>  upload an immutable billing bundle, then flip
#                                 the import-map pointer to it
#
# env:  S3_BUCKET      required
#       AWS_ENDPOINT_URL  optional — set to http://localhost:4566 for LocalStack
# Needs: aws (v2), node. Build first — this only uploads.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
: "${S3_BUCKET:?S3_BUCKET must be set}"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

need() { [ -f "$1" ] || { echo "missing $1 — run the build first" >&2; exit 1; }; }

case "${1:-}" in
  shell)
    need "$ROOT/apps/core-shell/dist/index.html"
    echo "Publishing core shell to s3://$S3_BUCKET/index.html"
    aws s3 cp "$ROOT/apps/core-shell/dist/index.html" "s3://$S3_BUCKET/index.html" \
      --cache-control 'no-cache'
    ;;

  billing)
    VERSION=${2:?usage: publish.sh billing <version, e.g. v42>}
    need "$ROOT/apps/sub-route-billing/dist/main.js"
    KEY="artifacts/billing/$VERSION/main.js"

    echo "Publishing immutable artifact s3://$S3_BUCKET/$KEY"
    aws s3 cp "$ROOT/apps/sub-route-billing/dist/main.js" "s3://$S3_BUCKET/$KEY" \
      --cache-control 'public, max-age=31536000, immutable'

    # Read the live manifest. ONLY "key does not exist yet" may start from an
    # empty map. Any other failure (bad credentials, network, wrong bucket)
    # must abort — otherwise we would overwrite a live manifest with an empty
    # one and take every sub-route offline.
    if aws s3api get-object --bucket "$S3_BUCKET" --key importmap.json \
         "$TMP/importmap.json" >/dev/null 2>"$TMP/err"; then
      :
    elif grep -q 'NoSuchKey' "$TMP/err"; then
      echo "No importmap.json yet — starting a new one"
      echo '{"imports":{}}' > "$TMP/importmap.json"
    else
      echo "Could not read the live importmap.json; refusing to overwrite it:" >&2
      cat "$TMP/err" >&2
      exit 1
    fi

    node "$HERE/update-importmap.js" "$TMP/importmap.json" '@mfe/sub-route-billing' "/$KEY"
    echo "Flipping manifest pointer"
    aws s3 cp "$TMP/importmap.json" "s3://$S3_BUCKET/importmap.json" \
      --cache-control 'no-cache' --content-type application/json
    ;;

  *)
    echo "usage: publish.sh shell | billing <version>" >&2
    exit 2
    ;;
esac
