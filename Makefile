DBG         ?= 0
PROJECT     ?= vertical-pod-autoscaler-operator
ORG_PATH    ?= github.com/openshift
REPO_PATH   ?= $(ORG_PATH)/$(PROJECT)
VERSION     ?= $(shell git describe --always --dirty --abbrev=7)
LD_FLAGS    ?= -X $(REPO_PATH)/pkg/version.Raw=$(VERSION)
BUILD_DEST  ?= bin/vertical-pod-autoscaler-operator
MUTABLE_TAG ?= latest
IMAGE        = origin-vertical-pod-autoscaler-operator

ifeq ($(DBG),1)
GOGCFLAGS ?= -gcflags=all="-N -l"
endif

.PHONY: all
all: build images check

NO_DOCKER ?= 0
ifeq ($(NO_DOCKER), 1)
  DOCKER_CMD =
  IMAGE_BUILD_CMD = imagebuilder
else
  DOCKER_CMD := podman run --rm -v "$(CURDIR):/go/src/$(REPO_PATH):Z" -w "/go/src/$(REPO_PATH)" openshift/origin-release:golang-1.12
  IMAGE_BUILD_CMD = buildah bud
endif

.PHONY: depend
depend:
	dep version || go get -u github.com/golang/dep/cmd/dep
	dep ensure

.PHONY: depend-update
depend-update:
	dep ensure -update

# This is a hack. The operator-sdk doesn't currently let you configure
# output paths for the generated CRDs.  It also requires that they
# already exist in order to regenerate the OpenAPI bits, so we do some
# copying around here.
.PHONY: generate
generate: ## Code generation (requires operator-sdk >= v0.5.0)
	mkdir -p deploy/crds

	cp install/01_vpacontroller.crd.yaml \
	  deploy/crds/autoscaling_v1_01_vpacontroller.crd.yaml

	operator-sdk generate k8s
	operator-sdk generate openapi

	cp deploy/crds/autoscaling_v1_01_vpacontroller.crd.yaml \
	  install/01_vpacontroller.crd.yaml

.PHONY: build
build: ## build binaries
	$(DOCKER_CMD) go build $(GOGCFLAGS) -ldflags "$(LD_FLAGS)" -o "$(BUILD_DEST)" "$(REPO_PATH)/cmd/manager"

.PHONY: images
images: ## Create images
	$(IMAGE_BUILD_CMD) -t "$(IMAGE):$(VERSION)" -t "$(IMAGE):$(MUTABLE_TAG)" ./

.PHONY: push
push:
	podman push "$(IMAGE):$(VERSION)"
	podman push "$(IMAGE):$(MUTABLE_TAG)"

.PHONY: check
check: fmt vet lint test ## Check your code

.PHONY: check-pkg
check-pkg:
	./hack/verify-actuator-pkg.sh

.PHONY: test
test: ## Run unit tests
	$(DOCKER_CMD) go test -race -cover ./...

.PHONY: test-e2e
test-e2e: ## Run e2e tests
	hack/e2e.sh

.PHONY: lint
lint: ## Go lint your code
	hack/go-lint.sh -min_confidence 0.3 $(go list -f '{{ .ImportPath }}' ./...)

.PHONY: fmt
fmt: ## Go fmt your code
	hack/go-fmt.sh .

.PHONY: vet
vet: ## Apply go vet to all go files
	hack/go-vet.sh ./...

.PHONY: help
help:
	@grep -E '^[a-zA-Z/0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
