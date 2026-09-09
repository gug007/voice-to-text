"use client";

import { useEffect, useState } from "react";
import type { CSSProperties } from "react";

import { DMG_URL } from "@/lib/constants";
import { Icon } from "@/components/ui/icon";

const BAR: CSSProperties = {
  position: "fixed",
  left: "12px",
  right: "12px",
  bottom: "max(12px, env(safe-area-inset-bottom))",
  zIndex: 90,
  display: "flex",
  alignItems: "center",
  gap: "10px",
  padding: "10px",
  borderRadius: "14px",
  border: "1px solid var(--hairline-2, var(--border-strong))",
  background: "color-mix(in srgb, var(--surface) 92%, transparent)",
  backdropFilter: "saturate(1.6) blur(14px)",
  WebkitBackdropFilter: "saturate(1.6) blur(14px)",
  boxShadow: "var(--shadow-2, var(--shadow-lg))",
  transition: "transform .26s cubic-bezier(.2,.7,.3,1), opacity .26s ease",
};

const HIDDEN: CSSProperties = { transform: "translateY(140%)", opacity: 0, pointerEvents: "none" };
const SHOWN: CSSProperties = { transform: "translateY(0)", opacity: 1 };
const BUTTON: CSSProperties = { flex: "1 1 auto", minWidth: 0 };
const CLOSE: CSSProperties = { flex: "none", fontSize: "18px", lineHeight: 1 };

export function StickyCta() {
  const [visible, setVisible] = useState(false);
  const [dismissed, setDismissed] = useState(false);

  useEffect(() => {
    if (dismissed) return;
    const narrow = window.matchMedia("(max-width: 640px)");

    const update = () => {
      if (!narrow.matches) {
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
  const ariaHidden = visible ? "false" : "true";

  return (
    <div
      className="sticky-cta"
      style={{ ...BAR, ...(visible ? SHOWN : HIDDEN) }}
      role="complementary"
      aria-hidden={ariaHidden}
      aria-label="Download VoiceToText"
    >
      <a
        className="btn btn--primary"
        style={BUTTON}
        href={DMG_URL}
        tabIndex={interactiveTabIndex}
        aria-hidden={ariaHidden}
        data-analytics-event="download_click"
        data-analytics-placement="mobile_sticky"
      >
        <Icon name="download" />
        <span>Get it free</span>
      </a>
      <button
        type="button"
        className="iconbtn"
        style={CLOSE}
        tabIndex={interactiveTabIndex}
        aria-hidden={ariaHidden}
        aria-label="Dismiss download bar"
        onClick={() => setDismissed(true)}
      >
        &times;
      </button>
    </div>
  );
}
