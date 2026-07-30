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
java -jar "$BOB" --variant=headless --settings test/testing.settings resolve build

echo "Running tests..."
# deftest.run() calls os.exit(0) on success and os.exit(1) on any failure or
# error, so dmengine_headless's own exit code IS the test result. `exec`
# replaces this shell with dmengine_headless so that code becomes this
# script's exit code directly.
exec "$DMENGINE"
