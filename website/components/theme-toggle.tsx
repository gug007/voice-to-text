"use client";

import { useCallback, useEffect, useSyncExternalStore } from "react";

type Theme = "light" | "dark";

const STORAGE_KEY = "vtt-theme";

/** Page ground per theme, used only if the live background cannot be read. */
const GROUND: Record<Theme, string> = { light: "#F5F5F5", dark: "#0B0C0F" };

/** Repaint the browser chrome to match the page.
 *
 *  `viewport.themeColor` in app/layout.tsx emits a prefers-color-scheme pair,
 *  which is right until the visitor uses this toggle — an OS-light visitor on
 *  the site's dark theme would otherwise keep a light toolbar band above a
 *  near-black page. Every theme-color meta is rewritten with the same value so
 *  the result does not depend on which one the browser picks first. */
function paintBrowserChrome(theme: Theme) {
  const measured = getComputedStyle(document.body).backgroundColor;
  const color =
    measured && !/^(transparent$|rgba\(0, 0, 0, 0\)$)/.test(measured) ? measured : GROUND[theme];
  const metas = document.head.querySelectorAll<HTMLMetaElement>('meta[name="theme-color"]');
  if (metas.length === 0) {
    const meta = document.createElement("meta");
    meta.name = "theme-color";
    meta.content = color;
    document.head.appendChild(meta);
    return;
  }
  metas.forEach((meta) => meta.setAttribute("content", color));
}

function readTheme(): Theme {
  const explicit = document.documentElement.getAttribute("data-theme");
  if (explicit === "light" || explicit === "dark") return explicit;
  return window.matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark";
}

function subscribeTheme(notify: () => void): () => void {
  const media = window.matchMedia("(prefers-color-scheme: light)");
  media.addEventListener("change", notify);
  const mo = new MutationObserver(notify);
  mo.observe(document.documentElement, {
    attributes: true,
    attributeFilter: ["data-theme"],
  });
  return () => {
    media.removeEventListener("change", notify);
    mo.disconnect();
  };
}

/** Sun/moon toggle. Reads the live theme from <html data-theme> so it stays
 *  in sync if anything else flips it (e.g. another tab). */
export function ThemeToggle() {
  const theme = useSyncExternalStore<Theme>(
    subscribeTheme,
    readTheme,
    () => "light",
  );

  useEffect(() => {
    paintBrowserChrome(theme);
  }, [theme]);

  const handleToggle = useCallback(() => {
    const next: Theme = readTheme() === "dark" ? "light" : "dark";
    document.documentElement.setAttribute("data-theme", next);
    try {
      localStorage.setItem(STORAGE_KEY, next);
    } catch {
      /* localStorage may be unavailable; the toggle still updates the DOM */
    }
  }, []);

  return (
    <button
      type="button"
      className="theme-toggle"
      onClick={handleToggle}
      aria-label={`Switch to ${theme === "dark" ? "light" : "dark"} theme`}
    >
      <svg className="theme-toggle__sun" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
        <circle cx="10" cy="10" r="3.5" />
        <path d="M10 2v2M10 16v2M2 10h2M16 10h2M4.5 4.5l1.4 1.4M14.1 14.1l1.4 1.4M4.5 15.5l1.4-1.4M14.1 5.9l1.4-1.4" />
      </svg>
      <svg className="theme-toggle__moon" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
        <path d="M16 11.2A6 6 0 018.8 4 6 6 0 1016 11.2z" />
      </svg>
    </button>
  );
}
