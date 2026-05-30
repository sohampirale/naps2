#!/usr/bin/env bash
set -euo pipefail

export MSBUILD_SINGLENODE=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$SCRIPT_DIR/NAPS2.App.WinForms"

echo "=== Restoring ==="
dotnet restore "$PROJECT"

echo ""
echo "=== Building for Windows (Debug) ==="
dotnet build "$PROJECT" -c Debug -r win-x64 -m:1

echo ""
echo "=== Running NAPS2 (Windows) ==="
dotnet run --project "$PROJECT" -c Debug "$@"
