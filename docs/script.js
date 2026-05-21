/* VoiceToText — landing page script.
   No frameworks, no bundler. ES2022.
   Responsibilities:
     1. Sticky nav scroll effect (toggle data-scrolled).
     2. IntersectionObserver scroll-reveal (respecting prefers-reduced-motion).
     3. Native <details> handles the FAQ — no JS needed for toggling.
     4. Copy-to-clipboard for any [data-copy] element (forward-looking; no
        install one-liner is shipped today but the handler is ready when
        T9/T10 add one). */

(() => {
  'use strict';

  const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');

  // --- 1. Sticky nav scroll effect ---------------------------------------
  const nav = document.querySelector('.nav');
  if (nav) {
    const syncScrolled = () => {
      const next = window.scrollY > 8 ? 'true' : 'false';
      if (nav.dataset.scrolled !== next) nav.dataset.scrolled = next;
    };
    syncScrolled();
    document.addEventListener('scroll', syncScrolled, { passive: true });
  }

  // --- 2. IntersectionObserver scroll-reveal -----------------------------
  const revealTargets = document.querySelectorAll('.reveal');
  if (revealTargets.length) {
    if (prefersReducedMotion.matches || !('IntersectionObserver' in window)) {
      revealTargets.forEach((el) => el.classList.add('is-visible'));
    } else {
      const io = new IntersectionObserver(
        (entries, obs) => {
          for (const entry of entries) {
            if (entry.isIntersecting) {
              entry.target.classList.add('is-visible');
              obs.unobserve(entry.target);
            }
          }
        },
        { threshold: 0.15, rootMargin: '0px 0px -40px 0px' }
      );
      revealTargets.forEach((el) => io.observe(el));
    }
  }

  // --- 2b. Staggered child reveals (feature/how/compare cards) -----------
  // Under reduced-motion the .reveal-child class is never applied (CSS guards it),
  // so content stays visible. Under normal motion, cards fade-up sequentially.
  if (!prefersReducedMotion.matches && 'IntersectionObserver' in window) {
    const CHILD_SELECTORS = '.how__step, .feature-card, .compare__card';
    const childGroups = document.querySelectorAll('.how__steps, .features__grid, .compare__mobile');
    childGroups.forEach((group) => {
      const children = group.querySelectorAll(CHILD_SELECTORS);
      children.forEach((child, idx) => {
        child.classList.add('reveal-child');
        child.style.transitionDelay = `${idx * 60}ms`;
      });
      const groupIo = new IntersectionObserver(
        (entries, obs) => {
          for (const entry of entries) {
            if (entry.isIntersecting) {
              entry.target.querySelectorAll('.reveal-child').forEach((child) => {
                child.classList.add('is-visible');
              });
              obs.unobserve(entry.target);
            }
          }
        },
        { threshold: 0.1, rootMargin: '0px 0px -30px 0px' }
      );
      groupIo.observe(group);
    });
  }

  // --- 3. Theme toggle ---------------------------------------------------
  const themeToggle = document.querySelector('[data-theme-toggle]');
  if (themeToggle) {
    const prefersLight = window.matchMedia('(prefers-color-scheme: light)');
    const currentTheme = () => {
      const explicit = document.documentElement.getAttribute('data-theme');
      if (explicit === 'light' || explicit === 'dark') return explicit;
      return prefersLight.matches ? 'light' : 'dark';
    };
    const syncToggleLabel = (theme) => {
      themeToggle.setAttribute('aria-label', theme === 'dark' ? 'Switch to light theme' : 'Switch to dark theme');
      themeToggle.setAttribute('aria-pressed', theme === 'dark' ? 'true' : 'false');
    };
    syncToggleLabel(currentTheme());
    themeToggle.addEventListener('click', () => {
      const next = currentTheme() === 'dark' ? 'light' : 'dark';
      document.documentElement.setAttribute('data-theme', next);
      try { localStorage.setItem('vtt-theme', next); } catch (e) {}
      syncToggleLabel(next);
    });
  }

  // --- 4. Copy-to-clipboard for any [data-copy] element ------------------
  // Usage: <button data-copy="text or selector">Copy</button>
  // If data-copy starts with '#', it is treated as a selector and the
  // element's textContent is copied; otherwise the attribute value is used.
  const flash = (el, msg) => {
    const original = el.dataset.flashOriginal ?? el.textContent;
    el.dataset.flashOriginal = original;
    if (el._flashTimer) clearTimeout(el._flashTimer);
    el.textContent = msg;
    el._flashTimer = window.setTimeout(() => {
      el.textContent = original;
      delete el.dataset.flashOriginal;
      el._flashTimer = null;
    }, 1500);
  };

  document.querySelectorAll('[data-copy]').forEach((btn) => {
    btn.addEventListener('click', async (e) => {
      e.preventDefault();
      const ref = btn.getAttribute('data-copy');
      let text = ref;
      if (ref && ref.startsWith('#')) {
        const src = document.querySelector(ref);
        if (src) text = src.textContent.trim();
      }
      if (!text) return;
      try {
        await navigator.clipboard.writeText(text);
        flash(btn, 'Copied');
      } catch {
        flash(btn, 'Press Cmd+C');
      }
    });
  });

  // --- 5. Demo dictation cycle ------------------------------------------
  // Animates the simulated VoiceToText recording HUD over a faux Claude
  // Code window: show HUD, type a prompt while the timer counts, hide HUD,
  // pause, then move to the next prompt. Pauses when off-screen, and
  // collapses to a static finished state under reduced-motion.
  const demoCard = document.querySelector('.demo-card');
  const demoField = demoCard && demoCard.querySelector('.demo-field');
  const demoHud = document.querySelector('[data-dictation-hud]');
  const demoText = document.querySelector('[data-dictation-text]');
  const demoTimer = document.querySelector('[data-dictation-timer]');
  const demoCanvas = document.querySelector('[data-dictation-canvas]');

  if (demoCard && demoField && demoHud && demoText && demoTimer && demoCanvas) {
    // ECG-trace ribbon — mirrors the SwiftUI Canvas in LiveHUD.swift:
    // 140-sample rolling buffer, filled shape mirrored above and below the
    // centre, write-head on the right, gradient mask on the left.
    const SAMPLES = 140;
    const SAMPLE_INTERVAL = 0.07;
    const trace = new Array(SAMPLES).fill(0);
    let traceSmoothed = 0;
    let tracePhase = Math.random() * 10;
    let traceAccum = 0;
    let traceRaf = null;
    const traceCtx = demoCanvas.getContext('2d');
    let traceDpr = 1;
    let traceLast = 0;
    let traceActive = false;

    function resizeTraceCanvas() {
      const rect = demoCanvas.getBoundingClientRect();
      traceDpr = Math.min(window.devicePixelRatio || 1, 2);
      demoCanvas.width = Math.max(1, Math.round(rect.width * traceDpr));
      demoCanvas.height = Math.max(1, Math.round(rect.height * traceDpr));
      traceCtx.setTransform(traceDpr, 0, 0, traceDpr, 0, 0);
    }

    function drawTrace() {
      const w = demoCanvas.width / traceDpr;
      const h = demoCanvas.height / traceDpr;
      traceCtx.clearRect(0, 0, w, h);

      const midY = h / 2;
      const amp = h * 0.48;
      const floor = 1.2;
      const stepX = w / (SAMPLES - 1);

      traceCtx.beginPath();
      for (let i = 0; i < SAMPLES; i++) {
        const off = Math.max(floor, trace[i] * amp);
        const x = i * stepX;
        const y = midY - off;
        if (i === 0) traceCtx.moveTo(x, y); else traceCtx.lineTo(x, y);
      }
      for (let i = SAMPLES - 1; i >= 0; i--) {
        const off = Math.max(floor, trace[i] * amp);
        traceCtx.lineTo(i * stepX, midY + off);
      }
      traceCtx.closePath();
      traceCtx.fillStyle = 'rgba(255,255,255,0.85)';
      traceCtx.fill();
    }

    function tickTrace(now) {
      if (!traceActive) return;
      if (!traceLast) traceLast = now;
      const dt = Math.min(0.1, (now - traceLast) / 1000);
      traceLast = now;
      tracePhase += dt;
      traceAccum += dt;
      let pushed = false;
      while (traceAccum >= SAMPLE_INTERVAL) {
        traceAccum -= SAMPLE_INTERVAL;
        const t = tracePhase;
        const envelope = 0.55 + 0.45 * Math.sin(t * 0.55);
        const raw = 0.42
          + 0.34 * Math.sin(t * 1.4)
          + 0.18 * Math.sin(t * 3.1 + 1.2)
          + (Math.random() - 0.5) * 0.22;
        const target = Math.max(0, Math.min(1, raw * envelope));
        traceSmoothed = traceSmoothed * 0.6 + target * 0.4;
        trace.shift();
        trace.push(traceSmoothed);
        pushed = true;
      }
      if (pushed) drawTrace();
      traceRaf = window.requestAnimationFrame(tickTrace);
    }

    function startTrace() {
      if (traceActive) return;
      traceActive = true;
      resizeTraceCanvas();
      traceLast = 0;
      traceRaf = window.requestAnimationFrame(tickTrace);
    }

    function stopTrace() {
      traceActive = false;
      if (traceRaf) window.cancelAnimationFrame(traceRaf);
      traceRaf = null;
      // Bleed the buffer back toward silence so a frozen trace looks idle.
      for (let i = 0; i < trace.length; i++) trace[i] *= 0.4;
      drawTrace();
    }

    window.addEventListener('resize', () => {
      if (traceActive) resizeTraceCanvas();
    }, { passive: true });
    const PROMPTS = [
      'refactor this function so it streams tokens instead of buffering, keep the type signature',
      'add a dark-mode toggle to the settings sheet and persist the choice',
      'write a quick benchmark comparing parakeet vs whisper-large',
    ];

    const formatTime = (seconds) => {
      const total = Math.floor(seconds);
      const m = Math.floor(total / 60);
      const s = total % 60;
      return `${m}:${s.toString().padStart(2, '0')}`;
    };

    const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
    const setText = (s) => {
      demoText.textContent = s;
      demoField.classList.toggle('has-text', s.length > 0);
    };

    let cycleToken = 0;
    let running = false;

    async function runCycle() {
      if (running) return;
      running = true;
      const myToken = ++cycleToken;
      let i = 0;
      while (myToken === cycleToken) {
        const prompt = PROMPTS[i % PROMPTS.length];
        setText('');
        demoTimer.textContent = '0:00';
        demoField.dataset.dictationState = 'idle';

        await sleep(900);
        if (myToken !== cycleToken) break;

        demoField.dataset.dictationState = 'recording';
        demoHud.classList.add('is-visible');
        startTrace();
        const startedAt = performance.now();
        const timerHandle = window.setInterval(() => {
          demoTimer.textContent = formatTime((performance.now() - startedAt) / 1000);
        }, 100);

        await sleep(320);
        if (myToken !== cycleToken) { clearInterval(timerHandle); break; }

        let typed = '';
        const baseDelay = 32;
        for (let k = 0; k < prompt.length; k++) {
          if (myToken !== cycleToken) break;
          typed += prompt[k];
          setText(typed);
          const ch = prompt[k];
          const jitter = ch === ' ' ? 60 : ch === ',' ? 140 : Math.random() * 30;
          await sleep(baseDelay + jitter);
        }
        clearInterval(timerHandle);
        if (myToken !== cycleToken) break;

        await sleep(650);
        demoHud.classList.remove('is-visible');
        demoField.dataset.dictationState = 'idle';
        stopTrace();

        await sleep(1700);
        i++;
      }
      running = false;
    }

    function stopCycle() {
      cycleToken++;
      demoHud.classList.remove('is-visible');
      demoField.dataset.dictationState = 'idle';
      stopTrace();
    }

    if (prefersReducedMotion.matches) {
      setText(PROMPTS[0]);
      demoTimer.textContent = '0:05';
      demoHud.classList.add('is-visible');
      demoField.dataset.dictationState = 'recording';
      resizeTraceCanvas();
      // Single static snapshot of a believable trace, no animation loop.
      for (let i = 0; i < SAMPLES; i++) {
        const t = i / SAMPLES;
        trace[i] = 0.35 + 0.25 * Math.sin(t * 14) + 0.12 * Math.sin(t * 38);
      }
      drawTrace();
    } else if ('IntersectionObserver' in window) {
      const demoIo = new IntersectionObserver((entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) runCycle();
          else stopCycle();
        }
      }, { threshold: 0.25 });
      demoIo.observe(demoCard);
      document.addEventListener('visibilitychange', () => {
        if (document.hidden) stopCycle();
        else if (demoCard.getBoundingClientRect().top < window.innerHeight) runCycle();
      });
    } else {
      runCycle();
    }
  }
  // --- 6. Sticky mobile CTA bar ----------------------------------------
  // Shows a bottom-pinned download button on <=640px viewports after the
  // user scrolls past the hero CTAs. Dismissible with an X button.
  // Respects prefers-reduced-motion: the bar still appears but without
  // the slide-in transition (handled by CSS transition: none rule).
  const stickyCta = document.getElementById('stickyCta');
  const stickyCta__close = document.getElementById('stickyCta__close');

  if (stickyCta && stickyCta__close) {
    const heroCtas = document.querySelector('.hero__ctas');
    let dismissed = false;

    // Only activate on narrow viewports
    const isNarrow = () => window.matchMedia('(max-width: 640px)').matches;

    const syncStickyCta = () => {
      if (dismissed || !isNarrow()) {
        stickyCta.classList.remove('is-visible');
        stickyCta.setAttribute('aria-hidden', 'true');
        stickyCta.querySelectorAll('a, button').forEach((el) => el.setAttribute('tabindex', '-1'));
        return;
      }

      // Show once the hero CTAs are scrolled out of the viewport
      const heroRect = heroCtas ? heroCtas.getBoundingClientRect() : null;
      const pastHero = heroRect ? heroRect.bottom < 0 : window.scrollY > 300;

      if (pastHero) {
        stickyCta.classList.add('is-visible');
        stickyCta.setAttribute('aria-hidden', 'false');
        stickyCta.querySelectorAll('a, button').forEach((el) => el.removeAttribute('tabindex'));
      } else {
        stickyCta.classList.remove('is-visible');
        stickyCta.setAttribute('aria-hidden', 'true');
        stickyCta.querySelectorAll('a, button').forEach((el) => el.setAttribute('tabindex', '-1'));
      }
    };

    document.addEventListener('scroll', syncStickyCta, { passive: true });
    window.addEventListener('resize', syncStickyCta, { passive: true });
    syncStickyCta();

    stickyCta__close.addEventListener('click', () => {
      dismissed = true;
      stickyCta.classList.remove('is-visible');
      stickyCta.classList.add('is-dismissed');
      stickyCta.setAttribute('aria-hidden', 'true');
    });
  }

})();
