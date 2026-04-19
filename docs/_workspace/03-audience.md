# T3 — Audience & Messaging Brief: VoiceToText

Status: Draft for T5 (IA) and T6 (copy). Product truth source: `/Users/gug007/Projects/voice-to-text/README.md`.

Assumption note: VoiceToText is a new open-source project. No star counts, install counts, or user testimonials have been verified. Anywhere this brief references social proof, it is a recommendation for future use, not a claim.

---

## 1. Primary Audience Segments

### Segment A — AI-native developers prompting coding agents by voice
- **Who they are:** Engineers on Apple Silicon who spend hours in Claude Code, Codex CLI, Cursor, Copilot Chat, Aider, and ChatGPT. They write long prompts (requirements, context, corrections) and feel the friction of typing them. They already use keyboard shortcuts aggressively and live in the terminal + one editor.
- **Top 3 pain points:**
  1. Typing multi-paragraph prompts to an agent is slow and kills flow; their thinking is faster than their fingers.
  2. Cloud dictation tools (Wispr Flow, Superwhisper Pro) are paid subscriptions or send audio off-device — not acceptable for prompts that include proprietary code.
  3. Apple Dictation is unreliable in terminals and code editors and doesn't handle technical vocabulary well.
- **Job-to-be-done:** "When I'm about to prompt my AI agent, I want to speak the prompt at natural speed directly into the editor, so I can stay in flow and get more iterations per hour."
- **Objection to a free app:** "Free usually means a weekend project with bad accuracy or a bait-and-switch freemium model." Also: "Will it break my flow with permission prompts, lag, or crashes?"
- **Decisive proof point:** It types directly into Claude Code / Cursor / terminal at the cursor (not via clipboard pop-ups), runs on the Apple Neural Engine so latency is sub-second on M-series, and the source is on GitHub — they can audit it.

### Segment B — Writers & knowledge workers who want reliable offline dictation
- **Who they are:** Writers, researchers, PMs, consultants, therapists, journalists, academics on Mac. They draft long-form text (docs, emails, notes, reports) and already know dictation is faster than typing, but they've been burned by accuracy or privacy tradeoffs.
- **Top 3 pain points:**
  1. Apple Dictation cuts off, misses punctuation, and won't run offline reliably on long passages.
  2. Cloud alternatives require a subscription for everyday use and won't work on a flight or in a SCIF / client site without Wi-Fi.
  3. Context switching between a separate dictation window and their real app (Notion, Scrivener, Gmail, Slack) breaks the writing train of thought.
- **Job-to-be-done:** "When I'm drafting in my normal writing tool, I want to speak a paragraph and have it appear in place, so I can write at conversation speed without leaving the app."
- **Objection to a free app:** "If it's free, is the accuracy good enough that I won't spend more time fixing transcription errors than I saved?"
- **Decisive proof point:** It uses OpenAI Whisper (via WhisperKit) and Parakeet (via FluidAudio) — the same state-of-the-art models behind paid tools — running locally on the Neural Engine. Push-to-talk means no cutoffs mid-sentence.

### Segment C — Privacy-conscious users who refuse cloud STT
- **Who they are:** Security engineers, lawyers, healthcare / clinical professionals, compliance teams, journalists protecting sources, enterprise developers under NDA, anyone handling regulated data (HIPAA, attorney-client, trade secrets). They have explicitly rejected cloud dictation for policy or principle reasons.
- **Top 3 pain points:**
  1. Every mainstream dictation app sends audio to a server; their employer, client, or conscience forbids it.
  2. "Offline mode" in other tools is often a downgraded fallback, not the default, and telemetry still phones home.
  3. They can't verify vendor privacy claims — there's no source code to audit.
- **Job-to-be-done:** "When I dictate work content, I need cryptographic certainty — not a privacy policy — that audio never leaves this Mac."
- **Objection to a free app:** "Free + open source sometimes means 'funded by telemetry' or 'we'll monetize later.' What's the catch?"
- **Decisive proof point:** No account, no telemetry, no network calls — and the repo is public on GitHub, so any network egress would be visible in the code or in Little Snitch. MIT-style open source means no future rug-pull.

---

## 2. Core Value Proposition

**Free, offline dictation for Mac that types into any app — hold a key, speak, release.**

### Supporting Pillars (each with a concrete proof point)

1. **Private by architecture, not by promise.**
   - *Proof:* 100% on-device transcription on the Apple Neural Engine. No account, no cloud, no telemetry. Source is on GitHub — audit it or watch network traffic.

2. **Fast enough to stay in flow.**
   - *Proof:* Native SwiftUI (no Electron), push-to-talk global hotkey (`⌥ Space` default), Neural Engine-accelerated Whisper / Parakeet models, direct text insertion into the focused app.

3. **Free and open, forever.**
   - *Proof:* Open-source on GitHub, no paywall, no subscription, no account, no "pro tier." A real alternative to Wispr Flow, Superwhisper, and MacWhisper for users who don't want to pay a monthly fee to speak to their computer.

4. **Built for how you actually work today.**
   - *Proof:* Types directly into Claude Code, Cursor, Codex, Slack, Notes, Mail, browsers, terminals — anywhere with a text field. No copy-paste step, no separate window to manage.

*(Recommendation to T6: lead with pillars 1, 2, 3. Pillar 4 is the "where it works" section / demo GIF, not a hero pillar.)*

---

## 3. Hero Headline Candidates

Each ≤10 words. Different styles for A/B consideration.

1. **Direct benefit:** "Free offline dictation for Mac. Type by voice, anywhere."
2. **Contrarian:** "Stop paying $15/month to talk to your Mac."
3. **Specific outcome:** "Prompt Claude Code and Cursor by voice, at thinking speed."
4. **Category definition:** "Push-to-talk dictation for Mac. 100% local. Free forever."
5. **Social-proof-style:** "The open-source dictation app for Apple Silicon developers." *(Note: avoid implying user counts we can't back up.)*

### Strongest Pick: #4 — "Push-to-talk dictation for Mac. 100% local. Free forever."

**Sub-headline candidate:**
"Hold ⌥ Space, speak, release — your words are typed into Claude Code, Cursor, Slack, or any focused app. Runs on the Apple Neural Engine, offline. No account, no subscription, no cloud."

Why this hero works: it names the *interaction model* (push-to-talk — the single biggest differentiator vs. Apple Dictation and most cloud tools), the *platform* (Mac), the *privacy posture* (100% local), and the *business model* (free forever) in under 10 words. Leaves room for the sub-headline to do the targeting to the developer / AI-agent use case via concrete app names.

---

## 4. Objections and How to Preempt Them

| Objection | Preempt in copy by... |
|---|---|
| "Is 'free' really free? What's the catch?" | State plainly: open source, MIT-style license (confirm in repo), no account, no telemetry, no 'pro tier.' Link to the GitHub repo and the license file. "If you can read code, read the code." |
| "Is offline accuracy actually good?" | Name the models: "Runs OpenAI Whisper (WhisperKit) and Parakeet (FluidAudio) — the same model families behind popular paid apps." Offer model-choice as a feature, not a limitation. Let the demo GIF do the talking. |
| "Does it work with my editor / terminal / Electron app?" | List concrete apps that work: Claude Code, Cursor, Codex CLI, VS Code, Slack, Messages, Mail, Chrome, Notes, Terminal. Show the demo GIF in a real editor. State the rule: "any focused text field." |
| "Will it slow down my Mac?" | "Native SwiftUI menu-bar app. No Electron. Uses the Apple Neural Engine so your CPU stays free." Include the machine requirement (Apple Silicon, macOS 14+). |
| "Why not just use Apple Dictation?" | Short comparison: push-to-talk (no awkward auto-cutoff), types into any app reliably (including terminals), modern Whisper/Parakeet accuracy, and handles code / technical vocabulary. |
| "Why not Wispr Flow / Superwhisper / MacWhisper?" | Direct positioning: "A free, open-source alternative. Same idea, no subscription, no cloud, source code you can audit." Don't trash the competitors — just be the free, local option. |
| "Is installing a .dmg from GitHub safe?" | Walk through install steps. Explain Microphone + Accessibility permissions up front and *why* each is needed (mic = capture audio; accessibility = type into the focused app). Consider mentioning notarization status (verify with engineering before claiming). |
| "Will it get abandoned?" | "Open source on GitHub — forkable, auditable, yours." Link recent commit activity once the project has it. Don't promise forever-maintenance; promise forever-available-code. |
| "I'm on Intel Mac / older macOS." | Requirements stated up-front: macOS 14 Sonoma+, Apple Silicon recommended. Don't bury it. |
| "Why should I trust a new project with mic access?" | "Source is public. No network calls. Verify with Little Snitch / Lulu. We'd rather earn trust by being auditable than by being loud." |

---

## 5. Social Proof Strategy (new OSS project, no fabrication)

Ground rule: **do not invent stars, installs, testimonials, or company logos.** We don't know real numbers; do not guess.

### What to use instead (in rough priority order):

1. **Live GitHub badge.** Embed a real-time star / fork / latest-release badge from shields.io on the landing page. It will show whatever the true count is — zero shame, no inflation. As the project grows, the page updates itself.
2. **"Built in public" narrative.** "Built by [maintainer name]. Open source on GitHub. Every commit, every issue, every release in the open." This is a proof of trustworthiness when you have no logos to show. (T6: confirm maintainer name/handle with T1 before publishing.)
3. **Model provenance as proof.** Name-drop the *models* you stand on, not fake customers: "Powered by OpenAI Whisper (via WhisperKit) and Parakeet (via FluidAudio)." These are credible, known names in the ML community.
4. **Platform provenance.** "Native SwiftUI. Runs on the Apple Neural Engine." Tells a technical audience you're not a cross-platform Electron wrapper.
5. **Category positioning (honest).** "A free alternative to Wispr Flow, Superwhisper, MacWhisper, and Apple Dictation." The README already does this — it's legitimate because it's a factual statement of the category, not a false comparison claim.
6. **Demo GIF.** The `docs/demo.gif` referenced in the README is itself social proof — it shows the thing working. Put it above the fold. This is already the single highest-leverage asset on the page.
7. **License + code transparency.** A "Read the code" / "Audit the source" link near the privacy claims. Invites scrutiny — which *is* social proof for the privacy-conscious segment.
8. **Once real, show real:** When actual users show up, add (with permission) a small "In the wild" section — real GitHub issues thanking the project, real tweets, real blog mentions. Until then, leave that section off entirely rather than fabricate.

### Do not:
- Fake "As seen in" logo bars.
- Use stock-photo avatars with made-up testimonials.
- Claim download numbers we can't verify.
- Claim "trusted by developers at [Company]" without a signed permission.
- Inflate star counts via badges pointing at other repos.

---

## Handoff Notes

- **For T5 (IA):** Recommend page order — Hero (headline + sub + demo GIF + primary CTA "Download" + secondary CTA "View on GitHub") → Pillars (privacy / speed / free & open) → "Works with" app grid (Claude Code, Cursor, Slack, etc.) → How it works (3-step push-to-talk diagram) → FAQ addressing the objections above → Install + requirements → Footer with repo / license links.
- **For T6 (Copy):** Lean on verbs (hold, speak, release, type) and named apps. Avoid adjective-stacking. Keep the privacy claim architectural ("on-device," "no network") rather than promissory ("we promise not to"). Numbers and benchmarks should be omitted unless engineering provides verified figures.
- **Open questions / need verification from team:**
  - Exact license text (MIT? Apache? check `LICENSE` file).
  - Notarization / Gatekeeper status of the DMG (affects install objection copy).
  - Any real benchmark numbers (WER, latency) we can cite.
  - Maintainer name/handle for "built by" attribution.
