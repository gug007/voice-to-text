"use client";

import { useEffect } from "react";

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

    const revealTargets = document.querySelectorAll<HTMLElement>(".reveal");
    let revealIo: IntersectionObserver | null = null;
    if (revealTargets.length) {
      if (reducedMotion.matches || !("IntersectionObserver" in window)) {
        revealTargets.forEach((el) => el.classList.add("is-visible"));
      } else {
        revealIo = new IntersectionObserver(
          (entries, obs) => {
            for (const entry of entries) {
              if (entry.isIntersecting) {
                entry.target.classList.add("is-visible");
                obs.unobserve(entry.target);
              }
            }
          },
          { threshold: 0.15, rootMargin: "0px 0px -40px 0px" },
        );
        revealTargets.forEach((el) => revealIo!.observe(el));
      }
    }

    let childIo: IntersectionObserver | null = null;
    if (!reducedMotion.matches && "IntersectionObserver" in window) {
      const CHILD_SELECTORS = ".how__step, .feature-card, .compare__card";
      const childGroups = document.querySelectorAll<HTMLElement>(
        ".how__steps, .features__grid, .compare__mobile",
      );
      childIo = new IntersectionObserver(
        (entries, obs) => {
          for (const entry of entries) {
            if (entry.isIntersecting) {
              entry.target
                .querySelectorAll<HTMLElement>(".reveal-child")
                .forEach((child) => child.classList.add("is-visible"));
              obs.unobserve(entry.target);
            }
          }
        },
        { threshold: 0.1, rootMargin: "0px 0px -30px 0px" },
      );
      childGroups.forEach((group) => {
        const children = group.querySelectorAll<HTMLElement>(CHILD_SELECTORS);
        children.forEach((child, idx) => {
          child.classList.add("reveal-child");
          child.style.transitionDelay = `${idx * 60}ms`;
        });
        childIo!.observe(group);
      });
    }

    return () => {
      if (nav) document.removeEventListener("scroll", syncScrolled);
      revealIo?.disconnect();
      childIo?.disconnect();
    };
  }, []);

  return null;
}
