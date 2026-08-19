# hoike-dev site build and deployment
#
# Targets:
#   make build    - Build docs and assemble deploy/
#   make serve    - Build and serve locally (mdBook only)
#   make deploy   - Build and deploy to Cloudflare Pages
#   make api      - Copy rustdoc from the hoike repo
#   make clean    - Remove build artifacts

HOIKE_REPO   ?= ../hoike
DEPLOY_DIR   := deploy
DOC_BUILD    := doc-build

.PHONY: build serve deploy api clean

build: docs api assemble

docs:
	cd doc && mdbook build

api:
	cd $(HOIKE_REPO) && cargo doc --workspace --no-deps \
		--config 'build.rustdocflags=["--extend-css", "../hoike-dev/api-theme.css", "--html-in-header", "../hoike-dev/api-header.html"]'
	rm -rf api
	cp -r $(HOIKE_REPO)/target/doc api

assemble: docs
	rm -rf $(DEPLOY_DIR)
	mkdir -p $(DEPLOY_DIR)/doc $(DEPLOY_DIR)/api
	cp index.html favicon.svg $(DEPLOY_DIR)/
	cp -r $(DOC_BUILD)/* $(DEPLOY_DIR)/doc/
	@if [ -d api ]; then cp -r api/* $(DEPLOY_DIR)/api/; fi

serve:
	cd doc && mdbook serve --open

deploy: build
	wrangler pages deploy $(DEPLOY_DIR)

clean:
	rm -rf $(DEPLOY_DIR) $(DOC_BUILD) api
