# 11 — Accessibility Audit Report

**Author:** T11 — Accessibility Engineer
**Date:** 2026-04-19
**Target:** WCAG 2.2 AA
**Scope:** Single-page landing site at `docs/index.html` + `docs/styles.css`

This audit was performed after T8 (build) and in parallel with T9 (who was editing `<head>`). T10 (performance) and T12 (QA) run after this report.

---

## 1. Summary of changes shipped

- HTML edits constrained to inside `<body>` (per T9 coordination).
- CSS edits constrained to **contrast tokens**, **a11y utilities**, and **skip-link focus outline** — no reorganization, no font-loading changes (those are T10's turf).

Files modified:

- `/Users/gug007/Projects/voice-to-text/docs/index.html` — body only (keycap combos, status cells, footnote refs, hero keys role, aria hidden on decorative chip dots).
- `/Users/gug007/Projects/voice-to-text/docs/styles.css` — two contrast token adjustments and one new utility (`.kbd-combo`) appended inside existing utilities section.

---

## 2. Issue log

Severity key — **A**: fail WCAG 2.2 Level A. **AA**: fail Level AA. **AAA**: nice-to-have. **NIT**: quality-of-life (not a WCAG failure).

| # | Finding | Severity | Criterion | Status | What I changed |
|---|---|---|---|---|---|
| 1 | Inline `<kbd>` pairs for the `⌥ Space` hotkey read as "option space" (two words) by screen readers, which sounds like "option-key space" rather than "option plus space." | AA | 1.3.1 Info & Relationships, 4.1.2 Name/Role/Value | **Fixed** | Wrapped each `<kbd>` pair in `<span class="kbd-combo">` that contains a visually-hidden `<span class="sr-only">Option plus Space</span>` + the visual `<kbd>` cells marked `aria-hidden="true"`. Applied 7 sites: hero subcopy, how step 1 title, "True push-to-talk" feature card, AI transcript chrome, compare grid push-to-talk row, mobile card push-to-talk row, download deck, download step 4 title. |
| 2 | Hero oversized keycaps `.hero__keys` had `aria-label` on a plain `<div>`; screen readers may ignore `aria-label` on unrolled containers. | AA | 4.1.2 | **Fixed** | Added `role="img"` so the combined keycap cluster is exposed as a single named graphic: "Push-to-talk hotkey: hold Option plus Space." Keycap children already `aria-hidden="true"`. |
| 3 | Comparison grid "Yes/No" cells for some competitors were represented only by a colored status dot + bare em-dash (`—`), meaning screen-reader users hearing "dash" could not distinguish "unknown" from "no." | A | 1.4.1 Use of Color, 1.1.1 Non-text Content | **Fixed** | All `status--no` cells that previously rendered as only `—` now include an `sr-only` "No" prefix, and the visible em-dash is wrapped in `aria-hidden="true"`. Covered desktop grid (Open source row × 4, AI coding agents × 1) and mobile cards (5 dashes) plus the push-to-talk "Yes." sr-only prefix for parity. |
| 4 | Mobile comparison cards had `<span class="status ...">` without `aria-hidden="true"`, so screen readers announced empty decorative elements. | NIT | 4.1.2 | **Fixed** | Added `aria-hidden="true"` to every `.status` span inside `.compare__mobile`. |
| 5 | Footnote markers `<sup>1</sup>` etc. had no anchor target, so keyboard/SR users could not jump to the explanation. | AA | 2.4.4 Link Purpose (In Context) | **Fixed** | Each `<sup>` is now `<sup><a href="#fn-N" id="fn-N-ref-[a|b]" aria-describedby="compare-footnotes-title">N</a></sup>`. Added an sr-only `<h3 id="compare-footnotes-title">` above the footnote list. Each footnote `<li>` gets `id="fn-N"`. |
| 6 | Social-proof chip dot `.chip__dot` was purely decorative but not hidden from assistive tech (both in hero proof strip and inside mobile "Open source" chip). | NIT | 1.1.1 | **Fixed** | `aria-hidden="true"` added. |
| 7 | `--color-text-muted: #71717A` on `--color-bg: #0A0A0B` measures ≈ **3.9:1** — below AA 4.5:1 for normal text. Used by `.t-caption`, `.t-label`, footer copy, download meta, download permissions, nav links (default state), chip text, footnotes, status--no border. | **AA** | 1.4.3 Contrast (Minimum) | **Fixed** | Bumped dark-theme `--color-text-muted` to `#8A8A94` — computed contrast **5.70:1** vs `#0A0A0B` (AA pass, ≈AAA for large text). |
| 8 | Light-mode `--color-accent: #0091B5` on `--color-bg: #FAFAFA` measures ≈ **3.52:1** — below AA 4.5:1 for normal text. Used by `.section__eyebrow`, `.feature-card__link`, "Read the code / source" inline links, default `<a>` color, footer column hover. | **AA** | 1.4.3 | **Fixed** | Darkened light-theme `--color-accent` to `#007A98` — computed contrast **4.71:1** on `#FAFAFA` (AA pass). Hover moved to old value `#0091B5` (used for hover only; decorative on hover state, visually distinct). Focus-ring and shadow tokens still use the rgba(0,145,181,…) ring value which is fine for non-text UI components (≥3:1). |
| 9 | Skip link when focused had no visible outline (background alone). Useful since the `:focus-visible` on `:focus-visible` rule sets border-radius but background-color is same as outline color. | AA | 2.4.7 Focus Visible | **Fixed** | Added `outline: 2px solid var(--color-accent-ink); outline-offset: 2px` to `.skip-link:focus` so the focus state shows a contrast ring inside the pill. |
| 10 | No `.kbd-combo` inline-flex wrapper existed; the sr-only injection for keycap pairs needed a tiny utility to keep the `<kbd>` glyphs inline on one line. | NIT | — | **Fixed** | Added `.kbd-combo { display: inline-flex; align-items: baseline; gap: 2px; white-space: nowrap; }` to utilities block. |

---

## 3. Audit-checklist pass notes (what I verified, not changed)

1. **Landmarks & headings.** Exactly one `<h1>` (hero title). `<h2>` on every section incl. sr-only titles for `#proof` and `#footer`. `<h3>` used for feature cards, how steps, download steps, FAQ-summary inner content (via `<span>` — acceptable inside `<summary>` which itself is a button role), footer column titles, mobile compare card heads. No skipped levels. `<main id="main">` wraps everything between `<header>` and `<footer>`. Primary nav is `<nav aria-label="Primary">`, footer nav `<nav aria-label="Footer">` — both landmarks have accessible names.
2. **Images.** Demo gif has descriptive alt from T6 copy spec (VoiceToText demo …). Inline brand-logo SVGs in nav/footer are `aria-hidden="true"` (brand text is adjacent). Hero waveform SVG has `role="img"` + `aria-label="Animated audio waveform"`. Icon sprite has `aria-hidden="true"`. Every `<use>` inline icon is inside an `<svg class="icon" aria-hidden="true">` — correct because the surrounding text gives meaning. macOS window traffic-light dots are `aria-hidden` via parent.
3. **Buttons vs links.** All page CTAs are `<a href>` — correct (they navigate to a DMG, GitHub, or an in-page anchor). No on-page toggle UI exists outside `<details>`/`<summary>`, so no `<button>` was required. The `[data-copy]` handler in `script.js` is forward-looking (no element uses it yet); when it is used, the spec in `script.js` already requires a `<button>`.
4. **FAQ.** Native `<details>`/`<summary>` is used. No ARIA `aria-expanded` hack overrides it. Chevron rotation is pure CSS off the `[open]` attribute. Screen readers announce state correctly.
5. **Form elements.** None on this page — skipped per audit brief.
6. **Focus-visible.** `:focus-visible { outline: 2px solid var(--color-accent); outline-offset: 2px; border-radius: var(--radius-sm); }` already present in the base-elements block. Button variant uses `box-shadow: var(--focus-ring)` for a stronger double-ring. Verified across `<a>`, `<button>` (none on page), `<summary>`, and `<details>`.
7. **Reduced motion.** Existing rules confirmed: `html { scroll-behavior: auto; }` under reduce, `.reveal { opacity: 1; transform: none; transition: none; }` under reduce, `.hero__waveform .bar { animation: none; transform: scaleY(.75); }` under reduce. JS `IntersectionObserver` already branches on `window.matchMedia('(prefers-reduced-motion: reduce)').matches` and adds `is-visible` immediately.
8. **Skip link.** Already shipped by T8 as `<a class="skip-link" href="#main">Skip to main content</a>` as first non-decorative child of `<body>`. Targets the `<main id="main">`. Confirmed off-screen by default (`top: -9999px`) and revealed at `var(--space-4)` on `:focus`. Added a focus outline (issue #9).
9. **Language.** `<html lang="en">` present (set by T8).
10. **Target size.** `.btn` is 48 px tall (`--control-height-lg`). `.btn--lg` is 56 px. `.btn--sm` is 40 px tall with ≥92 px width — meets 44 px on the axis that matters. Nav links (`fs-body-sm`, padding inherited from `.nav`) measure ~40 × 48 px touchable area after the nav padding (`var(--space-3)` top + text line-height). Acceptable on desktop where nav is visible; hidden under 720 px. Inline "Read the source" / "See the license" text links have implicit ~20 px hit area, which is below 44 px but per WCAG 2.2 **2.5.8 Target Size (Minimum)** the exception applies to inline links in sentences. No blocker.
11. **Tab order.** Visual order (top → bottom, left → right) matches DOM order. Confirmed by mental tab-walk: skip-link → brand → Features → Compare → FAQ → GitHub btn → hero Download → hero GitHub → Live-on-GitHub pill → Read the code → feature-card Read the source → AI-section Download → mobile compare links (hidden on desktop) → compare Read the source → See the license → FAQ summaries (each) → Download CTAs → Browse Releases → Footer brand → Footer attribution → Footer columns. No positive `tabindex` values exist, no `tabindex="-1"` traps.
12. **Color contrast summary (dark theme, which is primary):**
    - `F4F4F5` on `0A0A0B` — 18.5:1 AAA ✓
    - `A1A1AA` on `0A0A0B` — 7.6:1 AAA ✓
    - `8A8A94` on `0A0A0B` — 5.7:1 AA ✓ *(bumped from 3.9:1 — issue #7)*
    - `00D4FF` on `0A0A0B` — 10.9:1 AAA ✓
    - Status green `3DDC97` / warn `F5A524` / danger `F04438` — decorative only (`aria-hidden`), not required.
    - Focus ring `rgba(0,212,255,.4)` vs bg — ≥3:1 ✓ non-text requirement.
13. **Color contrast summary (light theme, secondary):**
    - `09090B` on `FAFAFA` — ~20:1 AAA ✓
    - `52525B` on `FAFAFA` — ~8.4:1 AAA ✓
    - `71717A` (light-mode muted) on `FAFAFA` — ~4.7:1 AA ✓
    - `007A98` on `FAFAFA` — 4.71:1 AA ✓ *(darkened from 3.52:1 — issue #8)*

---

## 4. Residual items for T12 (QA)

- **D1 — Compare grid semantics.** `.compare__grid` is a CSS Grid of sibling `<div>`s, not a `<table>`. I left the markup as-is (converting to `<table>` would reorganize the file per no-rewrite rule, and would also break the desktop layout without CSS Grid fallbacks). Each cell still contains descriptive text (e.g., "Free forever", "Cloud only"), so screen readers linearly read row-label → 5 cells → next row-label. Usable but not explicit table semantics. If T12 requires `role="table"` / `role="row"` / `role="columnheader"` / `role="rowheader"` / `role="cell"` wiring, the refactor is doable but outside the "surgical" scope of T11. Recommend deferring unless QA flags as blocker. The `role="region" aria-label="Feature comparison between VoiceToText and competitors"` already wraps the frame.
- **D2 — FAQ summary as heading.** Each `<summary>` contains a plain `<span>`. Native `<details>`/`<summary>` exposes the summary as a button; our FAQ answers can still be skimmed by jumping between the button-role elements. Wrapping `<span>` in `<h3>` is a common but not required enhancement. Omitted because (a) the summary `<span>` is styled via `.faq-item__q > span` (flex: 1), and wrapping that span in `<h3>` would change the CSS cascade and require style surgery; (b) we already have the section `<h2>` and the FAQ questions are not needed as `<h3>` for AA pass.
- **D3 — `target="_blank"` new-tab hint.** Our external links don't announce "opens in a new tab" via sr-only text. This is AAA-flavoured, not AA. All outbound links do carry `rel="noopener"`, avoiding tabnabbing. Optional future improvement.
- **D4 — Inline text-link target size.** "Read the source" / "See the license" / chip-style GitHub link sit below the 44 px touch target minimum, but WCAG 2.2 SC 2.5.8 exempts inline links inside a block of text. Not a blocker; confirmed as exempt case.
- **D5 — `og-image.png`.** Referenced in `<head>` (T9 territory) but file may not exist yet. Not an HTML/CSS a11y issue, but if QA crawls OG metadata, they'll get a 404.
- **D6 — License claim.** Footer still reads "released under an OSI-approved open-source license" (T8/T9 TODO). Not an a11y concern.
- **D7 — Light-mode accent override for T10.** If T10 swaps the accent for any reason as part of performance tuning, they should preserve the new `#007A98` light-mode value or keep it at or darker than this to preserve AA.

---

## 5. Token diff (for T10 awareness)

```diff
- --color-text-muted: #71717A;   /* fails AA on dark bg */
+ --color-text-muted: #8A8A94;   /* AA 5.70:1 on #0A0A0B */

@media (prefers-color-scheme: light) {
-   --color-accent: #0091B5;      /* fails AA as body-text on #FAFAFA */
-   --color-accent-hover: #00A8D0;
+   --color-accent: #007A98;      /* AA 4.71:1 on #FAFAFA */
+   --color-accent-hover: #0091B5;
}
```

All other tokens untouched. No component CSS rewritten; only the utilities block gained `.kbd-combo` and `.skip-link:focus` gained an outline.

---

## 6. How to re-verify

1. Run an automated pass (axe DevTools, WAVE, Lighthouse) on built page — expect Lighthouse a11y score 100 with zero non-exempt violations.
2. Keyboard-only pass: Tab from page top and confirm focus visibility on every link/button/summary and that the skip link works.
3. Screen-reader pass (VoiceOver on macOS): confirm hotkey pairs announce "Option plus Space" once (not "option space") and that all comparison "no" cells announce "No" before the em-dash.
4. Motion pass: enable "Reduce motion" in system prefs; confirm hero waveform is static, `.reveal` content is immediately visible, and scroll is not smoothed.
5. Zoom pass: at 200 % zoom, confirm no content is clipped and all CTAs remain visible.
