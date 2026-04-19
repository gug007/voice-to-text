# 01 — Competitor Briefing (VoiceToText)

**Author:** T1 — Competitor Research Analyst
**Date:** 2026-04-19
**For:** IA, Copywriter, Designer
**Purpose:** Honest, sharp positioning data for the VoiceToText landing page. Use this to build a comparison table and differentiated copy.

> Confidence notes: all pricing and feature data below was pulled from competitor homepages, product docs, and recent 2026 review posts. Where a fact could not be verified with high confidence, it is marked **unknown**. Numbers change — re-verify before ship.

---

## TL;DR — Market Map

| Tier | Competitors | Dominant model |
|---|---|---|
| "AI dictation SaaS" (paid subscription, cloud-assisted) | **Wispr Flow**, **Willow Voice**, **Aqua Voice** | $8–$15 / month, free trial or capped free plan, cloud AI for polish |
| "Power dictation on Mac" (paid, mostly local) | **Superwhisper**, **MacWhisper**, **BetterDictation** | Freemium or one-time purchase, local Whisper, Mac-native |
| OS built-in | **Apple Dictation** | Free, bundled, limited polish, Apple-controlled UX |
| **VoiceToText (us)** | — | **Free, open-source, 100% offline, Apple-Silicon-native, no account** |

The SaaS tier is crowding around ~$12–15/mo with cloud-polished output. The "power dictation" tier charges once and keeps you local. **There is no well-known free + open-source + native + offline + push-to-talk Mac app with mindshare.** That is our lane.

---

## 1. Wispr Flow — [flowvoice.ai](https://wisprflow.ai)

- **Positioning headline:** "Don't type, just speak."
- **Sub-headline:** "The voice-to-text AI that turns speech into clear, polished writing in every app."
- **Hero CTA:** "Download for free"
- **Pricing:**
  - **Basic (free):** 2,000 words/week on desktop, 1,000/week on iOS; hard block at 5,000 desktop / 1,500 iOS. Resets Sunday 12:00 AM PT.
  - **Pro:** $15/mo monthly, **$12/mo billed annually** ($144/yr).
  - **Enterprise:** custom.
  - 14-day free Pro trial, no card required.
- **Free tier?** Yes, capped by word count.
- **Offline?** **No.** Wispr Flow is cloud-based; reviews and their own docs flag this as a privacy concern.
- **Open source?** No.
- **Platforms:** macOS, Windows, iOS, Android, (web demo).
- **Key features:** AI auto-edit (removes fillers, fixes typos), personal dictionary, snippets/voice shortcuts, per-app tone adjustment, 100+ languages with auto-detect, cross-device sync, advertised to work in 40+ apps (X, WhatsApp, VS Code, Slack, Gmail…).
- **Target audience signals:** leaders, developers, content creators, customer support, students, lawyers, sales, accessibility, non-profits — very broad.
- **Comparison tables on site:** none on homepage.
- **Weakness to exploit:** cloud-only, subscription-only after free cap, not open source, privacy ambiguity.

---

## 2. Superwhisper — [superwhisper.com](https://superwhisper.com)

- **Positioning headline:** "Just speak. Write faster. Turn your voice into polished text."
- **Hero CTA:** "Download"
- **Pricing (2026, verify before ship — sources conflict):**
  - **Free:** small local Whisper models, up to 3 custom modes, **15-minute recording cap** to trial Pro, then free tier features continue.
  - **Pro:** ~$8.49/mo or ~$84.99/yr (40% student discount).
  - **Lifetime:** historically $249.99; **one 2026 source reports this was raised to $849** — treat as unknown, verify on site.
  - **Enterprise:** custom.
  - 30-day refund.
- **Free tier?** Yes, but effectively a trial (15-min cap unlocks, then limited mode).
- **Offline?** **Yes.** "Superwhisper works offline, so you can transcribe anytime. No Wi-Fi, no problem."
- **Open source?** No.
- **Platforms:** macOS (Intel + Apple Silicon), Windows, iOS.
- **Key features:** predefined modes for tone/structure/formatting, 100+ languages, clipboard/paste integration, meeting recording & transcription, file transcription (video/audio), custom vocabulary, offline.
- **Target audience signals:** "hundreds of thousands" of users; logos of Vercel, Spotify, OpenAI, Shopify, Meta, Apple employees; explicit Cursor / Claude Code ("agentic coding") integration messaging.
- **Comparison tables on site:** none on homepage.
- **Weakness to exploit:** paid, not open source, pricing recently ambiguous/volatile, closed source means no trust-by-inspection.

---

## 3. MacWhisper — [goodsnooze.gumroad.com/l/macwhisper](https://goodsnooze.gumroad.com/l/macwhisper) (by Jordi Bruin)

- Homepage fetch returned only the product header; details below come from Dave Swift's 2026 review and the MacWhisper alternatives roundups. **Verify before ship.**
- **Positioning:** private transcription assistant; dual-purpose audio-file transcriber **plus** system-wide Whisper dictation.
- **Pricing (2026):**
  - **Free:** Tiny, Base, Small Whisper models; basic transcription.
  - **Pro:** **$69–$79.99 lifetime** (sources differ; Mac App Store reported $79.99). Subscriptions also exist: ~$8.99/mo or ~$29.99/yr. One review quotes **€59 one-time** — pricing has changed over time.
  - Pro unlocks Medium / Large-v2 / Large-v3 / Large-v3 Turbo models, batch transcription, system audio recording, "Global mode" system-wide dictation.
- **Free tier?** Yes, meaningful but capped by model size and missing Global/system-wide dictation.
- **Offline?** **Yes** — Whisper runs locally; optional cloud AI text-cleanup requires user-supplied API keys.
- **Open source?** **No** (the app is proprietary; it wraps the open-source Whisper model).
- **Platforms:** macOS only.
- **Key features:** local Whisper transcription, system-wide dictation (Pro), YouTube URL transcription, AI cleanup with custom prompts, batch export, watch-folders, transcript chat, meeting/system audio capture.
- **Target audience signals:** podcasters, journalists, researchers, Mac power users; "never phones home" privacy angle.
- **Weakness to exploit:** push-to-talk system-wide dictation gated behind Pro paywall; not open source; pricing complexity (free vs subscription vs lifetime).

---

## 4. Apple Dictation (built-in macOS)

- **Positioning:** "Use the keyboard for text input, but also speak to enter text anywhere you can type it."
- **Pricing:** Free, bundled with macOS.
- **Free tier?** It's entirely free.
- **Offline?** On Apple Silicon Macs, can process on-device (Enhanced Dictation historically required a download; modern macOS on Apple Silicon processes locally for supported languages). Some settings/fallbacks may use Siri servers.
- **Open source?** No (closed Apple component).
- **Platforms:** macOS (and iOS/iPadOS versions exist as sibling features).
- **Input model:** press-and-release a Microphone key or keyboard shortcut; stops on 30 s silence. Not a held push-to-talk by default.
- **Language support:** not all languages/regions; consult macOS feature availability.
- **Key features:** system-wide text entry, auto punctuation, supports multiple languages, integrates with Siri.
- **Weakness to exploit:**
  - Not a true **held** push-to-talk (toggle-style, awkward for quick bursts).
  - Accuracy lags Whisper/Parakeet models, especially on technical vocabulary and code.
  - No customizable model choice, no AI-prompt-friendly handling of technical jargon.
  - Tied to Apple's release cycle / language availability.

---

## 5. BetterDictation — [betterdictation.com](https://betterdictation.com)

- **Positioning headline:** "Type so fast, your boss will think there's 3 of you!"
- **Sub-headline:** "BetterDictation is your personal scribe. You speak, and it will quickly and flawlessly transcribe into any app."
- **Hero CTA:** "Buy Now"
- **Pricing (lifetime-first, Pro upsell):**
  - **Basic:** $39 lifetime (1 device)
  - **Flex:** $49 lifetime + $2/mo Pro (3 devices, 3 free Pro months)
  - **Studio:** $149 lifetime + $2/mo/device Pro (10 devices)
  - **Enterprise:** custom
  - **Pro add-on:** $2/mo billed annually
- **Free tier?** **No.**
- **Offline?** Yes: "BetterDictation operates fully offline, processing voice-to-text locally on your device." Pro features (stammer correction, auto-format, grammar) require internet.
- **Open source?** No.
- **Platforms:** macOS only (Apple Silicon required; Intel unsupported; Windows "coming soon").
- **Key features:** push-to-talk dictation, 100+ languages, whisper-large-v3-turbo on the Neural Engine, stammer correction (Pro), auto-formatting (Pro), grammar correction (Pro), works in any app.
- **Target audience signals:** employees at Disney, Amazon, Goldman Sachs, Notion, Slack, Shopify; RSI sufferers; writers, journalists, multilingual pros.
- **Weakness to exploit:** no free tier at all, Pro features require internet, not open source, splits capability across two billing axes.

---

## 6. Aqua Voice — [aquavoice.com](https://aquavoice.com) (formerly withaqua.com, 308 redirect)

- **Positioning headline:** "We've typed for 150 years. It's time to speak."
- **Sub-headline:** "Fast, accurate, and private speech-to-text."
- **Hero CTA:** "Start transcribing"
- **Pricing:**
  - **Starter (free):** 1,000 words total, 5 custom-dictionary values.
  - **Pro:** $8/mo (annual), unlimited words, 800 dictionary values, custom instructions.
  - **Team:** $12/mo (annual), centralized billing, org privacy enforcement.
- **Free tier?** Yes, but a tiny 1,000-word lifetime allowance — effectively a trial.
- **Offline?** **Unknown / not advertised.** Uses a proprietary "Avalon" model and emphasizes privacy, but offline is not claimed on the homepage. Treat as cloud-first.
- **Open source?** No.
- **Platforms:** macOS, Windows, iOS, web (app.aquavoice.com). Android/Linux: no.
- **Key features:** real-time transcription + grammar correction, custom dictionary, 49 languages, context-aware style, client-side transcript history, syntax highlighting for code, "5x faster than typing, 2x more accurate."
- **Target audience signals:** developers, prompt engineers, Slack/team knowledge workers.
- **SEO title:** "Aqua Voice - Fast and Accurate Voice Dictation for Mac and Windows"
- **Meta description:** "Fast, accurate, and private speech-to-text. Use voice to write clean & natural text, contextually adjusted to every app."
- **Weakness to exploit:** unclear offline story, stingy free tier, subscription, closed source.

---

## 7. Willow Voice — [willowvoice.com](https://willowvoice.com)

- **Positioning headline:** "Stop typing. Start writing 5x faster with voice."
- **Sub-headline:** "AI-powered voice dictation that's so powerful it can replace your keyboard."
- **Hero CTA:** "Download for iOS" / "Start dictating for free"
- **Pricing:** ~$15/mo (per testimonial); free trial, no credit card.
- **Free tier?** Trial only.
- **Offline?** **Unknown / not advertised.**
- **Open source?** No.
- **Platforms:** macOS, Windows, iOS.
- **Key features:** automatic editing/formatting, style-matching per app, context awareness (spells names correctly), AI Mode (expands brief phrases to polished messages), voice commands ("dash," "new line"), whisper/noise optimization, multi-language.
- **Target audience signals:** leaders, developers, founders, students, writers.
- **SEO title:** "AI Speech to Text Mac, Windows and iPhone Dictation Software | Willow"
- **Meta description:** "Fast, accurate voice dictation for emails, documents, Cursor, note-taking, and messaging."
- **Comparison tables on site:** yes — an unnamed-competitor feature table comparing grammar/punctuation, context awareness, formatting, tone detection.
- **Weakness to exploit:** cloud AI, subscription, no offline claim, no open source.

---

## Where VoiceToText Can Credibly Win (angles)

Ranked by how defensibly true and how differentiated they are. Use these as copy pillars.

1. **Free forever, no paywall, no account.**
   Nobody else combines *all three*. Apple Dictation is free but closed and weaker. The rest are subscription, trial, or one-time paid.

2. **Open source.**
   Out of the seven competitors, **zero** are open source. This is a trust + auditability moat, especially for developers and privacy-conscious teams. "Read the code" is a legitimate, instantly-verifiable claim.

3. **Truly offline, 100% local, zero telemetry.**
   Matches Superwhisper, BetterDictation, MacWhisper (partially). Beats Wispr Flow, Aqua, Willow (cloud-assisted). Combined with open source, this is uniquely verifiable.

4. **Apple-Silicon-native, Neural Engine-accelerated, no Electron.**
   Lightweight native SwiftUI menu-bar app vs. Wispr Flow / Willow / Aqua (likely Electron-based cross-platform). Developers respect this. Shorter launch time, lower battery drain, better macOS integration.

5. **Built for AI agents — dictate prompts into Claude Code, Codex, Cursor, Copilot Chat, ChatGPT.**
   Superwhisper owns this messaging today ("agentic coding"). We can out-compete by being the **free, open-source, local** version of that pitch — the one you can audit before piping your prompts through it.

6. **True held push-to-talk (hold `⌥ Space`).**
   Apple Dictation is toggle-style; Wispr/Willow/Aqua variable. Held push-to-talk is friction-free for short bursts of prompt dictation — matches how people actually talk to AI.

7. **Multiple model backends (WhisperKit + FluidAudio/Parakeet).**
   Users pick quality/speed tradeoff. Most competitors give you one engine.

---

## Proposed Feature Comparison Table

Draft for the landing page. Mark cells **conservatively** — if we can't verify, say so. Rows chosen to play to our strengths without lying.

**Legend:** ✅ yes · ❌ no · 💲 paid / subscription · 🆓 free · ❓ unknown / not advertised

| Feature | **VoiceToText** | Wispr Flow | Superwhisper | MacWhisper | Apple Dictation |
|---|:---:|:---:|:---:|:---:|:---:|
| Free forever (no cap, no account) | ✅ | ❌ (2,000 words/wk free) | ❌ (15-min trial cap) | 🆓 basic models only | ✅ |
| Open source | ✅ | ❌ | ❌ | ❌ | ❌ |
| 100% offline / on-device | ✅ | ❌ (cloud) | ✅ | ✅ | ✅ (Apple Silicon) |
| No account / no login required | ✅ | ❌ | ❌ | ✅ | ✅ |
| Hold-to-talk (true push-to-talk) | ✅ `⌥ Space` | ✅ | ✅ | ✅ (Pro) | ❌ (toggle) |
| Works system-wide in any text field | ✅ | ✅ | ✅ | ✅ Pro (Global mode) | ✅ |
| Apple Silicon / Neural Engine accelerated | ✅ | ❓ | ✅ | ✅ | ✅ |
| Native macOS app (no Electron) | ✅ SwiftUI | ❌ (cross-platform shell) | ✅ | ✅ | ✅ |
| Multiple model engines (user choice) | ✅ WhisperKit + Parakeet | ❌ | ✅ (Whisper variants) | ✅ (Whisper variants, Pro) | ❌ |
| Built/tuned for AI coding agents (Claude Code, Cursor, Codex) | ✅ | ⚠️ works in apps | ✅ messaged | ⚠️ works in apps | ❌ |
| Price | 🆓 | 💲 $12–15/mo | 💲 $8.49/mo or ~$85/yr, lifetime varies | 💲 $69–80 lifetime (or sub) | 🆓 (OS built-in) |

Source notes for the table:
- Wispr Flow free cap and pricing: confirmed via wisprflow.ai/pricing and their docs (2,000 desktop words/wk, $12/mo annual / $15/mo monthly).
- Superwhisper offline, 15-min trial, pricing: superwhisper.com + 2026 pricing roundups; lifetime price is in flux (reports of $249.99 → $849) — treat as **verify at ship**.
- MacWhisper free-vs-Pro split and Global mode gate: 2026 review sources; verify on the Gumroad product page before ship. Homepage fetch returned minimal content.
- Apple Dictation behavior: Apple macOS user guide.
- "Built for AI coding agents" is marketing language; we hold it only because we say it and we live it. Superwhisper explicitly messages the same angle.

---

## Copy + IA Recommendations

- **Lead with the combination no one else owns:** *"Free. Open source. Offline. Native."* All four in one breath. Each one alone is a "me too" somewhere in the market — the stack is uniquely ours.
- **Put the comparison table above the fold on a `/compare` page**, and a condensed 4-row version on the homepage.
- **Avoid overclaiming accuracy.** Wispr and Aqua claim "5x faster, 2x more accurate." Our honest angle is choice of best-in-class open models (Whisper / Parakeet) running locally, not a new proprietary model.
- **Developer-first voice.** Our hook is dictating to AI agents. Screenshots should show Claude Code, Cursor, Codex, Chrome with ChatGPT, and a terminal — not Gmail and Slack.
- **Neutral tone on competitors.** Don't trash them. The table does the work. "Free, open-source alternative to Wispr Flow, Superwhisper, MacWhisper, and Apple Dictation" is already in the README and is the right register.
- **SEO:** target "open source wispr flow alternative", "free superwhisper alternative", "offline dictation mac", "voice to text claude code / cursor", "apple silicon dictation whisper".

---

## Tagline Candidates (for copywriter to riff on)

1. **"Free. Open source. Offline. Native. Voice-to-text for Mac, done right."**
2. "Hold a key. Speak. Your words appear — free, offline, open source."
3. "The free, open-source dictation app your Mac was waiting for."
4. "Voice input for the Apple Silicon era — free, offline, and auditable."
5. "Talk to your AI. For free. On your Mac. Nothing leaves the device."

My lead pick for a single crisp tagline: **"Hold a key. Speak. Your words appear — free, offline, and open source."**

---

## Open Questions / Verify Before Ship

- Current Superwhisper lifetime price (conflicting reports: $249.99 vs $849).
- MacWhisper exact 2026 Pro price ($69, $79.99, or €59 — all reported).
- Whether Aqua Voice and Willow Voice offer any offline mode (not advertised; likely cloud-first — treat as ❌ with a footnote).
- Apple Dictation offline reliability on specific macOS versions — screenshot for proof if we make a claim.
- Electron vs native for Wispr Flow, Willow, Aqua — we believe they're Electron/cross-platform shells; confirm before publishing a "not Electron" row if we want to be 100% safe. Safer framing: "Native SwiftUI menu-bar app" as a positive claim about us, not a negative one about them.
