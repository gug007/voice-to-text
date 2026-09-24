"use client";

import { useEffect, useState } from "react";
import type { CSSProperties } from "react";

import { DownloadButton } from "@/components/ui/download-button";

/* The bar is styled entirely by the `.sticky-cta` block in globals.css, which
 * already carries the ≤640px breakpoint, the shown/hidden transition and the
 * 44x44 dismiss target. This component only toggles `.is-visible`; it must not
 * re-declare those styles inline, or the stylesheet's `pointer-events` swap
 * never reaches the element. */

/* Height the bar occupies at the bottom of the viewport (68px bar + its 12px
 * inset + breathing room), reserved after the footer so the last footer row can
 * scroll clear of the bar instead of sitting permanently underneath it. */
const SPACER: CSSProperties = {
  height: "calc(92px + env(safe-area-inset-bottom, 0px))",
  background: "var(--bg-deep)",
};

/* A page's own closing download block. While one is on screen the bar would
 * only repeat the button right above it. */
const FINAL_CTA = "#download, [data-final-cta]";
const DISMISS_KEY = "vtt-sticky-cta-dismissed";

function readDismissed(): boolean {
  try {
    return sessionStorage.getItem(DISMISS_KEY) === "1";
  } catch {
    return false;
  }
}

export function StickyCta() {
  const [pastHero, setPastHero] = useState(false);
  const [finalInView, setFinalInView] = useState(false);
  const [narrow, setNarrow] = useState(false);
  const [dismissed, setDismissed] = useState(false);

  useEffect(() => {
    const syncDismissed = () => setDismissed(readDismissed());
    syncDismissed();
  }, []);

  useEffect(() => {
    if (dismissed) return;
    const narrowQuery = window.matchMedia("(max-width: 640px)");

    const update = () => {
      setNarrow(narrowQuery.matches);
      if (!narrowQuery.matches) {
        setPastHero(false);
        return;
      }
      const hero = document.querySelector<HTMLElement>(".hero__cta, .hero__ctas");
      const heroRect = hero?.getBoundingClientRect();
      setPastHero(heroRect ? heroRect.bottom < 0 : window.scrollY > 300);
    };

    const finals = document.querySelectorAll<HTMLElement>(FINAL_CTA);
    const onScreen = new Set<Element>();
    const io =
      finals.length && "IntersectionObserver" in window
        ? new IntersectionObserver((entries) => {
            for (const entry of entries) {
              if (entry.isIntersecting) onScreen.add(entry.target);
              else onScreen.delete(entry.target);
            }
            setFinalInView(onScreen.size > 0);
          })
        : null;
    finals.forEach((el) => io?.observe(el));

    update();
    document.addEventListener("scroll", update, { passive: true });
    window.addEventListener("resize", update, { passive: true });
    return () => {
      document.removeEventListener("scroll", update);
      window.removeEventListener("resize", update);
      io?.disconnect();
    };
  }, [dismissed]);

  if (dismissed) return null;

  const visible = pastHero && !finalInView;
  const dismiss = () => {
    setDismissed(true);
    try {
      sessionStorage.setItem(DISMISS_KEY, "1");
    } catch {
      /* storage may be blocked; the bar still closes for this page */
    }
  };

  // The wrapper is the body-level node MobileNav's inertOutside() toggles, so
  // it never fights React over the inner bar's own inert={!visible}.
  return (
    <div>
      {/* `inert` keeps the hidden bar's controls out of the tab order and the
          accessibility tree while it sits offscreen. */}
      <div
        className={`sticky-cta${visible ? " is-visible" : ""}`}
        aria-label="Download VoiceToText"
        role="region"
        inert={!visible}
      >
        <DownloadButton
          placement="mobile_sticky"
          size="md"
          label="Get it free"
          className="sticky-cta__btn"
        />
        <button
          type="button"
          className="sticky-cta__close"
          aria-label="Dismiss download bar"
          onClick={dismiss}
        >
          &times;
        </button>
      </div>
      {narrow ? <div style={SPACER} aria-hidden="true" /> : null}
    </div>
  );
}
