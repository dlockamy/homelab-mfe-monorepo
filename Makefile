# Variables
LOCALSTACK_URL=http://localhost:4566
S3_BUCKET=homelab-mfe-delivery-bucket
AWS_DEFAULT_REGION=us-east-1
LOCAL_PORT?=8080

.PHONY: all help init start-localstack stop-localstack build-shell build-billing simulate-pr-billing test-rollback clean serve-local run-local

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

all: init start-localstack build-shell build-billing ## Run clean installation and local build compilations

init: ## Install root and workspace project nodes
	@echo "Installing project dependencies..."
	npm install

ensure-localstack: ## Ensure LocalStack is running and the mock S3 bucket exists
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
	@AWS_DEFAULT_REGION=$(AWS_DEFAULT_REGION) aws --endpoint-url=$(LOCALSTACK_URL) s3api head-bucket --bucket $(S3_BUCKET) >/dev/null 2>&1 || AWS_DEFAULT_REGION=$(AWS_DEFAULT_REGION) aws --endpoint-url=$(LOCALSTACK_URL) s3 mb s3://$(S3_BUCKET)
	@echo '{"imports":{}}' > importmap.json
	@AWS_DEFAULT_REGION=$(AWS_DEFAULT_REGION) aws --endpoint-url=$(LOCALSTACK_URL) s3 cp importmap.json s3://$(S3_BUCKET)/importmap.json

start-localstack: ensure-localstack ## Boot up the community image and wait for internal S3 services to report ready

stop-localstack: ## Tear down LocalStack container
	@echo "Stopping LocalStack..."
	docker stop localstack-mfe || true
	docker rm localstack-mfe || true

build-shell: ensure-localstack ## Compile the Core Shell application and deploy to mock S3 root
	@echo "Compiling Core Shell application..."
	@cd apps/core-shell && npm run build
	@if [ -d "apps/core-shell/dist" ]; then \
		echo "Uploading core index frame to S3..."; \
		cp apps/core-shell/dist/index.html index.html; \
		AWS_DEFAULT_REGION=$(AWS_DEFAULT_REGION) aws --endpoint-url=$(LOCALSTACK_URL) s3 cp apps/core-shell/dist/index.html s3://$(S3_BUCKET)/index.html; \
	else \
		echo "Error: core-shell build output missing."; exit 1; \
	fi

build-billing: ensure-localstack ## Compile Billing Sub-route with an incremental local build counter
	@echo "Compiling Billing Sub-route..."
	@cd apps/sub-route-billing && npm run build
	@BUILD_NUM=$$(date +%s); \
	ASSET_PATH="artifacts/billing/v$$BUILD_NUM"; \
	mkdir -p $$ASSET_PATH; \
	cp apps/sub-route-billing/dist/main.js $$ASSET_PATH/main.js; \
	echo "Publishing Immutable Billing version v$$BUILD_NUM to mock CDN..." ; \
	AWS_DEFAULT_REGION=$(AWS_DEFAULT_REGION) aws --endpoint-url=$(LOCALSTACK_URL) s3 cp apps/sub-route-billing/dist/main.js s3://$(S3_BUCKET)/$$ASSET_PATH/main.js; \
	echo "Executing Manifest Pointer Flip via inline node logic..." ; \
	AWS_DEFAULT_REGION=$(AWS_DEFAULT_REGION) aws --endpoint-url=$(LOCALSTACK_URL) s3 cp s3://$(S3_BUCKET)/importmap.json ./importmap.json || echo '{"imports":{}}' > importmap.json; \
	node -e " \
		const fs = require('fs'); \
		let data = JSON.parse(fs.readFileSync('importmap.json')); \
		if (!data.imports) data.imports = {}; \
		data.imports['@mfe/sub-route-billing'] = '/$$ASSET_PATH/main.js'; \
		fs.writeFileSync('importmap.json', JSON.stringify(data, null, 2)); \
	"; \
	AWS_DEFAULT_REGION=$(AWS_DEFAULT_REGION) aws --endpoint-url=$(LOCALSTACK_URL) s3 cp importmap.json s3://$(S3_BUCKET)/importmap.json; \
	echo "Release completely live on mock network! Active bundle address: /$$ASSET_PATH/main.js"

serve-local: ## Serve the built app from the repo root over HTTP so the browser can load the import map and bundle
	@echo "Serving local app on http://localhost:$(LOCAL_PORT)"
	@python3 -m http.server $(LOCAL_PORT) --directory .

run-local: ## Build the app and serve it locally
	@$(MAKE) build-shell
	@$(MAKE) build-billing
	@$(MAKE) serve-local

simulate-pr-billing: ## Simulate a standalone Git PR merge updating only the billing sub-route code
	@echo "Simulating developer commit inside billing folder..."
	@echo "// Local update token: $$(date +%s)" >> apps/sub-route-billing/src/main.js
	@$(MAKE) build-billing

test-rollback: ## Instantly roll back the live application manifest to an empty import matrix
	@echo "Executing instantaneous disaster recovery fallback state..."
	@echo '{"imports": {}}' > rollback.json
	AWS_DEFAULT_REGION=$(AWS_DEFAULT_REGION) aws --endpoint-url=$(LOCALSTACK_URL) s3 cp rollback.json s3://$(S3_BUCKET)/importmap.json
	@rm rollback.json
	@echo "Rollback completed. Manifest cleared."

clean: ## Purge local build artifacts and node tracks
	rm -rf node_modules apps/core-shell/dist apps/sub-route-billing/dist importmap.json index.html artifacts
	@echo "Cleanup completed."
