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
      nav.dataset.scrolled = window.scrollY > 8 ? 'true' : 'false';
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

  // --- 3. Copy-to-clipboard for any [data-copy] element ------------------
  // Usage: <button data-copy="text or selector">Copy</button>
  // If data-copy starts with '#', it is treated as a selector and the
  // element's textContent is copied; otherwise the attribute value is used.
  const flash = (el, msg) => {
    const original = el.dataset.label || el.textContent;
    el.dataset.label = original;
    el.textContent = msg;
    window.setTimeout(() => {
      el.textContent = original;
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
})();
