# hoike-dev site build and deployment
#
# Targets:
#   make build    - Build docs and assemble deploy/
#   make serve    - Build and serve locally (mdBook only)
#   make deploy   - Build and deploy the production Worker
#   make api      - Copy rustdoc from the hoike repo
#   make clean    - Remove build artifacts

export PATH := $(HOME)/.cargo/bin:$(PATH)

HOIKE_REPO   ?= ../hoike
DEPLOY_DIR   := deploy
DOC_BUILD    := doc-build
API_TARGET_DIR ?= $(CURDIR)/.build/api-target

.PHONY: build docs assemble serve deploy api clean

build: assemble

docs:
	cd doc && mdbook build

api:
	# Clear stale target/doc first: --no-deps skips *generating* dependency
	# docs but leaves any pre-existing ones in place, and copying them all in
	# blows past Cloudflare Pages' 20,000-file/deployment limit.
	rm -rf "$(API_TARGET_DIR)/doc"
	CARGO_TARGET_DIR="$(API_TARGET_DIR)" cargo doc --locked --workspace --exclude hoike-cli --lib --no-deps \
		--manifest-path "$(HOIKE_REPO)/Cargo.toml" \
		--config 'build.rustdocflags=["--extend-css", "$(CURDIR)/api-theme.css", "--html-in-header", "$(CURDIR)/api-header.html"]'
	# The ahu binary collides with the ahu library's output path. Document the
	# hoike CLI separately so the bundle library's API index cannot be overwritten.
	CARGO_TARGET_DIR="$(API_TARGET_DIR)" cargo doc --locked -p hoike-cli --bin hoike --no-deps \
		--manifest-path "$(HOIKE_REPO)/Cargo.toml" \
		--config 'build.rustdocflags=["--extend-css", "$(CURDIR)/api-theme.css", "--html-in-header", "$(CURDIR)/api-header.html"]'
	rm -rf api
	cp -r "$(API_TARGET_DIR)/doc" api
	cp api-index.html api/index.html

assemble: docs api
	rm -rf $(DEPLOY_DIR)
	mkdir -p $(DEPLOY_DIR)/doc $(DEPLOY_DIR)/api
	cp index.html favicon.svg $(DEPLOY_DIR)/
	cp -r $(DOC_BUILD)/* $(DEPLOY_DIR)/doc/
	cp -r api/* $(DEPLOY_DIR)/api/
	node scripts/build-info.mjs "$(HOIKE_REPO)"
	node scripts/check-site.mjs

serve:
	cd doc && mdbook serve --open

deploy:
	npm run deploy

clean:
	rm -rf $(DEPLOY_DIR) $(DOC_BUILD) api
