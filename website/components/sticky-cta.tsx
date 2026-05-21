"use client";

import { useEffect, useState } from "react";

const DMG_URL = "https://github.com/gug007/voice-to-text/releases/latest/download/VoiceToText.dmg";

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
      const hero = document.querySelector<HTMLElement>(".hero__ctas");
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
      className={`sticky-cta${visible ? " is-visible" : ""}`}
      role="complementary"
      aria-hidden={ariaHidden}
      aria-label="Download VoiceToText"
    >
      <a
        className="sticky-cta__btn btn btn--primary"
        href={DMG_URL}
        download
        tabIndex={interactiveTabIndex}
        aria-hidden={ariaHidden}
      >
        <svg className="icon" aria-hidden="true">
          <use href="#i-download" />
        </svg>
        <span>Get it free</span>
      </a>
      <button
        type="button"
        className="sticky-cta__close"
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
