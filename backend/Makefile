GO ?= go
.PHONY: run test vet build
run:
	$(GO) run ./cmd/server
test:
	$(GO) test -race ./...
vet:
	$(GO) vet ./...
build:
	$(GO) build -o bin/server ./cmd/server
