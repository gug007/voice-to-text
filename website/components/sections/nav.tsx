import Image from "next/image";
import Link from "next/link";

import { DMG_URL, GUIDE_PATH, REPO_URL } from "@/lib/constants";
import { ExternalLink } from "@/components/ui/external-link";
import { MobileNav } from "@/components/mobile-nav";
import { ThemeToggle } from "@/components/theme-toggle";

/* Listed in the order the sections appear in the document, so the nav reads as
 * a table of contents rather than jumping the visitor back and forth. */
const HASH_LINKS = [
  { href: "#how-it-works", label: "How it works" },
  { href: "#demo", label: "Demo" },
  { href: "#features", label: "Privacy" },
  { href: "#models", label: "Models" },
] as const;

/* One label set for both navs — MobileNav renders these same arrays, so the
 * desktop bar and the mobile drawer cannot drift into two site maps. */
const ROUTE_LINKS = [
  { href: GUIDE_PATH, label: "Guide" },
  { href: "/offline-speech-to-text-mac", label: "Offline" },
  { href: "/meeting-recording", label: "Meetings" },
  { href: "/compare/best-dictation-apps-for-mac", label: "Compare" },
] as const;

/* The desktop bar has no room for a tenth item: measured at 1181-1440px, adding
 * one drops the gap between the link row and the right-hand cluster from 51px to
 * 17px and pushes that cluster 49px past the page grid. The drawer has the room,
 * so this route lives there, under the same label the bar would have used. */
const DRAWER_ONLY_LINKS = [
  { href: "/voice-to-text-for-coding", label: "Coding" },
] as const;

type NavProps = {
  /**
   * Prefix applied to in-page hash links. Empty on the home page (so links stay
   * same-document); "/" on sub-pages so the same anchors resolve to the home page.
   */
  linkPrefix?: string;
  /** Current route path; marks the matching nav item with aria-current="page". */
  current?: string;
};

export function Nav({ linkPrefix = "", current }: NavProps) {
  return (
    <header className="nav" id="nav" data-scrolled="false">
      <div className="wrap nav__in">
        <a className="brand" href={`${linkPrefix}#top`} aria-label="VoiceToText home">
          <Image className="brand__mark" src="/app-icon.png" width={26} height={26} alt="" priority />
          <span>VoiceToText</span>
        </a>
        <nav className="nav__links nav__primary" aria-label="Sections">
          {HASH_LINKS.map(({ href, label }) => (
            <a key={href} href={`${linkPrefix}${href}`}>{label}</a>
          ))}
          {ROUTE_LINKS.map(({ href, label }) => (
            <Link key={href} href={href} aria-current={current === href ? "page" : undefined}>
              {label}
            </Link>
          ))}
          <ExternalLink
            href={REPO_URL}
            data-analytics-event="github_outbound"
            data-analytics-placement="desktop_nav"
          >
            Source
          </ExternalLink>
        </nav>
        <div className="nav__right">
          {/* No-JS chrome only: the noscript block in app/layout.tsx swaps this in
              below 1181px, where the hamburger cannot open without JavaScript. */}
          <nav className="nav__fallback" aria-label="Quick links">
            <Link href={GUIDE_PATH}>Guide</Link>
            <Link href="/meeting-recording">Meetings</Link>
            <a
              className="btn btn--primary btn--sm"
              href={DMG_URL}
              data-analytics-event="download_click"
              data-analytics-placement="nav_fallback"
            >
              Download free
            </a>
          </nav>
          <MobileNav
            current={current}
            links={HASH_LINKS}
            routes={[...ROUTE_LINKS, ...DRAWER_ONLY_LINKS]}
            linkPrefix={linkPrefix}
          />
          <ThemeToggle />
          <a
            className="btn btn--primary btn--sm"
            href={DMG_URL}
            data-analytics-event="download_click"
            data-analytics-placement="desktop_nav"
          >
            Download for Mac<span className="btn__k">free</span>
          </a>
        </div>
      </div>
    </header>
  );
}
