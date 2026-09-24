"use client";

import { useEffect } from "react";

/** Page-wide effects that need the DOM: the nav's scrolled hairline, reduced-motion
 *  video pausing, and pausing decorative loops (anything marked
 *  `data-pause-offscreen`) while they are out of view. */
export function ScrollEffects() {
  useEffect(() => {
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

    if (reducedMotion.matches) {
      document
        .querySelectorAll<HTMLVideoElement>("video[data-respect-reduced-motion]")
        .forEach((video) => {
          video.pause();
          video.currentTime = 0;
        });
    }

    const nav = document.querySelector<HTMLElement>(".nav");
    const syncScrolled = () => {
      if (!nav) return;
      const next = window.scrollY > 8 ? "true" : "false";
      if (nav.dataset.scrolled !== next) nav.dataset.scrolled = next;
    };
    if (nav) {
      syncScrolled();
      document.addEventListener("scroll", syncScrolled, { passive: true });
    }

    // `.is-offscreen` pauses every CSS animation inside the element (globals.css),
    // so the hero wave and the HUD stop costing compositor time once scrolled past.
    const loops = document.querySelectorAll<HTMLElement>("[data-pause-offscreen]");
    const loopIo =
      loops.length && "IntersectionObserver" in window
        ? new IntersectionObserver(
            (entries) => {
              for (const entry of entries) {
                entry.target.classList.toggle("is-offscreen", !entry.isIntersecting);
              }
            },
            { rootMargin: "120px 0px" },
          )
        : null;
    loops.forEach((el) => loopIo?.observe(el));

    return () => {
      if (nav) document.removeEventListener("scroll", syncScrolled);
      loopIo?.disconnect();
      loops.forEach((el) => el.classList.remove("is-offscreen"));
    };
  }, []);

  return null;
}
