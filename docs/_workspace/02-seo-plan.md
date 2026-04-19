# VoiceToText — SEO Plan (T2)

**Author:** T2 — SEO Keyword Specialist
**Date:** 2026-04-19
**Target URL:** `https://gug007.github.io/voice-to-text/` (GitHub Pages; canonical must be configurable for later custom domain)
**Consumers:** T9 (engineering/implementation) and T6 (copywriter)

---

## 1. Keyword Strategy

### 1.1 Competitive snapshot (from SERP research)

Buyer-intent SERPs for this category are dominated by:

- **Paid/SaaS incumbents:** Wispr Flow, Superwhisper, MacWhisper (paid/subscription), Voicy, VoiceInk, SpeakMac, Spokenly.
- **Apple's own Dictation** (high-authority but generic).
- **Comparison/list listicles** ("Best Dictation Software For Mac 2026", "Wispr Flow Alternatives").
- **Open-source competitors** gaining traction: FreeFlow (Groq-API), VoiceInk (GPL, macOS), VoiceTypr (macOS/Windows), OpenWhispr.

**Gap we can own:** "free + open-source + offline + Apple Neural Engine + AI-coding-agents" — that exact combination is thinly covered. Strong "alternative" queries and "free" modifiers are where we win without fighting brand SEO.

### 1.2 Primary keyword cluster (head terms, 3–5)

These should appear in `<title>`, `<h1>`, `<meta description>`, URL slug (already `voice-to-text`), and the opening paragraph.

| # | Keyword | Intent | Why |
|---|---|---|---|
| P1 | **free mac dictation app** | Buyer | Highest buyer-intent modifier in this niche; beats paid incumbents on price |
| P2 | **offline speech to text mac** | Buyer | Privacy-focused users; matches our on-device story |
| P3 | **open-source Wispr Flow alternative** | Buyer (alternative) | Proven high-converting "alternative" query + we are actually open source |
| P4 | **push-to-talk dictation mac** | Buyer (feature) | Differentiator vs. Apple Dictation (hands-free) and MacWhisper (file-based) |
| P5 | **voice dictation for Claude Code** | Buyer (use-case) | Fast-growing, low-competition, matches README positioning |

### 1.3 Secondary / long-tail cluster (10–15)

These go into `<h2>`/`<h3>` headings, FAQ, feature bullets, alt text, and an "Alternatives" section.

1. free superwhisper alternative mac
2. free macwhisper alternative
3. whisper mac app free
4. apple neural engine speech to text
5. on-device speech recognition macOS
6. voice to text for cursor ide
7. voice prompting for ai coding agents
8. push to talk voice typing mac
9. dictate into any app mac
10. private dictation app no cloud
11. whisperkit mac app
12. parakeet speech to text mac
13. menu bar dictation app macOS
14. free offline voice typing for mac
15. mac dictation app for developers

### 1.4 Keywords to intentionally **avoid / de-emphasize**

- "transcribe audio file" / "transcribe mp3 to text" — we're real-time dictation, not batch file transcription. Don't fight MacWhisper/Whisper Transcription there.
- "meeting transcription" / "zoom transcription" — wrong vertical (Otter, Jamie dominate).
- "speech to text iPhone" / "iOS" — we're Mac-only; keep the ICP tight.

---

## 2. Meta Title & Description

### 2.1 Meta title (≤60 chars)

**Variant A (recommended — primary pick):**

> `VoiceToText — Free Offline Dictation App for Mac` *(51 chars)*

Hits P1 + P2 + brand. Clean, benefit-forward, mirrors README H1.

**Variant B (alternative-play):**

> `VoiceToText — Open-Source Wispr Flow Alternative` *(49 chars)*

Pivots to the high-converting "alternative" query; good if we A/B test later.

### 2.2 Meta description (≤155 chars)

**Variant A (recommended):**

> `Free, open-source macOS dictation. Hold a hotkey, speak, release — words type into any app. 100% offline, powered by the Apple Neural Engine.` *(142 chars)*

**Variant B:**

> `Free offline speech-to-text for Mac. Push-to-talk dictation into Claude Code, Cursor, Slack — anywhere. Open-source Wispr Flow alternative.` *(139 chars)*

### 2.3 Recommended pick (for first launch)

- **Title:** Variant A
- **Description:** Variant A
- Run B/B as a 60-day A/B after initial indexing via search console impressions.

---

## 3. Social cards (Open Graph + Twitter)

Put a `1200x630` PNG at `/og-image.png` (T9: engineer generates; T6 writes overlay text). OG and Twitter share the image.

### 3.1 Open Graph

```html
<meta property="og:type" content="website" />
<meta property="og:site_name" content="VoiceToText" />
<meta property="og:url" content="https://gug007.github.io/voice-to-text/" />
<meta property="og:title" content="VoiceToText — Free Offline Dictation App for Mac" />
<meta property="og:description" content="Free, open-source macOS dictation. Hold a hotkey, speak, release — words type into any app. 100% offline, powered by the Apple Neural Engine." />
<meta property="og:image" content="https://gug007.github.io/voice-to-text/og-image.png" />
<meta property="og:image:width" content="1200" />
<meta property="og:image:height" content="630" />
<meta property="og:image:alt" content="VoiceToText menu-bar app transcribing speech into a code editor on macOS" />
<meta property="og:locale" content="en_US" />
```

### 3.2 Twitter Card

```html
<meta name="twitter:card" content="summary_large_image" />
<meta name="twitter:title" content="VoiceToText — Free Mac Dictation (Offline, Open-Source)" />
<meta name="twitter:description" content="Push-to-talk dictation into any Mac app. Offline, on the Apple Neural Engine. A free open-source alternative to Wispr Flow & Superwhisper." />
<meta name="twitter:image" content="https://gug007.github.io/voice-to-text/og-image.png" />
<meta name="twitter:image:alt" content="VoiceToText demo: hold hotkey, speak, words typed into Claude Code" />
```

*(No `twitter:site` / `twitter:creator` — only add if we own a branded X/Twitter handle.)*

---

## 4. Schema.org JSON-LD

Inject three JSON-LD blocks in `<head>`. They're independent — engineers can ship them separately. **Skip `aggregateRating`** until we have verifiable review volume (fake ratings = manual-action risk).

### 4.1 `SoftwareApplication`

```html
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  "name": "VoiceToText",
  "description": "Free, open-source macOS dictation app. Push-to-talk speech-to-text that runs 100% offline on the Apple Neural Engine and types into any app.",
  "url": "https://gug007.github.io/voice-to-text/",
  "downloadUrl": "https://github.com/gug007/voice-to-text/releases/latest/download/VoiceToText.dmg",
  "applicationCategory": "UtilitiesApplication",
  "applicationSubCategory": "Dictation",
  "operatingSystem": "macOS 14.0",
  "processorRequirements": "Apple Silicon (M1 or newer)",
  "softwareVersion": "latest",
  "offers": {
    "@type": "Offer",
    "price": "0",
    "priceCurrency": "USD",
    "availability": "https://schema.org/InStock"
  },
  "license": "https://github.com/gug007/voice-to-text/blob/main/LICENSE",
  "isAccessibleForFree": true,
  "author": {
    "@type": "Person",
    "name": "Gurgen Abagyan",
    "url": "https://github.com/gug007"
  },
  "image": "https://gug007.github.io/voice-to-text/og-image.png",
  "screenshot": "https://gug007.github.io/voice-to-text/docs/demo.gif",
  "featureList": [
    "Push-to-talk global hotkey (⌥ Space, customizable)",
    "100% offline on-device transcription",
    "Apple Neural Engine acceleration",
    "WhisperKit and FluidAudio (Parakeet) engines",
    "Types into any focused macOS app",
    "Menu bar app, native SwiftUI"
  ]
}
</script>
```

> **T9 note:** If/when the `softwareVersion` is auto-bumped by the release pipeline, template it. Otherwise leave `"latest"`.

### 4.2 `FAQPage` (5–8 Q/A — recommended 6)

Target questions users literally type into Google. These also give Google surface area for featured snippets.

```html
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "Is VoiceToText really free?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Yes. VoiceToText is 100% free and open source, released under an OSI-approved license. There are no paid tiers, accounts, telemetry, or in-app purchases."
      }
    },
    {
      "@type": "Question",
      "name": "Does VoiceToText work offline?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Yes. All speech recognition runs on-device using the Apple Neural Engine. Your audio never leaves your Mac and no internet connection is required after installation."
      }
    },
    {
      "@type": "Question",
      "name": "How is VoiceToText different from Wispr Flow, Superwhisper, or MacWhisper?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "VoiceToText is free and open source. Wispr Flow and Superwhisper are paid subscription apps with cloud options. MacWhisper focuses on transcribing audio files. VoiceToText focuses on real-time push-to-talk dictation into any app, fully offline."
      }
    },
    {
      "@type": "Question",
      "name": "Can I use VoiceToText to dictate prompts into Claude Code, Cursor, or other AI coding tools?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Yes. VoiceToText types into whatever app has focus, including Claude Code, Codex CLI, Cursor, Copilot Chat, ChatGPT, and any terminal or code editor. It is purpose-built for voice prompting AI coding agents at natural speaking speed."
      }
    },
    {
      "@type": "Question",
      "name": "What Macs does VoiceToText support?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "VoiceToText requires macOS 14 (Sonoma) or later and an Apple Silicon Mac (M1 or newer). Intel Macs are not supported because there is no Apple Neural Engine."
      }
    },
    {
      "@type": "Question",
      "name": "Which speech recognition models does VoiceToText use?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "VoiceToText ships with two engines: WhisperKit (OpenAI's Whisper) for maximum accuracy, and FluidAudio (NVIDIA's Parakeet) for maximum speed. Both run locally on the Apple Neural Engine."
      }
    }
  ]
}
</script>
```

> **T6 note:** If copy on the landing page changes the answer to any of these Q's, update the JSON-LD to match the visible copy — Google penalizes structured data that doesn't reflect visible content.

### 4.3 `VideoObject` (optional — only if we embed a demo video)

We currently ship `docs/demo.gif`. If/when T6 produces an MP4/WebM demo hosted on YouTube or our own CDN, add:

```html
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "VideoObject",
  "name": "VoiceToText demo: push-to-talk dictation into any Mac app",
  "description": "A 30-second demo of VoiceToText transcribing speech into Claude Code and Slack on macOS using the Apple Neural Engine.",
  "thumbnailUrl": "https://gug007.github.io/voice-to-text/og-image.png",
  "uploadDate": "2026-04-19",
  "duration": "PT30S",
  "contentUrl": "https://gug007.github.io/voice-to-text/demo.mp4",
  "embedUrl": "https://www.youtube.com/embed/REPLACE_ID"
}
</script>
```

Skip this block on initial launch — an animated GIF is not a schema-eligible video.

---

## 5. Heading hierarchy & keyword distribution

Single `<h1>` (Google strongly prefers one). Cascade primary keywords into `<h2>`/`<h3>` by section. T6 writes prose; T9 enforces structure.

| Section | Tag | Suggested text (T6 can refine) | Keyword coverage |
|---|---|---|---|
| Hero | `<h1>` | **Free Offline Dictation for Mac** | P1 (free mac dictation), P2 (offline) |
| Sub-hero | `<p>` lead | "Push-to-talk speech-to-text that runs on the Apple Neural Engine..." | P4 (push-to-talk), L4 (apple neural engine) |
| Features | `<h2>` | **Why VoiceToText?** | brand |
| Feature 1 | `<h3>` | On-device & offline — nothing leaves your Mac | P2, L10 (private dictation) |
| Feature 2 | `<h3>` | Push-to-talk into any app | P4 |
| Feature 3 | `<h3>` | Apple Silicon native, Neural Engine accelerated | L4 |
| Feature 4 | `<h3>` | Built for Claude Code, Cursor & AI agents | P5, L6, L7 |
| Use-cases | `<h2>` | **Voice dictation for developers and AI coding** | P5, L15 (mac dictation for developers) |
| Comparison | `<h2>` | **A free open-source alternative to Wispr Flow, Superwhisper & MacWhisper** | P3, L1, L2 |
| Download | `<h2>` | **Download VoiceToText for macOS** | brand + macOS |
| How it works | `<h2>` | **How push-to-talk dictation works on Mac** | P4, L8 |
| FAQ | `<h2>` | **FAQ** | — (handled by JSON-LD + visible Q's as `<h3>`) |
| Footer | — | GitHub, license, privacy | — |

**Rules of the road:**
- Brand name + **one** primary keyword in `<h1>`; don't stuff.
- Exactly one `<h1>`; `<h2>` hierarchy stays flat.
- Use the **same phrasing** in headings as in the FAQ JSON-LD (answer parity).
- `<p>`-level copy should reach ~700–900 words total. Anything under 400 looks thin.

---

## 6. `robots.txt` and `sitemap.xml`

### 6.1 `/robots.txt`

```
User-agent: *
Allow: /

Sitemap: https://gug007.github.io/voice-to-text/sitemap.xml
```

> **T9 note:** If we later move to a custom domain, update the `Sitemap:` absolute URL and add a redirect from the github.io origin to preserve link equity.

### 6.2 `/sitemap.xml`

Single URL for now — we're a one-pager. Bump `lastmod` on content changes.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>https://gug007.github.io/voice-to-text/</loc>
    <lastmod>2026-04-19</lastmod>
    <changefreq>monthly</changefreq>
    <priority>1.0</priority>
  </url>
</urlset>
```

### 6.3 Canonical tag (must be configurable)

```html
<link rel="canonical" href="https://gug007.github.io/voice-to-text/" />
```

> **T9 note:** Parameterize this in the Jekyll/Hugo/static config (e.g., `site.url`) so flipping to a custom domain is a one-line change. Also emit it dynamically; do not hardcode in every partial.

---

## 7. Ranking hazards & mitigations

| # | Hazard | Mitigation |
|---|---|---|
| H1 | **Duplicate content vs. README.md** — GitHub's README is already indexed at `github.com/gug007/voice-to-text` and will compete with the landing page. | Rewrite landing copy 100% from scratch (T6). Don't paste README prose. The README can link to the site with `canonical`-style language ("Full documentation at..."). |
| H2 | **Thin content** — one-pagers with ≤300 words rank poorly. | Target 700–900 words on the landing page: hero, 4–6 feature blocks, comparison table vs. Wispr/Super/MacWhisper, use-case section, 6-question FAQ, footer. |
| H3 | **Missing alt text on demo GIF / OG image / screenshots** | Every `<img>` needs descriptive alt: e.g., `alt="VoiceToText demo: holding ⌥ Space to dictate into Claude Code on macOS"`. Decorative images get `alt=""`. |
| H4 | **Keyword cannibalization between README and landing page** | Differentiate intent: README = installer instructions + dev docs; landing page = buyer-intent ("free, offline, alternative"). Don't double up on the same head term. |
| H5 | **Non-HTTPS assets / mixed content** | GitHub Pages enforces HTTPS; keep all asset URLs protocol-relative or absolute `https://`. Don't embed `http://` resources. |
| H6 | **No `aggregateRating` evidence** → fake structured data risks manual action | Skip `aggregateRating` until we have ≥5 verifiable reviews with public sources. Never invent ratings. |
| H7 | **Core Web Vitals** — 685KB demo.gif will wreck LCP | T9: convert demo.gif → `demo.mp4` (`<video autoplay muted loop playsinline>`) or AVIF/WebP; target <200KB hero asset; preload hero image; defer non-critical JS. |
| H8 | **GitHub Pages serves `Cache-Control: max-age=600`** — not ideal but acceptable | Nothing to do now; if we move to Cloudflare/custom host, set aggressive cache on `/assets/*` and short cache on HTML. |
| H9 | **"VoiceTypr" name collision** — an existing Mac/Windows dictation app is called VoiceTypr (very similar name). | Brand consistently as one word **"VoiceToText"** (no hyphen, no spaces). Register the `<title>` brand exactly. Monitor SERP for confusion; if it's an issue, add a disambiguation line in meta description. |
| H10 | **macOS 14+ requirement** is a narrow market — don't overpromise | Always qualify "Apple Silicon, macOS 14+" in download CTA to avoid bounces from unsupported users. |

---

## 8. Implementation checklist for T9

- [ ] Add `<title>`, `<meta name="description">`, `<link rel="canonical">` with configurable `site.url`.
- [ ] Add all OG and Twitter meta tags (section 3).
- [ ] Add three JSON-LD blocks: `SoftwareApplication`, `FAQPage`, and (later) `VideoObject`.
- [ ] Generate `/og-image.png` at 1200×630.
- [ ] Commit `/robots.txt` and `/sitemap.xml` to the site root.
- [ ] Replace `demo.gif` on the landing page with an optimized video element (keep the GIF in `/docs` for README).
- [ ] Ensure every `<img>` has descriptive `alt`.
- [ ] Verify one `<h1>` per page; rest are `<h2>`/`<h3>`.
- [ ] Register the site in Google Search Console and submit the sitemap post-launch.
- [ ] Bing Webmaster Tools — import GSC property (one click; free distribution to Bing/DuckDuckGo/ChatGPT web search).

## 9. Implementation checklist for T6

- [ ] Write ~700–900 words of landing copy that does **not** copy README sentences.
- [ ] Hit primary keywords in H1, first paragraph, and at least two H2s.
- [ ] Weave 6–8 secondary/long-tail terms naturally across feature bullets and FAQ.
- [ ] Write FAQ answers that match the JSON-LD answers word-for-word.
- [ ] Write alt text for every image/GIF/screenshot.
- [ ] Draft the OG image overlay text ("Free. Offline. Open-source." works; ≤6 words).
