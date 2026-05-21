import Image from "next/image";

import {
  AUTHOR_URL,
  ISSUES_URL,
  LICENSE_URL,
  RELEASES_URL,
  REPO_URL,
} from "@/lib/constants";
import { ExternalLink } from "@/components/ui/external-link";

type Link =
  | { kind: "internal"; href: string; label: string }
  | { kind: "external"; href: string; label: string };

type FooterColumn = {
  title: string;
  links: Link[];
};

const COLUMNS: FooterColumn[] = [
  {
    title: "Product",
    links: [
      { kind: "internal", href: "#features", label: "Features" },
      { kind: "internal", href: "#cloud", label: "Cloud" },
      { kind: "internal", href: "#compare", label: "Compare" },
      { kind: "internal", href: "#faq", label: "FAQ" },
      { kind: "internal", href: "#download", label: "Download the app" },
    ],
  },
  {
    title: "Project",
    links: [
      { kind: "external", href: REPO_URL, label: "Source on GitHub" },
      { kind: "external", href: RELEASES_URL, label: "Release history" },
      { kind: "external", href: LICENSE_URL, label: "MIT license" },
      { kind: "external", href: ISSUES_URL, label: "Report an issue" },
    ],
  },
  {
    title: "Trust",
    links: [
      { kind: "internal", href: "#faq", label: "Privacy answers" },
      { kind: "external", href: REPO_URL, label: "Audit the source code" },
      { kind: "external", href: LICENSE_URL, label: "MIT license" },
      { kind: "external", href: RELEASES_URL, label: "All releases" },
      { kind: "external", href: ISSUES_URL, label: "Report an issue" },
    ],
  },
];

function FooterLink({ link }: { link: Link }) {
  if (link.kind === "external") {
    return <ExternalLink href={link.href}>{link.label}</ExternalLink>;
  }
  return <a href={link.href}>{link.label}</a>;
}

export function Footer() {
  return (
    <footer className="footer" id="footer" aria-labelledby="footer-title">
      <div className="container footer__inner">
        <h2 id="footer-title" className="sr-only">Site footer</h2>
        <div className="footer__brand-block">
          <a className="footer__brand" href="#top" aria-label="VoiceToText home">
            <Image className="brand-mark" src="/app-icon.png" width={28} height={28} alt="" />
            <span>VoiceToText</span>
          </a>
          <p className="footer__tagline">
            Free, local-first dictation for Mac. Open source on GitHub. MIT licensed.
          </p>
          <p className="footer__attribution t-caption">
            Built in public by <ExternalLink href={AUTHOR_URL}>@gug007</ExternalLink>.
          </p>
          <p className="footer__privacy t-caption">
            No telemetry. No account. No network calls in local mode.{" "}
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
                    <FooterLink link={link} />
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
