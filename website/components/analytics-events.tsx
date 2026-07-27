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
    const playedVideos = new WeakSet<HTMLVideoElement>();

    const trackClick = (event: MouseEvent) => {
      const origin = event.target;
      if (!(origin instanceof Element)) return;
      const target = origin.closest<HTMLElement>("[data-analytics-event]");
      const eventName = target?.dataset.analyticsEvent;
      if (!target || !eventName) return;
      // Video starts are tracked from the media `play` event below. Counting a
      // click here as well would double-report users who press the native play
      // control, and would miss autoplay starts.
      if (target instanceof HTMLVideoElement) return;

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

    const trackVideoPlay = (event: Event) => {
      const target = event.target;
      if (!(target instanceof HTMLVideoElement) || playedVideos.has(target)) return;
      const eventName = target.dataset.analyticsEvent;
      if (!eventName) return;

      playedVideos.add(target);
      trackAnalyticsEvent(eventName, {
        placement: target.dataset.analyticsPlacement,
        event_label: target.dataset.analyticsLabel,
        autoplay: target.autoplay,
      });
    };

    document.addEventListener("click", trackClick);
    document.addEventListener("toggle", trackToggle, true);
    document.addEventListener("play", trackVideoPlay, true);
    return () => {
      document.removeEventListener("click", trackClick);
      document.removeEventListener("toggle", trackToggle, true);
      document.removeEventListener("play", trackVideoPlay, true);
    };
  }, []);

  return null;
}
