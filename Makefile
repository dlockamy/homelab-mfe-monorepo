# Local development against LocalStack (a fake AWS). Nothing here touches real AWS:
# every aws call goes to $(LOCALSTACK_URL) and uses throwaway credentials.
#
# The publish logic itself lives in scripts/publish.sh — the same script
# Jenkinsfile.cd runs — so `make build-billing` rehearses the real release.

# Variables
LOCALSTACK_URL=http://localhost:4566
S3_BUCKET=homelab-mfe-delivery-bucket
AWS_DEFAULT_REGION=us-east-1
LOCAL_PORT?=8080
LOCAL_CDN=.local-cdn

# Throwaway credentials, and drop any real profile, so a stray `aws` call can
# never resolve real credentials. (Every call below also pins --endpoint-url.)
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION
unexport AWS_PROFILE AWS_SESSION_TOKEN

AWS_LOCAL=aws --endpoint-url=$(LOCALSTACK_URL)

.PHONY: all help init start-localstack ensure-localstack stop-localstack build-shell build-billing sync-local simulate-pr-billing test-rollback clean serve-local run-local

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

all: init start-localstack build-shell build-billing ## Run clean installation and local build compilations

init: ## Install root and workspace project nodes
	@echo "Installing project dependencies..."
	npm install

ensure-localstack: ## Ensure LocalStack is running and the mock S3 bucket + manifest exist
	@if docker ps -a --filter "name=^localstack-mfe$$" --format '{{.Names}}' | grep -q '^localstack-mfe$$'; then \
		echo "Found existing LocalStack container; starting it if needed..."; \
		docker start localstack-mfe >/dev/null; \
	else \
		echo "Starting LocalStack Community container (v4.4.0)..."; \
		docker run -d --name localstack-mfe -p 4566:4566 -p 4510-4559:4510-4559 localstack/localstack:4.4.0; \
	fi
	@echo "Waiting for internal S3 service layer to report initialization success..."
	@for i in $$(seq 1 30); do \
		curl -s $(LOCALSTACK_URL)/_localstack/health | grep -q '"s3":[^:]*"\(running\|available\)"' && break || true; \
		echo "Waiting for S3 runtime initialization ($$i/30)..."; \
		sleep 2; \
	done
	@$(AWS_LOCAL) s3api head-bucket --bucket $(S3_BUCKET) >/dev/null 2>&1 || $(AWS_LOCAL) s3 mb s3://$(S3_BUCKET)
	@# Seed an empty manifest ONLY if there isn't one. (This used to overwrite it on
	@# every target, so `make build-shell` silently took the billing route offline.)
	@$(AWS_LOCAL) s3api head-object --bucket $(S3_BUCKET) --key importmap.json >/dev/null 2>&1 || \
		echo '{"imports":{}}' | $(AWS_LOCAL) s3 cp - s3://$(S3_BUCKET)/importmap.json --content-type application/json

start-localstack: ensure-localstack ## Boot up the community image and wait for internal S3 services to report ready

stop-localstack: ## Tear down LocalStack container
	@echo "Stopping LocalStack..."
	docker stop localstack-mfe || true
	docker rm localstack-mfe || true

build-shell: ensure-localstack ## Compile the Core Shell application and publish it to mock S3
	@echo "Compiling Core Shell application..."
	@cd apps/core-shell && npm run build
	@S3_BUCKET=$(S3_BUCKET) AWS_ENDPOINT_URL=$(LOCALSTACK_URL) scripts/publish.sh shell

build-billing: ensure-localstack ## Compile Billing Sub-route and release it as v<timestamp> (immutable artifact + manifest flip)
	@echo "Compiling Billing Sub-route..."
	@cd apps/sub-route-billing && npm run build
	@VERSION=v$$(date +%s); \
	S3_BUCKET=$(S3_BUCKET) AWS_ENDPOINT_URL=$(LOCALSTACK_URL) scripts/publish.sh billing $$VERSION && \
	echo "Release live on mock CDN. Active bundle: /artifacts/billing/$$VERSION/main.js"

sync-local: ## Mirror the mock bucket into $(LOCAL_CDN)/ (what CloudFront would serve)
	@mkdir -p $(LOCAL_CDN)
	@$(AWS_LOCAL) s3 sync s3://$(S3_BUCKET) $(LOCAL_CDN) --delete --only-show-errors

serve-local: sync-local ## Serve the mock bucket contents over HTTP so the browser can load the import map and bundle
	@echo "Serving local app on http://localhost:$(LOCAL_PORT)"
	@python3 -m http.server $(LOCAL_PORT) --directory $(LOCAL_CDN)

run-local: ## Build the app and serve it locally
	@$(MAKE) build-shell
	@$(MAKE) build-billing
	@$(MAKE) serve-local

simulate-pr-billing: ## Simulate a standalone Git PR merge updating only the billing sub-route code
	@echo "Simulating developer commit inside billing folder..."
	@echo "// Local update token: $$(date +%s)" >> apps/sub-route-billing/src/main.js
	@$(MAKE) build-billing

test-rollback: ensure-localstack ## Instantly roll back the live application manifest to an empty import matrix
	@echo "Executing instantaneous disaster recovery fallback state..."
	@echo '{"imports": {}}' | $(AWS_LOCAL) s3 cp - s3://$(S3_BUCKET)/importmap.json --content-type application/json
	@echo "Rollback completed. Manifest cleared."

clean: ## Purge local build artifacts and node tracks
	rm -rf node_modules apps/core-shell/dist apps/sub-route-billing/dist $(LOCAL_CDN)
	@echo "Cleanup completed."
