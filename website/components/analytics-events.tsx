"use client";

import { useEffect } from "react";

declare global {
  interface Window {
    dataLayer?: unknown[];
    gtag?: (...args: unknown[]) => void;
  }
}

type AnalyticsParams = Record<string, string | number | boolean | undefined>;

export function trackAnalyticsEvent(name: string, params: AnalyticsParams = {}) {
  if (typeof window === "undefined") return;
  if (window.gtag) {
    window.gtag("event", name, params);
    return;
  }
  window.dataLayer?.push({ event: name, ...params });
}

/** Tracks declarative CTA and disclosure interactions without making links
 * depend on JavaScript. Add data-analytics-event and optional placement/label. */
export function AnalyticsEvents() {
  useEffect(() => {
    const trackClick = (event: MouseEvent) => {
      const origin = event.target;
      if (!(origin instanceof Element)) return;
      const target = origin.closest<HTMLElement>("[data-analytics-event]");
      const eventName = target?.dataset.analyticsEvent;
      if (!target || !eventName) return;

      trackAnalyticsEvent(eventName, {
        placement: target.dataset.analyticsPlacement,
        event_label: target.dataset.analyticsLabel,
        link_url: target instanceof HTMLAnchorElement ? target.href : undefined,
      });
    };

    const trackToggle = (event: Event) => {
      const target = event.target;
      if (!(target instanceof HTMLDetailsElement)) return;
      const eventName = target.dataset.analyticsToggle;
      if (!eventName) return;

      trackAnalyticsEvent(eventName, {
        placement: target.dataset.analyticsPlacement,
        event_label: target.dataset.analyticsLabel,
        open: target.open,
      });
    };

    document.addEventListener("click", trackClick);
    document.addEventListener("toggle", trackToggle, true);
    return () => {
      document.removeEventListener("click", trackClick);
      document.removeEventListener("toggle", trackToggle, true);
    };
  }, []);

  return null;
}
