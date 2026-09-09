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
  /** Column heading; also seeds the id that labels the column's <nav>. */
  id: string;
  title: string;
  links: FooterLink[];
};

const COLUMNS: FooterColumn[] = [
  {
    id: "ft-product",
    title: "Product",
    links: [
      { kind: "hash", href: "#how-it-works", label: "How it works" },
      { kind: "hash", href: "#features", label: "Privacy & features" },
      { kind: "hash", href: "#models", label: "Local models" },
      { kind: "route", href: "/meeting-recording", label: "Meeting recorder for Mac" },
      { kind: "hash", href: "#faq", label: "FAQ" },
      { kind: "hash", href: "#download", label: "Download the app" },
    ],
  },
  {
    id: "ft-learn",
    title: "Learn",
    links: [
      { kind: "route", href: GUIDE_PATH, label: "Mac voice-to-text setup" },
      { kind: "route", href: "/offline-speech-to-text-mac", label: "Offline speech to text" },
      { kind: "route", href: "/voice-to-text-for-coding", label: "Voice to text for coding" },
      { kind: "route", href: "/apple-dictation-alternative", label: "Apple Dictation alternative" },
      { kind: "route", href: "/whisper-vs-parakeet-mac", label: "Whisper vs. Parakeet" },
      { kind: "route", href: "/superwhisper-alternative", label: "Superwhisper alternative" },
      { kind: "route", href: "/wispr-flow-alternative", label: "Wispr Flow alternative" },
      { kind: "route", href: "/compare/best-dictation-apps-for-mac", label: "Best dictation apps for Mac" },
    ],
  },
  {
    id: "ft-source",
    title: "Source",
    links: [
      { kind: "external", href: REPO_URL, label: "Source on GitHub" },
      { kind: "external", href: RELEASES_URL, label: "Release history" },
      { kind: "external", href: INTEGRATION_URL, label: "Automation guide" },
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
    <footer className="foot" id="footer" aria-labelledby="footer-title">
      <div className="wrap">
        <h2 id="footer-title" className="sr-only">Site footer</h2>
        <div className="foot__grid">
          <div>
            <a className="brand" href={`${linkPrefix}#top`} aria-label="VoiceToText home">
              <Image className="brand__mark" src="/app-icon.png" width={26} height={26} alt="" />
              <span>VoiceToText</span>
            </a>
            <p className="foot__about">
              Free, local-first dictation and meeting transcription for macOS. Built in SwiftUI,
              transcribing on-device, with no servers of its own.
            </p>
            <p className="foot__about">
              No app telemetry. No account. Your audio stays on the Mac in local mode.{" "}
              <ExternalLink href={REPO_URL}>Audit the source on GitHub</ExternalLink>
            </p>
          </div>
          {COLUMNS.map((column) => (
            <nav key={column.id} aria-labelledby={column.id}>
              <p className="foot__h" id={column.id}>{column.title}</p>
              <ul>
                {column.links.map((link) => (
                  <li key={`${column.id}-${link.label}`}>
                    <FooterLinkView link={link} linkPrefix={linkPrefix} />
                  </li>
                ))}
              </ul>
            </nav>
          ))}
        </div>
        <div className="foot__bar">
          <span>© 2026 VoiceToText contributors</span>
          <span className="sep" aria-hidden="true" />
          <span>Free forever &middot; no accounts</span>
          <span className="sep" aria-hidden="true" />
          <span>macOS 15.0+</span>
          <span className="sep" aria-hidden="true" />
          <span>
            Built in public by <ExternalLink href={AUTHOR_URL}>@gug007</ExternalLink>
          </span>
        </div>
      </div>
    </footer>
  );
}
