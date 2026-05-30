#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$SCRIPT_DIR/NAPS2.App.Gtk"

export PATH="$HOME/.dotnet:$PATH"

# Use single node to reduce memory pressure
export MSBUILD_SINGLENODE=1

echo "=== Restoring dependencies ==="
dotnet restore "$PROJECT"

echo ""
echo "=== Building for Linux (Debug) ==="
dotnet build "$PROJECT" -c Debug -r linux-x64 -m:1

echo ""
echo "=== Running NAPS2 (Linux GTK) ==="
dotnet run --project "$PROJECT" -c Debug "$@"
