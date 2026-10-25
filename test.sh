#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
bash ./build-java.sh
mkdir -p build/test-classes
javac -encoding UTF-8 -cp build/classes -d build/test-classes ConverterTest.java
java -Djava.awt.headless=true -Xmx512m -cp build/classes:build/test-classes ConverterTest
