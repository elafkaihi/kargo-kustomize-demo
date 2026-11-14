SHELL := /bin/bash
TAG ?=

.PHONY: help tools up down preflight status release release-chart config break fix promote passwords

help: ## Show targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-17s %s\n", $$1, $$2}'

tools: ## Install pinned k3d/kustomize/gh/kargo/yq into ./bin
	@scripts/tools.sh

up: ## Create the cluster and everything on it (idempotent)
	@scripts/up.sh

down: ## Delete the cluster
	@scripts/down.sh

preflight: ## Check everything is healthy before the demo
	@scripts/preflight.sh

status: ## What runs where
	@scripts/status.sh

release: ## Publish a new podinfo image: make release TAG=6.16.0
	@scripts/release.sh $(TAG)

release-chart: ## Publish a new podinfo chart version: make release-chart VERSION=6.17.0
	@scripts/release-chart.sh $(VERSION)

config: ## Change base values in Git: make config MSG="Kustomize config v2"
	@demo/change-config.sh "$(MSG)"

break: ## Publish a bad release (HTTP 500s): make break [TAG=6.16.1]
	@demo/break.sh $(TAG)

fix: ## Roll forward with a good release: make fix [TAG=6.17.0]
	@demo/fix.sh $(TAG)

promote: ## make promote STAGE=dev [FREIGHT=<alias|name|image-tag>]
	@scripts/promote.sh $(STAGE) $(FREIGHT)

passwords: ## Print local UI passwords
	@. scripts/lib.sh; \
	echo "Argo CD admin: $$(k -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"; \
	echo "Kargo   admin: $$(cat .secrets/kargo-admin-password)"
