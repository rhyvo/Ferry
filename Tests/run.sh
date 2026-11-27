#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
files=()
for f in Sources/ModModels.swift Sources/ModLayout.swift Sources/ModFiles.swift Sources/ModSearch.swift Sources/InstalledPrograms.swift Sources/TaskList.swift Sources/ProgramChoice.swift Sources/Letterbox.swift Sources/Naming.swift Sources/AssistantText.swift Sources/AssistantSetup.swift Sources/AssistantPermissions.swift Sources/AssistantPrompts.swift Sources/AssistantChanges.swift Sources/AssistantCardRows.swift Sources/AssistantLookup.swift Sources/AssistantEdits.swift Sources/AssistantRuns.swift Sources/AssistantWire.swift Sources/AssistantServer.swift Sources/ChatWire.swift Sources/ChatLoop.swift Sources/AssistantFacts.swift Sources/AssistantModels.swift Sources/Keychain.swift Sources/MCPProtocol.swift Sources/MCPClientWire.swift Sources/Models.swift Sources/Support.swift Sources/SettingsCatalog.swift Sources/TroubleshootFixes.swift Sources/KnowledgePack.swift Sources/KnowledgeManifest.swift Sources/AppleChatLogic.swift Sources/ChatMarkdown.swift; do
  [ -f "$f" ] && files+=("$f")
done
mkdir -p build
xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 -o build/ferry-tests ${files[@]+"${files[@]}"} Tests/*.swift
FERRY_REPO="$PWD" build/ferry-tests
