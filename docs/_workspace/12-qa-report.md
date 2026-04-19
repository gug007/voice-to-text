# 12 — QA & Final Polish

**Author:** T12 — QA & Final Polish
**Date:** 2026-04-19
**Scope:** `docs/` production output after T8 → T9 → T10 → T11 passes.
**Verdict:** SHIP (with three documented pre-publish follow-ups).

---

## 1. Verdict

**Ship.** The page renders, validates structurally, meets WCAG 2.2 AA (per
T11), hits the perf budget (per T10), and the SEO chain (title, meta
description, canonical, OG/Twitter, JSON-LD, sitemap, robots, .nojekyll)
is coherent. No HTML validity issues, no broken internal anchors, no
mismatched quotes, no unclosed sections.

Three follow-ups are pre-publish but non-blocking today because the repo
is not yet GitHub-Pages-publish-targeted — the user can resolve them in
the same commit that enables Pages.

---

## 2. Issues found and fixed

| # | File | Line | Before | After | Why |
|---|---|---|---|---|---|
| F1 | `docs/index.html` | 1057-1059 | `&copy; 2026 VoiceToText contributors. Released under an OSI-approved open-source license.` + `<!-- T9/T11: resolve exact license name from /LICENSE and replace "an OSI-approved open-source license" with the concrete name. -->` | `&copy; 2026 VoiceToText contributors. Open source on GitHub.` | No `LICENSE` file exists in the repo; README does not declare MIT or any specific license; per T12 brief rule "write 'Open source' generically and log a TODO." Placeholder T9/T11 marker consumed. |
| F2 | `docs/index.html` | 958 | `<!-- T11: consider an install-command copy-to-clipboard once a brew/curl one-liner is available -->` | `<!-- Follow-up: add copy-to-clipboard install one-liner (brew/curl) when available; data-copy handler already wired in script.js -->` | Stripped stray `T11` marker; rephrased as a generic follow-up note so future readers aren't confused by team-role prefixes. |
| F3 | `docs/styles.css` | 16-18 | Leading `T12: consider a build-time minification step...` comment | `Follow-up: a build-time minification step...` | T12 was me; note consumed, rephrased as generic follow-up. |
| F4 | `docs/_workspace/README.md` | new | — | 15-line index of briefings 01-11 + this report | `_workspace/` is served by Pages (`_`-prefix is not excluded when `.nojekyll` is set); a brief README prevents confusion for visitors who browse into it. |

---

## 3. Issues found but deferred (follow-ups)

| # | Owner | Severity | Description |
|---|---|---|---|
| D1 | **repo maintainer** | **P1 — pre-publish** | **Add a `LICENSE` file at repo root.** The footer mentions "Open source on GitHub" generically, but three outbound links still target `github.com/gug007/voice-to-text/blob/main/LICENSE`: (a) the compare section "See the license" link (`index.html:839`), (b) the footer "License" link (`index.html:1043`), (c) the JSON-LD `SoftwareApplication.license` field (`index.html:212`). All three will 404 until a LICENSE exists. Recommend MIT (consistent with pre-build IA assumption in `05-ia.md` and `03-audience.md`) or Apache-2.0. Once added, the FAQ answer "released under an OSI-approved license" (both visible and in JSON-LD) can be swapped to the concrete name if desired — but the current phrasing is forward-compatible and does not require editing. |
| D2 | **designer / asset owner** | **P1 — pre-publish** | **Generate `og-image.png`.** Referenced four places (`og:image`, `twitter:image`, JSON-LD `image`) at `https://gug007.github.io/voice-to-text/og-image.png`. File does not exist in `docs/`. When shared on Twitter, Slack, iMessage, Discord, Facebook, LinkedIn, the preview card will fall back to no image. Target: 1200×630 PNG, <300 KB. Not a page-render issue; only affects social sharing. |
| D3 | **perf / assets** | P2 | **Convert `demo.gif` → `demo.webm` + poster.** T10 flagged this as highest-impact follow-up. Current 685 KB GIF is the dominant asset. WebM encode typically lands at 60-150 KB. Replace `<img src="demo.gif">` with `<video autoplay muted playsinline loop>` with a WebP poster. Requires ffmpeg work, not text edits. |
| D4 | — | P3 | **Build-time CSS minification.** External stylesheet is ~34 KB raw; cssnano/lightningcss would take it to ~22 KB raw / ~5 KB gzipped. Deferred because the project has no build step by design. Revisit if raw weight becomes a concern. |
| D5 | — | P3 | **`twitter:url` meta tag.** Not present; canonical + og:url cover the same semantics and Twitter's card validator honors canonical. Not required for correct rendering. Optional add-on. |
| D6 | accessibility | P3 | **Compare grid semantics (role="table").** T11 (D1 in that report) deferred converting CSS-grid siblings to explicit `role="table"/row/columnheader/cell`. Currently SR reads row-label then 5 cells linearly, which is acceptable but not ideal. Deferring because the refactor is non-surgical. |

None of D3–D6 block ship.

---

## 4. Verification notes — what I confirmed is correct

### A. Correctness & consistency

1. **HTML validity** — scanned for unclosed tags, mismatched quotes, stray team markers. All 10 `<section>` elements open/close cleanly. No orphan `<div>`, `<span>`, or `<ul>`. No remaining `<!-- T9 -->`, `<!-- T10 -->`, `<!-- T11 -->` markers after F1–F3 fixes. Two informational T10/T11 comments in head and CSS that *describe decisions* (font strategy, contrast tokens) retained — they are documentation, not placeholders.
2. **Links** — every `<a href>` traced:
   - Skip link `#main` → `<main id="main">` ✓
   - Nav brand `#top` → `<section id="top">` ✓
   - Nav `#features` → `<section id="features">` ✓
   - Nav `#compare` → `<section id="compare">` ✓
   - Nav `#faq` → `<section id="faq">` ✓
   - Footer `#features`, `#compare`, `#faq`, `#download`, `#faq` (Privacy alias) — all target valid ids ✓
   - Footnote refs `#fn-1`, `#fn-2`, `#fn-3` ↔ `<li id="fn-1/2/3">` — six refs (a/b) per note, all resolved ✓
   - Download button `https://github.com/gug007/voice-to-text/releases/latest/download/VoiceToText.dmg` ✓ (sensible pattern; only valid once a release exists)
   - GitHub link `https://github.com/gug007/voice-to-text` ✓
   - Releases `.../releases` ✓
   - License `.../blob/main/LICENSE` — **404 until LICENSE added; see D1**
   - Issues `.../issues` ✓
   - Author `https://github.com/gug007` ✓
3. **Canonical / OG URLs** — `canonical`, `og:url`, `sitemap.xml` all agree on `https://gug007.github.io/voice-to-text/`. `twitter:url` not present but not required (D5).
4. **Single title / description** — one `<title>`, one `<meta name="description">`. ✓
5. **JSON-LD** — two blocks (`SoftwareApplication`, `FAQPage`). Both visually lint: proper `@context`, `@type`, balanced braces/brackets, no unescaped quotes in text, URLs valid. FAQ JSON-LD entries match visible FAQ text word-for-word.
6. **Comparison table** — spot-checked 3 cells against `_workspace/01-competitors.md`:
   - Wispr Flow $12-15/mo ✓
   - Superwhisper $8.49/mo + paid lifetime ✓ (with footnote re flux)
   - MacWhisper $69-80 lifetime ✓ (with footnote re vendor-page variance)
7. **Copy consistency** — "macOS" used consistently (14 hits); no "Mac OS" or "MAC" regressions. Push-to-talk / hotkey references all say `Option + Space` / `⌥ Space`.
8. **Keycap rendering** — all 8 in-line hotkey mentions use `<span class="kbd-combo"><span class="sr-only">Option plus Space</span><kbd class="keycap keycap--inline" aria-hidden="true">&#8997;</kbd><kbd class="keycap keycap--inline" aria-hidden="true">Space</kbd></span>`. SR reads "Option plus Space" once; visual shows the keycaps. `&#8997;` (⌥) is correctly encoded; no double-escape.
9. **Footnote integrity** — 3 `<li id="fn-N">` anchors targeted by 6 `<sup><a href="#fn-N" id="fn-N-ref-[a|b]">` backrefs. All resolved.

### B. License / README alignment

10. No LICENSE file exists (`git ls-files | grep -i license` returns empty). README.md does not contain the word "License" or "MIT". Adjusted footer to generic "Open source on GitHub" per T12 brief rule. Logged D1 follow-up.
11. README headline claims match the page: hotkey `⌥ Space` ✓, "macOS 14 or later" / "Apple Silicon recommended" ✓, "WhisperKit (OpenAI Whisper) and FluidAudio (Parakeet)" ✓.

### C. GitHub Pages readiness

12. `.nojekyll` present (0 bytes, correct). ✓
13. `_workspace/` will be served (since Jekyll is disabled, nothing strips `_`-prefixed folders). Per T12 brief recommendation, left briefings public and added `_workspace/README.md` as an index/explainer.
14. All image/asset paths relative: `demo.gif`, `favicon.svg`, `styles.css`, `script.js`. No `/docs/` prefix leaks.

### D. Performance sanity

15. Inline critical CSS: lines 56-186, ~130 lines, ~13 KB raw / ~2-3 KB gzipped. Within spec (≤8-10 KB gzipped budget).
16. `<script src="script.js" defer>` present on line 1062 (below body). ✓
17. `demo.gif` has `width="1280" height="800"` + `loading="lazy"` + `decoding="async"`. ✓

### E. Accessibility sanity

18. Landmark walk: skip-link → `<header class="nav">` → `<main id="main">` → `<footer id="footer">`. `<h1>` in hero (single). `<h2>` per section (10 total, including sr-only on proof + footer). `<h3>` for cards / steps / FAQ questions. No level skip. Focus order matches visual.
19. Critical CSS inlines the T11 contrast tokens verbatim (`--color-text-muted: #8A8A94`, `--color-accent: #007A98` in light block). Not overridden.
20. `<main id="main">` exists (line 390), target for skip link.

---

## 5. Final file-size table (production files)

| File | Size | Notes |
|---|---:|---|
| `docs/index.html` | 70,086 B (68.4 KB) | Includes 2 JSON-LD blocks and inline critical CSS (~13 KB). Compresses to ~13-15 KB gzipped. |
| `docs/styles.css` | 35,306 B (34.5 KB) | External stylesheet loaded async. ~7-8 KB gzipped. |
| `docs/script.js` | 2,761 B (2.7 KB) | Vanilla JS, deferred. Handles sticky nav, reveal-on-scroll, data-copy. |
| `docs/favicon.svg` | 432 B | Inline-referenced. |
| `docs/robots.txt` | 84 B | Allow-all + sitemap pointer. |
| `docs/sitemap.xml` | 282 B | Single-URL sitemap for homepage. |
| `docs/demo.gif` | 685,287 B (669 KB) | Dominant asset — see D3 follow-up for WebM conversion. |
| `docs/.nojekyll` | 0 B | Disables Jekyll on GH Pages. |
| **Production total** | **794,238 B (~776 KB)** | Of which `demo.gif` is 86%. |

Workspace briefings (`_workspace/*.md`) are ~186 KB combined; not counted as production.

---

## 6. Ship gate checklist

- [x] HTML parses
- [x] All internal anchors resolve
- [x] External URLs sensible (one deferred — D1 license 404 until LICENSE committed)
- [x] SEO metadata coherent
- [x] JSON-LD valid + matches visible FAQ
- [x] A11y WCAG 2.2 AA (per T11)
- [x] Perf budgets met (per T10)
- [x] No stray team-role markers in shipped HTML/CSS
- [x] `_workspace/README.md` present
- [ ] `LICENSE` file committed to repo root (D1, pre-publish)
- [ ] `og-image.png` added to `docs/` (D2, pre-publish)

**Verdict: SHIP.** D1 and D2 are pre-publish chores for the repo owner and can land in the same commit that enables GitHub Pages.
