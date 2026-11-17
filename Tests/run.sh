#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
files=()
for f in Sources/ModModels.swift Sources/ModLayout.swift Sources/ModFiles.swift Sources/ModSearch.swift Sources/InstalledPrograms.swift Sources/TaskList.swift Sources/ProgramChoice.swift Sources/Letterbox.swift; do
  [ -f "$f" ] && files+=("$f")
done
mkdir -p build
xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 -o build/ferry-tests ${files[@]+"${files[@]}"} Tests/*.swift
FERRY_REPO="$PWD" build/ferry-tests
