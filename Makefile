.PHONY: help lint template kind-up kind-down dev staging prod chaos validate build-apps

NAMESPACE ?= helios
KIND_CLUSTER ?= helios-local

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-22s\033[0m %s\n", $$1, $$2}'

lint: ## Lint all Helm charts
	helm lint charts/helios-infrastructure
	helm lint charts/helios-platform
	helm lint charts/helios-app

template: ## Render all charts locally (no cluster needed)
	helm template helios-infra charts/helios-infrastructure > /tmp/helios-infra.rendered.yaml
	helm template helios-platform charts/helios-platform > /tmp/helios-platform.rendered.yaml
	helm template helios-app charts/helios-app > /tmp/helios-app.rendered.yaml
	@echo "Rendered manifests written to /tmp/helios-*.rendered.yaml"

kind-up: ## Create local kind cluster
	./hack/local-setup.sh

kind-down: ## Tear down local kind cluster
	kind delete cluster --name $(KIND_CLUSTER)

dev: ## Install Helios into current kube-context (dev profile)
	./scripts/setup-dev.sh

staging: ## Install Helios into current kube-context (staging profile)
	./scripts/setup-staging.sh

prod: ## Install Helios into current kube-context (prod profile)
	./scripts/setup-prod.sh

chaos: ## Run the chaos experiment suite
	./scripts/chaos-run.sh

validate: ## Run self-healing / MTTR validation
	./scripts/validate-self-healing.sh

build-apps: ## Build container images for demo-api, demo-worker, frontend
	docker build -t helios/demo-api:local apps/demo-api
	docker build -t helios/demo-worker:local apps/demo-worker
	docker build -t helios/frontend:local apps/frontend
