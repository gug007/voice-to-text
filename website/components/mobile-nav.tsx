"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import type { CSSProperties } from "react";

import { DMG_URL, REPO_URL } from "@/lib/constants";
import { ExternalLink } from "@/components/ui/external-link";
import { Icon } from "@/components/ui/icon";

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

export function MobileNav({ current, links, routes, linkPrefix }: MobileNavProps) {
  const [open, setOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!open) return;

    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setOpen(false);
        window.requestAnimationFrame(() => triggerRef.current?.focus());
      }
    };
    const closeOnOutsidePress = (event: PointerEvent) => {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false);
    };

    document.addEventListener("keydown", closeOnEscape);
    document.addEventListener("pointerdown", closeOnOutsidePress);
    return () => {
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
        if (!event.currentTarget.contains(event.relatedTarget as Node | null)) setOpen(false);
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
        aria-hidden={!open}
      >
        <nav aria-label="Mobile">
          <ul role="list">
            {links.map(({ href, label }) => (
              <li key={href}>
                <a
                  href={`${linkPrefix}${href}`}
                  tabIndex={open ? 0 : -1}
                  onClick={() => closeAndFocusHashTarget(href)}
                >
                  {label}
                </a>
              </li>
            ))}
            {routes.map(({ href, label }) => (
              <li key={href}>
                <Link
                  href={href}
                  aria-current={current === href ? "page" : undefined}
                  tabIndex={open ? 0 : -1}
                  onClick={close}
                >
                  {label}
                </Link>
              </li>
            ))}
            <li>
              <ExternalLink
                href={REPO_URL}
                tabIndex={open ? 0 : -1}
                onClick={close}
                data-analytics-event="github_outbound"
                data-analytics-placement="mobile_nav"
              >
                Source
              </ExternalLink>
            </li>
          </ul>
          <a
            className="btn btn--primary nav__menu-download"
            href={DMG_URL}
            tabIndex={open ? 0 : -1}
            onClick={close}
            data-analytics-event="download_click"
            data-analytics-placement="mobile_nav"
          >
            <Icon name="download" />
            <span>Download free</span>
          </a>
        </nav>
      </div>
    </div>
  );
}
