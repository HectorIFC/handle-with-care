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
WEB_BUNDLE   := dist/web
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

.PHONY: help test test-ci build clean verify play play-headless smoke checklist \
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
	@$(JAVA) $(JAVA_QUIET) -jar $(BOB) build

clean: ## Delete build output
	@rm -rf build
	@echo "removed build/"

verify: assets build test ## Assets + geometry + build + suite: the pre-commit gate

# --- playtest ----------------------------------------------------------
# Boot smoke test. This exists because `make play` crashed the first time it
# was ever run: main.collection declared its ten level proxies as
# `component: ".../level_01.collection"`, and a collection is not a
# component type, so the engine asserted inside dmEngine::Init. bob compiled
# it happily (the path IS a valid resource) and the suite boots
# test/test.collection, so nothing anywhere loaded main.collection.
#
# The crash happened before any graphics, which is why the HEADLESS engine
# catches it. Surviving the timeout is a pass: this asserts "the game
# initializes", not "the game works".
SMOKE_SECONDS ?= 8

# Playtest and diagnostics for ONE room, without beating the ones before
# it. Rooms are one screen and live in one
# collection (main/levels/room.collection) built at runtime from
# main/core/rooms.lua, so unlike levels they share a single proxy and the
# index travels by message — see room_builder.script. ROOM is validated
# against the room count in rooms.lua rather than a hardcoded ceiling, so
# adding rooms never means editing this file.
ROOM ?= 1
# Inside the project on purpose: bob walks the project tree to resolve a
# --settings path and NPEs on one outside it. build/ is gitignored.
LEVEL_SETTINGS := build/autostart.settings
ROOM_COUNT = $(shell grep -c '^\t\tid = "' main/core/rooms.lua)

define room_settings
	@case "$(ROOM)" in \
		''|*[!0-9]*) echo "ROOM must be a number 1..$(ROOM_COUNT) (got '$(ROOM)')"; exit 1 ;; \
	esac; \
	if [ "$(ROOM)" -lt 1 ] || [ "$(ROOM)" -gt $(ROOM_COUNT) ]; then \
		echo "ROOM must be 1..$(ROOM_COUNT) (got $(ROOM))"; exit 1; fi
	@mkdir -p $(dir $(LEVEL_SETTINGS))
	@printf '[hwc]\nautostart_room = $(ROOM)\n\n[engine]\nrun_while_iconified = 1\n' \
		> $(LEVEL_SETTINGS)
endef

play-room: require-java require-tools ## Play one room directly: make play-room ROOM=3
	$(room_settings)
	@$(JAVA) $(JAVA_QUIET) -jar $(BOB) --settings $(LEVEL_SETTINGS) build
	@rm -f $(LEVEL_SETTINGS)
	@test -f $(DMENGINE) || { echo "ERROR: $(DMENGINE) missing — run 'make test' once."; exit 1; }
	@echo "Launching room $(ROOM) of $(ROOM_COUNT)."
	@-$(DMENGINE)
	@echo "restoring the normal (menu) build..."
	@$(JAVA) $(JAVA_QUIET) -jar $(BOB) build > /dev/null

smoke-room: require-java require-tools ## Boot one room headless: make smoke-room ROOM=3
	$(room_settings)
	@$(JAVA) $(JAVA_QUIET) -jar $(BOB) --settings $(LEVEL_SETTINGS) build
	@rm -f $(LEVEL_SETTINGS)
	@log=$$(mktemp); \
	( $(DMENGINE_HL) > "$$log" 2>&1 & echo $$! > "$$log.pid" ); \
	sleep $(SMOKE_SECONDS); \
	pid=$$(cat "$$log.pid"); \
	if kill -0 "$$pid" 2>/dev/null; then kill "$$pid" 2>/dev/null; alive=1; else alive=0; fi; \
	wait "$$pid" 2>/dev/null || true; \
	echo "--- room boot log ---"; grep -aE "AUTOSTART|ROOM-START|ERROR|Assertion" "$$log" | head -20; \
	if grep -qaE "Assertion failed|ERROR:CRASH|ERROR:SCRIPT" "$$log"; then \
		echo "SMOKE-ROOM FAILED — see errors above"; rm -f "$$log" "$$log.pid"; exit 1; fi; \
	if [ "$$alive" = "0" ]; then \
		echo "SMOKE-ROOM FAILED — engine exited early"; tail -5 "$$log"; \
		rm -f "$$log" "$$log.pid"; exit 1; fi; \
	if ! grep -qa "ROOM-START " "$$log"; then \
		echo "SMOKE-ROOM FAILED — no ROOM-START line at all"; \
		rm -f "$$log" "$$log.pid"; exit 1; fi; \
	rm -f "$$log" "$$log.pid"; echo "smoke-room ok — room $(ROOM) built"
	@echo "restoring the normal (menu) build..."
	@$(JAVA) $(JAVA_QUIET) -jar $(BOB) build > /dev/null

smoke: build ## Boot the production build headless and fail if it crashes
	@log=$$(mktemp); \
	( $(DMENGINE_HL) > "$$log" 2>&1 & echo $$! > "$$log.pid" ); \
	sleep $(SMOKE_SECONDS); \
	pid=$$(cat "$$log.pid"); \
	if kill -0 "$$pid" 2>/dev/null; then kill "$$pid" 2>/dev/null; alive=1; else alive=0; fi; \
	wait "$$pid" 2>/dev/null || true; \
	if grep -qE "Assertion failed|ERROR:CRASH|Failed to find component type" "$$log"; then \
		echo "SMOKE FAILED — the game does not boot:"; \
		grep -E "ERROR|Assertion failed" "$$log" | head -5; \
		rm -f "$$log" "$$log.pid"; exit 1; \
	fi; \
	if [ "$$alive" = "0" ]; then \
		echo "SMOKE FAILED — the engine exited within $(SMOKE_SECONDS)s:"; \
		tail -5 "$$log"; rm -f "$$log" "$$log.pid"; exit 1; \
	fi; \
	rm -f "$$log" "$$log.pid"; \
	echo "smoke ok — booted and stayed up for $(SMOKE_SECONDS)s"

# `build` first, every time: the suite boots test/test.collection, so
# nothing automated ever compiles the ten level collections. Playing a stale
# build is how you end up debugging a bug you already fixed.
play: smoke ## Build and launch the game in a window (start here for playtest)
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
	@echo "Bundling wasm-web into $(WEB_BUNDLE)/ (may download the web engine once)..."
	@$(JAVA) $(JAVA_QUIET) -jar $(BOB) --archive --platform wasm-web \
		--bundle-output $(WEB_BUNDLE) distclean build bundle
	@echo "cleaning the archive out of build/ (dmengine prefers an archive when"
	@echo "  one exists, so a stale wasm archive would hijack the next test or"
	@echo "  play run — and bob distclean does NOT remove it, verified)..."
	@rm -rf build/default

serve: ## Serve the web bundle at http://localhost:8000
	@dir=$$(find $(WEB_BUNDLE) -name index.html -maxdepth 3 2>/dev/null | head -1); \
	if [ -z "$$dir" ]; then \
		echo "ERROR: no web bundle found. Run 'make bundle-web' first."; exit 1; \
	fi; \
	dir=$$(dirname "$$dir"); \
	echo "Serving $$dir at http://localhost:8000"; \
	cd "$$dir" && python3 -m http.server 8000

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
