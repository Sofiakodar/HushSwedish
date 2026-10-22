# Plan: Colleagues, meeting templates, and transcription glossary

Status: **considering** — not implemented. Companion to post-call **Speaker 2 / 3** naming (already in the app); this plan adds **persistence**, **faster UX**, **scheduled default titles**, and **glossary** in one place.

---

## Goals

1. **Colleagues** — Save people you meet with often; after a call, assign **Speaker 2, 3, …** by tapping names instead of retyping.
2. **Meeting templates** — Rules like “weekdays 09:00 → default title **Standup**” or “Wednesdays 10:00 → **Product meeting**”; pre-fill the popover **Name** field (user can override).
3. **Glossary** — Company/product terms and acronyms so transcripts spell them correctly (post-ASR first; optional Whisper prompt later).
4. **UI** — Manage all of the above in a **separate window** (like **Transcript Viewer**), keeping the menu popover small.

---

## Decisions (locked in for v1)

| Topic | Choice |
|--------|--------|
| **Window title** | **Meetings and speakers** (menu item e.g. “Meetings and speakers…”) |
| **Meeting templates scope** | **Call Capture** and **Transcribe file** only — **not Voice Memo** |
| **Glossary scope** | **Global** one list for the whole app (not per vault folder) |
| **Template time slot** | **5 minutes before** scheduled time through **20 minutes after** (app-wide defaults for v1) |
| **Overlapping rules** | If several match, use the rule whose **scheduled time is closest** to when recording started (see below) |

---

## What the time slot means (meeting templates)

Each rule has a **scheduled time** (e.g. **09:00** on selected weekdays). The default transcript title applies if you start **Call Capture** or **Transcribe file** while “now” falls in a fixed window around that time:

**Match interval:** **`[scheduledTime − 5 min, scheduledTime + 20 min]`** (local timezone, same calendar day).

| Scheduled | Window (inclusive start, exclusive end — see implementation note) |
|-----------|---------------------------------------------------------------------|
| Standup **09:00** | **08:55** … **09:20** |
| Product **Wed 10:00** | **09:55** … **10:20** on Wednesdays |

**Examples (Standup at 09:00):**

- Recording starts **08:55** → **Standup** ✓  
- Recording starts **09:18** → **Standup** ✓  
- Recording starts **09:30** → **not** Standup ✗ (unless another rule matches)

**v1:** **`minutesBefore: 5`** and **`minutesAfter: 20`** are **global defaults** for all templates (not per-meeting sliders yet). Optional later: per-rule overrides in the Meetings tab.

**Implementation note:** Use half-open interval **`[start, end)`** where `start = time − 5 min`, `end = time + 20 min + 1 min` or compare `>= start && < time + 21 min` so **09:20:59** still matches but **09:21:00** does not — align with user expectation “not at 9:30”.

**When to evaluate:** when the **popover opens** (pre-fill name if empty) and again when user starts **Call Capture** or **Transcribe file** (re-apply if still empty and user has not manually edited the name this session). Use the **recording start time** (tap on Call Capture / start of file import) as **`now`** for matching and tie-breaks — not an earlier popover-open time if the user waited before recording. **Voice Memo** skips template logic entirely.

**Overlapping rules:** If more than one template’s slot contains the start time, pick the one whose **scheduled `time` is closest** to the start instant (smallest absolute time delta on that calendar day).

Examples (both rules on the same weekday, slots overlap):

- Start **09:12** — **Standup 09:00** (12 min away) vs **Product 09:15** (3 min away) → **Product meeting**.
- Start **09:06** — Standup (6 min) vs Product (9 min) → **Standup**.

---

## What exists today

| Area | Today |
|------|--------|
| Live call | **You** + **Them** only |
| After Call Capture stop | Offline diarization → **Speaker 2, 3, …** on remote lines; **You** unchanged |
| Naming | **`SpeakerNamingView`** overlay in popover: free-text fields + previews; **no save for next time** |
| Session title | Optional **Name** in popover (`sessionTranscriptNameDraft`); not tied to schedule |
| Meeting apps | **No** title/participant list from Zoom/Teams |
| Glossary | **None** |

Remote speakers are labeled **Speaker 2, 3, …** (not “Speaker 1”). The plan uses **Speaker N** below to mean those diarized labels.

---

## Recommended UX: **Meetings and speakers** window

Mirror **Transcript Viewer** (`SummarizeView.openWindow`): menu item + toolbar button **Meetings and speakers…**.

**Why a separate window**

- Popover is ~480×360; roster + rules + glossary do not fit without clutter.
- Editing lists is a “sit down” task; recording is a “glance” task.
- Same pattern users already learn: popover = record; detached window = library/setup.

**Popover stays**

- Language, optional name (pre-filled from template on **Call Capture / file** only), Call / Voice Memo, waveform, restart capture.
- For meeting sessions only: one line when a rule matched, e.g. “Default title: **Standup**” (clears when user edits name manually).
- After stop: **compact** naming step OR “Open speaker naming…” if overlay is too tight (see Phase 2).

**Window sections (tabs or sidebar)**

| Section | Contents |
|---------|----------|
| **Speakers** | Colleague roster — name, optional aliases, optional note; add / edit / delete / reorder |
| **Meetings** | Scheduled default **transcript titles** (Call Capture + file only) |
| **Glossary** | Global canonical term + optional “often heard as” variants |

Link from **Settings → General** (“Open Meetings and speakers…”) for discoverability; primary entry remains menu bar.

---

## Feature 1: Colleague roster

### User story

After diarization, for each **Speaker 2 / 3 / …** row, show **chips of saved colleagues**. Tap **Erik** → that speaker row gets Erik. Tap again or “Other…” for custom text. Optionally **“Add Erik to colleagues”** when typing a new name.

### Data model (local file)

Store under Application Support, e.g. `~/Library/Application Support/HushSwedish/colleagues.json`:

```json
{
  "people": [
    { "id": "uuid", "displayName": "Erik Andersson", "aliases": ["Erik"], "lastUsed": "2026-10-22" }
  ]
}
```

- **No cloud** by default; fits local-first story.
- Optional later: export/import JSON for backup or Obsidian-adjacent workflows.

### Speaker assignment UX (post-call)

Replace or augment **`SpeakerNamingView`**:

```
Speaker 2   [ excerpt preview… ]
            [ Erik ] [ Maria ] [ Jonas ] [ Custom… ]

Speaker 3   …
```

- **One colleague per speaker row** (diarization already split voices).
- **Same person twice** (diarization error): allow same name on two rows or warn — product choice.
- **Skip** still leaves **Speaker 2** in the file.
- On **Apply**, reuse existing **`applySpeakerRenames`** + **`attendees:`** frontmatter.

### “Quick add who was in the meeting”

Optional summary step after naming:

- “Also mark as attended (for your records)” — checkboxes of **all colleagues** to append to **`attendees:`** even if they didn’t speak (silent participant). **Off by default** to avoid inventing speakers in the transcript body.

### What roster does *not* do (v1)

- **Auto-map** Speaker 2 → Erik by voice across meetings (voice embeddings = later phase).
- Pull names from Zoom/Teams (not available).

---

## Feature 2: Regular meetings (default transcript names)

### User story

When starting **Call Capture** or **Transcribe file**, if “now” matches a rule, pre-fill **Name** with e.g. **Standup**. **Voice Memo** never uses templates. User can edit before record; manual edit should **not** permanently disable rules (only for this session).

### Rule model

```json
{
  "templateMatchingDefaults": {
    "minutesBefore": 5,
    "minutesAfter": 20
  },
  "meetingTemplates": [
    {
      "id": "uuid",
      "title": "Standup",
      "enabled": true,
      "schedule": {
        "kind": "weekly",
        "weekdays": [1, 2, 3, 4, 5],
        "time": "09:00"
      }
    },
    {
      "id": "uuid",
      "title": "Product meeting",
      "enabled": true,
      "schedule": {
        "kind": "weekly",
        "weekdays": [3],
        "time": "10:00"
      }
    }
  ]
}
```

**Matching (defaults)**

- Use **local timezone** (`Calendar.current`).
- “Match” if start time is within **`[time − minutesBefore, time + minutesAfter]`** on a listed weekday (defaults **5** / **20** — see **Decisions** above).
- **`kind: daily`** — same time every day (weekdays optional filter).
- If **multiple rules match**: choose the template whose **scheduled `time` is closest** to the recording start instant (absolute time delta on that calendar day).
- If **no match**: leave name empty (current behavior).
- **Scope:** only **`SessionType.callCapture`** and **file import** — not **voice memo**.

**Not in v1 (optional later)**

- **EventKit** — match calendar event title (permission + ambiguity).
- **Auto-start record** — templates only set **name**, not tied to **`MeetingMonitor`**.

### Integration points

- On popover appear / before **Call Capture** or **file** session: **`MeetingTemplateStore.suggestedTitle(now:)`** → set `sessionTranscriptNameDraft` **only if** user has not typed a custom name this session (track `userEditedSessionName` flag per popover open).
- Filename: existing **`TranscriptFilename.makeFilename`** + **`customTitle`** unchanged.
- **Meetings** tab: list rules, add/edit/delete; show slot as **“−5 / +20 min”** around each time; preview “Next: Wed 09:55–10:20 → Product meeting”.

---

## Feature 3: Glossary (special names / acronyms)

### User story

Company name **HushSwedish**, acronym **SLA**, product **FooBar** always transcribed wrong → user adds entries; transcript text is corrected.

### Data model

**Global** glossary (single app-wide list), e.g. `glossary.json` under Application Support:

```json
{
  "entries": [
    { "canonical": "HushSwedish", "variants": ["hush swedish", "Hush Swedish"] },
    { "canonical": "KTH", "variants": ["k t h", "kth"] }
  ]
}
```

Applies to **all** transcription (Call Capture, Voice Memo, file) — only **meeting title templates** are restricted to meetings/file.

### Pipeline (phased)

| Phase | Behavior |
|-------|----------|
| **Glossary v1** | Apply on **final** utterances (and optionally on flush to disk), before append to `.md` |
| **Glossary v2** | Apply to **live partial** text in UI (can flicker if rules aggressive) |
| **Glossary v3** | Build **WhisperKit `DecodingOptions` prompt** from top N terms + colleague names (Whisper paths only) |

**Meetings and speakers → Glossary** tab: table of canonical + variants; “Test on sample sentence” debug field optional.

**Settings location:** not in popover; only in this window (and one-line link in Settings → General).

---

## Architecture sketch

```
┌─────────────────┐     ┌────────────────────────────┐
│ Menu popover    │     │ Meetings and speakers       │
│ (record)        │     │ Speakers / Meetings / Glossary │
└────────┬────────┘     └──────────┬─────────────────┘
         │                           │
         └───────────┬───────────────┘
                     ▼
         MeetingProfileStore (actor or @Observable)
           - colleagues.json
           - meeting-templates.json
           - glossary.json
                     │
         ┌───────────┼───────────┐
         ▼           ▼           ▼
  ContentView   SpeakerNaming   StreamingTranscriber
  (prefill name) (chip UI)      (GlossaryNormalizer)
```

- **`MeetingProfileStore`**: load/save, publish changes; inject via `AppSettings` or environment like `AppSettings` extension.
- **Window**: `MeetingsAndSpeakersView.openWindow(settings:store:)` parallel to **`SummarizeView.openWindow`**; window title **Meetings and speakers**.

---

## Implementation phases (suggested order)

### Phase 1 — Foundation + glossary (low risk, immediate value)

1. `MeetingProfileStore` + file paths under Application Support.
2. **Meetings and speakers** window shell (tabs: Speakers / Meetings / Glossary — Meetings/Speakers can be stubbed initially).
3. **Glossary** tab + **`GlossaryNormalizer`** on final transcript lines (global list).
4. Menu: **Meetings and speakers…**

**Exit criteria:** User can fix **KTH** / product names in saved transcripts.

### Phase 2 — Colleagues + naming UX

1. Colleagues tab (CRUD).
2. Redesign **`SpeakerNamingView`**: colleague chips + custom field; “Save to colleagues”.
3. Keep overlay in popover **or** move naming to small sheet centered on popover if height is an issue.

**Exit criteria:** Second meeting naming is mostly taps, not typing.

### Phase 3 — Meeting templates

1. Meetings tab + rule editor (weekday picker, time, duration, title).
2. **`suggestedTitle(now:)`** on popover open; respect manual override.
3. Subtle hint in popover when template applied.

**Exit criteria:** Monday 09:00 standup files land as `yyyy-MM-dd_Standup_….md` without typing.

### Phase 4 — Polish (optional)

- Whisper prompt from glossary + colleague first names.
- Import/export JSON.
- “Attended but silent” attendees checkboxes.
- Voice → colleague suggestion (embeddings).

---

## Popover vs Settings vs Workspace

| Surface | Keep |
|---------|------|
| **Menu popover** | Record, language, name (prefilled), models gate, waveform, restart capture |
| **Settings** (system) | Models, Recording, Privacy, Reset — **technical** app config |
| **Meetings and speakers** | Colleague roster, meeting title rules, global glossary |
| **Transcript Viewer** | Browse vault, summarize |

Avoid duplicating glossary/colleagues in Settings tabs; one **“Open Meetings and speakers…”** link is enough.

---

## Risks and mitigations

| Risk | Mitigation |
|------|------------|
| Wrong colleague assigned to wrong **Speaker N** | Previews + confirm; don’t auto-assign from roster |
| Template wrong title | Always editable; show “Using rule: Standup”; easy disable rule |
| Glossary breaks normal words | Whole-word match; case rules; user test field |
| Popover naming too tall with many speakers | Scroll in overlay or defer to Workspace “Finish naming last session” banner |
| Diarization only on **Them** | Document: colleagues = remote speakers; **You** is separate |

---

## Open questions (remaining)

1. **Single JSON file** vs three files (`colleagues.json`, `meeting-templates.json`, `glossary.json`)?
2. After naming, open **Transcript Viewer** automatically? (suggest **no** — stay optional)
3. **File import:** pre-fill title from template at import time only, or also when opening file picker? (suggest: when import **starts**, same as Call Capture)
4. Per-meeting **custom** before/after minutes (override global 5 / 20)? (suggest **later**, not v1)

---

## Docs / README (when shipped)

- README **Day-to-day use**: **Meetings and speakers** for colleagues, standup titles, glossary.
- **`changes-from-hushscribe.md`**: post-call chip naming, scheduled titles, glossary.
- Onboarding: one slide pointing to Workspace (optional).

---

## Related

- Post-call flow: **`SpeakerNamingView`**, **`TranscriptLogger.applySpeakerRenames`**
- Session title: **`sessionTranscriptNameDraft`**, **`TranscriptFilename`**
- Window pattern: **`SummarizeView.openWindow`**
- Future: [plan-kb-whisper-small.md](plan-kb-whisper-small.md) (Whisper prompt for glossary v3)
