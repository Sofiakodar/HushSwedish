# HushSwedish — major changes from HushScribe

This document summarizes what **HushSwedish** changes compared to the upstream [HushScribe](https://github.com/drcursor/HushScribe) app ([hushscribe.app](https://hushscribe.app/)). HushSwedish is an independent fork focused on **reliable Swedish (and English) transcription**, while keeping HushScribe’s local-first design: menu bar capture, on-device models, Markdown vault output, no cloud APIs.

Upstream behavior still applies unless listed here. For session-language design details, see [plan-recording-language-sv-en.md](plan-recording-language-sv-en.md).

---

## Identity and installation

| Topic | HushScribe | HushSwedish |
|--------|------------|-------------|
| App name | HushScribe | **HushSwedish** |
| Bundle ID | `com.drcursor.hushscribe` | **`com.hushswedish.app`** |
| Default vault folders | HushScribe paths in Settings | **`~/Documents/HushSwedish/Meetings`** and **`~/Documents/HushSwedish/Voice`** |
| UserDefaults / permissions | Separate from fork | **Separate** — safe to install alongside official HushScribe |
| ASR model cache (Whisper, Parakeet, MLX) | System cache paths | **Same caches** — no second download if you already use HushScribe |
| Distribution | Homebrew cask, signed DMG | **Build from source** in this repo (`scripts/release.sh test`) |

---

## Transcription defaults and models

### Whisper Large v3 is the default for new installs

- **Upstream:** Parakeet-TDT v3 is the typical default for new users.
- **HushSwedish:** **Whisper Large v3** is `TranscriptionModel.defaultSelection` in Settings → Models.
- Rationale: stronger Swedish when combined with explicit session language (below). Users can still switch to Parakeet or Whisper Base.

### Download before first recording

- **Upstream:** Parakeet could block recording even when another model was selected; Whisper could start downloading mid-session.
- **HushSwedish:** **Call Capture**, **Voice Memo**, and **Transcribe File** stay disabled until the **selected** model is on disk. The main popover explains recommendations: **Whisper Large v3** (Swedish + English), **Parakeet** (English-only meetings). **Apple Speech** was removed (unreliable with the VAD + chunk pipeline).

### Model warm-up, idle offload, and memory pressure

**Problem:** Whisper Large v3 in RAM is large (~1–3 GB). Loading on every “Record” felt slow; keeping models loaded all day wasted memory for a menu-bar app.

**HushSwedish:**

1. **Warm-up** — When you open the menu bar popover (or the detached main window), the app preloads **VAD + the selected ASR model** if files are already cached (WhisperKit or Parakeet). Same warm-up runs again during the pre-record **“Transcribing…”** step if needed.
2. **Pre-record countdown** — **3 → 2 → 1 → “Transcribing…”** before capture starts, so the session timer and mic align with a ready engine and you know when to start speaking.
3. **Idle offload** — When the popover/window **closes** and you are not recording or downloading, a timer starts (**Settings → Recording → Memory**): **30 minutes**, **1 hour** (default), or **2 hours**. When it fires, in-memory ASR + VAD are released; **disk cache is unchanged** (no re-download).
4. **Memory pressure** — macOS **warning/critical** memory pressure unloads models early (unless a session or download is active), even if the idle timer has not fired.
5. **Next meeting** — Open the menu again; warm-up reloads from cache in a few seconds, then countdown → record. You do **not** need to quit HushSwedish between morning and afternoon meetings.

Offload does **not** run while the UI is visible, while recording, or while a model download is in progress.

---

## Session language (Swedish / English)

**Goal:** Swedish speech should be transcribed as Swedish, not treated as English.

- Before **Call Capture** or **Voice Memo**, the control bar has a **language picker (SV / EN)**.
- The choice is **remembered** for the next session (`lastSessionTranscriptionLanguage` in preferences).
- **WhisperKit:** decoding uses explicit language codes (`sv` / `en`) — **transcribe**, not translate.
- **Parakeet:** still auto-detects; the picker applies primarily to Whisper (UI explains this).
- Saved transcripts include YAML frontmatter: **`transcription_language: "sv"`** or **`"en"`**.

Default session language for new installs: **Swedish**.

---

## Naming transcript files

- Optional **Name** field in the record step (menu popover), above the language picker.
- Filenames use ISO-style dates and a slug from your title:
  - With name: **`2026-10-21_Meeting_about_release.md`**
  - Without name: **`2026-10-21_14-30-45_Call_Recording.md`** (date + time avoids same-day collisions)
- Spaces become underscores; unsafe path characters are stripped.
- The markdown heading uses your name when provided.
- The draft name is **remembered** between popover opens until you change it.

---

## Pause and stop — finish the last sentence

**User expectation:** pausing or stopping should not drop words you just said.

- **Pause:** stops new audio, shows **“Finishing current speech…”**, then **flushes buffered speech** through the ASR (mic and system audio on call capture) before entering the paused state.
- **Stop:** if the session was not already paused, the same **flush** runs **before** capture is torn down.
- In-flight ASR work is **serialized** so flush and live transcription do not fight each other.
- Very short tails (< ~0.25 s of audio) may still be skipped; gray **partial** text that never reached the model is not promoted to a final line.

---

## Recording UX and permissions

### Voice memo without screen-recording permission

- **Call capture** still needs **Screen & system audio recording** (for “Them”).
- **Voice memo** starts **mic-only** and does **not** start system-audio capture, so it should not trigger screen-capture permission for memo-only use.

### Local dev builds and screen recording

- Unsigned or frequently rebuilt `dist/HushSwedish.app` copies can make macOS show the screen-recording dialog every session even when Settings shows an old toggle.
- **`release.sh test`** now **ad-hoc signs** when no Developer ID is available, and the app **preflights** screen capture before ScreenCaptureKit to reduce repeated system prompts.
- After a rebuild, you may need to **remove and re-enable** HushSwedish under **Privacy → Screen & System Audio Recording**.

---

## Summary model download

**Upstream:** Settings → Models → AI Summaries downloads a model by loading it into MLX immediately. MLX calls `exit` when `mlx.metallib` is missing, so the app closes with no crash report once the download finishes. The “downloaded” check also looks in `~/Library/Caches/models/`, while swift-transformers writes the files under `~/Documents/huggingface/models/`.

**HushSwedish:**

- **Download fetches the weight files only.** The model is loaded later, when you generate a summary.
- If the download fails (network, or a gated Gemma repo), the error is shown on that model row instead of quitting the app.
- “Downloaded” and **Show Models in Finder** use **`~/Documents/huggingface/models/`**, the folder the downloader actually uses. That cache is still shared with HushScribe.
- **`scripts/release.sh`** compiles **`mlx.metallib`** and places it next to the binary. The script fails if the Metal compiler is missing, instead of shipping an app that quits on the first summary load. On Xcode 26, install the compiler with `xcodebuild -downloadComponent MetalToolchain`.

---

## Transcript Viewer

- **Duplicate entries fix:** if Meetings and Voice vault paths point at the **same folder**, the browse sidebar no longer lists every file twice (dedupe by path; skip double scan when paths are equal).

---

## Branding and docs

- UI wordmark, notifications, temp files, and logger subsystem use **HushSwedish** / `hushswedish` tokens.
- README and static docs site updated for the fork; upstream **CNAME** for hushscribe.app removed from this repo.
- GitHub: [Sofiakodar/HushSwedish](https://github.com/Sofiakodar/HushSwedish).

---

## Unchanged from HushScribe (still worth knowing)

These are **not** fork-specific changes; they remain as in upstream unless you change settings:

- On-device **AI summary models** (Apple NL, Qwen3, Gemma 3, Gemma 4). Download behavior differs; see above.
- **Auto-record meetings** for native meeting apps (not browser tabs).
- **Speaker diarization** after the session.
- **Transcribe file** import pipeline.
- **Silence auto-stop**, privacy mode (hidden from screen share by default).
- Plain **Markdown + YAML** vault output for Obsidian and similar tools.

---

## Not done yet (ideas / backlog)

- **KB-Whisper** or other Swedish-specialized Whisper checkpoints (see language plan doc).
- Larger **Qwen** (or other MLX) summary models — optional, not required for transcription.
- Homebrew cask / notarized DMG for HushSwedish (requires your Apple Developer ID in `scripts/release.sh`).
- New marketing screenshots in `assets/` (optional).

---

## Commit trail (fork-only work on `main`)

Rough order of fork-specific commits:

1. Allow recording without Parakeet when another ASR model is selected  
2. Session language SV/EN for Whisper  
3. Rebrand to HushSwedish (bundle ID, vault paths)  
4. README and UI branding  
5. Default new installs to Whisper Large v3  
6. Optional transcript names; Transcript Viewer dedupe  
7. Screen capture permission handling for local builds  
8. Flush in-flight speech on pause/stop  
9. Summary model download no longer quits the app  
10. Warm-load on popover open, pre-record countdown, require ASR download before record  
11. Remove Apple Speech; idle model offload + memory-pressure handling  

For exact diffs, use `git log` on this repository from the first fork commit through `HEAD`.
