#!/usr/bin/env bash
# Builds the relay for the chain tests (P7, test/chain/): build/relay/relay.
# Needs Go (relay/go.mod).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/relay
(cd relay && go build -trimpath -o ../build/relay/relay .)
echo "build/relay/relay"
