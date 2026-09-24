"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import type { CSSProperties } from "react";
import { createPortal } from "react-dom";

import { REPO_URL } from "@/lib/constants";
import { DownloadButton } from "@/components/ui/download-button";
import { ExternalLink } from "@/components/ui/external-link";

type MobileNavLink = {
  href: string;
  label: string;
};

type MobileNavProps = {
  current?: string;
  /** In-page anchors, in document order. */
  links: readonly MobileNavLink[];
  /** Sub-page routes — the same array the desktop bar renders. */
  routes: readonly MobileNavLink[];
  linkPrefix: string;
};

/* The panel must be opaque. Its own backdrop-filter cannot work: the ancestor
 * `.nav` declares one and so becomes the backdrop root, leaving the menu
 * sampling an empty backdrop while page copy reads straight through the 8%
 * transparency of its fill. An opaque surface is the only reliable separation
 * (the @supports fallback in globals.css patches `.nav`, never this panel). */
const PANEL: CSSProperties = {
  background: "var(--surface)",
  backdropFilter: "none",
  WebkitBackdropFilter: "none",
};

/* While the menu is open everything outside the header is inert, so Tab cannot
 * wander into page content hidden behind the panel. Returns the undo. */
function inertOutside(keep: Element): () => void {
  const made = Array.from(document.body.children).filter(
    (el): el is HTMLElement =>
      el instanceof HTMLElement && !el.contains(keep) && !el.classList.contains("nav__scrim") && !el.inert,
  );
  made.forEach((el) => {
    el.inert = true;
  });
  return () =>
    made.forEach((el) => {
      el.inert = false;
    });
}

export function MobileNav({ current, links, routes, linkPrefix }: MobileNavProps) {
  const [open, setOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!open || !rootRef.current) return;

    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setOpen(false);
        window.requestAnimationFrame(() => triggerRef.current?.focus());
      }
    };
    // The scrim closes on its own click; closing here on pointerdown would let
    // the click that follows land on the page underneath.
    const closeOnOutsidePress = (event: PointerEvent) => {
      const target = event.target;
      if (!(target instanceof Element) || target.closest(".nav__scrim")) return;
      if (!rootRef.current?.contains(target)) setOpen(false);
    };

    const restoreInert = inertOutside(rootRef.current);
    document.addEventListener("keydown", closeOnEscape);
    document.addEventListener("pointerdown", closeOnOutsidePress);
    return () => {
      restoreInert();
      document.removeEventListener("keydown", closeOnEscape);
      document.removeEventListener("pointerdown", closeOnOutsidePress);
    };
  }, [open]);

  useEffect(() => {
    const desktop = window.matchMedia("(min-width: 1181px)");
    const closeAtDesktopWidth = (event: MediaQueryListEvent) => {
      if (!event.matches) return;
      if (open) {
        rootRef.current
          ?.closest<HTMLElement>(".nav__in")
          ?.querySelector<HTMLElement>(".brand")
          ?.focus();
      }
      setOpen(false);
    };
    desktop.addEventListener("change", closeAtDesktopWidth);
    return () => desktop.removeEventListener("change", closeAtDesktopWidth);
  }, [open]);

  const close = () => setOpen(false);
  const closeAndFocusHashTarget = (href: string) => {
    close();
    if (linkPrefix || !href.startsWith("#")) return;

    window.requestAnimationFrame(() => {
      const section = document.getElementById(href.slice(1));
      if (!section) return;
      const labelId = section.getAttribute("aria-labelledby");
      const target = (labelId ? document.getElementById(labelId) : null) ?? section;
      const hadTabIndex = target.hasAttribute("tabindex");
      if (!hadTabIndex) target.tabIndex = -1;
      target.focus({ preventScroll: true });
      if (!hadTabIndex) {
        target.addEventListener("blur", () => target.removeAttribute("tabindex"), { once: true });
      }
    });
  };

  return (
    <div
      ref={rootRef}
      className="nav__mobile"
      onBlur={(event) => {
        // Only a real focus move closes the menu. A press on the scrim blurs to
        // nothing, and the scrim's own click handles that.
        const next = event.relatedTarget;
        if (next && !event.currentTarget.contains(next)) setOpen(false);
      }}
    >
      <button
        ref={triggerRef}
        type="button"
        className="nav__menu-trigger"
        aria-label={open ? "Close navigation" : "Open navigation"}
        aria-expanded={open}
        aria-controls="mobile-navigation"
        onClick={() => setOpen((value) => !value)}
      >
        <span className="nav__menu-lines" aria-hidden="true">
          <span />
          <span />
        </span>
      </button>

      <div
        id="mobile-navigation"
        className={`nav__menu${open ? " is-open" : ""}`}
        style={PANEL}
        inert={!open}
      >
        <nav aria-label="Mobile">
          <ul role="list">
            {links.map(({ href, label }) => (
              <li key={href}>
                <a href={`${linkPrefix}${href}`} onClick={() => closeAndFocusHashTarget(href)}>
                  {label}
                </a>
              </li>
            ))}
            {routes.map(({ href, label }) => (
              <li key={href}>
                <Link href={href} aria-current={current === href ? "page" : undefined} onClick={close}>
                  {label}
                </Link>
              </li>
            ))}
            <li>
              <ExternalLink
                href={REPO_URL}
                onClick={close}
                data-analytics-event="github_outbound"
                data-analytics-placement="mobile_nav"
              >
                Source
              </ExternalLink>
            </li>
          </ul>
          <DownloadButton
            placement="mobile_nav"
            size="md"
            label="Download free"
            className="nav__menu-download"
          />
        </nav>
      </div>

      {/* Portalled to <body>: `.nav` has a backdrop-filter, which would make it
          the containing block for a fixed child and shrink the scrim to the bar. */}
      {open
        ? createPortal(<div className="nav__scrim" aria-hidden="true" onClick={close} />, document.body)
        : null}
    </div>
  );
}
