import Image from "next/image";
import Link from "next/link";

import { DMG_URL, REPO_URL } from "@/lib/constants";
import { ExternalLink } from "@/components/ui/external-link";
import { Icon } from "@/components/ui/icon";
import { MobileNav } from "@/components/mobile-nav";
import { ThemeToggle } from "@/components/theme-toggle";

const HASH_LINKS = [
  { href: "#features", label: "Features" },
  { href: "#cloud", label: "Cloud" },
  { href: "#realtime", label: "Real-time" },
  { href: "#compare", label: "Compare" },
  { href: "#faq", label: "FAQ" },
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
    <header className="nav" data-scrolled="false">
      <div className="nav__inner">
        <a className="nav__brand" href={`${linkPrefix}#top`} aria-label="VoiceToText home">
          <Image className="brand-mark" src="/app-icon.png" width={26} height={26} alt="" priority />
          <span>VoiceToText</span>
        </a>
        <nav className="nav__primary" aria-label="Primary">
          <ul className="nav__links" role="list">
            {HASH_LINKS.map(({ href, label }) => (
              <li key={href} className="nav__link--hash"><a href={`${linkPrefix}${href}`}>{label}</a></li>
            ))}
            <li>
              <Link
                href="/meeting-recording"
                aria-current={current === "/meeting-recording" ? "page" : undefined}
              >
                Meetings
              </Link>
            </li>
          </ul>
        </nav>
        <MobileNav current={current} links={HASH_LINKS} linkPrefix={linkPrefix} />
        <nav className="nav__fallback" aria-label="Quick links">
          <Link href="/meeting-recording">Meetings</Link>
          <a className="btn btn--primary btn--sm" href={DMG_URL}>Download free</a>
        </nav>
        <ThemeToggle />
        <ExternalLink className="btn btn--secondary btn--sm" href={REPO_URL}>
          <Icon name="github" />
          <span>View source on GitHub</span>
        </ExternalLink>
      </div>
    </header>
  );
}
