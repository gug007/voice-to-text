import Image from "next/image";

import { REPO_URL } from "@/lib/constants";
import { ExternalLink } from "@/components/ui/external-link";
import { Icon } from "@/components/ui/icon";
import { ThemeToggle } from "@/components/theme-toggle";

const NAV_LINKS = [
  { href: "#features", label: "Features" },
  { href: "#cloud", label: "Cloud" },
  { href: "#compare", label: "Compare" },
  { href: "#faq", label: "FAQ" },
] as const;

export function Nav() {
  return (
    <header className="nav" data-scrolled="false">
      <div className="nav__inner">
        <a className="nav__brand" href="#top" aria-label="VoiceToText home">
          <Image className="brand-mark" src="/app-icon.png" width={26} height={26} alt="" priority />
          <span>VoiceToText</span>
        </a>
        <ul className="nav__links" role="list">
          {NAV_LINKS.map(({ href, label }) => (
            <li key={href}><a href={href}>{label}</a></li>
          ))}
        </ul>
        <ThemeToggle />
        <ExternalLink className="btn btn--secondary btn--sm" href={REPO_URL}>
          <Icon name="github" />
          <span>View source on GitHub</span>
        </ExternalLink>
      </div>
    </header>
  );
}
