# 04 — Design Trends Briefing (T4 → T7 Visual Designer, T8 Lead Dev)

**Product:** VoiceToText — free, offline, on-device macOS dictation app. Push-to-talk (`⌥ Space`), Apple Neural Engine, native SwiftUI.
**Goal:** A landing page that reads as *modern 2026 dev-tool native* — privacy-first, keyboard-first, offline-first. Not another SaaS template.

---

## 1. Reference Site Audit

### linear.app
- **Palette vibe:** Light-first 2026, minimal. Off-white bg, near-black body (#0A0A0A range), cool muted blue accents (#5E6AD2-ish) on links/CTAs. No ornamental gradients; occasional very subtle grain/noise overlays.
- **Typography:** Custom sans (Inter-like geometric). Regular + medium + semibold. Display headline ~56–80px, body 15–17px. All sans.
- **Hero pattern:** Tagline-dominant + muted CTA + stacked product screenshots scrolling into view below the fold. No 3D, no video autoplay.
- **Spacing density:** Very airy. ~160–200px vertical section padding. Wide margins.
- **Motion:** Subtle; mostly on-scroll fade/translate-Y, tasteful hover states, zero parallax.
- **Comparison table:** Not used on the main page.

### raycast.com
- **Palette vibe:** Dark-first. Near-black bg (#0A0A0A / #121212), glass-morphism cards over subtle radial glows, electric cyan/blue (#4E9FFF-ish) and soft red brand accents. Light-mode section mid-scroll for contrast.
- **Typography:** Custom sans (close to Inter / SF). Display 64–96px, tight tracking. All sans.
- **Hero pattern:** Tagline ("Your shortcut to everything") + keyboard-metaphor visualization (keys & rows) — *not* a screenshot. Dual download CTAs. Abstract reinforces keyboard-first positioning.
- **Spacing density:** Loose, generous. Vertical rhythm is long.
- **Motion:** Interactive key presses, smooth scroll transitions, spring easing.
- **Comparison table:** None. Uses feature callouts w/ icons ("Fast", "Ergonomic", "Native", "Reliable").

### cursor.com
- **Palette vibe:** Dark-first charcoal (#0E0E0E-ish), pure white text, near-zero chroma. Very subtle painted/gradient wash behind hero demo. Accent restraint.
- **Typography:** Modern sans (geometric). Huge display (~80–120px) — text takes center stage. All sans.
- **Hero pattern:** Tagline + dual CTA + multi-tab interactive demo (CLI / Desktop / Agent) with realistic IDE shots.
- **Spacing density:** Generous whitespace, loose vertical rhythm.
- **Motion:** Spring-based layout transitions, shared-element transitions between demo tabs. No flash.
- **Comparison table:** None; uses capability cards instead.

### arc.net
- **Palette vibe:** Light, neutral. Editorial feel, clean whites, dark text, subtle product-color tints.
- **Typography:** Bold sans display. Hero repeats headline as a press-pull quote.
- **Hero pattern:** Tagline + dual-download CTAs + product screenshot.
- **Spacing density:** Very loose, editorial.
- **Motion:** Static / minimal.
- **Comparison table:** None.

### ghostty.org
- **Palette vibe:** Minimal; terminal-inspired. Dark-first possible, supports themed light/dark, "hundreds of built-in themes" vibe translates to restrained site chrome (assume near-black bg, pure text, monospaced accents).
- **Typography:** Ghostty wordmark uses custom lettering; site likely pairs a neutral sans for body with a mono for demos.
- **Hero pattern:** Wordmark + tagline + minimal CTA. No bloat.
- **Spacing density:** Tight to moderate — documentation-feel.
- **Motion:** Minimal.
- **Comparison table:** None.

### zed.dev
- **Palette vibe:** Light-first. White/off-white, charcoal text, Tailwind-blue CTA (`bg-blue-600` / `hover:bg-blue-700` → #2563EB / #1D4ED8). Clean, dev-documentation feel.
- **Typography:** Modern sans (Inter-like). H1 large but not gigantic; confident typographic hierarchy.
- **Hero pattern:** Tagline-only with a code-editor mockup screenshot below showing real syntax highlighting.
- **Spacing density:** Airy. Generous padding. `divide-y` dividers in lists (not heavy borders).
- **Motion:** Minimal; video embeds for feature demos but no autoplay.
- **Comparison table:** None. Uses testimonial and feature card sections.

### warp.dev
- **Palette vibe:** Dark-first. Deep charcoal/near-black with warm-cool gradient punches (coral → violet on brand elements). Clean editorial type.
- **Typography:** Modern sans display, confident hierarchy.
- **Hero pattern:** Tagline + dual product CTAs. Parallel product sections (Terminal + Oz) rather than single demo.
- **Spacing density:** Moderate/airy.
- **Motion:** Dynamic loading; subtle.
- **Comparison table:** None. Uses press/testimonial proof.

### Cross-reference synthesis
- **Dark-first dominates** among keyboard-/terminal-native tools (Raycast, Cursor, Warp, Ghostty). Light-first reads as "document editor" (Linear, Zed, Arc).
- **No one uses generic comparison tables.** When competitors are acknowledged, it's through opinionated, branded treatments.
- **Hero visuals are metaphorical, not literal.** Raycast shows keyboard keys, not a screenshot. Cursor shows a minimal IDE mock. Linear shows a clipped UI snippet.
- **Typography is always sans. No serifs.** Weights 400 / 500 / 600 / 700. No italics in display.
- **Motion is subtle.** Spring / fade / translate-Y on scroll. Zero parallax, zero autoplay video, zero scroll-jacking.
- **Accent discipline.** One brand accent, used sparingly. Gradients reserved for a single CTA or a single background glow.

---

## 2. Recommended Direction for VoiceToText: **Dark-First Keyboard-Native**

### Rationale
VoiceToText is **local, offline, keyboard-driven, and developer-adjacent** (its headline use case is prompting Claude Code / Codex / Cursor by voice). Dark-first aligns with:
- Privacy positioning (dark = "your data stays here, quiet, unflashy")
- Keyboard-native feel (Raycast, Warp, Ghostty set the vocabulary)
- Terminal/editor where it will be used
- Dev-tool peer group (differentiates from Wispr Flow's glossy consumer-white)

### Palette (exact hex)

| Role | Hex | Usage |
|---|---|---|
| `bg-0` primary bg | `#0A0A0B` | Page background (nearly black, slight warm undertone) |
| `bg-1` elevated surface | `#121214` | Cards, nav, comparison table rows |
| `bg-2` subtle hover | `#17171A` | Hover states on cards / rows |
| `border-subtle` | `#1F1F24` | Hairline borders (1px) |
| `border-strong` | `#2A2A31` | Emphasized borders on focus / active |
| `text-primary` | `#F4F4F5` | Body copy, default text |
| `text-secondary` | `#A1A1AA` | Captions, secondary info, deck text |
| `text-tertiary` | `#71717A` | Metadata, footnotes, disabled |
| `accent` (brand) | `#00D4FF` | Primary accent — electric cyan/teal (evokes voice/waveform) |
| `accent-hover` | `#33DDFF` | Hover on accent |
| `accent-muted` | `#00D4FF` @ 12% opacity | Accent glows, chip backgrounds |
| `success` | `#3DDC97` | Only for "Yes/Free/Local" cells in comparison |
| `warn` | `#F5A524` | Only for partial-support cells |
| `danger` | `#F04438` | Only for "No/Paid/Cloud" cells |

**CTA gradient (single, reserved for primary Download button):**
`linear-gradient(135deg, #00D4FF 0%, #7B8CFF 100%)` — cyan → soft indigo. Evokes waveform sweep. **Use once** per page.

**Background glow (hero only):**
`radial-gradient(60% 50% at 50% 20%, rgba(0,212,255,0.12) 0%, rgba(0,212,255,0) 70%)` — a single soft halo behind the hero. Nothing else.

### Typography

**Primary stack — Geist Sans (free, open-source, SIL OFL via Vercel), fallback to Inter and system:**
```
font-family: "Geist", "Inter", ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
```
Rationale: Geist is purpose-built for developer tooling (Vercel ships it on vercel.com, v0, shadcn). Free under OFL. Pairs 1:1 with system SF on macOS users, so locals see near-native rendering while the web font hands off gracefully on Windows/Linux visitors.

**Mono stack — Geist Mono, fallback JetBrains Mono, then system mono:**
```
font-family: "Geist Mono", "JetBrains Mono", ui-monospace, "SF Mono", Menlo, Consolas, monospace;
```
Use mono for: hotkey chips (`⌥ Space`), code snippet showing Claude Code prompt example, any filename/command.

**Type scale (fluid, clamp-based):**
| Token | Size | Weight | Line | Use |
|---|---|---|---|---|
| `display-xl` | `clamp(56px, 8vw, 96px)` | 600 | 1.02 | Hero headline |
| `display-l` | `clamp(40px, 5vw, 64px)` | 600 | 1.05 | Section headlines |
| `display-m` | `clamp(28px, 3vw, 40px)` | 600 | 1.1 | Sub-section |
| `body-l` | `20px` | 400 | 1.55 | Hero subcopy |
| `body` | `17px` | 400 | 1.6 | Default body |
| `body-s` | `15px` | 400 | 1.55 | Captions, deck |
| `label` | `13px` | 500 | 1.3 | Uppercase eyebrows, nav |
| `mono` | `14px` | 500 | 1.3 | Hotkey pills, code |

Tracking: `-0.02em` on display sizes, `0` on body, `+0.04em` on uppercase labels.

**Loading strategy:** self-host Geist from `/fonts`, use `font-display: swap`, preload only the Regular + SemiBold weights of Geist Sans + Regular of Geist Mono (3 files total, ~180KB WOFF2).

---

## 3. Hero Pattern — **Keyboard-Key Visual with Ambient Waveform**

### Recommendation
A **centered, oversized keyboard key visualization** (`⌥` + `Space`) as the hero centerpiece — rendered as two glassmorphic keycaps with realistic bevel and a thin cyan accent ring on the `Space` key. Under the keys, a **subtle animated waveform line** (CSS/SVG only, not video) breathes at a slow cadence, implying "press and speak." Below, the demo.gif sits in a macOS window chrome frame as the "proof" section immediately beneath the hero, not inside it.

### Why this over alternatives
| Option | Verdict |
|---|---|
| Just the tagline | Too sparse — user asked for *premium*, not minimalist. |
| Animated waveform *alone* | Too abstract — doesn't say "hotkey." |
| Code editor mock showing voice input | Misleading; the product isn't an editor. |
| **demo.gif front and center** | GIF is ~several MB, LCP-killer, and competes with hero typography. Demote to below-hero. |
| **Keyboard keys + ambient waveform** (winner) | Says "press this, speak, done" in one glance. Mirrors Raycast's winning keyboard metaphor but distinguishes via voice. Pure CSS/SVG = fast. |

### Hero layout spec
```
┌─────────────────────────────────────────────────┐
│  [nav: VoiceToText · Features · Compare · GH]   │
│                                                  │
│        Dictate into any app.                    │  ← display-xl, #F4F4F5
│        On-device. Free forever.                 │  ← second line in #A1A1AA
│                                                  │
│        [ ⌥ ]  [ Space ]  ← keycap SVG, ~180px   │
│             ∿∿∿∿∿  ← cyan waveform 2s loop       │
│                                                  │
│   Free, offline dictation for macOS. Hold      │  ← body-l, #A1A1AA, max 560px
│   ⌥ Space, speak, release. Runs on Apple       │
│   Neural Engine. Your voice never leaves your  │
│   Mac.                                          │
│                                                  │
│   [ Download for Mac ]   [ View on GitHub ]    │  ← gradient CTA + ghost CTA
│       ^ cyan→indigo gradient                   │
│   Free · macOS 14+ · Apple Silicon              │  ← mono label, #71717A
└─────────────────────────────────────────────────┘
    ↓ ambient radial glow behind — stops here

┌─────────────────────────────────────────────────┐
│          [ demo.gif in macOS window chrome ]    │ ← separate section, "See it work"
└─────────────────────────────────────────────────┘
```

### Waveform animation detail
- 5–7 vertical bars in a row, each oscillating at different phase offsets, 1.6–2.0s period.
- Color: `#00D4FF` at 80% opacity.
- Respect `prefers-reduced-motion`: bars freeze at medium height, no animation.
- Pure CSS keyframes, no JS.

---

## 4. Comparison Table Treatment — **Card-Row Hybrid, Opinionated**

The user explicitly asked for a competitor comparison (vs Wispr Flow, Superwhisper, MacWhisper, Apple Dictation). A default `<table>` reads generic and corporate. **Build it as a card-framed row-and-column grid with deliberate typographic hierarchy and colored status glyphs.**

### Structure
- Outer container: `bg-1` (#121214), rounded 16px, 1px `border-subtle`.
- Internal grid: 5 columns (Feature + 4 products), first column left-aligned, product columns centered.
- Product column headers: product name in `label` (13px, 500, uppercase, `text-tertiary`), followed by mini logo if legally available, else type-only.
- Feature rows: `body` (17px) for feature name, status glyphs for each product's cell.
- VoiceToText column gets a **subtle cyan top-border glow** (`inset 0 2px 0 0 rgba(0,212,255,0.4)`) and slightly elevated bg (`#17171A`) — visually asserts "this is the one we care about" without being tacky.

### Status glyphs (not checkmarks and X's)
- **Full support:** `#3DDC97` filled circle + label text ("Free", "On-device", "Unlimited", etc.) — show the value, not just a checkmark.
- **Partial:** `#F5A524` half-circle + label ("Trial only", "Cloud", etc.).
- **None:** `#71717A` em-dash + label ("Paid", "—").

### Rows (recommended features)
| Feature | VoiceToText | Wispr Flow | Superwhisper | MacWhisper | Apple Dictation |
|---|---|---|---|---|---|
| Price | Free forever | Subscription | Paid | Paid | Free (built-in) |
| Runs offline | On-device | Cloud | On-device | On-device | Limited on-device |
| Push-to-talk hotkey | ⌥ Space | Customizable | Customizable | Varies | Limited |
| Works in any app | Yes | Yes | Yes | Limited | Limited |
| Apple Neural Engine | Native | — | Yes | Yes | Yes |
| Open source | Yes | — | — | — | — |
| Telemetry | None | Yes | Varies | Varies | Apple-level |
| Optimized for AI coding agents | Yes | Partial | Partial | — | — |

### Visual treatment notes
- Feature names left-aligned, `body` weight 500, `text-primary`.
- Cell text `body-s` 15px, weight 400, `text-secondary` by default.
- On hover of a row: `bg-2` (#17171A). No row borders — use `divide-y` style 1px `border-subtle`.
- Mobile: collapse to stacked cards, one per competitor, with VoiceToText pinned top.
- **Do not fake logos.** Use text wordmarks only unless you have rights.

### Copy tone in the cells
Avoid "Yes/No." Say what it *gives you.* "Free forever" beats "✓". "Cloud only" beats "✗." Opinionated, factual.

---

## 5. Motion Principles

### Core rules
1. **Respect `prefers-reduced-motion: reduce`.** All non-essential motion must degrade to static states.
2. **No parallax. Ever.** No scroll-hijack, no pinned sections with transform-on-scroll.
3. **No autoplay video.** The demo.gif is the only moving thing on the page, and it loops at reduced frame rate.
4. **Subtle entrance animations.** Elements fade in + translate-Y 8–12px over 400–500ms with `cubic-bezier(0.2, 0.8, 0.2, 1)` (a soft spring-out). Trigger via `IntersectionObserver` at ~15% visibility.
5. **Hover states on interactive elements only.** CTAs brighten accent by 10%, elevate shadow subtly. 150ms ease-out.
6. **Waveform in hero** is the only continuous animation. 2s period. Pauses on reduced-motion.
7. **No hover-zoom on the demo.gif.** Static framing.
8. **No counter-up animations, no number tickers, no "trusted by" logo carousels.**

### Performance budget
- Target LCP < 1.5s, CLS < 0.05.
- Hero visual is SVG (inline), waveform is CSS keyframes — zero JS to paint first frame.
- demo.gif lazy-loaded below hero with `loading="lazy"` and explicit width/height.

---

## 6. Anti-Patterns — Do NOT do these

1. **Generic purple-to-pink SaaS gradient** over every button and heading. Tired, 2022. Our one gradient is cyan→indigo, used *once*, on the primary CTA only.
2. **Fake "Trusted by" logo row** (YC, Fortune 500 logos, "As seen on TechCrunch"). We don't have them. Don't imply we do. If we want proof, use the GitHub star count and a single real quote.
3. **Generic SaaS illustration blobs** — floating 3D shapes, isometric laptops, waving characters. Every AI-generated landing page has these. We are not another SaaS.
4. **Generic competitor comparison with green ✓ and red ✗.** It signals "compliance checklist," not "opinionated product." Use status glyphs + descriptive labels (see §4).
5. **Hero video autoplay / looping MP4 background.** Kills LCP, hostile to data-conscious users, competes with copy. demo.gif lives *below* the hero.
6. **Parallax scroll & scroll-jacking.** Feels 2019. Motion-sickness-hostile. Zero parallax.
7. **"Join the waitlist" / email capture in hero.** This is free OSS. The CTA is Download, not signup.
8. **Overloaded nav with 8+ items.** Keep nav to: VoiceToText wordmark · Features · Compare · GitHub · Download. Five max.
9. **Emoji headlines** (🚀 "Supercharge your productivity"). Never. The mono `⌥ Space` chip is our only glyph.
10. **Placeholder testimonials** ("Game changer!" — J.S., CEO). Don't fabricate social proof. If you have one real user quote, use it; otherwise skip the section entirely.

---

## 7. Deliverables Summary for T7 (Visual) and T8 (Dev)

**T7 Visual Designer — produce:**
- Figma with tokens matching §2 palette, §2 type scale
- Hero keycap SVG (`⌥` + `Space`, ~180px square each, glassmorphic bevel, cyan accent ring on Space)
- Waveform SVG (5–7 bars, stagger-animated, CSS keyframes spec)
- Primary CTA button component (gradient, rounded 12px, 48px tall)
- Comparison table layout at 1280px, 768px, 375px (stacks to cards on mobile)
- macOS window chrome frame component for demo.gif

**T8 Lead Developer — implement with:**
- Self-hosted Geist Sans + Geist Mono via WOFF2, `font-display: swap`, 3 files preloaded
- CSS custom properties for all §2 hex tokens
- `prefers-reduced-motion` branch in every animation
- `loading="lazy"` + explicit aspect-ratio on demo.gif
- No JS framework required for hero; IntersectionObserver vanilla JS for scroll-fades
- Single CTA gradient implemented via CSS `background-image`, not image asset
- Target: Lighthouse Performance 95+, Accessibility 100, LCP < 1.5s on 4G

---

## TL;DR Direction
Dark-first (`#0A0A0B` bg), Geist Sans, one cyan accent (`#00D4FF`), one cyan→indigo gradient used only on the primary Download CTA, hero anchored by a large `⌥ Space` keycap pair with an ambient waveform, demo.gif beneath in macOS chrome, opinionated card-style comparison table with colored status labels (not checkmarks), subtle on-scroll fade/translate motion, zero parallax, zero stock illustrations, zero fake social proof.
