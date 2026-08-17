#!/usr/bin/env bash
# Runs the deftest unit + integration suite headless, without needing the
# Defold Editor open. Mirrors deftest's own recommended CI setup
# (https://github.com/britzl/deftest#running-tests-from-a-ci-system), adapted
# to keep /game.project's bootstrap pointed at the real game while tests use
# /test/testing.settings as an override (see deftest's "Bootstrap" section).
#
# On first run it downloads the pinned dmengine_headless + bob.jar release
# into ./.defold/ (gitignored) and reuses them on subsequent runs. Both
# downloads are verified against a pinned SHA-256 before being trusted, since
# d.defold.com serves archives over plain HTTP (its https endpoint redirects
# straight back down to http, so scheme alone cannot be relied on here).
#
# Usage: ./scripts/run_tests.sh [platform]
#   platform defaults to the current OS/arch. Pass it explicitly to match a
#   CI runner, e.g.: ./scripts/run_tests.sh x86_64-linux
#
# Bumping the Defold version: change DEFOLD_VERSION/DEFOLD_SHA1 below, then
# regenerate the three DMENGINE_SHA256_* values and BOB_SHA256 by downloading
# each artifact once and running `shasum -a 256` on it. This is a deliberate,
# reviewable step, not something resolved automatically at run time (a prior
# version of this script did that and silently ran whatever the toolchain
# happened to be on a given day).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Pinned Defold release. Update deliberately (see header comment above).
DEFOLD_VERSION="1.13.0"
DEFOLD_SHA1="f735c12192bf95684e6ae1ae27c400b8170fc6d8"
BOB_SHA256="22e651025834603794ba6873b09924f11412dff66eee0e38aaef8955eb534655"
DMENGINE_SHA256_arm64_macos="b3b3f4ec34059b3531898d0dec1dc2f1a276e6bad1e62fc2058312c2e1e98f4a"
DMENGINE_SHA256_x86_64_macos="139ddc7859b67ba5951f0a1d30edffb7d0b63164f8d6b51f8814aabd0beafcaf"
DMENGINE_SHA256_x86_64_linux="e92603177b4f967842f8d5a4179c51e6a249539d377a743b4a68469aaad807df"

if [ $# -ge 1 ]; then
	PLATFORM="$1"
else
	case "$(uname -s)-$(uname -m)" in
		Darwin-arm64) PLATFORM="arm64-macos" ;;
		Darwin-x86_64) PLATFORM="x86_64-macos" ;;
		Linux-x86_64) PLATFORM="x86_64-linux" ;;
		*)
			echo "Unsupported platform: $(uname -s)-$(uname -m)." >&2
			echo "Pass it explicitly, e.g.: ./scripts/run_tests.sh x86_64-linux" >&2
			exit 1
			;;
	esac
fi

case "$PLATFORM" in
	arm64-macos) DMENGINE_SHA256="$DMENGINE_SHA256_arm64_macos" ;;
	x86_64-macos) DMENGINE_SHA256="$DMENGINE_SHA256_x86_64_macos" ;;
	x86_64-linux) DMENGINE_SHA256="$DMENGINE_SHA256_x86_64_linux" ;;
	*)
		echo "No pinned dmengine_headless checksum for platform '$PLATFORM'." >&2
		echo "Supported: arm64-macos, x86_64-macos, x86_64-linux." >&2
		exit 1
		;;
esac

echo "Using Defold ${DEFOLD_VERSION} (${DEFOLD_SHA1}) for platform ${PLATFORM}"

TOOLS_DIR="$ROOT_DIR/.defold"
mkdir -p "$TOOLS_DIR"

DMENGINE="$TOOLS_DIR/dmengine_headless"
BOB="$TOOLS_DIR/bob.jar"

# Downloads $2 to a temp file, verifies it against the expected SHA-256 ($3),
# and only then moves it into place at $1 — so a failed/tampered/truncated
# download never gets treated as a valid cached artifact.
fetch_verified() {
	local dest="$1" url="$2" expected_sha256="$3"
	local tmp
	tmp="$(mktemp "${dest}.XXXXXX")"
	echo "Downloading ${url}..."
	if ! curl -fsSL -o "$tmp" "$url"; then
		echo "Download failed: ${url}" >&2
		rm -f "$tmp"
		exit 1
	fi
	local actual_sha256
	actual_sha256="$(shasum -a 256 "$tmp" | cut -d' ' -f1)"
	if [ "$actual_sha256" != "$expected_sha256" ]; then
		echo "Checksum mismatch for ${url}" >&2
		echo "  expected: ${expected_sha256}" >&2
		echo "  actual:   ${actual_sha256}" >&2
		rm -f "$tmp"
		exit 1
	fi
	mv "$tmp" "$dest"
}

if [ ! -f "$DMENGINE" ]; then
	fetch_verified "$DMENGINE" \
		"http://d.defold.com/archive/${DEFOLD_SHA1}/engine/${PLATFORM}/dmengine_headless" \
		"$DMENGINE_SHA256"
	chmod +x "$DMENGINE"
fi

if [ ! -f "$BOB" ]; then
	fetch_verified "$BOB" \
		"http://d.defold.com/archive/${DEFOLD_SHA1}/bob/bob.jar" \
		"$BOB_SHA256"
fi

echo "Building test bootstrap (test/testing.settings)..."
# `resolve` re-fetches the deftest dependency from GitHub on EVERY run, and
# GitHub rate-limits: an HTTP 429 there fails the whole build with a stack
# trace, even though the library has been sitting in .internal/lib since the
# first run. That is a transient network condition reported as a test
# failure, which is the worst way to report anything.
#
# So resolve is attempted, and if it fails while a populated cache exists,
# the build goes ahead with what is already there. A cold cache still fails
# loudly — CI has nothing to fall back ON, which is exactly when resolving
# has to work.
if ! java -jar "$BOB" --variant=headless --settings test/testing.settings resolve build; then
	if [ -n "$(ls -A .internal/lib 2>/dev/null)" ]; then
		echo "resolve failed (rate limit?) — building from the cached library"
		java -jar "$BOB" --variant=headless --settings test/testing.settings build
	else
		echo "ERROR: could not resolve dependencies and no cached library exists"
		exit 1
	fi
fi

echo "Running tests..."
# deftest.run() calls os.exit(0) on success and os.exit(1) on any failure or
# error, so dmengine_headless's own exit code IS the test result, and this
# script propagates it unchanged.
#
# dmengine_headless wedges intermittently — ~1 run in 3 when first measured,
# but observed at ~4 attempts in 5 during phase 27, which is why
# MAX_ATTEMPTS is 10 rather than a handful. The
# process stays alive and its main loop keeps sleeping in the normal frame
# limiter, but the engine stops running the update phase entirely — no game
# object updates, and test_runner.script's own unconditional heartbeat stops
# printing, so no test ever completes and this script would otherwise wait
# forever. It is NOT caused by this project's code: it reproduces at the
# boundary of phase 1/2 suites that have been stable for many phases, with a
# healthy engine and zero errors logged. See CLAUDE.md for the full
# investigation and the hypotheses already ruled out.
#
# Retrying is safe here specifically because it only ever retries a run that
# produced NO result. A genuine pass (0) or genuine test failure (1) is
# returned immediately and never retried, so this cannot mask a real failing
# test (CLAUDE.md architecture rule 8) — it only distinguishes "the engine
# died without answering" from "the tests answered".
# Backstop only: caps an attempt that wedges (or fails to boot) BEFORE
# test_runner.script ever writes a heartbeat, which the idle check below
# cannot see. ~1.5x a healthy ~120s run (433 tests), and it must grow as the
# suite grows
# — export STALL_TIMEOUT rather than editing this default when running on a
# slower machine or a loaded CI runner.
STALL_TIMEOUT="${STALL_TIMEOUT:-180}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-10}"
# The primary detector: how long test_runner.script's file heartbeat may stop
# advancing before the run is treated as wedged. This is what keeps a wedge
# cheap — caught in ~15s instead of burning the whole STALL_TIMEOUT, which
# matters a lot given how often attempts wedge. It watches a file rather than
# stdout because the engine block-buffers its output when that output is not
# a terminal, so a perfectly healthy run can look silent for tens of seconds.
HEARTBEAT_IDLE="${HEARTBEAT_IDLE:-15}"

HEARTBEAT_FILE="$(mktemp "${TMPDIR:-/tmp}/hwc_heartbeat.XXXXXX")"
export HWC_HEARTBEAT_FILE="$HEARTBEAT_FILE"
trap 'rm -f "$HEARTBEAT_FILE"' EXIT

attempt=1
while :; do
	: > "$HEARTBEAT_FILE"
	attempt_started="$SECONDS"
	"$DMENGINE" &
	engine_pid=$!
	(
		waited=0
		idle=0
		last=""
		while kill -0 "$engine_pid" 2>/dev/null; do
			sleep 3
			waited=$((waited + 3))
			current="$(cat "$HEARTBEAT_FILE" 2>/dev/null || true)"
			if [ -n "$current" ] && [ "$current" = "$last" ]; then
				idle=$((idle + 3))
			else
				idle=0
				last="$current"
			fi
			# The idle check needs the heartbeat to have started at all, so
			# STALL_TIMEOUT stays as the backstop for a run that wedges (or
			# never boots) before writing even once.
			if [ "$idle" -ge "$HEARTBEAT_IDLE" ] || [ "$waited" -ge "$STALL_TIMEOUT" ]; then
				kill -9 "$engine_pid" 2>/dev/null || true
				exit 0
			fi
		done
	) &
	watchdog_pid=$!

	engine_code=0
	wait "$engine_pid" || engine_code=$?

	kill "$watchdog_pid" 2>/dev/null || true
	wait "$watchdog_pid" 2>/dev/null || true

	# deftest.run() calls os.exit(0) on success and os.exit(1) on any failure
	# or error, so these two are the real test result and are final.
	if [ "$engine_code" -eq 0 ] || [ "$engine_code" -eq 1 ]; then
		exit "$engine_code"
	fi

	# Anything else means the watchdog killed a wedged engine (128+9=137).
	# Report the attempt's real duration rather than a fixed number: a wedge
	# is normally caught by the heartbeat in ~HEARTBEAT_IDLE seconds, and
	# only falls back to the much longer STALL_TIMEOUT when it wedged before
	# writing a heartbeat at all — telling those apart matters if this ever
	# needs debugging again.
	attempt_seconds=$((SECONDS - attempt_started))
	if [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
		echo "Engine wedged (no test result) on all ${MAX_ATTEMPTS} attempts; giving up." >&2
		exit 1
	fi
	echo "Engine wedged (no test result) after ${attempt_seconds}s; retrying (attempt $((attempt + 1))/${MAX_ATTEMPTS})..." >&2
	attempt=$((attempt + 1))
done
