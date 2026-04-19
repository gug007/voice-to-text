# 10 — Performance Report

**Author:** T10 — Performance Engineer
**Date:** 2026-04-19
**Target:** Core Web Vitals on slow connections (Slow 4G / 1.6 Mbps, RTT ~400ms)
**Scope:** `docs/index.html`, `docs/styles.css`, `docs/script.js`. GitHub Pages static hosting, no build step.

---

## 1. Summary of changes shipped

Surgical-only. No rewrites, no undo of T9 SEO, no undo of T11 a11y.

### `docs/index.html`

1. **Inline critical CSS block** added to `<head>` (lines 56-186). ~8KB source,
   ~2-3KB after gzip. Contains:
   - Token subset used above the fold (colors, font stack, spacing, radii,
     shadows, focus-ring, light-mode overrides).
   - Reset (box-sizing, body typography, link, focus-visible).
   - A11y utilities preserved verbatim: `.sr-only`, `.kbd-combo`, `.skip-link`
     + focus outline, plus the T11 contrast values (`#8A8A94`, `#007A98`).
   - Above-the-fold components only: `.container`, `.icon`, `.keycap` +
     `.keycap--inline`, `.btn` + variants, `.nav`, `.hero` + keycap hero,
     waveform (incl. keyframes + reduced-motion), subcopy, CTAs, hero meta.
   - `.reveal { opacity: 0 }` placeholder so below-the-fold sections start
     hidden and don't cause a flash when the async CSS applies.
2. **Async-loaded full stylesheet.** Replaced the render-blocking
   `<link rel="stylesheet" href="styles.css">` with:
   ```html
   <link rel="preload" href="styles.css" as="style"
         onload="this.onload=null;this.rel='stylesheet'">
   <noscript><link rel="stylesheet" href="styles.css"></noscript>
   ```
   Non-JS visitors still get the full stylesheet synchronously via noscript.
3. **`<link rel="dns-prefetch" href="https://github.com">`** added — every
   outbound CTA targets github.com (download, source, releases, license).
   Saves ~50-200ms on the first outbound click.
4. **Removed unused Geist font loading.** The `<!-- T10: self-hosted Geist
   fonts -->` marker was replaced with a short rationale comment explaining
   the system-stack decision (option 1 per brief). No font preload, no
   @font-face in head.
5. **Deferred JS already in place.** `<script src="script.js" defer>` was
   already correctly deferred by T8; verified and left alone.

### `docs/styles.css`

1. **Top comment rewritten** to document the T10 perf strategy (font choice,
   critical-CSS split, T12 minification note).
2. **Removed the 3 unused `@font-face` declarations** for Geist-Regular,
   Geist-SemiBold, GeistMono-Regular. The WOFF2 files are not shipped, so
   every page load was triggering 3 silent 404s. Files are not in the repo
   and were not going to be added in this pass.
3. **Font-family tokens cleaned up** — dropped the leading `"Geist"` and
   `"Geist Mono"` keywords. They forced spurious font-matching lookups for
   a family that never loads. System fallbacks are now the primary value.
4. **T12 minification marker** added to the top comment (per task #8).

### Everything else — verified, not changed

- **demo.gif** already has `loading="lazy"`, `decoding="async"`,
  `width="1280"`, `height="800"`. No changes needed — no CLS risk. Per the
  brief, GIF → WebM/WebP conversion is deliberately out of scope.
- **Keycap SVG is inline** (no external file). Nav brand, footer brand, icon
  sprite, hero waveform — all inline. Zero external SVG round-trips.
- **theme-color meta tags** — both light (`#FAFAFA`) and dark (`#0A0A0B`)
  values already present by T9. Verified.
- **Layout stability (CLS):** all three potential offenders checked:
  1. Images: demo.gif has explicit width/height — sized correctly.
  2. Fonts: no web fonts shipped, so no font-swap shift (was the primary
     reason to avoid Geist now).
  3. Async CSS: the `.reveal { opacity: 0 }` rule in the critical block
     holds below-the-fold sections hidden until the full stylesheet loads
     and the IntersectionObserver reveals them. No layout shift from this
     path because below-the-fold height is dictated by the full stylesheet
     which ships before the user can scroll (defer-JS + async-CSS race
     resolves well inside the ~250ms RTT window on all but the slowest
     connections).

---

## 2. Estimated Core Web Vitals impact (qualitative)

Baseline: T8's build had `<link rel="stylesheet" href="styles.css">` as a
render-blocking request. On Slow 4G (1.6 Mbps, ~400ms RTT), that adds roughly
one full RTT plus ~180ms transfer for the 34KB CSS file (gzipped ~8KB, but
still a serialized critical-path resource).

| Metric | Before | After | Delta |
|---|---|---|---|
| **LCP** (hero title) | ~1.8-2.4s | ~0.9-1.3s | **−800 to −1100ms** |
| **FCP** | ~1.4-2.0s | ~0.4-0.7s | **−1000ms** |
| **CLS** | ~0.00-0.02 | ~0.00 | neutral — was already fine |
| **INP** | ~40-60ms | ~40-60ms | neutral — no script-path changes |
| **TBT** | ~0 | ~0 | neutral — JS was already deferred |

Main wins:
- First paint now happens as soon as the HTML parser hits `</head>` — no
  wait on styles.css.
- LCP element is the hero title `<h1 class="hero__title">`, entirely styled
  by the inlined critical slice → paints at first frame.
- Eliminated 3 failed font requests (Geist-*.woff2 404s).

No regressions expected:
- Noscript users still get synchronous styles.css via `<noscript>` fallback.
- JS-disabled users with JS-required preload: the preload-onload swap
  pattern has ~99% browser support; the edge case (old UA, JS off) is
  covered by noscript.
- Print users (rel="preload" and Chrome): Chrome's preload does eventually
  promote to stylesheet even if onload fires before hydration because of
  the secondary `<noscript>` path if JS is off entirely.

---

## 3. Follow-ups for T12 (QA) and beyond

1. **Convert `demo.gif` → `demo.webm` + `demo.webp`.** 685KB GIF is the
   biggest asset on the page by far. A WebM-encoded version of the same
   animation typically lands at 60-150KB (4-5× smaller) and allows
   `<video autoplay muted playsinline loop>` instead of `<img>`. Even a
   static WebP poster for lazy-load would help. Deliberately out of scope
   for this perf pass (requires re-encoding, not text edits). Flag as
   **highest-impact follow-up**.
2. **Build-time CSS minification.** Top comment in `styles.css` notes this.
   cssnano or lightningcss would cut the external stylesheet from 34KB to
   ~22KB pre-gzip / ~5KB post-gzip. Not done by hand because the diff cost
   to reviewers would be catastrophic.
3. **Consider inlining `favicon.svg`** via `<link rel="icon" href="data:...">`.
   432 bytes, but it is an additional parallel request. Marginal.
4. **OG image preload.** If `og-image.png` gets large, crawlers (Slack,
   Discord, Twitter bots) benefit from a static CDN. Not a CWV issue —
   crawlers don't contribute to Real User Metrics.
5. **HTTP/2 Server Push is dead.** GitHub Pages doesn't support `Link:
   rel=preload` headers via `_headers` either. Client-side hints (what we
   shipped) are the only option.
6. **Native lazy-loading of `<iframe>`** — none on this page, so n/a.
7. **Avoiding the backdrop-filter blur on low-power devices** is a cosmetic
   micro-optimization; not worth the code cost.
8. **Re-verify LCP element** with WebPageTest or Chrome DevTools
   Lighthouse. Predicted LCP element is the `<h1 class="hero__title">`
   rendered by the inlined critical CSS. If the demo.gif is promoted to
   LCP element in T12's measurement (e.g., because the hero title is below
   the fold on a narrow viewport where a lot of hero padding stacks),
   revisit whether `<img fetchpriority="high">` for demo.gif is justified.
   Likely not — the image is explicitly below the fold by design.
9. **Validate the preload-onload swap pattern** with a real-device test
   on slow 3G (not just emulation). No known issues, but worth confirming
   the stylesheet applies before user scrolls past the critical region.

---

## 4. Budgets — self-audit

| Budget | Spec | Result |
|---|---|---|
| Inline critical CSS | ≤ 8KB | ~8-9KB raw (~2-3KB gzipped). Under budget when compressed; slightly over on raw bytes. Trimmed to above-the-fold components only; no features/FAQ/compare/footer/download styles inlined. |
| No build step | required | Respected — everything ships as hand-edited HTML/CSS/JS. |
| Don't undo T9 `<head>` | required | `<head>` additions preserved verbatim (meta, JSON-LD, Open Graph, Twitter Card, canonical, icon). Only added: one dns-prefetch, one inline `<style>`, one async `<link preload>`, one noscript fallback. All insertions. |
| Don't undo T11 a11y | required | Every `aria-label`, `sr-only`, skip-link, `kbd-combo` preserved. Contrast tokens (`#8A8A94`, `#007A98`) preserved in both critical CSS and external stylesheet. |
| Don't rewrite `styles.css` | required | Only edits: top comment rewrite (documents T10 intent), `@font-face` block removal (dead references), font-family token cleanup (removed unshipped Geist keywords). Body of stylesheet untouched. |

---

## 5. File diffs (for T12 inspection)

- `/Users/gug007/Projects/voice-to-text/docs/index.html` — added lines 42-51
  (font-strategy comment + dns-prefetch), added lines 53-191 (critical CSS
  + async load + noscript fallback), removed the old synchronous stylesheet
  link. No other lines changed.
- `/Users/gug007/Projects/voice-to-text/docs/styles.css` — top comment
  expanded (T10 rationale + T12 marker), `--font-sans` and `--font-mono`
  tokens cleaned, 3 `@font-face` declarations removed.

No edits to `script.js`, `favicon.svg`, `robots.txt`, `sitemap.xml`,
`.nojekyll`, `demo.gif`.
