#!/usr/bin/env bash
set -euo pipefail

export MSBUILD_SINGLENODE=1
exec dotnet run --project "$(dirname "$0")/NAPS2.App.Mac" -c Debug --no-build "$@"
