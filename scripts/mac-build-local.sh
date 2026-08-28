#!/usr/bin/env bash
# Local macOS build: YTubic.app + DMG, ad-hoc signed.
#
# Skips updater artifacts (those need TAURI_SIGNING_PRIVATE_KEY) and
# Apple notarization. Bundles land under src-tauri/target/release/bundle/.
#
# Refuses to build if this tree still keeps the cookie AES key in Keychain.
# Ad-hoc rebuilds change the code signature; Keychain ACLs then deny the key,
# which pops a permission dialog and looks like a sign-out. Local login must
# use the file-backed key from fix/macos-auth (d9d3bb7).
#
# Usage:
#   ./scripts/mac-build-local.sh
#   ./scripts/mac-build-local.sh --open

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "this script builds a macOS .app/.dmg; run it on a Mac" >&2
  exit 1
fi

OPEN_APP=0
for arg in "$@"; do
  case "$arg" in
    --open) OPEN_APP=1 ;;
    -h|--help)
      sed -n '2,14p' "$0"
      exit 0
      ;;
    *)
      echo "unknown argument: $arg" >&2
      echo "usage: $0 [--open]" >&2
      exit 1
      ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Vanilla main still uses keyring → macOS Keychain. A local ad-hoc .app from
# that tree will prompt for Keychain and drop the session. See AGENTS.md.
if grep -E -q 'keyring_encryption_key|KEYRING_SERVICE' src-tauri/src/lib.rs; then
  echo "refusing to build: this tree still keeps the cookie key in macOS Keychain." >&2
  echo "ad-hoc rebuilds then prompt for Keychain access and look like a sign-out." >&2
  echo "build from a branch that includes fix/macos-auth (file-backed cookie key)," >&2
  echo "e.g. fix/macos-auth or local/our-fixes-on-0.4.7." >&2
  exit 1
fi

if ! command -v pnpm >/dev/null; then
  echo "pnpm is required (https://pnpm.io/installation)" >&2
  exit 1
fi
if ! command -v cargo >/dev/null; then
  echo "Rust/cargo is required (https://rustup.rs)" >&2
  exit 1
fi

if [[ ! -d node_modules ]]; then
  echo "==> pnpm install"
  pnpm install
fi

echo "==> tauri build (app + dmg, no updater signing)"
# createUpdaterArtifacts needs TAURI_SIGNING_PRIVATE_KEY; without it the
# .app/.dmg are still produced but the command exits 1. Turn them off
# for a local installable build.
pnpm tauri build --config '{"bundle":{"createUpdaterArtifacts":false}}'

APP="$ROOT/src-tauri/target/release/bundle/macos/YTubic.app"
DMG="$(ls -1t "$ROOT"/src-tauri/target/release/bundle/dmg/YTubic_*.dmg 2>/dev/null | head -n1 || true)"

echo
echo "Built:"
[[ -d "$APP" ]] && echo "  app  $APP"
[[ -n "$DMG" && -f "$DMG" ]] && echo "  dmg  $DMG"

if [[ "$OPEN_APP" -eq 1 ]]; then
  if [[ ! -d "$APP" ]]; then
    echo "YTubic.app was not produced" >&2
    exit 1
  fi
  echo "==> opening app"
  open "$APP"
fi
