# Handle With Care — the single entry point for running things.
#
# Everything here wraps something that already existed but had to be
# remembered: scripts/run_tests.sh, the three asset generators, and bob.jar
# invocations that lived only in shell history. The one genuinely new
# capability is `make play` — until now nothing in this repository launched
# the game, even though docs/playtest_checklist.md is seven sections of
# things you can only check by playing it.
#
# Run `make` (or `make help`) for the target list.

SHELL := /bin/bash

DEFOLD_DIR   := .defold
BOB          := $(DEFOLD_DIR)/bob.jar
DMENGINE     := $(DEFOLD_DIR)/dmengine
DMENGINE_HL  := $(DEFOLD_DIR)/dmengine_headless
BUILD_DIR    := build/default
WEB_BUNDLE   := build/web
CHECKLIST    := docs/playtest_checklist.md

# bob.jar is compiled to class file major 69, i.e. Java 25. Anything older
# dies with UnsupportedClassVersionError before running a single task — the
# exact failure the CI workflow was shipping until this Makefile was added.
JAVA_MIN := 25
JAVA     := $(if $(JAVA_HOME),$(JAVA_HOME)/bin/java,java)

# bob.jar prints ~30 lines of JVM and protobuf warnings before doing any
# work. None are actionable from this project — they are about how bob
# itself was built — and they bury the one line that matters ("100%
# Building" or an error). Silenced, not filtered, so a real error still
# reaches the terminal.
JAVA_QUIET := --enable-native-access=ALL-UNNAMED \
              -Dcom.google.protobuf.use_unsafe_pre22_gencode=true

.PHONY: help test test-ci build clean verify play play-headless checklist \
        bundle-web serve assets sprites audio font doctor require-java \
        require-tools

help: ## Show this list
	@echo "Handle With Care — make targets"
	@echo
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| sort \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "Playtest starts with: make play"

# --- guards ------------------------------------------------------------
# Depended on by every target that shells out to bob, so a wrong JDK
# produces a sentence instead of a Java stack trace.
require-java:
	@command -v $(JAVA) >/dev/null 2>&1 || { \
		echo "ERROR: no java found (looked for '$(JAVA)')."; \
		echo "       bob.jar needs Java $(JAVA_MIN)+."; exit 1; }
	@major=$$($(JAVA) -version 2>&1 | head -1 \
		| sed -E 's/.*"1\.([0-9]+).*/\1/; s/.*"([0-9]+).*/\1/'); \
	if [ "$$major" -lt $(JAVA_MIN) ]; then \
		echo "ERROR: bob.jar needs Java $(JAVA_MIN)+, found $$major."; \
		echo "       Set JAVA_HOME to a $(JAVA_MIN)+ JDK, e.g."; \
		echo "       JAVA_HOME=\$$HOME/.sdkman/candidates/java/25.0.3-tem make build"; \
		exit 1; \
	fi

# The tools are downloaded on demand by run_tests.sh (verified against
# pinned checksums), so the fix for a missing one is always `make test`.
require-tools:
	@test -f $(BOB) || { \
		echo "ERROR: $(BOB) is missing."; \
		echo "       Run 'make test' once — it downloads and checksums the"; \
		echo "       pinned Defold tooling into $(DEFOLD_DIR)/."; exit 1; }

# --- tests and build ---------------------------------------------------
test: ## Run the unit + integration suite (exit code IS the result)
	@./scripts/run_tests.sh

test-ci: ## Run the suite exactly as CI does (x86_64-linux)
	@./scripts/run_tests.sh x86_64-linux

build: require-java require-tools ## Compile the production bootstrap
	@$(JAVA) $(JAVA_QUIET) -jar $(BOB) --variant=headless build

clean: ## Delete build output
	@rm -rf build
	@echo "removed build/"

verify: assets build test ## Assets + production build + suite: the pre-commit gate

# --- playtest ----------------------------------------------------------
# `build` first, every time: the suite boots test/test.collection, so
# nothing automated ever compiles the ten level collections. Playing a stale
# build is how you end up debugging a bug you already fixed.
play: build ## Build and launch the game in a window (start here for playtest)
	@test -f $(DMENGINE) || { \
		echo "ERROR: $(DMENGINE) is missing — run 'make test' to fetch the tooling."; \
		exit 1; }
	@echo "Launching the game. Checklist: $(CHECKLIST)"
	@$(DMENGINE)

play-headless: build ## Launch the production build headless (boot smoke test)
	@$(DMENGINE_HL)

checklist: ## Print the playtest checklist
	@cat $(CHECKLIST)

bundle-web: require-java require-tools ## Bundle for the browser (PRD 9.5 perf pass)
	@echo "Bundling js-web into $(WEB_BUNDLE)/ (may download the web engine once)..."
	@$(JAVA) $(JAVA_QUIET) -jar $(BOB) --archive --platform js-web \
		--bundle-output $(WEB_BUNDLE) distclean build bundle

serve: ## Serve the web bundle at http://localhost:8000
	@dir=$$(find $(WEB_BUNDLE) -name index.html -maxdepth 3 2>/dev/null | head -1); \
	if [ -z "$$dir" ]; then \
		echo "ERROR: no web bundle found. Run 'make bundle-web' first."; exit 1; \
	fi; \
	echo "Serving $$(dirname $$dir) at http://localhost:8000"; \
	cd "$$(dirname $$dir)" && python3 -m http.server 8000

# --- assets ------------------------------------------------------------
# All three generators are deterministic and check their own contracts, so
# regenerating is safe: `git diff` staying empty afterwards is the proof.
assets: sprites audio font ## Regenerate every generated asset

sprites: ## Regenerate sprites and the atlas
	@python3 scripts/generate_sprites.py

audio: ## Regenerate all music and sound effects
	@python3 scripts/generate_audio.py

font: ## Regenerate the UI pixel font
	@python3 scripts/generate_font.py

# --- environment -------------------------------------------------------
doctor: ## Check the toolchain without changing anything
	@echo "Toolchain check"
	@printf '  %-22s' "java >= $(JAVA_MIN):"; \
	if ! command -v $(JAVA) >/dev/null 2>&1; then echo "MISSING"; else \
		major=$$($(JAVA) -version 2>&1 | head -1 \
			| sed -E 's/.*"1\.([0-9]+).*/\1/; s/.*"([0-9]+).*/\1/'); \
		if [ "$$major" -ge $(JAVA_MIN) ]; then echo "ok ($$major)"; \
		else echo "TOO OLD ($$major) — bob.jar will not run"; fi; fi
	@printf '  %-22s' "ffmpeg:"; \
	command -v ffmpeg >/dev/null 2>&1 && echo "ok" || echo "MISSING (make audio needs it)"
	@printf '  %-22s' "python3:"; \
	command -v python3 >/dev/null 2>&1 && echo "ok" || echo "MISSING"
	@printf '  %-22s' "numpy:"; \
	python3 -c "import numpy" 2>/dev/null && echo "ok" || echo "MISSING (make audio needs it)"
	@printf '  %-22s' "Pillow:"; \
	python3 -c "import PIL" 2>/dev/null && echo "ok" || echo "MISSING (make sprites/font need it)"
	@printf '  %-22s' "defold tooling:"; \
	test -f $(BOB) && test -f $(DMENGINE) && echo "ok" \
		|| echo "not downloaded yet (run 'make test' once)"
