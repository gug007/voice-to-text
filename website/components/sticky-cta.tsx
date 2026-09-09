"use client";

import { useEffect, useState } from "react";
import type { CSSProperties } from "react";

import { DMG_URL } from "@/lib/constants";
import { Icon } from "@/components/ui/icon";

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

export function StickyCta() {
  const [visible, setVisible] = useState(false);
  const [narrow, setNarrow] = useState(false);
  const [dismissed, setDismissed] = useState(false);

  useEffect(() => {
    if (dismissed) return;
    const narrowQuery = window.matchMedia("(max-width: 640px)");

    const update = () => {
      setNarrow(narrowQuery.matches);
      if (!narrowQuery.matches) {
        setVisible(false);
        return;
      }
      const hero = document.querySelector<HTMLElement>(".hero__cta, .hero__ctas");
      const heroRect = hero?.getBoundingClientRect();
      const pastHero = heroRect ? heroRect.bottom < 0 : window.scrollY > 300;
      setVisible(pastHero);
    };

    update();
    document.addEventListener("scroll", update, { passive: true });
    window.addEventListener("resize", update, { passive: true });
    return () => {
      document.removeEventListener("scroll", update);
      window.removeEventListener("resize", update);
    };
  }, [dismissed]);

  if (dismissed) return null;

  const interactiveTabIndex = visible ? 0 : -1;

  return (
    <>
      <div
        className={`sticky-cta${visible ? " is-visible" : ""}`}
        aria-hidden={!visible}
        aria-label="Download VoiceToText"
      >
        <a
          className="btn btn--primary sticky-cta__btn"
          href={DMG_URL}
          tabIndex={interactiveTabIndex}
          data-analytics-event="download_click"
          data-analytics-placement="mobile_sticky"
        >
          <Icon name="download" />
          <span>Get it free</span>
        </a>
        <button
          type="button"
          className="sticky-cta__close"
          tabIndex={interactiveTabIndex}
          aria-label="Dismiss download bar"
          onClick={() => setDismissed(true)}
        >
          &times;
        </button>
      </div>
      {narrow ? <div style={SPACER} aria-hidden="true" /> : null}
    </>
  );
}
