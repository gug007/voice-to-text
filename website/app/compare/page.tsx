import type { Metadata } from "next";
import Link from "next/link";

import { JsonLd } from "@/components/json-ld";
import { ScrollEffects } from "@/components/scroll-effects";
import { Footer } from "@/components/sections/footer";
import { Nav } from "@/components/sections/nav";
import styles from "@/components/seo/seo-landing.module.css";
import { StickyCta } from "@/components/sticky-cta";
import { DownloadButton } from "@/components/ui/download-button";
import { ExternalLink } from "@/components/ui/external-link";
import { Icon } from "@/components/ui/icon";
import { AUTHOR_URL, ISSUES_URL, REPO_URL, SITE_URL } from "@/lib/constants";
import { formatDisplayDate, page, pageUrl, type PagePath } from "@/lib/pages";
import { INDEXABLE_ROBOTS, PERSON_ID, SOFTWARE_ID, WEBSITE_ID, personJsonLd } from "@/lib/seo";

const PATH = "/compare";
const PAGE_URL = pageUrl(PATH);
const TITLE = "Mac Dictation & Transcription App Comparisons";
const DESCRIPTION =
  "VoiceToText compared with Wispr Flow, Superwhisper, Apple Dictation, Granola and MacWhisper, each with a short verdict, sources and the date checked.";
const H1 = "Compare VoiceToText with other Mac dictation and transcription apps.";

type Comparison = {
  path: PagePath;
  title: string;
  /** One honest line: what the other option does better, and when VoiceToText fits. */
  verdict: string;
};

type ComparisonGroup = {
  id: string;
  eyebrow: string;
  title: string;
  items: Comparison[];
};

const GROUPS: ComparisonGroup[] = [
  {
    id: "dictation-apps",
    eyebrow: "Dictation apps",
    title: "Talking into any app on your Mac.",
    items: [
      {
        path: "/compare/best-dictation-apps-for-mac",
        title: "Best dictation apps for Mac",
        verdict:
          "Mac dictation apps side by side on dictation, files, meetings, privacy path, languages and price, with a test protocol you can rerun.",
      },
      {
        path: "/wispr-flow-alternative",
        title: "VoiceToText vs. Wispr Flow",
        verdict:
          "Wispr Flow adds AI editing and apps beyond the Mac, but transcribes in the cloud. Pick VoiceToText when audio must be transcribed on your Mac.",
      },
      {
        path: "/superwhisper-alternative",
        title: "VoiceToText vs. Superwhisper",
        verdict:
          "Both run models locally. Superwhisper covers more platforms and formats text for you; VoiceToText is free, with its source on GitHub.",
      },
      {
        path: "/apple-dictation-alternative",
        title: "VoiceToText vs. Apple Dictation",
        verdict:
          "Apple Dictation is built in and needs no install. VoiceToText adds a review step, model choice, meeting capture and file import.",
      },
    ],
  },
  {
    id: "meetings-and-files",
    eyebrow: "Meetings and files",
    title: "Recording calls and transcribing recordings.",
    items: [
      {
        path: "/granola-alternative",
        title: "VoiceToText vs. Granola",
        verdict:
          "Neither sends a bot. Granola turns the notes you take during the call into AI meeting notes and syncs your calendar; VoiceToText is free and transcribes on your Mac.",
      },
      {
        path: "/macwhisper-alternative",
        title: "VoiceToText vs. MacWhisper",
        verdict:
          "MacWhisper is the deeper file tool, with exports, batch runs and an editor. VoiceToText is free and built around dictation and meetings.",
      },
    ],
  },
  {
    id: "speech-models",
    eyebrow: "Speech models",
    title: "Choosing the model inside VoiceToText.",
    items: [
      {
        path: "/whisper-vs-parakeet-mac",
        title: "Whisper vs. Parakeet on Mac",
        verdict:
          "Parakeet is the quick default for 25 European languages. Whisper Large v3 scores higher on the app’s quality scale but runs English-only here.",
      },
    ],
  },
];

const COMPARISONS = GROUPS.flatMap((group) => group.items);

/** Pages that cite vendor sources show when those were checked; the rest show their last update. */
function checkedLine(path: PagePath) {
  const record = page(path);
  const date = record.sourcesReviewed ?? record.modified;
  return (
    <>
      {record.sourcesReviewed ? "Sources checked" : "Updated"}{" "}
      <time dateTime={date}>{formatDisplayDate(date)}</time>
    </>
  );
}

export const metadata: Metadata = {
  title: TITLE,
  description: DESCRIPTION,
  alternates: { canonical: PATH },
  robots: INDEXABLE_ROBOTS,
  openGraph: {
    type: "article",
    url: PAGE_URL,
    siteName: "VoiceToText",
    title: TITLE,
    description: DESCRIPTION,
    locale: "en_US",
    publishedTime: page(PATH).published,
    modifiedTime: page(PATH).modified,
    authors: [AUTHOR_URL],
  },
  twitter: {
    card: "summary_large_image",
    title: "Every VoiceToText comparison in one place",
    description:
      "Wispr Flow, Superwhisper, Apple Dictation, Granola, MacWhisper and Whisper vs. Parakeet: honest verdicts with sources.",
  },
};

function schemas() {
  const { published, modified } = page(PATH);

  const collection = {
    "@context": "https://schema.org",
    "@type": "CollectionPage",
    "@id": `${PAGE_URL}#webpage`,
    name: TITLE,
    headline: H1,
    description: DESCRIPTION,
    url: PAGE_URL,
    datePublished: published,
    dateModified: modified,
    inLanguage: "en",
    isPartOf: { "@id": WEBSITE_ID },
    about: { "@id": SOFTWARE_ID },
    author: { "@id": PERSON_ID },
    breadcrumb: { "@id": `${PAGE_URL}#breadcrumb` },
    mainEntity: { "@id": `${PAGE_URL}#comparisons` },
  };

  const breadcrumb = {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    "@id": `${PAGE_URL}#breadcrumb`,
    itemListElement: [
      { "@type": "ListItem", position: 1, name: "Home", item: `${SITE_URL}/` },
      { "@type": "ListItem", position: 2, name: "Compare", item: PAGE_URL },
    ],
  };

  const itemList = {
    "@context": "https://schema.org",
    "@type": "ItemList",
    "@id": `${PAGE_URL}#comparisons`,
    name: "VoiceToText comparisons",
    numberOfItems: COMPARISONS.length,
    itemListElement: COMPARISONS.map((comparison, index) => ({
      "@type": "ListItem",
      position: index + 1,
      item: {
        "@type": "WebPage",
        "@id": `${pageUrl(comparison.path)}#webpage`,
        url: pageUrl(comparison.path),
        name: comparison.title,
        description: comparison.verdict,
        dateModified: page(comparison.path).modified,
      },
    })),
  };

  return { collection, breadcrumb, itemList };
}

export default function ComparePage() {
  const { collection, breadcrumb, itemList } = schemas();
  const { published } = page(PATH);

  return (
    <>
      <JsonLd data={collection} />
      <JsonLd data={breadcrumb} />
      <JsonLd data={itemList} />
      <JsonLd data={personJsonLd} />

      <Nav linkPrefix="/" current={PATH} />
      <main id="main" tabIndex={-1}>
        <article className={styles.article}>
          <header className={styles.hero} id="top" aria-labelledby="page-title">
            <div className={`container ${styles.heroInner}`}>
              <nav className="breadcrumb" aria-label="Breadcrumb">
                <ol role="list">
                  <li><Link href="/">Home</Link></li>
                  <li aria-current="page">Compare</li>
                </ol>
              </nav>
              <p className={styles.eyebrow}>
                <span className={styles.eyebrowDot} aria-hidden="true" />
                Comparisons · {COMPARISONS.length} pages
              </p>
              <h1 className={styles.title} id="page-title">{H1}</h1>
              <p className={styles.lead}>
                Each page puts VoiceToText next to one alternative, says where that app wins, lists what you give
                up by switching, and links the vendor pages behind every claim. Start with the one you use today.
              </p>
              {/* `hero__ctas` is the hook StickyCta watches to know the hero CTA has scrolled away. */}
              <div className={`hero__ctas ${styles.heroActions}`}>
                <DownloadButton placement="compare_hub_hero" />
                <a className="btn btn--secondary btn--lg" href={`#${GROUPS[0].id}`}>
                  <span>See the comparisons</span>
                  <Icon name="arrow-right" />
                </a>
              </div>
              <p className={styles.byline}>
                Written by <a href={AUTHOR_URL} rel="author">Gurgen Abagyan</a>
                {" "}· Published <time dateTime={published}>{formatDisplayDate(published)}</time>
              </p>
              <aside className={styles.disclosure} aria-label="Publisher disclosure">
                <strong>Publisher disclosure.</strong> VoiceToText’s developer writes these comparisons, so read
                them as an interested party’s work. <a href="#how-we-compare">How we compare</a> explains the
                rules each page follows.
              </aside>
            </div>
          </header>

          {GROUPS.map((group, index) => (
            <section
              className={`${styles.chapter}${index % 2 === 1 ? ` ${styles.chapterAlt}` : ""}`}
              id={group.id}
              aria-labelledby={`${group.id}-title`}
              key={group.id}
            >
              <div className={`container ${styles.content}`}>
                <header className={styles.chapterHeader}>
                  <p className={styles.sectionLabel}>{group.eyebrow}</p>
                  <h2 className={styles.sectionTitle} id={`${group.id}-title`}>{group.title}</h2>
                </header>
                <div className={`${styles.relatedGrid} ${styles.hubGrid}`}>
                  {group.items.map((comparison) => (
                    <Link className={styles.relatedCard} href={comparison.path} key={comparison.path}>
                      <h3>{comparison.title}</h3>
                      <p>{comparison.verdict}</p>
                      <span className={`${styles.relatedArrow} ${styles.relatedMeta}`}>
                        <span>{checkedLine(comparison.path)}</span>
                        <span className={styles.relatedRead}>Read →</span>
                      </span>
                    </Link>
                  ))}
                </div>
              </div>
            </section>
          ))}

          <section
            className={`${styles.chapter}${GROUPS.length % 2 === 1 ? ` ${styles.chapterAlt}` : ""}`}
            id="how-we-compare"
            aria-labelledby="how-we-compare-title"
          >
            <div className={`container ${styles.content}`}>
              <header className={styles.chapterHeader}>
                <p className={styles.sectionLabel}>Method</p>
                <h2 className={styles.sectionTitle} id="how-we-compare-title">How we compare.</h2>
                <p className={styles.sectionIntro}>
                  The author has a stake in the result, so the pages are written to be checked rather than trusted.
                </p>
              </header>
              <div className={styles.paragraphs}>
                <p>
                  Facts about other apps come only from that vendor’s own website, pricing page, documentation or
                  store page. Each comparison links them under its sources and says when they were last checked.
                  If a feature can’t be found on an official page, it’s left out, and a price appears only where the
                  vendor publishes one.
                </p>
                <p>
                  Every app comparison says where the other app wins and what you give up with VoiceToText. No page
                  ranks apps on accuracy or speed that hasn’t been measured; the best-apps page publishes a test
                  protocol instead of a score.
                </p>
                <p>
                  Facts about VoiceToText are checked against the app’s source code, which is public on GitHub.
                  If something is wrong or out of date,{" "}
                  <ExternalLink href={ISSUES_URL}>open an issue</ExternalLink> and the page will be corrected.
                </p>
              </div>
            </div>
          </section>

          <section className={styles.finalCta} aria-labelledby="final-cta-title" data-final-cta>
            <div className="container">
              <h2 id="final-cta-title">The fastest comparison is your own.</h2>
              <p>
                VoiceToText is free and needs no account. Install it next to the app you use now and dictate the
                same paragraph into both.
              </p>
              <div className={styles.finalActions}>
                <DownloadButton placement="compare_hub_bottom" label="Download VoiceToText" />
                <ExternalLink
                  className="btn btn--secondary btn--lg"
                  href={REPO_URL}
                  data-analytics-event="github_outbound"
                  data-analytics-placement="compare_hub_bottom"
                >
                  <Icon name="github" />
                  <span>Inspect the source</span>
                </ExternalLink>
              </div>
            </div>
          </section>
        </article>
      </main>
      <Footer linkPrefix="/" />
      <StickyCta />
      <ScrollEffects />
    </>
  );
}
