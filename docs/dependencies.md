# Dependencies (HushSwedish)

All third-party **code** for the macOS app comes from **Swift Package Manager** under `HushSwedish/`. There is no npm, CocoaPods, or bundled Python runtime in the shipped app.

**Source of truth for exact versions:** [`HushSwedish/Package.swift`](../HushSwedish/Package.swift) (direct deps) and [`HushSwedish/Package.resolved`](../HushSwedish/Package.resolved) (full lockfile, including transitive packages). Update this doc when you change pins.

---

## Direct packages (used by the app)

| Package | Purpose |
|---------|---------|
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | Parakeet ASR, Silero VAD, offline speaker diarization |
| [WhisperKit](https://github.com/argmaxinc/WhisperKit) | Whisper Base / Large v3 (Core ML) |
| [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | On-device summary LLMs (Qwen, Gemma) via MLX |
| [swift-transformers](https://github.com/huggingface/swift-transformers) | Hugging Face **Hub** + **Tokenizers** (model download / load) |

FluidAudio and mlx-swift-lm are pinned to **git revisions** in `Package.swift`. WhisperKit and swift-transformers use **minimum versions**; resolved versions live in `Package.resolved`.

---

## Transitive packages (from `Package.resolved`)

Pulled in by the packages above, not declared directly:

| Package | Resolved |
|---------|----------|
| mlx-swift | 0.31.3 |
| swift-crypto | 4.3.1 |
| swift-asn1 | 1.6.0 |
| swift-collections | 1.4.1 |
| swift-jinja | 2.3.5 |
| swift-numerics | 1.1.1 |
| swift-argument-parser | 1.7.1 |
| swift-syntax | 603.0.1 |
| yyjson | 0.12.0 |

---

## Not in SPM (still part of the product)

| Item | Notes |
|------|--------|
| **Apple frameworks** | AVFoundation, Core Audio, ScreenCaptureKit, SwiftUI, etc. |
| **ML model weights** | Downloaded when you choose models in Settings (Hugging Face and vendor caches). Not versioned in `Package.resolved`. |
| **Xcode + Metal toolchain** | Build-time only (`scripts/release.sh` compiles MLX `metallib`). |

Settings credits [pyannote.audio](https://github.com/pyannote/pyannote-audio) for the diarization model lineage; runtime diarization goes through **FluidAudio**, not a Python install.

---

## Security notes

- HushSwedish is a **local desktop app**: no app backend, no meeting upload path in our Swift sources. Network use is mainly **optional model downloads** inside dependencies.
- **CVE coverage for Swift SPM is incomplete.** Pin updates + smoke tests (record, transcribe, summarize) are the practical check.
- Optional local scan: [OSV-Scanner](https://google.github.io/osv-scanner/) against the repo (treat as a hint, not proof).

**GitHub Dependabot** (security + version update PRs) is **free** on free GitHub accounts for public and private repos. Paid **GitHub Advanced Security** is a separate product (org-focused secret scanning, etc.); you do not need it just to enable Dependabot alerts. Swift support in Dependabot exists but can be spotty—still worth enabling under **Settings → Security → Code security**.

---

## Bumping dependencies

1. Edit `HushSwedish/Package.swift` or run `swift package update` in `HushSwedish/`.
2. Commit the updated `Package.resolved`.
3. Rebuild: `scripts/release.sh test` (or `cd HushSwedish && swift build -c release`).
4. Smoke-test: model download (if needed), Call Capture or Voice Memo, optional AI summary.

See also [ARCHITECTURE.md](../ARCHITECTURE.md) and [local-privacy-audit.md](local-privacy-audit.md).
