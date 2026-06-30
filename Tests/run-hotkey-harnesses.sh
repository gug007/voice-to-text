#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/voice-to-text-hotkey-harnesses.XXXXXX")"
trap 'rm -rf "$TMPDIR"' EXIT

swiftc -parse-as-library \
  VoiceToText/VoiceToText/Hotkey/HotkeyActionPolicy.swift \
  Tests/HotkeyBehaviorHarness.swift \
  -o "$TMPDIR/hotkey-behavior-harness"
"$TMPDIR/hotkey-behavior-harness"

swiftc -parse-as-library \
  VoiceToText/VoiceToText/Dictation/RecordingStartGate.swift \
  Tests/RecordingStartGateHarness.swift \
  -o "$TMPDIR/recording-start-gate-harness"
"$TMPDIR/recording-start-gate-harness"

swiftc -parse-as-library \
  VoiceToText/VoiceToText/Hotkey/RecordingEscapePolicy.swift \
  Tests/RecordingEscapePolicyHarness.swift \
  -o "$TMPDIR/recording-escape-policy-harness"
"$TMPDIR/recording-escape-policy-harness"

swiftc -parse-as-library \
  VoiceToText/VoiceToText/Hotkey/HotkeyActionPolicy.swift \
  VoiceToText/VoiceToText/Hotkey/HotkeyBinding.swift \
  Tests/HotkeyBindingHarness.swift \
  -o "$TMPDIR/hotkey-binding-harness"
"$TMPDIR/hotkey-binding-harness"

swiftc -parse-as-library \
  VoiceToText/VoiceToText/Hotkey/StandaloneModifierHotkeyState.swift \
  Tests/StandaloneModifierHotkeyHarness.swift \
  -o "$TMPDIR/standalone-modifier-hotkey-harness"
"$TMPDIR/standalone-modifier-hotkey-harness"

swiftc -parse-as-library \
  VoiceToText/VoiceToText/Hotkey/HotkeyActionPolicy.swift \
  VoiceToText/VoiceToText/Hotkey/StandaloneModifierEventCoordinator.swift \
  Tests/StandaloneModifierEventCoordinatorHarness.swift \
  -o "$TMPDIR/standalone-modifier-event-coordinator-harness"
"$TMPDIR/standalone-modifier-event-coordinator-harness"

swiftc -parse-as-library \
  VoiceToText/VoiceToText/Hotkey/HotkeyActionPolicy.swift \
  VoiceToText/VoiceToText/Hotkey/HotkeyBinding.swift \
  VoiceToText/VoiceToText/Hotkey/HotkeyCaptureSession.swift \
  Tests/HotkeyCaptureHarness.swift \
  -o "$TMPDIR/hotkey-capture-harness"
"$TMPDIR/hotkey-capture-harness"

swiftc -parse-as-library \
  VoiceToText/VoiceToText/Hotkey/HotkeyActionPolicy.swift \
  VoiceToText/VoiceToText/Hotkey/HotkeyBinding.swift \
  Tests/HotkeyStoreHarness.swift \
  -o "$TMPDIR/hotkey-store-harness"
"$TMPDIR/hotkey-store-harness"

swiftc -parse-as-library \
  VoiceToText/VoiceToText/Support/LaunchContext.swift \
  Tests/LaunchContextHarness.swift \
  -o "$TMPDIR/launch-context-harness"
"$TMPDIR/launch-context-harness"

swiftc -parse-as-library \
  VoiceToText/VoiceToText/Support/OpenAIAPIKey.swift \
  VoiceToText/VoiceToText/Actions/DictationAction.swift \
  VoiceToText/VoiceToText/Actions/ActionRunner.swift \
  Tests/ActionRunnerHarness.swift \
  -o "$TMPDIR/action-runner-harness"
"$TMPDIR/action-runner-harness"

swiftc -parse-as-library \
  VoiceToText/VoiceToText/History/RecordingHistoryEntry.swift \
  VoiceToText/VoiceToText/Meetings/MeetingTranscriptJoiner.swift \
  Tests/RecordingHistoryHarness.swift \
  -o "$TMPDIR/recording-history-harness"
"$TMPDIR/recording-history-harness"

swiftc -parse-as-library \
  VoiceToText/VoiceToText/Audio/WAVEncoder.swift \
  VoiceToText/VoiceToText/Audio/StreamingWAVWriter.swift \
  Tests/StreamingWAVWriterHarness.swift \
  -o "$TMPDIR/streaming-wav-writer-harness"
"$TMPDIR/streaming-wav-writer-harness"

swiftc -parse-as-library \
  VoiceToText/VoiceToText/Audio/WAVEncoder.swift \
  VoiceToText/VoiceToText/Audio/StreamingWAVWriter.swift \
  VoiceToText/VoiceToText/Support/AppConstants.swift \
  VoiceToText/VoiceToText/Audio/AudioFileExtractor.swift \
  Tests/AudioFileExtractorHarness.swift \
  -o "$TMPDIR/audio-file-extractor-harness"
"$TMPDIR/audio-file-extractor-harness"
