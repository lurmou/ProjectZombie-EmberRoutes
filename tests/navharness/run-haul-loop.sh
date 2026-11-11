#!/bin/sh
# Run the haul-loop harness (tests/navharness) headless under lua5.4.
# Usage: tests/navharness/run-haul-loop.sh [repo-root]
# Defaults to the repo root implied by this script's location.
# Exit 0 = all scenarios pass. Full event traces are written next to
# this script as haul-loop-trace-s<N>.txt.
set -e
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=${1:-$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)}
export NAV_HARNESS_DIR="$SCRIPT_DIR"
LUA_DIR="$ROOT/Contents/mods/EmberRoutesProbe/42/media/lua"
export LUA_PATH="$SCRIPT_DIR/?.lua;$LUA_DIR/client/?.lua;$LUA_DIR/shared/?.lua;;"
exec lua5.4 "$SCRIPT_DIR/haul-loop-scenarios.lua"
