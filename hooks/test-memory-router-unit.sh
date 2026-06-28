#!/usr/bin/env bash
# kimiflow — Python unit tests for the memory_router package.
# Runs all three test modules and follows the repo's ok/bad idiom.
# Run: bash hooks/test-memory-router-unit.sh
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"

# Ensure jq is reachable — contracts test needs it
[ -d /opt/homebrew/bin ] && export PATH="/opt/homebrew/bin:$PATH"

FAILS=0

cd "$DIR"
if python3 -m unittest memory_router.tests.test_dispatch \
                        memory_router.tests.test_contracts \
                        memory_router.tests.test_store -v; then
  : # all green
else
  FAILS=$((FAILS + 1))
fi

echo "----"
if [ "$FAILS" -eq 0 ]; then echo "ALL GREEN"; exit 0; else echo "$FAILS FAILED"; exit 1; fi
