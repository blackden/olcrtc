# olcrtc developer toolbelt.
#
# Conventions:
#   - GNU Make 3.81+ (macOS default).
#   - All recipes work without a local Go toolchain by falling back to
#     script/dev/in-docker.sh (golang:1.26-alpine).
#   - mage remains canonical for CI and advanced flows; this file is
#     for everyday human ergonomics.

SHELL := /bin/sh
.DEFAULT_GOAL := help

# Detect local Go.
HAVE_GO := $(shell command -v go 2>/dev/null)
GO      := $(if $(HAVE_GO),go,./script/dev/in-docker.sh go)

# Detect local golangci-lint; otherwise use docker.
HAVE_GCL := $(shell command -v golangci-lint 2>/dev/null)
GCL_IMAGE := golangci/golangci-lint:v2.6-alpine
GCL := $(if $(HAVE_GCL),golangci-lint,docker run --rm --network=host \
        -v $(CURDIR):/src -w /src \
        -v olcrtc-dev-gomod:/go/pkg/mod \
        -v olcrtc-dev-gocache:/root/.cache/go-build \
        $(GCL_IMAGE) golangci-lint)

COMPOSE := docker compose
PROFILE ?= server

.PHONY: help
help:  ## show this help
	@awk 'BEGIN {FS = ":.*?## "} \
	     /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' \
	     $(MAKEFILE_LIST)
	@echo ""
	@echo "Variables:"
	@echo "  PROFILE   docker compose profile (server|client|gen) [default: server]"
	@echo "  TEST      go test -run regex (for test-stress)"
	@echo "  N         iteration count (for test-stress) [default: 10]"
	@echo "  RACE      enable -race in test-stress: RACE=1"

.PHONY: test
test:  ## run all unit tests with -race
	$(GO) test -race -count=1 ./...

.PHONY: test-stress
test-stress:  ## stress-run one test: make test-stress TEST=^TestX$$ N=50 [RACE=1]
	@test -n "$(TEST)" || { echo "error: TEST=^TestName\$$ required" >&2; exit 2; }
	$(GO) test $(if $(filter 1,$(RACE)),-race,) -count=$(or $(N),10) \
	    -timeout 600s -run '$(TEST)' ./internal/e2e

.PHONY: build
build:  ## build olcrtc binary into build/
	$(GO) build -trimpath -ldflags="-s -w" -o build/olcrtc ./cmd/olcrtc

.PHONY: lint
lint:  ## run golangci-lint
	$(GCL) run ./...

.PHONY: tidy
tidy:  ## go mod tidy
	$(GO) mod tidy

.PHONY: docker
docker:  ## build local docker image (olcrtc:dev)
	docker build --network=host -t olcrtc:dev .

.PHONY: up
up:  ## docker compose up -d for PROFILE (server|client|gen)
	$(COMPOSE) --profile $(PROFILE) up -d

.PHONY: down
down:  ## docker compose down (all profiles)
	$(COMPOSE) --profile server --profile client --profile gen down

.PHONY: logs
logs:  ## tail compose logs for PROFILE
	$(COMPOSE) --profile $(PROFILE) logs -f --tail=200

.PHONY: ps
ps:  ## list running compose services
	$(COMPOSE) ps

.PHONY: compose-check
compose-check:  ## validate compose.yaml for all profiles
	@for p in server client gen; do \
	    echo "=== profile: $$p ==="; \
	    $(COMPOSE) --profile $$p config -q || exit 1; \
	done
	@echo "OK"

.PHONY: clean
clean:  ## remove build artifacts (does NOT touch docker volumes)
	rm -rf build/ dist/

.PHONY: clean-cache
clean-cache:  ## remove docker volume caches (forces fresh go-mod download)
	-docker volume rm olcrtc-dev-gomod olcrtc-dev-gocache

.PHONY: doctor
doctor:  ## diagnose local toolchain
	@echo "go:             $(if $(HAVE_GO),$(HAVE_GO),NOT INSTALLED → using docker fallback)"
	@echo "golangci-lint:  $(if $(HAVE_GCL),$(HAVE_GCL),NOT INSTALLED → using docker fallback)"
	@command -v docker >/dev/null && echo "docker:         $$(docker --version)" || echo "docker:         NOT INSTALLED (required)"
	@command -v mage   >/dev/null && echo "mage:           $$(mage -version 2>&1 | head -1)" || echo "mage:           NOT INSTALLED (optional)"
