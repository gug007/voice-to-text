import Link from "next/link";
import type { ReactNode } from "react";

import { JsonLd } from "@/components/json-ld";
import { ScrollEffects } from "@/components/scroll-effects";
import { Footer } from "@/components/sections/footer";
import { Nav } from "@/components/sections/nav";
import { StickyCta } from "@/components/sticky-cta";
import { ExternalLink } from "@/components/ui/external-link";
import { Icon } from "@/components/ui/icon";
import { AUTHOR_URL, DMG_URL, REPO_URL, SITE_URL } from "@/lib/constants";
import { PERSON_ID, SOFTWARE_ID, WEBSITE_ID, personJsonLd } from "@/lib/seo";

import styles from "./seo-landing.module.css";

export type ContentCard = {
  title: string;
  body: ReactNode;
};

export type ContentSection = {
  id: string;
  eyebrow: string;
  title: string;
  intro?: ReactNode;
  paragraphs?: ReactNode[];
  cards?: ContentCard[];
  note?: ReactNode;
};

export type ComparisonTable = {
  caption: string;
  columns: string[];
  rows: Array<{
    label: string;
    cells: ReactNode[];
  }>;
  note?: ReactNode;
};

export type SourceLink = {
  label: string;
  href: string;
  detail: string;
};

export type RelatedLink = {
  href: string;
  title: string;
  description: string;
};

export type SeoLandingConfig = {
  path: string;
  title: string;
  description: string;
  breadcrumb: string;
  eyebrow: string;
  readingTime: string;
  h1: string;
  lead: string;
  heroPoints: string[];
  summaryTitle: string;
  summary: ReactNode;
  sections: ContentSection[];
  comparison?: ComparisonTable;
  sources?: SourceLink[];
  related: RelatedLink[];
  ctaTitle: string;
  ctaBody: string;
  analyticsPlacement: string;
  published?: string;
  modified?: string;
};

const DEFAULT_DATE = "2026-07-27";
const DISPLAY_DATE_FORMATTER = new Intl.DateTimeFormat("en-US", {
  dateStyle: "long",
  timeZone: "UTC",
});

function formatDisplayDate(value: string) {
  return DISPLAY_DATE_FORMATTER.format(new Date(`${value}T00:00:00Z`));
}

function schemas(config: SeoLandingConfig) {
  const pageUrl = `${SITE_URL}${config.path}`;
  const published = config.published ?? DEFAULT_DATE;
  const modified = config.modified ?? DEFAULT_DATE;

  const breadcrumb = {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    "@id": `${pageUrl}#breadcrumb`,
    itemListElement: [
      {
        "@type": "ListItem",
        position: 1,
        name: "Home",
        item: `${SITE_URL}/`,
      },
      {
        "@type": "ListItem",
        position: 2,
        name: config.breadcrumb,
        item: pageUrl,
      },
    ],
  };

  const article = {
    "@context": "https://schema.org",
    "@type": "Article",
    "@id": `${pageUrl}#article`,
    headline: config.h1,
    description: config.description,
    url: pageUrl,
    datePublished: published,
    dateModified: modified,
    inLanguage: "en",
    author: { "@id": PERSON_ID },
    publisher: { "@id": PERSON_ID },
    image: {
      "@type": "ImageObject",
      url: `${SITE_URL}/opengraph-image`,
      width: 1200,
      height: 630,
    },
    isPartOf: { "@id": WEBSITE_ID },
    about: { "@id": SOFTWARE_ID },
    mainEntityOfPage: { "@id": `${pageUrl}#webpage` },
  };

  const webPage = {
    "@context": "https://schema.org",
    "@type": "WebPage",
    "@id": `${pageUrl}#webpage`,
    name: config.title,
    description: config.description,
    url: pageUrl,
    datePublished: published,
    dateModified: modified,
    inLanguage: "en",
    isPartOf: { "@id": WEBSITE_ID },
    about: { "@id": SOFTWARE_ID },
    author: { "@id": PERSON_ID },
    breadcrumb: { "@id": `${pageUrl}#breadcrumb` },
    mainEntity: { "@id": `${pageUrl}#article` },
  };

  return { article, webPage, breadcrumb };
}

function PageSection({ section, index }: { section: ContentSection; index: number }) {
  return (
    <section
      className={`${styles.chapter}${index % 2 === 1 ? ` ${styles.chapterAlt}` : ""}`}
      id={section.id}
      aria-labelledby={`${section.id}-title`}
    >
      <div className={`container ${styles.content}`}>
        <header className={styles.chapterHeader}>
          <p className={styles.sectionLabel}>{section.eyebrow}</p>
          <h2 className={styles.sectionTitle} id={`${section.id}-title`}>
            {section.title}
          </h2>
          {section.intro ? <div className={styles.sectionIntro}>{section.intro}</div> : null}
        </header>

        {section.paragraphs?.length ? (
          <div className={styles.paragraphs}>
            {section.paragraphs.map((paragraph, paragraphIndex) => (
              <p key={paragraphIndex}>{paragraph}</p>
            ))}
          </div>
        ) : null}

        {section.cards?.length ? (
          <div className={styles.cards}>
            {section.cards.map((card, cardIndex) => (
              <article className={styles.card} key={card.title}>
                <span className={styles.cardIndex} aria-hidden="true">
                  {String(cardIndex + 1).padStart(2, "0")}
                </span>
                <h3>{card.title}</h3>
                <p>{card.body}</p>
              </article>
            ))}
          </div>
        ) : null}

        {section.note ? <aside className={styles.note}>{section.note}</aside> : null}
      </div>
    </section>
  );
}

export function SeoLandingPage({ config }: { config: SeoLandingConfig }) {
  const { article, webPage, breadcrumb } = schemas(config);
  const published = config.published ?? DEFAULT_DATE;
  const modified = config.modified ?? DEFAULT_DATE;

  return (
    <>
      <JsonLd data={article} />
      <JsonLd data={webPage} />
      <JsonLd data={breadcrumb} />
      <JsonLd data={personJsonLd} />

      <Nav linkPrefix="/" current={config.path} />
      <main id="main" tabIndex={-1}>
        <article className={styles.article}>
          <header className={styles.hero} id="top" aria-labelledby="page-title">
            <div className={`container ${styles.heroInner}`}>
              <nav className="breadcrumb" aria-label="Breadcrumb">
                <ol role="list">
                  <li><Link href="/">Home</Link></li>
                  <li aria-current="page">{config.breadcrumb}</li>
                </ol>
              </nav>
              <p className={styles.eyebrow}>
                <span className={styles.eyebrowDot} aria-hidden="true" />
                {config.eyebrow} · {config.readingTime}
              </p>
              <h1 className={styles.title} id="page-title">{config.h1}</h1>
              <p className={styles.lead}>{config.lead}</p>
              <div className={`hero__ctas ${styles.heroActions}`}>
                <a
                  className="btn btn--primary btn--lg"
                  href={DMG_URL}
                  data-analytics-event="download_click"
                  data-analytics-placement={`${config.analyticsPlacement}_hero`}
                >
                  <Icon name="download" />
                  <span>Download for Mac — free</span>
                </a>
                <a className="btn btn--secondary btn--lg" href="#answer">
                  <span>Read the short answer</span>
                  <Icon name="arrow-right" />
                </a>
              </div>
              <p className={styles.byline}>
                Written by{" "}
                <a href={AUTHOR_URL} rel="author">Gurgen Abagyan</a>
                {" "}· Published <time dateTime={published}>{formatDisplayDate(published)}</time>
                {modified !== published ? (
                  <> · Updated <time dateTime={modified}>{formatDisplayDate(modified)}</time></>
                ) : null}
              </p>
              <ul className={styles.heroPoints} role="list">
                {config.heroPoints.map((point) => <li key={point}>{point}</li>)}
              </ul>
            </div>
          </header>

          <section className={styles.chapter} id="answer" aria-labelledby="answer-title">
            <div className={`container ${styles.content}`}>
              <div className={styles.summary}>
                <h2 id="answer-title">{config.summaryTitle}</h2>
                <p>{config.summary}</p>
              </div>
            </div>
          </section>

          {config.sections.map((section, index) => (
            <PageSection section={section} index={index} key={section.id} />
          ))}

          {config.comparison ? (
            <section className={`${styles.chapter} ${styles.chapterAlt}`} aria-labelledby="comparison-title">
              <div className={`container ${styles.content}`}>
                <header className={styles.chapterHeader}>
                  <p className={styles.sectionLabel}>Side-by-side</p>
                  <h2 className={styles.sectionTitle} id="comparison-title">Compare the practical differences.</h2>
                </header>
                <div className={styles.tableWrap}>
                  <table className={styles.comparisonTable}>
                    <caption>{config.comparison.caption}</caption>
                    <thead>
                      <tr>
                        <th scope="col">Decision point</th>
                        {config.comparison.columns.map((column) => <th scope="col" key={column}>{column}</th>)}
                      </tr>
                    </thead>
                    <tbody>
                      {config.comparison.rows.map((row) => (
                        <tr key={row.label}>
                          <th scope="row">{row.label}</th>
                          {row.cells.map((cell, cellIndex) => <td key={cellIndex}>{cell}</td>)}
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
                {config.comparison.note ? <aside className={styles.note}>{config.comparison.note}</aside> : null}
              </div>
            </section>
          ) : null}

          {config.sources?.length ? (
            <section className={styles.chapter} aria-labelledby="sources-title">
              <div className={`container ${styles.content}`}>
                <header className={styles.chapterHeader}>
                  <p className={styles.sectionLabel}>Primary sources</p>
                  <h2 className={styles.sectionTitle} id="sources-title">Check the claims at the source.</h2>
                  <p className={styles.sectionIntro}>
                    Product behavior changes. These official pages were reviewed on July 27, 2026.
                  </p>
                </header>
                <ul className={styles.sourceList} role="list">
                  {config.sources.map((source) => (
                    <li className={styles.sourceItem} key={source.href}>
                      <ExternalLink href={source.href}>{source.label} ↗</ExternalLink>
                      <p>{source.detail}</p>
                    </li>
                  ))}
                </ul>
              </div>
            </section>
          ) : null}

          <section className={`${styles.chapter} ${styles.chapterAlt}`} aria-labelledby="related-title">
            <div className={`container ${styles.content}`}>
              <header className={styles.chapterHeader}>
                <p className={styles.sectionLabel}>Keep exploring</p>
                <h2 className={styles.sectionTitle} id="related-title">Related Mac voice-to-text guides.</h2>
              </header>
              <div className={styles.relatedGrid}>
                {config.related.map((related) => (
                  <Link className={styles.relatedCard} href={related.href} key={related.href}>
                    <h3>{related.title}</h3>
                    <p>{related.description}</p>
                    <span className={styles.relatedArrow}>Read the guide →</span>
                  </Link>
                ))}
              </div>
            </div>
          </section>

          <section className={styles.finalCta} aria-labelledby="final-cta-title">
            <div className="container">
              <h2 id="final-cta-title">{config.ctaTitle}</h2>
              <p>{config.ctaBody}</p>
              <div className={styles.finalActions}>
                <a
                  className="btn btn--primary btn--lg"
                  href={DMG_URL}
                  data-analytics-event="download_click"
                  data-analytics-placement={`${config.analyticsPlacement}_bottom`}
                >
                  <Icon name="download" />
                  <span>Download VoiceToText</span>
                </a>
                <ExternalLink
                  className="btn btn--secondary btn--lg"
                  href={REPO_URL}
                  data-analytics-event="github_outbound"
                  data-analytics-placement={`${config.analyticsPlacement}_bottom`}
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
