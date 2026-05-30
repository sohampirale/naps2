#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.dotnet:$PATH"
export MSBUILD_SINGLENODE=1

PROJECT="$(dirname "$0")/NAPS2.App.WinForms"
OUTPUT="$(dirname "$0")/publish/win-x64"

echo "=== Restoring ==="
dotnet restore "$PROJECT" -r win-x64

echo ""
echo "=== Publishing for Windows (win-x64) ==="
dotnet publish "$PROJECT" -c Release -r win-x64 --self-contained true \
  -p:PublishSingleFile=true -o "$OUTPUT"

echo ""
echo "=== Done ==="
echo "Windows executable at: $OUTPUT/NAPS2.exe"
