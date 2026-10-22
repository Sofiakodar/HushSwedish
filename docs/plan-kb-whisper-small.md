# Plan: KB-Whisper Small in HushSwedish

Status: **considering** — not implemented. This doc captures integration steps, hosting, and product tradeoffs.

## Why consider it

- **Source:** [KBLab/kb-whisper-small](https://huggingface.co/KBLab/kb-whisper-small) — Swedish Whisper fine-tunes from the National Library of Sweden (~563 MB PyTorch weights).
- **Compute:** Smaller than **Whisper Large v3** (~1.5 GB WhisperKit download today): less disk, lower RAM when loaded, faster inference on Apple Silicon.
- **Quality (Swedish):** KBLab reports **lower WER than `openai/whisper-large-v3`** on Swedish benchmarks (FLEURS, Common Voice, NST). Validate on your own meetings before changing defaults.
- **English sessions:** Model is **Swedish-centric**. Keep Whisper Large (or Parakeet) for EN-heavy meetings, or show a clear UI warning when EN is selected with KB-Whisper Small.

HushSwedish today loads **WhisperKit Core ML** bundles from **`argmaxinc/whisperkit-coreml`**. KBLab does **not** ship that format — only Hugging Face PyTorch, GGML, ONNX, CTranslate2, etc. So integration requires **conversion once** and **hosting the converted files** (typically on Hugging Face), not shipping raw `model.safetensors` in the app.

---

## Conversion + hosting (summary)

| Step | What |
|------|------|
| Source | `KBLab/kb-whisper-small` (pin a **revision**; KBLab offers default / `subtitle` / `strict` styles) |
| Convert | [WhisperKitTools](https://github.com/argmaxinc/whisperkittools): `whisperkit-generate-model --model-version KBLab/kb-whisper-small --output-dir <out>` on a Mac with Python + compatible deps |
| Host | Upload output folder tree to **your** Hugging Face model repo (stable subfolder name, e.g. `kb-whisper-small`) |
| App (later) | `WhisperKitConfig(model: "<folder>", modelRepo: "<your-org>/<your-repo>")`; extend `TranscriptionModel`, download gate, cache paths, Settings copy |

**Community shortcut (spike only):** e.g. [mickekringai/kb-whisper-coreml](https://huggingface.co/mickekringai/kb-whisper-coreml) — verify license, revision, and Swedish QA before relying on it in production. Prefer **your own repo + pinned revision** for a fork you maintain.

---

## Step-by-step integration (when you decide to build)

### 1. Product decisions

- Position **KB-Whisper Small** as **“Swedish (recommended)”** vs Whisper Large as **“SV + EN / multilingual”**.
- Default model for new installs? (Only change after QA.)
- When session language is **EN**, block KB-Whisper Small, auto-switch model, or allow with disclaimer.
- Update README system requirements (smaller RAM/disk option).

### 2. License and attribution

- Read the KBLab model card license (redistribution of **converted** weights).
- Model card on your HF repo: source `KBLab/kb-whisper-small`, conversion tool (WhisperKitTools + versions), HushSwedish usage note.

### 3. Convert to WhisperKit / Core ML

1. Set up Python env per WhisperKitTools README (e.g. Python 3.11, `pip install -e .`).
2. Run generation (example):

   ```bash
   whisperkit-generate-model \
     --model-version KBLab/kb-whisper-small \
     --output-dir ./kb-whisper-small-coreml
   ```

3. Pin KBLab revision if using `from_pretrained(..., revision="strict")` equivalent in tooling.
4. Note on-disk size of the full bundle (MelSpectrogram + AudioEncoder + TextDecoder + JSON/tokenizer) — often **~500 MB–1 GB** depending on fp16 vs quantization.
5. Optional: compressed variant if WhisperKitTools supports it for small (compare WER vs speed).

### 4. Validation (before users see it)

- Swedish clips: compare transcripts vs current **Whisper Large v3 + `language: sv`**.
- English clip: confirm acceptable or document limitation.
- Live session: Call Capture + Voice Memo, warm-up, idle offload, model switch.
- Measure: load time, RAM (Activity Monitor), latency per VAD segment.

### 5. Publish on Hugging Face (your repo)

See **“Hosting on Hugging Face yourself”** below.

### 6. App changes (HushSwedish codebase)

- `TranscriptionModel`: new case, `whisperModelID`, `sizeLabel`, descriptions.
- `TranscriptionEngine`: load with custom `modelRepo`; update `whisperCacheURL` / `isModelDownloaded` / `removeModel` / download UI.
- Settings + popover recommendations (SV → KB-Whisper Small).
- `WhisperKitASRBackend`: keep `language: "sv"` for Swedish sessions (still transcribe, not translate).
- Docs: `README.md`, `changes-from-hushscribe.md`, this plan → mark implemented or archive.

### 7. QA checklist

- [ ] Download only when selected (download gate)
- [ ] No second download if folder already present
- [ ] Remove model from Settings clears correct cache path
- [ ] EN session behavior matches product decision
- [ ] Shared HF cache behavior documented if users also run HushScribe

---

## Hosting on Hugging Face yourself

You do **not** need a paid Hugging Face plan to host public model files for app downloads. You need an account, a model repository, and (for private repos or API uploads) a token.

### 1. Create an account

1. Go to [huggingface.co/join](https://huggingface.co/join).
2. Sign up (email or GitHub/Google). Confirm email if prompted.
3. Optional: create an **Organization** (e.g. `hushswedish` or your username) under **Settings → Organizations** if you want the repo under a project name rather than a personal account.

### 2. Create a model repository

1. [huggingface.co/new](https://huggingface.co/new) → **Model**.
2. Choose owner (user or org), repo name (e.g. `hushswedish-whisperkit`).
3. Visibility: **Public** (simplest for WhisperKit to pull without auth in the app). **Private** is possible but then the app must send a **read token** — avoid for v1 unless you have a strong reason.
4. Add a **Model card** (`README.md` on the repo): what it is, link to KBLab source, conversion date, folder layout, license.

### 3. Upload the converted Core ML bundle

**Layout must match what WhisperKit expects** for the `model` folder name you pass in code (same idea as `openai_whisper-large-v3` under Argmax’s repo).

Options:

- **Web UI:** Model repo → **Files** → Upload folder (drag the converted directory).
- **Git LFS:** Clone the repo with Git; large files use [Git LFS](https://git-lfs.github.com/) (HF enables LFS for models). Good for reproducible uploads from CI.
- **CLI:** Install `huggingface_hub` (`pip install huggingface_hub`), then:

  ```bash
  huggingface-cli login
  huggingface-cli upload <your-org>/hushswedish-whisperkit ./kb-whisper-small-coreml/kb-whisper-small kb-whisper-small
  ```

  Adjust paths to match your local output tree.

### 4. Access token (for uploads and optional private repos)

1. **Settings → Access Tokens** on Hugging Face.
2. Create a token with **Write** (upload) or **Read** (download private models).
3. Use locally: `huggingface-cli login` or `HF_TOKEN` in CI — **never commit tokens** to git.

WhisperKit’s default download for **public** repos typically does not require embedding a token in the shipped app.

### 5. Pin versions

- Upload from a tagged release or note the **commit hash** on HF in your app/docs.
- When KBLab updates weights, re-run conversion, upload a new revision (or new subfolder), and bump what HushSwedish references.

### 6. Costs and limits

- Public model hosting on HF is **free** for normal open-model use within their fair-use/storage policies.
- Bandwidth: downloads count against HF and your users’ networks; first download per machine is one-time (cached under `~/Documents/huggingface/models/` in HushSwedish’s Whisper path today for Argmax — custom repo will use a parallel path once `modelRepo` is set).

### 7. Legal

- KBLab license governs the **weights**; your repo redistributes **converted** weights — confirm that is allowed and credit KBLab on the model card.
- Argmax WhisperKit / WhisperKitTools have their own licenses for tooling.

---

## Size comparison (reference)

| Artifact | Approx. size |
|----------|----------------|
| KBLab `kb-whisper-small` safetensors | ~563 MB |
| HushSwedish Whisper Large v3 (WhisperKit) | ~1.5 GB (UI label) |
| KBLab `kb-whisper-large` safetensors | ~3.2 GB |
| Converted KB-Whisper Small Core ML (typical) | ~0.5–1 GB (measure after conversion) |

RAM while loaded: expect **less than Whisper Large** for small architecture; measure on target Macs.

---

## Open questions (decide before implementation)

1. Default ASR for new installs: stay **Whisper Large v3** or switch to **KB-Whisper Small** for Swedish-first positioning?
2. HF repo name and owner (`Sofiakodar/...` vs org)?
3. KBLab revision: default, `strict`, or `subtitle`?
4. Spike on community Core ML repo first, or convert in-house immediately?
5. English session policy when KB-Whisper Small is selected.

---

## Related docs

- [plan-recording-language-sv-en.md](plan-recording-language-sv-en.md) — SV/EN session language (future note: KB-Whisper Large).
- [changes-from-hushscribe.md](changes-from-hushscribe.md) — backlog mention of KB-Whisper.
