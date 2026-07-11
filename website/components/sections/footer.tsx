import Image from "next/image";
import Link from "next/link";

import {
  AUTHOR_URL,
  GUIDE_PATH,
  INTEGRATION_URL,
  ISSUES_URL,
  RELEASES_URL,
  REPO_URL,
} from "@/lib/constants";
import { ExternalLink } from "@/components/ui/external-link";

type FooterLink =
  | { kind: "hash"; href: string; label: string }
  | { kind: "route"; href: string; label: string }
  | { kind: "external"; href: string; label: string };

type FooterColumn = {
  title: string;
  links: FooterLink[];
};

const COLUMNS: FooterColumn[] = [
  {
    title: "Product",
    links: [
      { kind: "route", href: GUIDE_PATH, label: "Mac voice-to-text guide" },
      { kind: "hash", href: "#features", label: "Features" },
      { kind: "hash", href: "#cloud", label: "Cloud" },
      { kind: "route", href: "/meeting-recording", label: "Record meetings" },
      { kind: "hash", href: "#compare", label: "Compare" },
      { kind: "hash", href: "#faq", label: "FAQ" },
      { kind: "hash", href: "#download", label: "Download the app" },
    ],
  },
  {
    title: "Project",
    links: [
      { kind: "external", href: REPO_URL, label: "Source on GitHub" },
      { kind: "external", href: RELEASES_URL, label: "Release history" },
      { kind: "external", href: INTEGRATION_URL, label: "Automation guide" },
      { kind: "external", href: ISSUES_URL, label: "Report an issue" },
    ],
  },
  {
    title: "Trust",
    links: [
      { kind: "hash", href: "#faq", label: "Privacy answers" },
      { kind: "external", href: REPO_URL, label: "Audit the source code" },
      { kind: "external", href: RELEASES_URL, label: "All releases" },
      { kind: "external", href: ISSUES_URL, label: "Report an issue" },
    ],
  },
];

function FooterLinkView({ link, linkPrefix }: { link: FooterLink; linkPrefix: string }) {
  if (link.kind === "external") {
    return <ExternalLink href={link.href}>{link.label}</ExternalLink>;
  }
  if (link.kind === "route") {
    return <Link href={link.href}>{link.label}</Link>;
  }
  return <a href={`${linkPrefix}${link.href}`}>{link.label}</a>;
}

type FooterProps = {
  /** Prefix applied to in-page hash links; "/" on sub-pages, "" on the home page. */
  linkPrefix?: string;
};

export function Footer({ linkPrefix = "" }: FooterProps) {
  return (
    <footer className="footer" id="footer" aria-labelledby="footer-title">
      <div className="container footer__inner">
        <h2 id="footer-title" className="sr-only">Site footer</h2>
        <div className="footer__brand-block">
          <a className="footer__brand" href={`${linkPrefix}#top`} aria-label="VoiceToText home">
            <Image className="brand-mark" src="/app-icon.png" width={28} height={28} alt="" />
            <span>VoiceToText</span>
          </a>
          <p className="footer__tagline">
            Free, local-first dictation and meeting transcription for Mac. Open source on GitHub.
          </p>
          <p className="footer__attribution t-caption">
            Built in public by <ExternalLink href={AUTHOR_URL}>@gug007</ExternalLink>.
          </p>
          <p className="footer__privacy t-caption">
            No telemetry. No account. Your audio stays on the Mac in local mode.{" "}
            <ExternalLink className="link" href={REPO_URL}>Audit the source on GitHub →</ExternalLink>
          </p>
        </div>
        <nav className="footer__columns" aria-label="Footer">
          {COLUMNS.map((column) => (
            <div key={column.title} className="footer__col">
              <h3 className="footer__col-title t-label">{column.title}</h3>
              <ul role="list">
                {column.links.map((link) => (
                  <li key={`${column.title}-${link.label}`}>
                    <FooterLinkView link={link} linkPrefix={linkPrefix} />
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </nav>
        <p className="footer__copyright t-caption">
          © 2026 VoiceToText contributors. Open source on GitHub.
        </p>
      </div>
    </footer>
  );
}
