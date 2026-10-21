# Plan: Session language (Swedish / English) when starting a recording

**Status:** Implemented (Unreleased)  
**Goal:** Before each recording, choose **Swedish** or **English** and pass that choice into Whisper Large v3 as an **explicit** Whisper language code (`sv` / `en`), **not** auto-detect. Supports alternating EN/SV meetings in one day without changing Settings.

**Related context:** Today WhisperKit is called with no `DecodingOptions`, so Whisper defaults to English prefill and Swedish speech often appears as English text. See `WhisperKitBackend.swift` and the earlier architecture review.

---

## User experience

### When idle (not recording)

Add a compact **language control** near the record actions (recommended: in `ControlBar`, above or between “Call Capture” and “Voice Memo”):

| Control | Behavior |
|--------|----------|
| **Segmented picker** | `Swedish` \| `English` |
| **Default** | Remember **last choice** for the next session (persist in `UserDefaults`) |
| **Visibility** | Always visible when idle; hidden or read-only while recording (language is fixed for the session) |

While recording, show the chosen language in the stop bar subtitle, e.g. `Call Capture · Teams · Swedish`.

### Start paths (all must use the same session language)

| Entry point | File / mechanism |
|-------------|------------------|
| Call Capture button / ⌘R | `ContentView.startSession(type: .callCapture)` |
| Voice Memo button / ⌘⇧R | `ContentView.startSession(type: .voiceMemo)` |
| Menu bar | `StatusBarController` → `hushscribeStartCallCapture` / `hushscribeStartVoiceMemo` |
| Auto meeting detect | `MeetingMonitor` → `hushscribeStartCallCapture` |
| File import (optional phase) | `startFileSession(url:)` — same picker value if import is in scope |

**Design choice:** Auto-start and keyboard shortcuts use the **currently selected** segmented value (no extra dialog). User sets Swedish vs English once per meeting before pressing record (or leaves the segment on the last meeting’s language).

### Out of scope for v1 (can note in UI)

- Auto-detect language
- More than SV/EN in the start picker (Settings can grow later)
- Changing language **mid-recording** (requires stop + new session)

---

## Data model

### New type (suggested location: `AppSettings.swift` or `Models.swift`)

```swift
enum SessionTranscriptionLanguage: String, CaseIterable, Codable {
    case swedish = "sv"
    case english = "en"

    var displayName: String { ... }  // "Swedish" / "English"
    var localeIdentifier: String { ... }  // "sv-SE" / "en-US" for Apple Speech
}
```

### Persistence

| Key | Purpose |
|-----|---------|
| `lastSessionTranscriptionLanguage` | Raw value `sv` / `en`; default **`sv`** or **`en`** (product decision; **`en`** matches current `transcriptionLocale` default) |

Store on:

- Picker change (immediate), and/or
- Successful session start (redundant but safe)

### Relationship to existing `transcriptionLocale`

| Setting | Role after this feature |
|---------|-------------------------|
| `transcriptionLocale` | Deprecate for live recording **or** keep only as fallback for Apple Speech until picker exists everywhere. **Recommendation:** Session picker is **source of truth** at record start; map to `Locale(identifier:)` for Apple Speech and to Whisper `language` for WhisperKit. |
| Settings → Transcription | Optional later: “Default language for new sessions” bound to the same enum. **v1:** picker on main window only + `lastSessionTranscriptionLanguage`. |

---

## Engine and backend changes

### 1. Thread language through `TranscriptionEngine.start`

**Today:** `start(locale: Locale, ...)` receives `settings.locale` (`en-US` default) but **WhisperKit ignores it**.

**Change:**

```swift
func start(
    sessionLanguage: SessionTranscriptionLanguage,
    inputDeviceID: AudioDeviceID = 0,
    appBundleID: String? = nil,
    sysVadThreshold: Double = 0.92
) async
```

- **Apple Speech:** `SFSpeechBackend(locale: Locale(identifier: sessionLanguage.localeIdentifier))`
- **WhisperKit:** pass `sessionLanguage.whisperCode` (`sv` / `en`) into `WhisperKitASRBackend`
- **Parakeet (FluidAudio):** no API change required for v1; language picker still shown for consistency, but Parakeet remains auto-detect internally (document in UI tooltip: “Language selection applies to Whisper models”)

Apply the same parameter to `startFileTranscription(url:sessionLanguage:)` if file import is included in v1.

### 2. `WhisperKitASRBackend`

**File:** `HushScribe/Sources/HushScribe/Transcription/WhisperKitBackend.swift`

- Add `private let languageCode: String` (or `SessionTranscriptionLanguage`) on init.
- On each `transcribe` call:

```swift
let options = DecodingOptions(
    task: .transcribe,
    language: languageCode,
    detectLanguage: false,
    withoutTimestamps: true  // optional; good for short VAD segments — validate quality
)
let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
```

**Important:** `detectLanguage: false` and explicit `language` avoid English prefill when `language` is nil (WhisperKit default).

### 3. Backend lifecycle when language changes

`whisperKitBackend` is cached on `TranscriptionEngine`. If the user records in Swedish, stops, switches picker to English, and starts again:

- **Option A (simple):** Include `languageCode` in backend identity; recreate `WhisperKitASRBackend` when code differs (model weights unchanged; only decode options differ — can also store language on backend and pass per call without recreating `WhisperKit`).
- **Recommended:** Store language on `WhisperKitASRBackend` and pass options per `transcribe` call; no need to reload CoreML model.

Recreate `SFSpeechBackend` when session language changes (new `SFSpeechRecognizer` locale).

### 4. `ContentView.startSession`

Replace:

```swift
await transcriptionEngine.start(locale: settings.locale, ...)
```

with:

```swift
await transcriptionEngine.start(sessionLanguage: selectedSessionLanguage, ...)
```

`selectedSessionLanguage` comes from `@State` bound to the segmented control, initialized from `UserDefaults` on appear.

---

## UI implementation sketch

### `ControlBar.swift`

New parameters:

- `sessionLanguage: Binding<SessionTranscriptionLanguage>` (or `SessionTranscriptionLanguage` + callback)
- Optional: `showLanguagePicker: Bool` (true when `!isRecording`)

Layout (480pt-wide window):

```
┌─────────────────────────────────────┐
│  Language:  [ Swedish | English ]   │  ← new row when idle
│  [ Call Capture ]  [ Voice Memo ]   │
└─────────────────────────────────────┘
```

Use `Picker` with `.segmented` style for macOS.

### `ContentView.swift`

- `@State private var sessionLanguage: SessionTranscriptionLanguage` loaded from `UserDefaults` in `.onAppear` or `@AppStorage`.
- Pass binding into `ControlBar`.
- Persist on change with `.onChange(of: sessionLanguage)`.

### Recording indicator

Extend `ControlBar.activeSessionLabel` or stop-button subtitle with `· Swedish` / `· English`.

---

## Transcript metadata (recommended)

When starting a session, record the language in the markdown frontmatter or session context so Obsidian notes reflect which mode was used.

**File:** `TranscriptLogger.startSession` — add optional `transcriptionLanguage: String?` and write e.g. `transcription_language: sv` in YAML (name to match existing frontmatter conventions in that file).

---

## Files to touch (checklist)

| File | Changes |
|------|---------|
| `Settings/AppSettings.swift` | Add `SessionTranscriptionLanguage`, optional helper for `UserDefaults` |
| `Views/ControlBar.swift` | Segmented picker when idle; label while recording |
| `Views/ContentView.swift` | State, persistence, pass language into `start` / `startFileTranscription` |
| `Transcription/WhisperKitBackend.swift` | `DecodingOptions` + stored language |
| `Transcription/TranscriptionEngine.swift` | Replace/locale parameter; wire Whisper + Apple Speech; file path |
| `Storage/TranscriptLogger.swift` | Optional frontmatter field |
| `CHANGELOG.md` | User-facing note when implemented |

**No change required for v1:** `SettingsView` model list (still pick Whisper Large v3 there; language per session on main window).

---

## Implementation phases

### Phase 1 — Core fix (Whisper + wiring)

1. Add `SessionTranscriptionLanguage` + persistence key.
2. Update `WhisperKitASRBackend` with explicit `DecodingOptions`.
3. Update `TranscriptionEngine.start` / `startFileTranscription` to accept session language.
4. Update `ContentView` to pass selected language (temporary: hardcode from `@AppStorage` without UI).

**Verify:** Whisper Large v3 + Swedish picker → Swedish transcript; English picker → English transcript.

### Phase 2 — UI

1. Segmented control in `ControlBar`.
2. Session subtitle while recording.
3. Tooltip when Parakeet is active: language applies to Whisper / Apple Speech.

### Phase 3 — Polish

1. Frontmatter `transcription_language`.
2. File import uses same picker.
3. Optional Settings default: “Default session language” syncing with `lastSessionTranscriptionLanguage`.

---

## Test plan

| # | Scenario | Expected |
|---|----------|----------|
| 1 | Model = Whisper Large v3, picker = Swedish, speak Swedish | Swedish text, not English |
| 2 | Same, speak English | Poor/WER expected (forced `sv`); user should pick English |
| 3 | Picker = English, speak English | English transcript |
| 4 | SV session → stop → EN session → stop | Each session correct; no bleed from cached backend |
| 5 | Apple Speech + Swedish picker | Recognizer uses `sv-SE` |
| 6 | Parakeet + Swedish picker | Still works; auto-detect (no regression) |
| 7 | Auto meeting detect | Uses current picker value |
| 8 | ⌘R / menu bar start | Same as button |
| 9 | Whisper model not downloaded | Existing download flow; language applied after load |

Manual debug (optional): enable WhisperKit debug logging and confirm prefill tokens include `<|sv|>` / `<|en|>` and `<|transcribe|>`.

---

## Risks and mitigations

| Risk | Mitigation |
|------|------------|
| Short VAD chunks (~6s) + fixed language | Accept for v1; tune `withoutTimestamps` / segment length if quality suffers |
| User forgets to switch picker | Persist last choice; visible segment; recording label shows language |
| `modelsReady` only tracks Parakeet | Whisper row uses `engine.isModelDownloaded`; confirm Call Capture isn’t blocked when Whisper selected but Parakeet not downloaded (pre-existing quirk — verify during QA) |
| Forced wrong language | User education in one-line hint under picker |

---

## Future (not in this plan)

- KB-Whisper Large as separate model (still use `language: "sv"`).
- Auto-detect third option in Settings for power users.
- Per-session language in auto-record confirmation dialog.

---

## Branch workflow

1. Create feature branch from `main`.
2. Implement Phase 1 → Phase 2.
3. Manual test matrix above.
4. Update `CHANGELOG.md` under Unreleased.
