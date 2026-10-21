<p align="center">
  <img src="assets/logo.svg" width="80" alt="HushSwedish logo" />
</p>

<h1 align="center">HushSwedish</h1>

<p align="center">
  <strong>Local-only meeting transcription for macOS — tuned for Swedish and English. <br>No cloud services or API keys. Your data never leaves your computer.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-6.3-F05138?logo=swift&logoColor=white" alt="Swift 6.3" />
  <img src="https://img.shields.io/badge/macOS-26%2B-000000?logo=apple&logoColor=white" alt="macOS 26+" />
  <img src="https://img.shields.io/badge/License-MIT-blue" alt="MIT License" />
  <img src="https://img.shields.io/badge/Apple%20Silicon-Required-333333?logo=apple&logoColor=white" alt="Apple Silicon" />
</p>

---

## About this fork

**HushSwedish** is an independent fork of [HushScribe](https://github.com/drcursor/HushScribe). It is **not** affiliated with or maintained by the HushScribe project ([hushscribe.app](https://hushscribe.app/)).

This repo keeps HushScribe’s local-first architecture (menu bar capture, on-device ASR, Markdown vault output) and adds changes aimed at **reliable Swedish transcription** and **running alongside the official app**:

| | HushScribe | HushSwedish |
|---|---|---|
| Bundle ID | `com.drcursor.hushscribe` | `com.hushswedish.app` |
| Default transcript folders | HushScribe paths in Settings | `~/Documents/HushSwedish/Meetings` and `~/Documents/HushSwedish/Voice` |
| ASR model cache on disk | Shared Hugging Face / FluidAudio paths | **Same caches** — no second Whisper download if you already use HushScribe |

Upstream install (Homebrew / DMG) remains on the [HushScribe repo](https://github.com/drcursor/HushScribe).

## Overview

HushSwedish is a macOS menu bar app that captures meetings and voice memos, transcribes them on-device, and writes structured `.md` files to a folder of your choice (eg. your Obsidian vault).

Every step runs locally. Transcription uses on-device models (Parakeet-TDT v3, WhisperKit, or Apple Speech). AI summaries are generated on-device via Qwen3, Gemma 3, Gemma 4, or Apple's NaturalLanguage framework.

*No audio, no transcripts, and no data of any kind is ever sent to the internet.*

<p align="center">
  <img src="assets/main.png" height="280" alt="HushSwedish — main" style="vertical-align:middle"/>
  <img src="assets/settings.png" height="280" alt="HushSwedish — settings" style="vertical-align:middle" />
</p>

## What’s different from upstream HushScribe

- **Session language (Swedish / English).** Pick **SV** or **EN** in the control bar before you record. WhisperKit uses explicit `sv` / `en` decoding (transcribe, not translate). Apple Speech uses a matching locale. The choice is remembered and stored in transcript frontmatter as `transcription_language`.
- **Whisper Swedish fix.** Whisper backends pass language into `DecodingOptions` so Swedish is not treated as English by default.
- **No Parakeet required.** Recording is gated on the model you select in **Settings → Models**. You can use Whisper Large v3 or Apple Speech without downloading Parakeet; only Parakeet shows the main-window download prompt when it is the active model.
- **Separate app identity.** Own bundle ID, preferences, permissions, and default vault paths — safe to install next to official HushScribe.

## Installing

There is no Homebrew cask for this fork yet. Build from source (Apple Silicon, macOS 26+):

```bash
git clone https://github.com/Sofiakodar/HushSwedish.git
cd HushSwedish
scripts/release.sh test
open dist/HushSwedish.app
```

For a release binary only:

```bash
cd HushScribe
swift build -c release
# executable: HushScribe/.build/release/HushSwedish
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for project layout. Signed DMG/notarization needs your own Apple Developer ID (see `scripts/release.sh`).

**Official HushScribe** (unchanged):

```bash
brew tap drcursor/hushscribe https://github.com/drcursor/HushScribe
brew install --cask hushscribe
```

## Why HushSwedish?

- **Entirely local.** Transcription and AI summary both run on-device. Nothing ever leaves your computer.
- **Swedish-first workflow.** Session language control and Whisper decoding aligned with Swedish (and English) meetings.
- **Your data, your files.** Plain `.md` with YAML frontmatter, timestamps, and speaker labels.
- **No accounts, no subscriptions, no API keys.** Download (or build) and run.

```
speak → capture → md transcription → optional summary → knowledge base
```

## Features

Inherited from HushScribe unless noted above:

- **Multilingual transcription** via Parakeet-TDT v3 ([FluidAudio](https://github.com/FluidInference/FluidAudio)) — 25 European languages, auto-detected, runs on Apple Silicon ANE.
- **Multiple transcription models.** Parakeet-TDT v3, WhisperKit Base, WhisperKit Large v3, or Apple Speech (built-in). All on-device.
- **Auto-record meetings.** Starts when a supported meeting app is running and the mic is in use; configurable stop delay. Browser-based meetings (e.g. Google Meet in a browser) are not detected.
- **Call Capture** — mic + system audio, filtered to the active conferencing app.
- **Voice Memo** — mic-only, separate folder.
- **On-device AI summary** in the Transcript Viewer (Qwen3, Gemma 3, Gemma 4, or Apple NL).
- **Transcript Viewer** — browse by date, export Markdown / SRT / JSON.
- **Transcribe File** — offline pipeline for audio/video files.
- **Speaker diarization** after the session ends.
- **Obsidian-friendly** frontmatter: `type`, `created`, `attendees`, `tags`, `source_app`, `transcription_language`.
- **Silence auto-stop** and **privacy mode** (hidden from screen sharing by default; transcripts only on disk).

## Privacy

- All transcription and summary models run on-device. No audio is sent anywhere.
- No network calls, analytics, or telemetry in the app design.
- No audio saved to disk — text transcripts only.
- Transcripts are plain `.md` in folders you choose.

## Models

### Transcription

| Model | Engine | Size |
|-------|--------|------|
| **[Parakeet-TDT v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2)** | [FluidAudio](https://github.com/FluidInference/FluidAudio) | ~600 MB |
| **[Whisper Base](https://huggingface.co/openai/whisper-base)** | [WhisperKit](https://github.com/argmaxinc/WhisperKit) | ~150 MB |
| **[Whisper Large v3](https://huggingface.co/openai/whisper-large-v3)** | [WhisperKit](https://github.com/argmaxinc/WhisperKit) | ~1.5 GB |
| **[Apple Speech](https://developer.apple.com/documentation/speech)** | macOS built-in | Built-in |

For Swedish meetings, **Whisper Large v3** with session language **SV** is the usual choice after you set it active in **Settings → Models**.

### AI Summary

| Model | Provider | Size |
|-------|----------|------|
| **[Apple NL](https://developer.apple.com/documentation/naturallanguage)** *(default)* | macOS built-in | Built-in |
| **[Qwen3 0.6B](https://huggingface.co/mlx-community/Qwen3-0.6B-4bit)** | [Alibaba Cloud](https://qwenlm.github.io) | ~500 MB |
| **[Gemma 3 1B](https://huggingface.co/mlx-community/gemma-3-1b-it-qat-4bit)** | [Google](https://ai.google.dev/gemma) | ~600 MB |
| **[Gemma 4 E4B](https://huggingface.co/mlx-community/gemma-4-e4b-it-4bit)** | [Google](https://ai.google.dev/gemma) | ~800 MB |

Model weights have their own licenses on Hugging Face and vendor sites; the app downloads them at runtime.

## Known limitations

Same class of issues as upstream HushScribe, plus fork-specific notes:

- **Apple Silicon only** for Parakeet / FluidAudio; **macOS 26+**.
- **Screen Recording** permission may re-prompt monthly (macOS).
- **Diarization** is post-session and imperfect with laptop speakers.
- **Microphone / system audio** can stall; try a fixed input device in Settings → Recording or triple-click the app logo to reset capture.
- **Screenshots:** the window is hidden from screen sharing by default — turn off in Settings → Privacy or `defaults write com.hushswedish.app hideFromScreenShare -bool false`.
- **KB-Whisper** and other Swedish-specialized Whisper variants are not integrated yet (see `docs/plan-recording-language-sv-en.md`).

## Output

```markdown
---
type: meeting
created: "2026-03-23"
time: "10:00"
duration: "18:42"
source_app: "Zoom"
transcription_language: "sv"
attendees: ["You", "Speaker 2"]
tags:
  - log/meeting
  - status/inbox
  - source/hushswedish
---


# Call Recording — 2026-03-23 10:00

## Transcript

**You** (10:00:03)
God morgon. Snabb avstämning kring lanseringen.

**John** (10:00:07)
Vi ligger bra till. QA gav klartecken igår.
```

Voice memos use `type: fleeting` with a single speaker.

<p align="center">
  <img src="assets/transcription.png" width="420" alt="HushSwedish — transcription" />
  <img src="assets/summary.png" width="420" alt="HushSwedish — AI summary" />
</p>

## Permissions

| Permission | When | Why |
|---|---|---|
| **Microphone** | All modes | Captures your voice |
| **Screen Recording** | Call Capture only | System audio from conferencing apps |
| **Speech Recognition** | Apple Speech only | `SFSpeechRecognizer` |

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md).

## Credits

**HushSwedish** is a fork of **[HushScribe](https://github.com/drcursor/HushScribe)**, which is a fork of **[Tome](https://github.com/Gremble-io/Tome)** by [Gremble-io](https://github.com/Gremble-io), which started from **[OpenGranola](https://github.com/yazinsai/OpenGranola)**.

**Models and libraries:**

- [FluidAudio](https://github.com/FluidInference/FluidAudio) — Parakeet-TDT v3 ASR and Silero VAD.
- [WhisperKit](https://github.com/argmaxinc/WhisperKit) — Whisper Base and Large v3 on Apple Silicon.
- [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) and [mlx-swift](https://github.com/ml-explore/mlx-swift) — on-device LLM summaries.
- [Qwen3](https://huggingface.co/Qwen), [Gemma 3 / Gemma 4](https://ai.google.dev/gemma) — summary models.
- [pyannote.audio](https://github.com/pyannote/pyannote-audio) — speaker diarization.

## Changelog

Fork changes are listed under **Unreleased** in [CHANGELOG.md](CHANGELOG.md). Upstream release history follows below that section.

## License

[MIT](LICENSE) — retain the copyright notices in `LICENSE` when you redistribute or publish your own fork.
