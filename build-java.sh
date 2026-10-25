#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/classes dist
javac_flags=(-encoding UTF-8)
if javac -version 2>&1 | head -n 1 | grep -q 'javac 1\.8\.'; then
  javac_flags+=(-source 8 -target 8)
else
  javac_flags+=(--release 8)
fi
javac "${javac_flags[@]}" -d build/classes NcmConvert.java NcmWindow.java
jar cfe dist/ncm-converter.jar NcmConvert -C build/classes .
