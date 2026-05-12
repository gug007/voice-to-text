#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

swiftc -parse-as-library \
  VoiceToText/VoiceToText/Hotkey/HotkeyActionPolicy.swift \
  Tests/HotkeyBehaviorHarness.swift \
  -o /tmp/voice-to-text-hotkey-behavior-harness
/tmp/voice-to-text-hotkey-behavior-harness

swiftc -parse-as-library \
  VoiceToText/VoiceToText/Dictation/RecordingStartGate.swift \
  Tests/RecordingStartGateHarness.swift \
  -o /tmp/voice-to-text-recording-start-gate-harness
/tmp/voice-to-text-recording-start-gate-harness

swiftc -parse-as-library \
  VoiceToText/VoiceToText/Hotkey/HotkeyActionPolicy.swift \
  VoiceToText/VoiceToText/Hotkey/HotkeyBinding.swift \
  Tests/HotkeyStoreHarness.swift \
  -o /tmp/voice-to-text-hotkey-store-harness
/tmp/voice-to-text-hotkey-store-harness
