"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";

import { DMG_URL } from "@/lib/constants";
import { Icon } from "@/components/ui/icon";

type MobileNavLink = {
  href: string;
  label: string;
};

type MobileNavProps = {
  current?: string;
  links: readonly MobileNavLink[];
  linkPrefix: string;
};

export function MobileNav({ current, links, linkPrefix }: MobileNavProps) {
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
    const desktop = window.matchMedia("(min-width: 961px)");
    const closeAtDesktopWidth = (event: MediaQueryListEvent) => {
      if (!event.matches) return;
      if (open) {
        rootRef.current
          ?.closest<HTMLElement>(".nav__inner")
          ?.querySelector<HTMLElement>(".nav__brand")
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
            <li>
              <Link
                href="/meeting-recording"
                aria-current={current === "/meeting-recording" ? "page" : undefined}
                tabIndex={open ? 0 : -1}
                onClick={close}
              >
                Meetings
              </Link>
            </li>
          </ul>
          <a
            className="btn btn--primary nav__menu-download"
            href={DMG_URL}
            tabIndex={open ? 0 : -1}
            onClick={close}
          >
            <Icon name="download" />
            <span>Download free</span>
          </a>
        </nav>
      </div>
    </div>
  );
}
