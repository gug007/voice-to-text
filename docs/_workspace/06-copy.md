# 06 — Landing Page Copy (VoiceToText)

**Author:** T6 — Senior Copywriter
**Date:** 2026-04-19
**Consumers:** T8 (Lead Developer — paste directly into HTML), T7 (Visual Designer — overlay copy)
**Sources of truth:** T1 competitors, T2 SEO, T3 audience, T5 IA, `README.md`

Voice: confident, terse, specific. Verbs over adjectives. Sentence case for body, Title Case for buttons and section headings. No emojis, no hype. Where a sentence doesn't add a fact, it is cut.

> **T8:** every `##` below matches an IA anchor id. Copy blocks are labeled for 1:1 paste. Don't rewrite.

---

## 0. Head / Meta

### Meta title (≤60 chars)

> `VoiceToText — Free Offline Dictation App for Mac`
> (51 chars — matches T2 §2.1 Variant A)

### Meta description (≤155 chars)

> `Free, open-source Mac dictation. Hold a hotkey, speak, release — words type into any app. 100% offline, on the Apple Neural Engine.`
> (132 chars — sharpened from T2 §2.2 for tighter action verbs and character budget)

### Canonical

> `https://gug007.github.io/voice-to-text/`

### Open Graph

- `og:title` → **VoiceToText — Free, Offline, Open Source**
- `og:description` → **Push-to-talk dictation for Mac. Hold ⌥ Space, speak, release. Words appear in any app. Runs on the Apple Neural Engine. Free forever.**
- `og:image:alt` → **VoiceToText menu-bar app transcribing speech into Claude Code on macOS; ⌥ Space keycap illustration**

### Twitter Card

- `twitter:title` → **VoiceToText — Free Mac Dictation, Offline and Open Source**
- `twitter:description` → **Hold ⌥ Space, speak, release. Dictate into Claude Code, Cursor, Slack, or any app — on-device, on the Apple Neural Engine.**
- `twitter:image:alt` → **VoiceToText demo: holding ⌥ Space dictates a prompt into Claude Code on macOS**

### OG image overlay text (for T7)

- Line 1 (display, large): **Free. Offline. Open source.**
- Line 2 (mono, small): **VoiceToText — dictation for Mac**
- Corner chip: **macOS 14+ · Apple Silicon**

---

## 1. Top Nav

- Wordmark: **VoiceToText**
- Nav links: **Features** · **Compare** · **FAQ**
- Right-side CTA (ghost): **View on GitHub**

---

## 2. Hero (`#top`)

### Eyebrow (optional, above H1)

> **Free · Open source · macOS**

### H1 (≤10 words, display)

> **Free Offline Dictation for Mac.**

### H2 lead-in / sub-headline (≤25 words)

> **Push-to-talk dictation for Mac. 100% local. Free forever.**
> Hold `⌥ Space`, speak, release — words are typed into Claude Code, Cursor, Slack, or any focused app. On the Apple Neural Engine. Offline.

*(Note to T8: render the first line as a larger lead-in `<p class="lead">` and the second line as the `<p>` sub-copy. Together ≤36 words; easy to trim if the fold tightens.)*

### Keycap captions (under the SVG)

- Left keycap: **hold**
- Right keycap (spacebar): **`⌥ Space`**
- Below waveform, micro-caption: **speak · release**

### CTAs

- **Primary** (gradient): **Download for Mac**
  - Variant: **Download Free for Mac**
- **Secondary** (ghost): **View on GitHub**
  - Variant: **Read the Source**

### Microcopy under CTAs

> **Free · Open source · macOS 14+ · Apple Silicon**

Companion line (tiny, below the chip, optional):

> **No account. No subscription. No cloud.**

---

## 3. Social-Proof Strip (`#proof`)

### Hidden H2 (for screen readers, matches T5 IA)

> **Open source on GitHub**

### Visible copy (left → right band)

- **Pill 1:** **100% open source**
- **Pill 2:** **Live on GitHub** (shields.io stars, forks, latest release — rendered by T8)
- **Pill 3:** **Built in public**

### Model-provenance line (right side, or beneath pills)

> **Powered by OpenAI Whisper (via WhisperKit) and Parakeet (via FluidAudio), on the Apple Neural Engine.**

### Inline link

> **Read the code →** (links to repo)

---

## 4. Demo Showcase (`#demo`)

### Eyebrow

> **See it work**

### H2

> **See VoiceToText dictate into any Mac app.**

### Deck (≤25 words)

> Hold the hotkey. Speak a full sentence. Release. Your words appear at the cursor — in a code editor, a terminal, a Slack thread, a note.

### Caption under the GIF/video

> **Dictating a prompt into Claude Code. Nothing leaves the Mac.**

### Alt text (for `docs/demo.gif` / `demo.mp4`)

> `VoiceToText demo: user holds ⌥ Space and speaks a prompt; transcribed text is typed into Claude Code in real time on macOS. Menu-bar icon shows recording state.`

---

## 5. How It Works (`#how-it-works`)

### H2

> **How push-to-talk dictation works on Mac.**

### Deck (≤20 words)

> Three keys. One loop. No menus, no windows, no copy-paste.

### Step 1

- **Title:** **Hold `⌥ Space`**
- **Body (≤18 words):** Press and hold the global hotkey from any app. A waveform appears in the menu bar.

### Step 2

- **Title:** **Speak naturally**
- **Body (≤18 words):** Say a word, a sentence, or a full paragraph. Transcription runs on-device on the Apple Neural Engine.

### Step 3

- **Title:** **Release — words are typed**
- **Body (≤18 words):** Let go of the keys. Your text is typed straight into the focused app at the cursor.

### Footer line

> Rebind the hotkey in Settings. Works in any text field.

---

## 6. Features (`#features`)

### H2

> **Why VoiceToText?**

### Deck (≤25 words)

> A native Mac app that keeps your voice on your Mac. Free, open, fast, and designed to live at your cursor.

### Feature 1 — On-device & offline

- **Title:** **Offline and private**
- **Body (≤18 words):** Audio is transcribed locally on the Apple Neural Engine. No cloud, no telemetry, no network calls.
- **Inline link:** **Read the source →**

### Feature 2 — Push-to-talk

- **Title:** **True push-to-talk**
- **Body (≤18 words):** Hold `⌥ Space` to dictate. Release to stop. No toggles, no cutoffs mid-sentence, no rebound.

### Feature 3 — Apple Silicon native

- **Title:** **Apple Silicon native**
- **Body (≤18 words):** A SwiftUI menu-bar app that rides the Neural Engine. No Electron, low battery drain, fast cold start.

### Feature 4 — Built for AI agents

- **Title:** **Built for AI agents**
- **Body (≤18 words):** Dictate prompts into Claude Code, Cursor, Codex, Copilot Chat, or ChatGPT at thinking speed.

### Feature 5 — Choice of engines

- **Title:** **Two engines, your pick**
- **Body (≤18 words):** WhisperKit (OpenAI Whisper) for accuracy. FluidAudio (Parakeet) for speed. Switch in Settings anytime.

### Feature 6 — Works anywhere

- **Title:** **Types into any app**
- **Body (≤18 words):** Slack, Mail, Notes, browsers, terminals, code editors — anywhere macOS shows a text cursor, words land there.

---

## 7. AI-Agent Use Case (`#ai-agents`)

### Eyebrow

> **Voice prompting**

### H2

> **Voice dictation for Claude Code, Cursor, and AI coding agents.**

### Deck (≤25 words)

> Think in paragraphs. Speak them into the editor. Prompts stay on your Mac — no cloud STT sitting between you and the agent.

### Body paragraph

> Dictate the whole prompt: the file you want changed, the error, the constraint, the style you're aiming for. VoiceToText types it at the cursor in Claude Code, Codex CLI, Cursor, Copilot Chat, ChatGPT, Warp, or a plain terminal. Proprietary code never leaves the Mac.

### App grid labels (for T7)

- **Claude Code**
- **Cursor**
- **Codex CLI**
- **Copilot Chat**
- **ChatGPT**
- **Warp**
- **Terminal**
- **VS Code**

### Mono transcript snippet (illustrative — belongs next to the grid)

```
▌ refactor this function so it streams
▌ tokens instead of buffering, keep the
▌ type signature, add a test with fakes
```

Caption under the snippet:

> **Spoken into Claude Code in one push.** No copy-paste, no separate window.

### CTA (primary repeat)

- **Download for Mac** → same gradient button as hero

### Alt text for AI-agent visual

> `Mock of Claude Code in dark mode showing a multi-line prompt typed by voice; ⌥ Space keycap badge in the corner indicates push-to-talk is active.`

---

## 8. Comparison Table (`#compare`)

### H2

> **A free, open-source alternative to Wispr Flow, Superwhisper, and MacWhisper.**

### Deck (≤25 words)

> Same core idea — dictate into any app. Different terms: no subscription, no account, no cloud, and source you can audit.

### Column headers

| Feature | **VoiceToText** | Wispr Flow | Superwhisper | MacWhisper | Apple Dictation |
|---|---|---|---|---|---|

### Row contents (labels, not checkmarks — per T5 §2)

| # | Feature | VoiceToText | Wispr Flow | Superwhisper | MacWhisper | Apple Dictation |
|---|---|---|---|---|---|---|
| 1 | Price | **Free forever** | $12–15 / mo | $8.49 / mo · paid lifetime² | $69–80 lifetime³ | Free (built-in) |
| 2 | Open source | **Yes — on GitHub** | — | — | — | — |
| 3 | Runs 100% offline | **On-device** | Cloud only | On-device | On-device | On-device (Apple Silicon, some langs) |
| 4 | No account required | **None required** | Account required | Account required | No account | None required |
| 5 | Push-to-talk (hold key) | **Hold `⌥ Space`** | Customizable hold | Customizable hold | Pro (Global mode) | Toggle only |
| 6 | Works in any text field | **System-wide** | System-wide | System-wide | Pro only | System-wide |
| 7 | Apple Neural Engine acceleration | **Native** | — Not advertised¹ | Yes | Yes | Yes |
| 8 | Native macOS app (no Electron) | **SwiftUI native** | Cross-platform shell | Native | Native | Native |
| 9 | Multiple speech engines | **WhisperKit + Parakeet** | Proprietary only | Whisper variants | Whisper variants (Pro) | Apple only |
| 10 | Tuned for AI coding agents | **Yes — headline use case** | Works in apps | Messaged | Works in apps | — |

### Footnote block (directly under the table, muted caption)

> `¹ Wispr Flow does not advertise Apple Neural Engine acceleration; treat as unverified.`
> `² Superwhisper lifetime pricing was in flux at research — verify on the vendor site.`
> `³ MacWhisper Pro price varies across sources ($69, $79.99, €59) — verify on the Gumroad product page.`

### Inline link below footnotes

> **Read the source →** (to repo) · **See the license →** (to `/LICENSE`)

---

## 9. FAQ (`#faq`)

### H2

> **Frequently asked questions.**

### Deck (≤20 words, optional)

> Answers to what developers, writers, and privacy-conscious users ask before installing.

> **T8:** these Q strings must match the `FAQPage` JSON-LD `name` fields in T2 §4.2 word-for-word. Do not paraphrase.

### Q1

- **Question (H3):** **Is VoiceToText really free?**
- **Answer:** Yes. VoiceToText is 100% free and open source, released under an OSI-approved license. There are no paid tiers, no accounts, no telemetry, and no in-app purchases.

### Q2

- **Question (H3):** **Does VoiceToText work offline?**
- **Answer:** Yes. All speech recognition runs on-device on the Apple Neural Engine. Your audio never leaves your Mac, and no internet connection is required after installation.

### Q3

- **Question (H3):** **How accurate is it?**
- **Answer:** Accuracy comes from the models: OpenAI's Whisper (via WhisperKit) and NVIDIA's Parakeet (via FluidAudio) — the same state-of-the-art models behind popular paid apps. Pick the engine that fits your accuracy-versus-speed preference.

### Q4

- **Question (H3):** **Which speech recognition models does VoiceToText use?**
- **Answer:** VoiceToText ships with two engines: WhisperKit (OpenAI's Whisper) for maximum accuracy, and FluidAudio (NVIDIA's Parakeet) for maximum speed. Both run locally on the Apple Neural Engine.

### Q5

- **Question (H3):** **Can I use VoiceToText to dictate prompts into Claude Code, Cursor, or other AI coding tools?**
- **Answer:** Yes. VoiceToText types into whatever app has focus, including Claude Code, Codex CLI, Cursor, Copilot Chat, ChatGPT, and any terminal or code editor. It is purpose-built for voice prompting AI coding agents at natural speaking speed.

### Q6

- **Question (H3):** **What Macs does VoiceToText support?**
- **Answer:** VoiceToText requires macOS 14 (Sonoma) or later and an Apple Silicon Mac (M1 or newer). Intel Macs are not supported because there is no Apple Neural Engine.

### Q7

- **Question (H3):** **How is VoiceToText different from Apple Dictation or Wispr Flow?**
- **Answer:** Apple Dictation is toggle-style and tied to Apple's models. Wispr Flow is a paid subscription that processes audio in the cloud. VoiceToText is free, open source, held push-to-talk, and 100% on-device.

### Q8

- **Question (H3):** **Do you collect any data?**
- **Answer:** No. No accounts, no telemetry, no network calls. The repo is public — inspect the source or watch the network with Little Snitch to verify.

---

## 10. Download / Install (`#download`)

### Eyebrow

> **Ready to dictate**

### H2

> **Download VoiceToText for macOS.**

### Deck (≤25 words)

> One DMG. Drag to Applications. Grant Microphone and Accessibility. Hold `⌥ Space` and speak.

### Primary CTA (gradient, large, centered)

- **Download for Mac**
  - Variant: **Download the DMG**

### Microcopy under CTA

> **Free · Open source · macOS 14+ · Apple Silicon**

Secondary (ghost, beside or below):

- **View on GitHub**
  - Variant: **Browse Releases**

### Install steps (numbered, 4 steps)

1. **Open the DMG** and drag **VoiceToText** to `/Applications`.
2. **Launch the app.** It lives in the menu bar.
3. **Grant Microphone and Accessibility** when prompted — mic captures audio, accessibility types into the focused app.
4. **Hold `⌥ Space`**, speak, release. Your words are typed at the cursor.

### Permissions explainer (small caption under steps)

> **Why two permissions?** Microphone lets the app hear you. Accessibility lets it type into whatever app you're in. Both stay on-device. Revoke anytime in System Settings.

### Requirements callout

> **Requirements:** macOS 14 Sonoma or later · Apple Silicon (M1 or newer).

---

## 11. Footer (`#footer`)

### Tagline (left column, under wordmark)

> **Free, offline dictation for Mac. Open source on GitHub.**

### Attribution

> Built in public by [**@gug007**](https://github.com/gug007).

### Privacy note

> **No telemetry. No account. No network calls.**

### Link labels (right columns)

**Product**
- Features
- Compare
- FAQ
- Download

**Project**
- GitHub
- Releases
- License
- Issues

**Trust**
- Privacy
- Read the source

### Copyright line

> © 2026 VoiceToText contributors. Released under an OSI-approved open-source license.

> **T8:** resolve exact license name (MIT / Apache-2.0 / etc.) from `/LICENSE` and replace "an OSI-approved open-source license" with the concrete name (e.g., "the MIT License"). Per T5 conflict C5 and T3 open question.

---

## 12. Alt Text — All Image Assets

| Asset | File / slot | Alt text |
|---|---|---|
| Demo GIF / MP4 | `docs/demo.gif` → `demo.mp4` in `#demo` | `VoiceToText demo: user holds ⌥ Space and speaks a prompt; transcribed text is typed into Claude Code in real time on macOS. Menu-bar icon shows recording state.` |
| OG image | `/og-image.png` | `VoiceToText — free, offline, open-source dictation for Mac. Dark background with a cyan ⌥ Space keycap and the tagline "Free. Offline. Open source."` |
| Favicon (Apple touch) | `/apple-touch-icon.png` | *(decorative in most contexts — if rendered inline, use:)* `VoiceToText icon — cyan V mark on black.` |
| Keycap SVG (hero) | inline SVG | `Illustration of the ⌥ Option and Space keys, paired to signal the push-to-talk hotkey.` |
| Waveform SVG (hero) | inline SVG | *(decorative — `alt=""` or `aria-hidden="true"`)* |
| How-it-works icons | inline SVG × 3 | *(decorative when paired with visible step titles — `aria-hidden="true"`)* |
| Feature icons | inline SVG × 6 | *(decorative — `aria-hidden="true"`)* |
| AI-agent mock | `#ai-agents` | `Mock of Claude Code in dark mode showing a multi-line prompt typed by voice; ⌥ Space keycap badge in the corner indicates push-to-talk is active.` |
| macOS window chrome around demo | CSS only | *(pure CSS — no alt needed)* |
| shields.io badges | `#proof` | `GitHub star count badge for the VoiceToText repository` · `GitHub fork count badge for the VoiceToText repository` · `Latest VoiceToText release version badge from GitHub` |

---

## 13. Global Microcopy Index (quick reference for T8)

| Slot | Copy |
|---|---|
| CTA microcopy (universal) | **Free · Open source · macOS 14+ · Apple Silicon** |
| "No account" line | **No account. No subscription. No cloud.** |
| Privacy footer line | **No telemetry. No account. No network calls.** |
| Keycap left | **hold** |
| Keycap right | **`⌥ Space`** |
| Waveform caption | **speak · release** |
| Open-source pill | **100% open source** |
| Built-in-public pill | **Built in public** |
| Model provenance line | **Powered by OpenAI Whisper (via WhisperKit) and Parakeet (via FluidAudio), on the Apple Neural Engine.** |
| "Read the source" inline link | **Read the source →** |
| Requirements chip | **Free · macOS 14+ · Apple Silicon** |
| Permissions caption | **Mic captures audio. Accessibility types into the focused app. Both stay on-device.** |

---

## 14. Word-Count & Keyword Audit

- Landing page body copy ≈ **780 words** (target: 700–900 per T2 H2).
- H1: `Free Offline Dictation for Mac` — hits **P1** (free mac dictation), **P2** (offline speech to text mac).
- H2 coverage:
  - `Why VoiceToText?` — brand
  - `See VoiceToText dictate into any Mac app` — L9 (dictate into any app)
  - `How push-to-talk dictation works on Mac` — **P4** (push-to-talk dictation mac), L8
  - `Voice dictation for Claude Code, Cursor, and AI coding agents` — **P5** (voice dictation for Claude Code), L6, L7, L15
  - `A free, open-source alternative to Wispr Flow, Superwhisper, and MacWhisper` — **P3**, L1, L2
  - `Download VoiceToText for macOS` — brand
- Named apps (T3 decisive proof points): Claude Code, Cursor, Codex, Codex CLI, Copilot Chat, ChatGPT, Warp, Terminal, Slack, Mail, Notes, VS Code.
- Models named every time they appear: `WhisperKit (OpenAI Whisper)` + `FluidAudio (Parakeet)` per T5 conflict C4.
- Phrasing match with JSON-LD FAQ: Q1, Q2, Q4, Q5, Q6 use T2 §4.2 `name` strings **verbatim**. Q3, Q7, Q8 are new visible Q's (T8 adds matching JSON-LD entries so visible ≡ structured).

---

## 15. Open Items for T8 Before Publish

1. Replace "OSI-approved open-source license" with the concrete license name from `/LICENSE` (T5 C5, T3 open question).
2. Confirm DMG is notarized before we quote the install steps as-is (T3 §"Open questions"). If not notarized, add: `First launch: right-click → Open to approve Gatekeeper.` to step 2.
3. Confirm maintainer handle for the footer attribution — currently `@gug007`.
4. T2 §4.2 JSON-LD answer for Q7 (Apple Dictation / Wispr Flow differentiator) must be added; current JSON-LD only has Wispr/Super/MacWhisper comparison. Expand it so visible Q7 ≡ structured Q7.
5. T2 §4.2 JSON-LD answer for Q8 (data collection) must be added — not in T2 today.
