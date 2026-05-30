#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.dotnet:$PATH"
export MSBUILD_SINGLENODE=1
exec dotnet run --project "$(dirname "$0")/NAPS2.App.Gtk" -c Debug --no-build "$@"
