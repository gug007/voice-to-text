# 07 — Design System Spec (T7 → T8)

**Author:** T7 — Visual Designer
**Date:** 2026-04-19
**For:** T8 Lead Developer. Consumes: `04-design-trends.md` (T4), `01-competitors.md` (T1), `03-audience.md` (T3), `README.md`.
**Purpose:** A fully implementable design system. Copy CSS blocks as-is into `styles.css`. Component sections specify markup + class names + behaviour. Almost zero invention should be required at implementation time.

---

## 0. Validation of T4 Direction

**Verdict: shipping T4's direction as-is, with three small refinements.**

Kept as specified:
- Dark-first (`#0A0A0B` bg), one cyan accent (`#00D4FF`), one cyan→indigo gradient reserved for the primary Download CTA.
- Geist Sans + Geist Mono (self-hosted, `font-display: swap`, preload Regular + SemiBold of Sans + Regular of Mono).
- Hero centred on a large `⌥ Space` keycap pair with an ambient CSS/SVG waveform; demo.gif lives below the hero inside a macOS window chrome.
- Card-style opinionated comparison table with cyan top-glow on the VoiceToText column and colored status glyphs (not check/X).
- Motion: subtle fade + translate-Y on scroll; single continuous waveform; respect `prefers-reduced-motion`.

Refinements (minor, justified):
1. **Added a `prefers-color-scheme: light` token set.** T4's doc is dark-first (correct for primary), but browsers on developer laptops increasingly respect system preference, and Apple's own macOS docs pages adapt. A secondary light theme is cheap (it reuses every token name) and signals polish. It is **not** a marketed mode — no toggle — it just graces light-mode visitors.
2. **Renamed T4's `text-tertiary` → `text-muted`** in the token namespace to match the naming the user requested in the brief. Semantics identical. Adds `text-tertiary` as an alias for T4 continuity.
3. **Added semantic `success / warn / danger` tokens** (T4 listed them; I'm formalising hex + dark/light pairs so they survive theme flip without re-specifying).

No other overrides. T4's direction ships.

---

## 1. Design Tokens (CSS Custom Properties)

All tokens live in `:root`. The full stylesheet assumes `box-sizing: border-box` and a CSS reset (see §12).

### 1.1 Full token block — paste into top of `styles.css`

```css
/* =========================================================================
   VoiceToText — Design Tokens
   Dark-first. Light theme inherits and overrides via prefers-color-scheme.
   ========================================================================= */

:root {
  /* ---- Color — Surfaces & Chrome -------------------------------------- */
  --color-bg:                #0A0A0B;              /* page background */
  --color-surface:           #121214;              /* cards, nav, tables */
  --color-surface-elevated:  #17171A;              /* hover on surface */
  --color-surface-sunken:    #070708;              /* rare — inside code blocks */
  --color-border:            #1F1F24;              /* hairline 1px */
  --color-border-strong:     #2A2A31;              /* emphasised / focus */

  /* ---- Color — Text ---------------------------------------------------- */
  --color-text-primary:      #F4F4F5;
  --color-text-secondary:    #A1A1AA;
  --color-text-muted:        #71717A;
  --color-text-tertiary:     #71717A;              /* alias for T4 compat */

  /* ---- Color — Brand accent -------------------------------------------- */
  --color-accent:            #00D4FF;              /* cyan, brand */
  --color-accent-hover:      #33DDFF;
  --color-accent-muted:      rgba(0, 212, 255, 0.12);   /* chip bg, glow fills */
  --color-accent-subtle:     rgba(0, 212, 255, 0.06);   /* hero radial halo tail */
  --color-accent-ring:       rgba(0, 212, 255, 0.40);   /* focus ring, top-glow */
  --color-accent-ink:        #001014;              /* text on solid accent */

  /* The one and only brand gradient. Used ONCE on primary CTA. */
  --color-accent-gradient:
    linear-gradient(135deg, #00D4FF 0%, #7B8CFF 100%);
  --color-accent-gradient-hover:
    linear-gradient(135deg, #33DDFF 0%, #92A0FF 100%);

  /* Hero radial glow — placed behind headline, fades to page bg. */
  --color-hero-glow:
    radial-gradient(60% 50% at 50% 20%,
      rgba(0, 212, 255, 0.12) 0%,
      rgba(0, 212, 255, 0.00) 70%);

  /* ---- Color — Semantic (status cells in comparison table) ------------- */
  --color-success:           #3DDC97;
  --color-success-muted:     rgba(61, 220, 151, 0.12);
  --color-warn:              #F5A524;
  --color-warn-muted:        rgba(245, 165, 36, 0.12);
  --color-danger:            #F04438;
  --color-danger-muted:      rgba(240, 68, 56, 0.12);

  /* ---- Typography — Families ------------------------------------------- */
  --font-sans:
    "Geist", "Inter", ui-sans-serif, -apple-system, BlinkMacSystemFont,
    "Segoe UI", Helvetica, Arial, sans-serif;
  --font-mono:
    "Geist Mono", "JetBrains Mono", ui-monospace, "SF Mono", Menlo,
    Consolas, monospace;

  /* ---- Typography — Scale (fluid, clamp-based) ------------------------- */
  --fs-display-1:  clamp(56px, 8vw,  96px);   /* hero headline */
  --fs-display-2:  clamp(44px, 6vw,  72px);   /* rare — press-pull */
  --fs-display-3:  clamp(40px, 5vw,  64px);   /* section headlines */
  --fs-display-4:  clamp(28px, 3vw,  40px);   /* sub-sections */
  --fs-h1:         clamp(32px, 4vw,  48px);
  --fs-h2:         clamp(24px, 2.6vw, 32px);
  --fs-h3:                 20px;
  --fs-h4:                 17px;
  --fs-body-lg:            20px;
  --fs-body-md:            17px;
  --fs-body-sm:            15px;
  --fs-caption:            13px;
  --fs-code:               14px;

  /* ---- Typography — Line heights --------------------------------------- */
  --lh-display:  1.02;
  --lh-heading:  1.1;
  --lh-body:     1.6;
  --lh-tight:    1.3;
  --lh-caption:  1.45;

  /* ---- Typography — Letter spacing ------------------------------------- */
  --ls-display:  -0.022em;    /* tighten large type */
  --ls-heading:  -0.01em;
  --ls-body:      0;
  --ls-label:     0.04em;     /* uppercase eyebrow */
  --ls-mono:     -0.01em;     /* Geist Mono at small sizes */

  /* ---- Typography — Weight --------------------------------------------- */
  --fw-regular:  400;
  --fw-medium:   500;
  --fw-semibold: 600;
  --fw-bold:     700;

  /* ---- Spacing (8px base) ---------------------------------------------- */
  --space-0:    0;
  --space-1:    4px;
  --space-2:    8px;
  --space-3:    12px;
  --space-4:    16px;
  --space-5:    20px;
  --space-6:    24px;
  --space-8:    32px;
  --space-10:   40px;
  --space-12:   48px;
  --space-16:   64px;
  --space-20:   80px;
  --space-24:   96px;
  --space-32:   128px;
  --space-40:   160px;       /* section vertical padding desktop */

  /* ---- Layout — Container widths --------------------------------------- */
  --container-sm:   640px;
  --container-md:   768px;
  --container-lg:  1024px;
  --container-xl:  1200px;   /* default page content max-width */
  --container-2xl: 1440px;
  --page-gutter:   24px;     /* mobile gutter; see §6 for bp overrides */

  /* ---- Radii ----------------------------------------------------------- */
  --radius-sm:    6px;       /* chips, small pills */
  --radius-md:    10px;      /* buttons, inputs */
  --radius-lg:    14px;      /* feature cards */
  --radius-xl:    20px;      /* comparison table, macOS chrome */
  --radius-full:  9999px;    /* round pill */

  /* ---- Shadows --------------------------------------------------------- */
  --shadow-sm:
    0 1px 2px 0 rgba(0, 0, 0, 0.35);
  --shadow-md:
    0 4px 12px -2px rgba(0, 0, 0, 0.45),
    0 2px 4px -1px rgba(0, 0, 0, 0.30);
  --shadow-lg:
    0 20px 40px -12px rgba(0, 0, 0, 0.55),
    0 6px 16px -6px rgba(0, 0, 0, 0.35);

  /* Hero CTA glow — cyan, only on primary button + focus ring. */
  --shadow-cyan-glow:
    0 0 0 1px rgba(0, 212, 255, 0.25),
    0 8px 28px -4px rgba(0, 212, 255, 0.45),
    0 2px 6px -1px rgba(0, 0, 0, 0.50);
  --shadow-cyan-glow-hover:
    0 0 0 1px rgba(0, 212, 255, 0.40),
    0 12px 36px -4px rgba(0, 212, 255, 0.55),
    0 2px 6px -1px rgba(0, 0, 0, 0.50);

  /* macOS window chrome shadow — softer, neutral. */
  --shadow-macos:
    0 40px 80px -20px rgba(0, 0, 0, 0.60),
    0 12px 28px -8px rgba(0, 0, 0, 0.45),
    0 2px 6px -1px rgba(0, 0, 0, 0.30);

  /* ---- Motion — Durations ---------------------------------------------- */
  --duration-instant: 80ms;    /* micro (e.g. active press) */
  --duration-fast:    150ms;   /* hover, small state flips */
  --duration-base:    250ms;   /* default transitions */
  --duration-slow:    450ms;   /* on-scroll entrance */
  --duration-ambient: 2000ms;  /* waveform loop period */

  /* ---- Motion — Easings ------------------------------------------------ */
  --ease-standard:  cubic-bezier(0.4, 0.0, 0.2, 1);    /* generic */
  --ease-enter:     cubic-bezier(0.2, 0.8, 0.2, 1);    /* spring-out on entry */
  --ease-exit:      cubic-bezier(0.4, 0.0, 1.0, 1);    /* accelerate on exit */
  --ease-linear:    linear;                             /* for the waveform only */

  /* ---- Z-index scale --------------------------------------------------- */
  --z-base:      0;
  --z-raised:    10;
  --z-dropdown:  100;
  --z-sticky:    200;
  --z-nav:       300;
  --z-overlay:   400;
  --z-modal:     500;
  --z-toast:     600;

  /* ---- Opacity --------------------------------------------------------- */
  --opacity-disabled: 0.5;

  /* ---- Form element sizing --------------------------------------------- */
  --control-height-sm:  32px;
  --control-height-md:  40px;
  --control-height-lg:  48px;   /* primary button */

  /* ---- Focus ring ------------------------------------------------------ */
  --focus-ring:
    0 0 0 2px var(--color-bg),
    0 0 0 4px var(--color-accent-ring);
}

/* =========================================================================
   Light-theme overrides (secondary; no UI toggle, respects system only).
   All other tokens inherit from :root unchanged.
   ========================================================================= */

@media (prefers-color-scheme: light) {
  :root {
    --color-bg:                #FAFAFA;
    --color-surface:           #FFFFFF;
    --color-surface-elevated:  #F4F4F5;
    --color-surface-sunken:    #F0F0F1;
    --color-border:            #E4E4E7;
    --color-border-strong:     #D4D4D8;

    --color-text-primary:      #09090B;
    --color-text-secondary:    #52525B;
    --color-text-muted:        #71717A;
    --color-text-tertiary:     #71717A;

    /* Accent holds, but meanings shift slightly for contrast. */
    --color-accent:            #0091B5;              /* darker cyan for AA on white */
    --color-accent-hover:      #00A8D0;
    --color-accent-muted:      rgba(0, 145, 181, 0.10);
    --color-accent-subtle:     rgba(0, 145, 181, 0.05);
    --color-accent-ring:       rgba(0, 145, 181, 0.45);
    --color-accent-ink:        #FFFFFF;

    --color-accent-gradient:
      linear-gradient(135deg, #0091B5 0%, #5E6AD2 100%);
    --color-accent-gradient-hover:
      linear-gradient(135deg, #00A8D0 0%, #7180E0 100%);

    --color-hero-glow:
      radial-gradient(60% 50% at 50% 20%,
        rgba(0, 145, 181, 0.10) 0%,
        rgba(0, 145, 181, 0.00) 70%);

    --color-success:           #15803D;
    --color-success-muted:     rgba(21, 128, 61, 0.10);
    --color-warn:              #B45309;
    --color-warn-muted:        rgba(180, 83, 9, 0.10);
    --color-danger:            #B91C1C;
    --color-danger-muted:      rgba(185, 28, 28, 0.10);

    --shadow-sm:  0 1px 2px 0 rgba(0, 0, 0, 0.06);
    --shadow-md:  0 4px 12px -2px rgba(0, 0, 0, 0.08),
                  0 2px 4px -1px rgba(0, 0, 0, 0.05);
    --shadow-lg:  0 20px 40px -12px rgba(0, 0, 0, 0.12),
                  0 6px 16px -6px rgba(0, 0, 0, 0.08);
    --shadow-cyan-glow:
      0 0 0 1px rgba(0, 145, 181, 0.20),
      0 8px 28px -4px rgba(0, 145, 181, 0.35),
      0 2px 6px -1px rgba(0, 0, 0, 0.10);
    --shadow-cyan-glow-hover:
      0 0 0 1px rgba(0, 145, 181, 0.35),
      0 12px 36px -4px rgba(0, 145, 181, 0.45),
      0 2px 6px -1px rgba(0, 0, 0, 0.10);
    --shadow-macos:
      0 40px 80px -20px rgba(0, 0, 0, 0.18),
      0 12px 28px -8px rgba(0, 0, 0, 0.12),
      0 2px 6px -1px rgba(0, 0, 0, 0.06);
  }
}
```

### 1.2 Type utility classes — paste below tokens

Used only where a class is preferable to a semantic element. Otherwise, the element-level base styles in §12 set the right defaults.

```css
.t-display-1 { font-size: var(--fs-display-1); font-weight: var(--fw-semibold);
                line-height: var(--lh-display); letter-spacing: var(--ls-display); }
.t-display-3 { font-size: var(--fs-display-3); font-weight: var(--fw-semibold);
                line-height: var(--lh-heading); letter-spacing: var(--ls-display); }
.t-display-4 { font-size: var(--fs-display-4); font-weight: var(--fw-semibold);
                line-height: var(--lh-heading); letter-spacing: var(--ls-heading); }
.t-body-lg   { font-size: var(--fs-body-lg);   line-height: var(--lh-body);
                color: var(--color-text-secondary); }
.t-body      { font-size: var(--fs-body-md);   line-height: var(--lh-body); }
.t-body-sm   { font-size: var(--fs-body-sm);   line-height: var(--lh-body);
                color: var(--color-text-secondary); }
.t-caption   { font-size: var(--fs-caption);   line-height: var(--lh-caption);
                color: var(--color-text-muted); }
.t-label     { font-size: var(--fs-caption);   font-weight: var(--fw-medium);
                line-height: var(--lh-tight); letter-spacing: var(--ls-label);
                text-transform: uppercase; color: var(--color-text-muted); }
.t-mono      { font-family: var(--font-mono); font-size: var(--fs-code);
                font-weight: var(--fw-medium); letter-spacing: var(--ls-mono); }
```

---

## 2. Component Specs

All components target the dark theme tokens. All respect `prefers-reduced-motion`. All hit AA contrast on text.

### 2.1 Nav — `.nav` (transparent → blur-on-scroll)

**Structure:**
```html
<header class="nav" data-scrolled="false">
  <div class="nav__inner">
    <a class="nav__brand" href="/">
      <!-- inline SVG logo -->
      <span>VoiceToText</span>
    </a>
    <nav class="nav__links">
      <a href="#features">Features</a>
      <a href="#compare">Compare</a>
      <a href="#faq">FAQ</a>
      <a href="https://github.com/gug007/voice-to-text">GitHub</a>
    </nav>
    <a class="btn btn--primary btn--sm" href="#download">Download</a>
  </div>
</header>
```

**Behaviour:** On page load, transparent background. Once `window.scrollY > 8`, JS toggles `data-scrolled="true"` on `.nav`, which swaps to a blurred surface. No layout shift; nav is `position: fixed`.

```css
.nav {
  position: fixed; top: 0; left: 0; right: 0;
  z-index: var(--z-nav);
  padding: var(--space-4) var(--page-gutter);
  background: transparent;
  border-bottom: 1px solid transparent;
  transition: background var(--duration-base) var(--ease-standard),
              backdrop-filter var(--duration-base) var(--ease-standard),
              border-color var(--duration-base) var(--ease-standard);
}
.nav[data-scrolled="true"] {
  background: rgba(10, 10, 11, 0.72);
  backdrop-filter: saturate(1.4) blur(14px);
  -webkit-backdrop-filter: saturate(1.4) blur(14px);
  border-bottom-color: var(--color-border);
}
.nav__inner {
  max-width: var(--container-xl);
  margin-inline: auto;
  display: flex; align-items: center; gap: var(--space-8);
}
.nav__brand {
  display: inline-flex; align-items: center; gap: var(--space-2);
  font-weight: var(--fw-semibold); color: var(--color-text-primary);
  text-decoration: none;
}
.nav__links {
  display: flex; gap: var(--space-6); margin-left: auto;
}
.nav__links a {
  font-size: var(--fs-body-sm); color: var(--color-text-secondary);
  text-decoration: none;
  transition: color var(--duration-fast) var(--ease-standard);
}
.nav__links a:hover { color: var(--color-text-primary); }

@media (max-width: 640px) {
  .nav__links { display: none; }         /* hamburger not needed; 3-item nav */
}
```

**JS (inline, ≤10 lines):**
```js
const nav = document.querySelector('.nav');
const onScroll = () =>
  nav.dataset.scrolled = window.scrollY > 8 ? 'true' : 'false';
document.addEventListener('scroll', onScroll, { passive: true });
onScroll();
```

### 2.2 Buttons — `.btn`, `.btn--primary`, `.btn--secondary`, `.btn--ghost`

Primary is the ONLY element on the page using `--color-accent-gradient`. Reserved for Download CTA.

```css
.btn {
  display: inline-flex; align-items: center; justify-content: center;
  gap: var(--space-2);
  height: var(--control-height-lg);            /* 48px */
  padding-inline: var(--space-6);
  border-radius: var(--radius-md);
  font: var(--fw-semibold) var(--fs-body-md)/1 var(--font-sans);
  letter-spacing: var(--ls-heading);
  text-decoration: none;
  cursor: pointer;
  border: 1px solid transparent;
  transition: background var(--duration-fast) var(--ease-standard),
              box-shadow var(--duration-fast) var(--ease-standard),
              transform var(--duration-fast) var(--ease-standard),
              color var(--duration-fast) var(--ease-standard);
  user-select: none;
}
.btn:active { transform: translateY(1px); }
.btn:focus-visible { outline: none; box-shadow: var(--focus-ring); }

/* --- Sizes --- */
.btn--sm { height: var(--control-height-md); padding-inline: var(--space-5);
            font-size: var(--fs-body-sm); }

/* --- Variants --- */

.btn--primary {
  background: var(--color-accent-gradient);
  color: var(--color-accent-ink);
  box-shadow: var(--shadow-cyan-glow);
}
.btn--primary:hover {
  background: var(--color-accent-gradient-hover);
  box-shadow: var(--shadow-cyan-glow-hover);
}

.btn--secondary {
  background: var(--color-surface);
  color: var(--color-text-primary);
  border-color: var(--color-border-strong);
}
.btn--secondary:hover {
  background: var(--color-surface-elevated);
  border-color: var(--color-accent);
  color: var(--color-text-primary);
}

.btn--ghost {
  background: transparent;
  color: var(--color-text-secondary);
}
.btn--ghost:hover {
  color: var(--color-text-primary);
  background: var(--color-surface);
}
```

### 2.3 Keycap — `.keycap`

Used for `⌥ Space` in hero, plus inline in copy (`<kbd class="keycap keycap--inline">⌥</kbd>`).

```css
.keycap {
  display: inline-flex; align-items: center; justify-content: center;
  min-width: 2.5em; height: 2em;
  padding: 0 var(--space-3);
  font-family: var(--font-mono);
  font-size: var(--fs-code);
  font-weight: var(--fw-medium);
  color: var(--color-text-primary);
  background: linear-gradient(180deg, #1B1B1F 0%, #121214 100%);
  border: 1px solid var(--color-border-strong);
  border-radius: var(--radius-sm);
  box-shadow:
    inset 0 1px 0 0 rgba(255, 255, 255, 0.06),    /* bevel highlight */
    inset 0 -2px 0 0 rgba(0, 0, 0, 0.45),          /* bevel shadow */
    0 1px 2px 0 rgba(0, 0, 0, 0.40);
}
.keycap--inline { font-size: 0.9em; height: 1.7em; min-width: 1.7em; }

/* Hero oversized keycap pair */
.keycap--hero {
  height: clamp(96px, 14vw, 180px);
  min-width: clamp(96px, 14vw, 180px);
  border-radius: var(--radius-lg);
  font-size: clamp(32px, 4vw, 56px);
  padding: 0 var(--space-8);
}
.keycap--hero.is-space {
  min-width: clamp(180px, 28vw, 360px);
  padding: 0 var(--space-12);
  /* Cyan accent ring on the Space key — primary visual anchor */
  border-color: var(--color-accent-ring);
  box-shadow:
    inset 0 1px 0 0 rgba(255, 255, 255, 0.08),
    inset 0 -2px 0 0 rgba(0, 0, 0, 0.45),
    0 0 0 1px rgba(0, 212, 255, 0.25),
    0 10px 36px -6px rgba(0, 212, 255, 0.35),
    0 2px 8px 0 rgba(0, 0, 0, 0.40);
}
```

### 2.4 Badge / Chip — `.chip`, `.chip--accent`

Small labels for "Free forever", "Open source", etc. in the hero sub-copy area or feature cards.

```css
.chip {
  display: inline-flex; align-items: center; gap: var(--space-2);
  height: 24px; padding: 0 var(--space-3);
  font: var(--fw-medium) var(--fs-caption)/1 var(--font-sans);
  letter-spacing: var(--ls-label);
  text-transform: uppercase;
  color: var(--color-text-secondary);
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-full);
}
.chip--accent {
  color: var(--color-accent);
  background: var(--color-accent-muted);
  border-color: transparent;
}
.chip__dot {
  width: 6px; height: 6px; border-radius: var(--radius-full);
  background: currentColor;
}
```

### 2.5 Comparison Table — `.compare`

Card-framed, 5-column grid. VoiceToText column gets the cyan top-glow. On mobile, stacks into vertical cards. T4 §4 is authoritative for content.

```html
<section class="compare" id="compare">
  <div class="compare__frame">
    <div class="compare__grid">
      <div class="compare__head"></div>
      <div class="compare__head compare__head--ours">VoiceToText</div>
      <div class="compare__head">Wispr Flow</div>
      <div class="compare__head">Superwhisper</div>
      <div class="compare__head">MacWhisper</div>
      <div class="compare__head">Apple Dictation</div>

      <div class="compare__row-label">Price</div>
      <div class="compare__cell compare__cell--ours">
        <span class="status status--ok"></span>Free forever
      </div>
      <div class="compare__cell">
        <span class="status status--no"></span>$12–15/mo
      </div>
      <!-- etc. -->
    </div>
  </div>
</section>
```

```css
.compare__frame {
  max-width: var(--container-xl);
  margin-inline: auto;
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-xl);
  overflow: hidden;
}
.compare__grid {
  display: grid;
  grid-template-columns: minmax(180px, 1.4fr) repeat(5, minmax(120px, 1fr));
}
.compare__head {
  padding: var(--space-6) var(--space-5);
  font: var(--fw-medium) var(--fs-caption)/1.3 var(--font-sans);
  letter-spacing: var(--ls-label); text-transform: uppercase;
  color: var(--color-text-muted);
  text-align: center;
  border-bottom: 1px solid var(--color-border);
}
.compare__head--ours {
  color: var(--color-text-primary);
  background: var(--color-surface-elevated);
  /* Cyan top-glow — the marker that says "this is our column". */
  box-shadow: inset 0 2px 0 0 var(--color-accent-ring);
  position: relative;
}
.compare__row-label {
  padding: var(--space-5);
  font-size: var(--fs-body-md); font-weight: var(--fw-medium);
  color: var(--color-text-primary);
  border-top: 1px solid var(--color-border);
}
.compare__cell {
  padding: var(--space-5);
  display: inline-flex; align-items: center; gap: var(--space-2);
  justify-content: center;
  font-size: var(--fs-body-sm);
  color: var(--color-text-secondary);
  border-top: 1px solid var(--color-border);
  text-align: center;
}
.compare__cell--ours {
  background: var(--color-surface-elevated);
  color: var(--color-text-primary);
}

.status {
  width: 10px; height: 10px; border-radius: var(--radius-full);
  flex-shrink: 0;
}
.status--ok      { background: var(--color-success); }
.status--partial { background: var(--color-warn); }
.status--no      { background: transparent;
                    border: 2px solid var(--color-text-muted); }

/* Mobile stack: one card per competitor, VoiceToText pinned first */
@media (max-width: 1024px) {
  .compare__grid {
    display: flex; flex-direction: column;
  }
  .compare__head, .compare__cell, .compare__row-label {
    border-top: none; border-bottom: 1px solid var(--color-border);
  }
  /* T8: re-structure markup for mobile as vertical cards — see §6.3 */
}
```

### 2.6 FAQ Accordion — `.faq-item`

Uses native `<details>` + `<summary>`. Zero JS. Chevron rotates via CSS.

```html
<section class="faq" id="faq">
  <h2 class="t-display-3">Questions, answered.</h2>
  <details class="faq-item">
    <summary class="faq-item__q">
      Is it really free?
      <svg class="faq-item__chevron" viewBox="0 0 16 16" aria-hidden="true">
        <path d="M4 6l4 4 4-4" stroke="currentColor" stroke-width="1.5"
              fill="none" stroke-linecap="round" stroke-linejoin="round"/>
      </svg>
    </summary>
    <div class="faq-item__a">
      Yes. MIT-style open source, no account, no telemetry, no pro tier.
      Read the code on GitHub.
    </div>
  </details>
</section>
```

```css
.faq-item {
  border-top: 1px solid var(--color-border);
  padding: var(--space-6) 0;
}
.faq-item:last-child { border-bottom: 1px solid var(--color-border); }
.faq-item__q {
  display: flex; justify-content: space-between; align-items: center;
  gap: var(--space-6);
  font-size: var(--fs-body-lg); font-weight: var(--fw-medium);
  color: var(--color-text-primary);
  cursor: pointer; list-style: none;
}
.faq-item__q::-webkit-details-marker { display: none; }
.faq-item__chevron {
  width: 16px; height: 16px; color: var(--color-text-muted);
  transition: transform var(--duration-base) var(--ease-standard);
  flex-shrink: 0;
}
.faq-item[open] .faq-item__chevron { transform: rotate(180deg); }
.faq-item__a {
  margin-top: var(--space-4);
  font-size: var(--fs-body-md); line-height: var(--lh-body);
  color: var(--color-text-secondary);
  max-width: 680px;
}
```

### 2.7 Feature Card — `.feature-card`

Used in the "Pillars" row (3 or 4 cards) and the "Works with" grid.

```css
.feature-card {
  padding: var(--space-6);
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  transition: border-color var(--duration-fast) var(--ease-standard),
              background var(--duration-fast) var(--ease-standard);
}
.feature-card:hover {
  border-color: var(--color-border-strong);
  background: var(--color-surface-elevated);
}
.feature-card__icon {
  width: 40px; height: 40px;
  display: inline-flex; align-items: center; justify-content: center;
  background: var(--color-accent-muted);
  color: var(--color-accent);
  border-radius: var(--radius-md);
  margin-bottom: var(--space-4);
}
.feature-card__title {
  font-size: var(--fs-h3); font-weight: var(--fw-semibold);
  color: var(--color-text-primary);
  margin-bottom: var(--space-2);
}
.feature-card__body {
  font-size: var(--fs-body-sm); line-height: var(--lh-body);
  color: var(--color-text-secondary);
}
```

### 2.8 Code block — `.code-block`

Used to show a Claude Code prompt example or install step.

```html
<pre class="code-block"><code>hold ⌥ Space → "refactor this function to use async iterators"</code></pre>
```

```css
.code-block {
  padding: var(--space-5) var(--space-6);
  background: var(--color-surface-sunken);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  overflow-x: auto;
}
.code-block code {
  font-family: var(--font-mono);
  font-size: var(--fs-code);
  line-height: var(--lh-tight);
  color: var(--color-text-primary);
  white-space: pre;
}
.code-block .token-accent { color: var(--color-accent); }
.code-block .token-muted  { color: var(--color-text-muted); }
```

### 2.9 Footer — `.footer`

```html
<footer class="footer">
  <div class="footer__inner">
    <div class="footer__brand">
      <svg class="footer__logo" ...></svg>
      <span>VoiceToText</span>
    </div>
    <nav class="footer__links">
      <a href="https://github.com/gug007/voice-to-text">GitHub</a>
      <a href="https://github.com/gug007/voice-to-text/releases">Releases</a>
      <a href="https://github.com/gug007/voice-to-text/blob/main/LICENSE">License</a>
      <a href="#privacy">Privacy</a>
    </nav>
    <p class="footer__meta t-caption">
      Free and open source. MIT-licensed. Your voice stays on your Mac.
    </p>
  </div>
</footer>
```

```css
.footer {
  border-top: 1px solid var(--color-border);
  padding: var(--space-16) var(--page-gutter) var(--space-12);
  color: var(--color-text-muted);
}
.footer__inner {
  max-width: var(--container-xl); margin-inline: auto;
  display: grid; gap: var(--space-8);
  grid-template-columns: auto 1fr auto; align-items: center;
}
.footer__brand {
  display: inline-flex; gap: var(--space-2); align-items: center;
  font-weight: var(--fw-semibold); color: var(--color-text-primary);
}
.footer__links {
  display: flex; gap: var(--space-6); justify-content: center;
}
.footer__links a {
  color: var(--color-text-secondary); text-decoration: none;
  font-size: var(--fs-body-sm);
}
.footer__links a:hover { color: var(--color-accent); }
.footer__meta { grid-column: 1 / -1; text-align: center; margin-top: var(--space-4); }

@media (max-width: 640px) {
  .footer__inner { grid-template-columns: 1fr; text-align: center; }
  .footer__links { flex-wrap: wrap; }
}
```

### 2.10 Section container — `.section`, `.container`

```css
.section {
  padding-block: clamp(var(--space-20), 12vw, var(--space-40));
}
.section + .section { border-top: none; }   /* prevent double-dividers */
.container {
  max-width: var(--container-xl);
  margin-inline: auto;
  padding-inline: var(--page-gutter);
}
.section__eyebrow { /* "eyebrow" = small uppercase label above section h2 */
  color: var(--color-accent);
  font-size: var(--fs-caption); font-weight: var(--fw-medium);
  letter-spacing: var(--ls-label); text-transform: uppercase;
  margin-bottom: var(--space-4);
}
```

---

## 3. Hero Composition

### 3.1 Layout grid

Single-column, centred, vertically stacked. Max content width 800px for headline/subcopy; keycap pair is visually wider (up to ~560px). No side-by-side product shot in hero — demo.gif goes in the *next* section.

```
┌───────────────────────────────────────────────────────┐
│  top padding: clamp(120px, 14vh, 180px)               │
│  (clears the fixed nav)                               │
│                                                        │
│  H1 — display-1, --color-text-primary, centred        │
│  "Push-to-talk dictation for Mac."                    │
│                                                        │
│  second line, display-1, --color-text-secondary       │
│  "100% local. Free forever."                          │
│                                                        │
│  gap: 64px                                            │
│                                                        │
│    ┌────────┐         ┌──────────────────────┐       │
│    │        │         │                      │       │
│    │   ⌥    │  gap24  │        Space         │       │
│    │        │         │                      │       │
│    └────────┘         └──────────────────────┘       │
│       ~180px square   ~360px × 180px, cyan ring       │
│                                                        │
│         ┃ ┃ ┃ ┃ ┃ ┃ ┃   ← waveform SVG, 64px tall     │
│                                                        │
│  gap: 48px                                            │
│                                                        │
│  body-lg subcopy, --color-text-secondary,             │
│  centred, max-width 560px                             │
│                                                        │
│  [Download for Mac]   [View on GitHub]  ← buttons     │
│                                                        │
│  ·chip row· Free forever · macOS 14+ · Apple Silicon  │
│                                                        │
│  bottom padding: clamp(120px, 14vh, 160px)            │
└───────────────────────────────────────────────────────┘
```

### 3.2 HTML

```html
<section class="hero">
  <div class="hero__glow" aria-hidden="true"></div>
  <div class="container hero__inner">
    <h1 class="hero__title">
      Push-to-talk dictation for Mac.<br>
      <span class="hero__title--muted">100% local. Free forever.</span>
    </h1>

    <div class="hero__keys" aria-hidden="true">
      <span class="keycap keycap--hero">⌥</span>
      <span class="keycap keycap--hero is-space">Space</span>
    </div>

    <!-- Waveform — see §3.4 -->
    <svg class="hero__waveform" viewBox="0 0 160 40"
         role="img" aria-label="Audio waveform">
      <rect class="bar b1" x="2"  y="14" width="6" height="12" rx="3"/>
      <rect class="bar b2" x="16" y="8"  width="6" height="24" rx="3"/>
      <rect class="bar b3" x="30" y="4"  width="6" height="32" rx="3"/>
      <rect class="bar b4" x="44" y="12" width="6" height="16" rx="3"/>
      <rect class="bar b5" x="58" y="6"  width="6" height="28" rx="3"/>
      <rect class="bar b6" x="72" y="10" width="6" height="20" rx="3"/>
      <rect class="bar b7" x="86" y="2"  width="6" height="36" rx="3"/>
      <!-- repeat mirror on right side for visual balance -->
      <rect class="bar b6" x="100" y="10" width="6" height="20" rx="3"/>
      <rect class="bar b5" x="114" y="6"  width="6" height="28" rx="3"/>
      <rect class="bar b4" x="128" y="12" width="6" height="16" rx="3"/>
      <rect class="bar b3" x="142" y="4"  width="6" height="32" rx="3"/>
    </svg>

    <p class="hero__subcopy">
      Hold <kbd class="keycap keycap--inline">⌥</kbd>
      <kbd class="keycap keycap--inline">Space</kbd>, speak, release.
      Your words are typed into Claude Code, Cursor, Slack, or any
      focused app. Runs on the Apple Neural Engine. Your voice never
      leaves your Mac.
    </p>

    <div class="hero__ctas">
      <a class="btn btn--primary" href="#download">
        <svg aria-hidden="true" width="16" height="16" viewBox="0 0 16 16">
          <path d="M8 1v9m0 0l-3-3m3 3l3-3M2 13h12"
                stroke="currentColor" stroke-width="1.5"
                fill="none" stroke-linecap="round" stroke-linejoin="round"/>
        </svg>
        Download for Mac
      </a>
      <a class="btn btn--secondary"
         href="https://github.com/gug007/voice-to-text">
        <svg aria-hidden="true" width="16" height="16" viewBox="0 0 16 16">
          <!-- GitHub mark path — see §7 -->
        </svg>
        View on GitHub
      </a>
    </div>

    <p class="hero__meta">
      <span class="chip"><span class="chip__dot" style="color:var(--color-success)"></span>Free forever</span>
      <span class="chip">macOS 14+</span>
      <span class="chip">Apple Silicon</span>
    </p>
  </div>
</section>
```

### 3.3 Hero CSS

```css
.hero {
  position: relative;
  padding-top: clamp(120px, 14vh, 180px);
  padding-bottom: clamp(96px, 12vh, 160px);
  overflow: hidden;                          /* contain the glow */
  text-align: center;
}
.hero__glow {
  position: absolute; inset: 0 0 auto 0;
  height: 720px;
  background: var(--color-hero-glow);
  pointer-events: none;
  z-index: var(--z-base);
}
.hero__inner {
  position: relative; z-index: var(--z-raised);
  display: flex; flex-direction: column; align-items: center;
  gap: var(--space-8);
}
.hero__title {
  font-size: var(--fs-display-1);
  font-weight: var(--fw-semibold);
  line-height: var(--lh-display);
  letter-spacing: var(--ls-display);
  color: var(--color-text-primary);
  max-width: 14ch;
  margin: 0;
}
.hero__title--muted { color: var(--color-text-secondary); }

.hero__keys {
  display: flex; gap: var(--space-6);
  margin-top: var(--space-8);
}

.hero__waveform {
  width: clamp(200px, 40vw, 320px);
  height: auto;
  color: var(--color-accent);
  margin-top: var(--space-2);
}
.hero__waveform .bar {
  fill: currentColor;
  opacity: 0.85;
  transform-origin: center;
  animation: wave var(--duration-ambient) var(--ease-standard) infinite;
}
.hero__waveform .b1 { animation-delay: 0ms;   }
.hero__waveform .b2 { animation-delay: 120ms; }
.hero__waveform .b3 { animation-delay: 240ms; }
.hero__waveform .b4 { animation-delay: 360ms; }
.hero__waveform .b5 { animation-delay: 480ms; }
.hero__waveform .b6 { animation-delay: 600ms; }
.hero__waveform .b7 { animation-delay: 720ms; }

@keyframes wave {
  0%, 100% { transform: scaleY(0.5); opacity: 0.55; }
  50%      { transform: scaleY(1.0); opacity: 0.95; }
}
@media (prefers-reduced-motion: reduce) {
  .hero__waveform .bar { animation: none; transform: scaleY(0.75); }
}

.hero__subcopy {
  font-size: var(--fs-body-lg);
  line-height: var(--lh-body);
  color: var(--color-text-secondary);
  max-width: 560px;
  margin: var(--space-8) auto 0;
}
.hero__ctas {
  display: flex; gap: var(--space-4);
  margin-top: var(--space-6);
  flex-wrap: wrap; justify-content: center;
}
.hero__meta {
  display: flex; gap: var(--space-3);
  margin-top: var(--space-6);
  flex-wrap: wrap; justify-content: center;
}
```

### 3.4 Waveform — pure CSS/SVG spec

- 12 bars total (T4 said 5–7; mirrored to 12 reads as a proper waveform strip and balances visually with the double-keycap). Each bar is an SVG `<rect>` with `rx="3"`.
- Width: 6px each; gap: 8px; total width ≈ 160px in viewBox, rendered fluidly 200–320px.
- Heights vary between 12–36px in the viewBox; the animation scales Y from 0.5× to 1.0× and back with staggered delays.
- Color: `currentColor` (set via `.hero__waveform { color: var(--color-accent); }`) so it inherits theme correctly.
- One CSS keyframe, `wave`, reused across every bar with staggered `animation-delay`.
- `prefers-reduced-motion: reduce` freezes them at `scaleY(0.75)` — still looks like a waveform, just still.
- **No canvas, no WebGL, no MP4, no Lottie.** Just SVG + CSS.

### 3.5 Keycap SVG alternative (if pure text glyph proves problematic)

The `⌥` character renders consistently in Geist Mono and system fonts on macOS. If QA reveals a rendering gap on Windows/Linux visitors, T8 swaps the text for an inline SVG:

```html
<svg viewBox="0 0 24 24" width="28" height="28" aria-hidden="true">
  <path d="M4 5h6l7 14h3" stroke="currentColor" stroke-width="2"
        fill="none" stroke-linecap="round" stroke-linejoin="round"/>
  <line x1="14" y1="5" x2="20" y2="5" stroke="currentColor" stroke-width="2"
        stroke-linecap="round"/>
</svg>
```

This is the Option / Alt glyph, reasonably legible at any size.

---

## 4. Responsive Breakpoints

### 4.1 Definitions

| Name | Range | `--page-gutter` | Notes |
|---|---|---|---|
| **mobile** | ≤640px | 16px | Single column, hamburger absent (nav links hidden) |
| **tablet** | 641–1024px | 24px | Two-column grids start here |
| **desktop** | 1025–1439px | 32px | Standard target |
| **wide** | ≥1440px | 40px | Optional: bump max container to `--container-2xl` |

```css
@media (min-width: 641px)  { :root { --page-gutter: 24px; } }
@media (min-width: 1025px) { :root { --page-gutter: 32px; } }
@media (min-width: 1440px) { :root { --page-gutter: 40px; } }
```

### 4.2 Component change matrix

| Component | Mobile ≤640 | Tablet 641–1024 | Desktop 1025–1439 | Wide ≥1440 |
|---|---|---|---|---|
| **Nav** | Links hidden; brand + Download button only | Full nav | Full nav | Full nav |
| **Hero title** | `display-1` floor 56px | clamp | clamp | 96px cap |
| **Hero keys** | Stacked vertically, `gap: var(--space-4)` | Row | Row | Row |
| **Hero CTAs** | Full-width buttons stacked | Row | Row | Row |
| **Feature cards grid** | 1 col | 2 cols | 3 cols | 3 cols |
| **Compare table** | Vertical stacked cards, VoiceToText pinned top | 5-col grid (cramped) | 5-col grid | 5-col grid |
| **FAQ** | Full width | Max 720px | Max 720px | Max 720px |
| **Footer** | Single column, centred | 3-column grid | 3-column grid | 3-column grid |
| **macOS demo frame** | 100% width (no margins) | 100% width, radius lg | Max 960px, radius xl | Max 1120px |

### 4.3 Mobile hero keys stack

```css
@media (max-width: 640px) {
  .hero__keys {
    flex-direction: column;
    gap: var(--space-3);
  }
  .keycap--hero { height: 72px; min-width: 88px; font-size: 24px; }
  .keycap--hero.is-space { min-width: 200px; padding: 0 var(--space-8); }
  .hero__ctas { width: 100%; flex-direction: column; }
  .hero__ctas .btn { width: 100%; }
}
```

### 4.4 Mobile compare — markup change

Below 1024px, render one `.compare__card` per competitor rather than the grid:

```html
<article class="compare__card compare__card--ours">
  <header>
    <h3>VoiceToText</h3>
    <span class="chip chip--accent">Open source</span>
  </header>
  <dl>
    <dt>Price</dt><dd><span class="status status--ok"></span>Free forever</dd>
    <dt>Runs offline</dt><dd><span class="status status--ok"></span>On-device</dd>
    <!-- etc. -->
  </dl>
</article>
```

```css
.compare__card {
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  padding: var(--space-6);
  display: grid; gap: var(--space-4);
}
.compare__card--ours {
  border-color: var(--color-accent-ring);
  box-shadow: inset 0 2px 0 0 var(--color-accent-ring);
}
.compare__card dl {
  display: grid; grid-template-columns: 1fr auto; gap: var(--space-2) var(--space-4);
  margin: 0;
}
.compare__card dt { color: var(--color-text-muted); font-size: var(--fs-body-sm); }
.compare__card dd { margin: 0; color: var(--color-text-primary); font-size: var(--fs-body-sm);
                     display: inline-flex; gap: var(--space-2); align-items: center; }
```

T8 can render **both** markup trees and hide one per breakpoint, or render once and restructure with JS. Recommended: render both, `display: none` one per breakpoint. ~4KB HTML cost, zero runtime cost.

---

## 5. macOS Window Chrome — `.macos-window`

Used to frame `docs/demo.gif` in the "See it in action" section directly below the hero.

### 5.1 Proportions and anatomy

- Title bar: 36px tall.
- Traffic lights: 3× 12px circles, 8px gap. Colors: `#FF5F57` (close), `#FEBC2E` (min), `#28C840` (max). Positioned 16px from left, vertically centred.
- Optional centred title text: Geist 13px/500, `--color-text-muted`. "VoiceToText — Demo" or none.
- Body: where demo.gif lives. No internal padding — gif fills edge-to-edge.
- Corner radius: `--radius-xl` (20px), clipped via `overflow: hidden` on the frame.
- Border: 1px `--color-border`.
- Shadow: `--shadow-macos` for a realistic floating feel.

### 5.2 Markup

```html
<section class="section" id="demo">
  <div class="container">
    <div class="macos-window">
      <div class="macos-window__chrome">
        <span class="macos-window__dot" style="--c:#FF5F57"></span>
        <span class="macos-window__dot" style="--c:#FEBC2E"></span>
        <span class="macos-window__dot" style="--c:#28C840"></span>
        <span class="macos-window__title">VoiceToText — Demo</span>
      </div>
      <div class="macos-window__body">
        <img src="/docs/demo.gif"
             alt="VoiceToText dictating into Claude Code"
             loading="lazy"
             width="1280" height="800">
      </div>
    </div>
  </div>
</section>
```

### 5.3 CSS

```css
.macos-window {
  max-width: 960px;
  margin-inline: auto;
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-xl);
  box-shadow: var(--shadow-macos);
  overflow: hidden;
}
.macos-window__chrome {
  position: relative;
  height: 36px;
  display: flex; align-items: center; gap: 8px;
  padding: 0 var(--space-4);
  background: linear-gradient(180deg, #1B1B1F 0%, #141418 100%);
  border-bottom: 1px solid var(--color-border);
}
.macos-window__dot {
  width: 12px; height: 12px; border-radius: var(--radius-full);
  background: var(--c);
  box-shadow: inset 0 0 0 0.5px rgba(0, 0, 0, 0.2);
}
.macos-window__title {
  position: absolute; left: 0; right: 0;
  text-align: center;
  font-size: var(--fs-caption);
  font-weight: var(--fw-medium);
  color: var(--color-text-muted);
  pointer-events: none;
}
.macos-window__body { background: #000; }      /* in case gif loads late */
.macos-window__body img {
  display: block; width: 100%; height: auto;
}

@media (prefers-color-scheme: light) {
  .macos-window__chrome {
    background: linear-gradient(180deg, #F4F4F5 0%, #E4E4E7 100%);
  }
}

@media (max-width: 1024px) {
  .macos-window { border-radius: var(--radius-lg); }
}
```

---

## 6. Icon System

### 6.1 Approach: inline SVG, stroke-based, 16×16 or 20×20

**Rationale:** no icon font (avoids extra HTTP request + FOUT), no external svg library. Every icon is a small `<svg>` defined inline where used, or cloned from a `<symbol>` sprite at the top of `<body>` for shared reuse. Strokes use `currentColor` so icons pick up text color automatically.

**Style rules:**
- Stroke width: 1.5px at 16px size, 1.75px at 20px.
- Line caps + joins: `round`.
- Grid: 16px canvas with 1px internal padding.
- Fill: `none` (outlined style — matches Geist + Linear + Raycast idiom).
- Two filled exceptions: GitHub mark (uses official path), and status dots (solid filled circles).

### 6.2 Icon inventory (and where each is used)

| Icon | Size | Location | Path notes |
|---|---|---|---|
| **Logo** / favicon | 32×32 | Nav brand, footer brand, `<link rel="icon">` | Waveform-in-a-rounded-square mark; see §6.4 |
| **Download** (arrow into tray) | 16 | Primary hero CTA | `M8 1v9 m5-3l-5 3-5-3 M2 13h12` |
| **GitHub mark** | 16 | Secondary hero CTA, footer | Official Octicon path; filled |
| **External link** | 12 | Any outbound link in body copy (optional) | `M6 3H3v10h10V10 M9 3h4v4 M7 9l6-6` |
| **Chevron down** | 16 | FAQ accordion summary | `M4 6l4 4 4-4` |
| **Lock (privacy)** | 20 | Feature card for "100% local" | Shield/lock variant |
| **Bolt (speed / Neural Engine)** | 20 | Feature card for "Fast enough to stay in flow" | `M9 2L3 10h5l-1 6 6-8h-5l1-6z` |
| **Box (open source)** | 20 | Feature card for "Free & open forever" | Outlined cube |
| **Microphone** | 20 | "How it works" step 2 | Capsule with base |
| **Keyboard** | 20 | "How it works" step 1 | Rectangle with 6 dots |
| **Sparkle/insertion caret** | 20 | "How it works" step 3 | Caret with plus |

### 6.3 Paste-ready sprite

Place once at top of `<body>`:

```html
<svg aria-hidden="true" width="0" height="0" style="position:absolute">
  <defs>
    <symbol id="i-download" viewBox="0 0 16 16">
      <path d="M8 1v9m0 0l-3-3m3 3l3-3M2 13h12"
            stroke="currentColor" stroke-width="1.5"
            fill="none" stroke-linecap="round" stroke-linejoin="round"/>
    </symbol>
    <symbol id="i-github" viewBox="0 0 16 16">
      <path fill="currentColor"
            d="M8 .2a8 8 0 00-2.53 15.59c.4.07.55-.17.55-.38v-1.34c-2.22.48-2.7-1.07-2.7-1.07-.36-.92-.89-1.17-.89-1.17-.73-.5.06-.49.06-.49.8.06 1.23.83 1.23.83.72 1.23 1.88.87 2.34.67.07-.52.28-.88.51-1.08-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.58.82-2.14-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82a7.65 7.65 0 014 0c1.53-1.03 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.14 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48v2.2c0 .21.15.46.55.38A8 8 0 008 .2"/>
    </symbol>
    <symbol id="i-chevron-down" viewBox="0 0 16 16">
      <path d="M4 6l4 4 4-4" stroke="currentColor" stroke-width="1.5"
            fill="none" stroke-linecap="round" stroke-linejoin="round"/>
    </symbol>
    <symbol id="i-lock" viewBox="0 0 20 20">
      <rect x="4" y="9" width="12" height="9" rx="2"
            stroke="currentColor" stroke-width="1.75" fill="none"/>
      <path d="M7 9V6a3 3 0 016 0v3"
            stroke="currentColor" stroke-width="1.75" fill="none"
            stroke-linecap="round"/>
    </symbol>
    <symbol id="i-bolt" viewBox="0 0 20 20">
      <path d="M11 2L4 11h5l-1 7 7-9h-5l1-7z"
            stroke="currentColor" stroke-width="1.75" fill="none"
            stroke-linecap="round" stroke-linejoin="round"/>
    </symbol>
    <symbol id="i-box" viewBox="0 0 20 20">
      <path d="M10 2L3 6v8l7 4 7-4V6l-7-4zM3 6l7 4 7-4M10 10v8"
            stroke="currentColor" stroke-width="1.75" fill="none"
            stroke-linecap="round" stroke-linejoin="round"/>
    </symbol>
    <symbol id="i-mic" viewBox="0 0 20 20">
      <rect x="7" y="2" width="6" height="11" rx="3"
            stroke="currentColor" stroke-width="1.75" fill="none"/>
      <path d="M4 10a6 6 0 0012 0M10 16v3"
            stroke="currentColor" stroke-width="1.75" fill="none"
            stroke-linecap="round"/>
    </symbol>
    <symbol id="i-keyboard" viewBox="0 0 20 20">
      <rect x="2" y="5" width="16" height="10" rx="2"
            stroke="currentColor" stroke-width="1.75" fill="none"/>
      <path d="M5 9h.01M8 9h.01M11 9h.01M14 9h.01M6 12h8"
            stroke="currentColor" stroke-width="1.75"
            stroke-linecap="round"/>
    </symbol>
  </defs>
</svg>
```

Use via `<svg class="icon"><use href="#i-download"/></svg>`.

```css
.icon {
  width: 16px; height: 16px;
  display: inline-block; vertical-align: middle;
  flex-shrink: 0;
}
.icon--lg { width: 20px; height: 20px; }
```

### 6.4 Favicon / logo concept

Simple waveform mark inside a rounded 32px square. Filled background = `--color-accent`, bars = white. Provides a strong silhouette at 16px (tab favicon) and scales cleanly to 512px (Apple touch icon). T7 ships as:
- `/favicon.svg` — inline gradient for modern browsers
- `/favicon.ico` — fallback 32×32
- `/apple-touch-icon.png` — 180×180 PNG, same mark on `--color-bg` background

Ready-to-ship SVG:

```html
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
  <rect width="32" height="32" rx="7" fill="#00D4FF"/>
  <g fill="#001014">
    <rect x="6"  y="13" width="3" height="6"  rx="1.5"/>
    <rect x="11" y="10" width="3" height="12" rx="1.5"/>
    <rect x="16" y="7"  width="3" height="18" rx="1.5"/>
    <rect x="21" y="10" width="3" height="12" rx="1.5"/>
    <rect x="26" y="13" width="3" height="6"  rx="1.5"/>
  </g>
</svg>
```

---

## 7. Section-Level CSS (ready-to-paste)

Reset + base:

```css
*, *::before, *::after { box-sizing: border-box; }
html, body { margin: 0; padding: 0; }
html { scroll-behavior: smooth; }
@media (prefers-reduced-motion: reduce) {
  html { scroll-behavior: auto; }
}

body {
  font-family: var(--font-sans);
  font-size: var(--fs-body-md);
  line-height: var(--lh-body);
  color: var(--color-text-primary);
  background: var(--color-bg);
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
  text-rendering: optimizeLegibility;
  font-feature-settings: "ss01", "cv11";    /* Geist stylistic set */
}

h1, h2, h3, h4 { margin: 0; font-weight: var(--fw-semibold); letter-spacing: var(--ls-heading); }
p { margin: 0; }
img, svg { display: block; max-width: 100%; }
a { color: var(--color-accent); }
a:hover { color: var(--color-accent-hover); }

:focus-visible {
  outline: 2px solid var(--color-accent);
  outline-offset: 2px;
}

::selection { background: var(--color-accent); color: var(--color-accent-ink); }
```

Font face declarations (T8 pastes these verbatim once fonts are in `/fonts`):

```css
@font-face {
  font-family: "Geist";
  src: url("/fonts/Geist-Regular.woff2") format("woff2");
  font-weight: 400; font-style: normal; font-display: swap;
}
@font-face {
  font-family: "Geist";
  src: url("/fonts/Geist-SemiBold.woff2") format("woff2");
  font-weight: 600; font-style: normal; font-display: swap;
}
@font-face {
  font-family: "Geist Mono";
  src: url("/fonts/GeistMono-Regular.woff2") format("woff2");
  font-weight: 400; font-style: normal; font-display: swap;
}
```

In `<head>`, preload the three files:

```html
<link rel="preload" href="/fonts/Geist-Regular.woff2"
      as="font" type="font/woff2" crossorigin>
<link rel="preload" href="/fonts/Geist-SemiBold.woff2"
      as="font" type="font/woff2" crossorigin>
<link rel="preload" href="/fonts/GeistMono-Regular.woff2"
      as="font" type="font/woff2" crossorigin>
```

---

## 8. Scroll-fade utility (IntersectionObserver)

For section entrance animations per T4 §5:

```css
.reveal {
  opacity: 0;
  transform: translateY(12px);
  transition: opacity var(--duration-slow) var(--ease-enter),
              transform var(--duration-slow) var(--ease-enter);
}
.reveal.is-visible { opacity: 1; transform: none; }

@media (prefers-reduced-motion: reduce) {
  .reveal { opacity: 1; transform: none; transition: none; }
}
```

```js
const io = new IntersectionObserver((entries) => {
  for (const e of entries) {
    if (e.isIntersecting) {
      e.target.classList.add('is-visible');
      io.unobserve(e.target);
    }
  }
}, { threshold: 0.15 });
document.querySelectorAll('.reveal').forEach(el => io.observe(el));
```

---

## 9. Accessibility checklist (must-ship)

- [ ] All buttons have visible text (no icon-only CTA in hero).
- [ ] All SVGs either have `aria-hidden="true"` (decorative) or `role="img"` + `aria-label` (informative).
- [ ] Color contrast: body on bg ≥ 7:1 (AAA). Accent on bg verified AA for text sizes ≥ 18px. Accent as a focus ring color is fine (non-text).
- [ ] Focus ring: `:focus-visible` produces the `--focus-ring` double-ring on every interactive.
- [ ] `prefers-reduced-motion` pauses the waveform and disables reveal animations.
- [ ] FAQ uses native `<details>`/`<summary>` — keyboard-accessible by default.
- [ ] Comparison table mobile version uses semantic `<dl>` pairs.
- [ ] `<img>` demo.gif has explicit `alt` text describing the action, `width` + `height` to prevent CLS.
- [ ] Nav is a `<header>`, main page content in `<main>`, site-end in `<footer>`.
- [ ] Skip link for keyboard users:
```css
.skip-link {
  position: absolute; top: -999px; left: var(--space-4);
  background: var(--color-accent); color: var(--color-accent-ink);
  padding: var(--space-2) var(--space-4); border-radius: var(--radius-sm);
}
.skip-link:focus { top: var(--space-4); z-index: var(--z-toast); }
```

---

## 10. Performance budget (reaffirms T4 §5)

- LCP < 1.5s: hero text paints first, keycaps inline HTML/CSS (no network), waveform SVG inline, demo.gif below fold with `loading="lazy"`.
- CLS < 0.05: all images have explicit width/height. Nav is fixed and doesn't reflow page. Fonts use `font-display: swap` with the system-font fallback pre-sized similarly (Geist metrics approximate SF/Inter).
- TTFB target: static HTML, no server runtime. Host on Pages/Netlify/Vercel.
- No JS framework. Single `<script>` of ~30 lines for nav scroll toggle + reveal observer.
- Bundle size target: < 80KB CSS, < 2KB JS, ~180KB of WOFF2 fonts, demo.gif (accept whatever size it is, lazy-loaded).

---

## 11. Sketched page order (for T8 to match)

Mirrors T3 §6 handoff + T4's hero decision:

1. `<header class="nav">`
2. `<section class="hero">` — §3
3. `<section class="section" id="demo">` — macOS window chrome with demo.gif — §5
4. `<section class="section" id="features">` — 3–4 `.feature-card`s (Private by architecture / Fast enough to stay in flow / Free and open / Works everywhere)
5. `<section class="section" id="how-it-works">` — 3-step diagram: Hold key (icon) → Speak (mic icon + mini waveform) → Release (caret icon) + "words appear" copy
6. `<section class="section" id="compare">` — comparison table — §2.5
7. `<section class="section" id="faq">` — FAQ accordion — §2.6
8. `<section class="section" id="download">` — repeat primary CTA + install instructions + requirements
9. `<footer class="footer">` — §2.9

---

## 12. Handoff checklist to T8

- [ ] Drop §1.1 block verbatim into top of `styles.css`.
- [ ] Drop §1.2 utility classes after.
- [ ] Drop §7 reset + base right after utilities.
- [ ] Drop font-face block from §7 once fonts live at `/fonts/`.
- [ ] Drop §8 reveal utility + JS observer.
- [ ] Copy component blocks from §2 as each section is built.
- [ ] Copy hero block from §3 (HTML + CSS).
- [ ] Copy macOS window chrome from §5.
- [ ] Copy icon sprite from §6.3 once at top of `<body>`.
- [ ] Preload the 3 fonts from §7 in `<head>`.
- [ ] Verify color contrasts in Chrome DevTools.
- [ ] Run Lighthouse — target Performance 95+, Accessibility 100, LCP <1.5s.

---

## TL;DR for T8

One CSS file. Paste §1.1 → §1.2 → §7 reset → font-face → component CSS as you build each section. HTML follows §11 order. The only JS on the page is 30 lines: nav scroll toggle + IntersectionObserver for `.reveal`. Icons are a single inline sprite at top of `<body>`, referenced with `<use href="#i-...">`. The hero waveform is pure CSS keyframes on 12 SVG rects. Demo.gif sits inside `.macos-window` in its own section below the hero. Comparison table has two DOM trees (grid + mobile cards), toggled via `display: none` per breakpoint.
