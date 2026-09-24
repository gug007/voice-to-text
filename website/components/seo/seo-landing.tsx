import type { Metadata } from "next";
import Link from "next/link";
import type { CSSProperties, ReactNode } from "react";

import { JsonLd } from "@/components/json-ld";
import { ScrollEffects } from "@/components/scroll-effects";
import { Footer } from "@/components/sections/footer";
import { Nav } from "@/components/sections/nav";
import { StickyCta } from "@/components/sticky-cta";
import { DownloadButton } from "@/components/ui/download-button";
import { ExternalLink } from "@/components/ui/external-link";
import { Icon } from "@/components/ui/icon";
import { AUTHOR_URL, REPO_URL, SITE_URL } from "@/lib/constants";
import { formatDisplayDate, page, pageUrl, type PagePath } from "@/lib/pages";
import { PERSON_ID, SOFTWARE_ID, WEBSITE_ID, personJsonLd } from "@/lib/seo";
import { INDEXABLE_ROBOTS } from "@/lib/seo-ids";

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
  /** Section heading. Defaults to "Compare the practical differences." (or "At a glance."). */
  title?: string;
  caption: string;
  /** Header of the row-label column. Defaults to "Decision point". */
  rowHeader?: string;
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
  href: PagePath;
  title: string;
  description: string;
};

/** Plain text on purpose: the same strings are the visible answers and the FAQPage JSON-LD. */
export type LandingFaqEntry = {
  question: string;
  answer: string;
};

export type SeoLandingConfig = {
  /** Also the key into lib/pages.ts, which supplies every date the page shows or emits. */
  path: PagePath;
  /**
   * Optional middle breadcrumb (e.g. the /compare hub), rendered as a link and
   * emitted as the second BreadcrumbList item. The URL itself does not change.
   */
  parent?: { name: string; path: PagePath };
  title: string;
  description: string;
  breadcrumb: string;
  eyebrow: string;
  /** Honest estimate of the main content at ~230 words per minute, e.g. "6 min". */
  readingTime: string;
  h1: string;
  lead: string;
  heroPoints: string[];
  summaryTitle: string;
  summary: ReactNode;
  /** Compact table shown right after the short answer, for readers who only want the verdict. */
  atAGlance?: ComparisonTable;
  sections: ContentSection[];
  comparison?: ComparisonTable;
  faq?: LandingFaqEntry[];
  faqTitle?: string;
  sources?: SourceLink[];
  related: RelatedLink[];
  /** Publisher disclosure shown under the byline, e.g. on pages comparing VoiceToText with a competitor. */
  disclosure?: ReactNode;
  ctaTitle: string;
  ctaBody: string;
  analyticsPlacement: string;
};

/** Shared metadata for every SeoLandingPage route, so canonical, og:url and dates all come from config.path. */
export function landingMetadata(
  config: SeoLandingConfig,
  twitter: { title: string; description: string },
): Metadata {
  const { published, modified } = page(config.path);
  return {
    title: config.title,
    description: config.description,
    alternates: { canonical: config.path },
    robots: INDEXABLE_ROBOTS,
    openGraph: {
      type: "article",
      url: pageUrl(config.path),
      siteName: "VoiceToText",
      title: config.title,
      description: config.description,
      locale: "en_US",
      publishedTime: published,
      modifiedTime: modified,
      authors: [AUTHOR_URL],
    },
    twitter: { card: "summary_large_image", ...twitter },
  };
}

function schemas(config: SeoLandingConfig) {
  const url = pageUrl(config.path);
  const { published, modified } = page(config.path);

  const breadcrumb = {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    "@id": `${url}#breadcrumb`,
    itemListElement: [
      { name: "Home", item: `${SITE_URL}/` },
      ...(config.parent ? [{ name: config.parent.name, item: pageUrl(config.parent.path) }] : []),
      { name: config.breadcrumb, item: url },
    ].map((crumb, index) => ({ "@type": "ListItem", position: index + 1, ...crumb })),
  };

  const article = {
    "@context": "https://schema.org",
    "@type": "Article",
    "@id": `${url}#article`,
    headline: config.h1,
    description: config.description,
    url,
    datePublished: published,
    dateModified: modified,
    inLanguage: "en",
    author: { "@id": PERSON_ID },
    publisher: { "@id": PERSON_ID },
    image: {
      "@type": "ImageObject",
      // The route's own opengraph-image.tsx; every landing route ships one.
      url: `${url}/opengraph-image`,
      width: 1200,
      height: 630,
    },
    isPartOf: { "@id": WEBSITE_ID },
    about: { "@id": SOFTWARE_ID },
    mainEntityOfPage: { "@id": `${url}#webpage` },
  };

  const webPage = {
    "@context": "https://schema.org",
    "@type": "WebPage",
    "@id": `${url}#webpage`,
    name: config.title,
    description: config.description,
    url,
    datePublished: published,
    dateModified: modified,
    inLanguage: "en",
    isPartOf: { "@id": WEBSITE_ID },
    about: { "@id": SOFTWARE_ID },
    author: { "@id": PERSON_ID },
    breadcrumb: { "@id": `${url}#breadcrumb` },
    mainEntity: { "@id": `${url}#article` },
  };

  const faqPage = config.faq?.length
    ? {
        "@context": "https://schema.org",
        "@type": "FAQPage",
        "@id": `${url}#faq`,
        url,
        isPartOf: { "@id": `${url}#webpage` },
        mainEntity: config.faq.map(({ question, answer }) => ({
          "@type": "Question",
          name: question,
          acceptedAnswer: { "@type": "Answer", text: answer },
        })),
      }
    : null;

  return { article, webPage, breadcrumb, faqPage };
}

function ComparisonTableView({
  table,
  labelledBy,
  compact = false,
}: {
  table: ComparisonTable;
  labelledBy: string;
  compact?: boolean;
}) {
  const captionId = `${labelledBy}-caption`;
  return (
    <>
      <p className={styles.scrollHint} id={captionId}>
        {table.caption}
        <span className={styles.swipeHint}> Swipe sideways to see every column.</span>
      </p>
      <div
        className={styles.tableWrap}
        tabIndex={0}
        role="region"
        aria-labelledby={labelledBy}
        aria-describedby={captionId}
      >
        <table
          className={`${styles.comparisonTable}${compact ? ` ${styles.compactTable}` : ""}`}
          style={{ "--cols": table.columns.length } as CSSProperties}
        >
          <caption className="sr-only">{table.caption}</caption>
          <thead>
            <tr>
              <th scope="col">{table.rowHeader ?? "Decision point"}</th>
              {table.columns.map((column) => <th scope="col" key={column}>{column}</th>)}
            </tr>
          </thead>
          <tbody>
            {table.rows.map((row) => (
              <tr key={row.label}>
                <th scope="row">{row.label}</th>
                {row.cells.map((cell, cellIndex) => <td key={cellIndex}>{cell}</td>)}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {table.note ? <aside className={styles.note}>{table.note}</aside> : null}
    </>
  );
}

function PageSection({ section, index }: { section: ContentSection; index: number }) {
  const paragraphs = section.paragraphs?.length ? (
    <div className={styles.paragraphs}>
      {section.paragraphs.map((paragraph, paragraphIndex) => (
        <p key={paragraphIndex}>{paragraph}</p>
      ))}
    </div>
  ) : null;
  const note = section.note ? <aside className={styles.note}>{section.note}</aside> : null;
  // A prose-only chapter with a note sets the note beside the paragraphs on wide screens.
  const proseWithNote = Boolean(paragraphs && note && !section.cards?.length);

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

        {proseWithNote ? (
          <div className={styles.prose}>
            {paragraphs}
            {note}
          </div>
        ) : (
          paragraphs
        )}

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

        {proseWithNote ? null : note}
      </div>
    </section>
  );
}

export function SeoLandingPage({ config }: { config: SeoLandingConfig }) {
  const { article, webPage, breadcrumb, faqPage } = schemas(config);
  const { published, modified, sourcesReviewed } = page(config.path);

  // The optional blocks after the content sections keep the sections'
  // alternating band going, whichever of them a page includes.
  const tail = [
    config.comparison ? "comparison" : null,
    config.faq?.length ? "faq" : null,
    config.sources?.length ? "sources" : null,
    "related",
  ].filter(Boolean);
  const tailStartsBanded = config.sections.length % 2 === 1;
  const band = (block: string) =>
    (tail.indexOf(block) % 2 === 0) === tailStartsBanded ? ` ${styles.chapterAlt}` : "";

  return (
    <>
      <JsonLd data={article} />
      <JsonLd data={webPage} />
      <JsonLd data={breadcrumb} />
      {faqPage ? <JsonLd data={faqPage} /> : null}
      <JsonLd data={personJsonLd} />

      <Nav linkPrefix="/" current={config.path} />
      <main id="main" tabIndex={-1}>
        <article className={styles.article}>
          <header className={styles.hero} id="top" aria-labelledby="page-title">
            <div className={`container ${styles.heroInner}`}>
              <nav className="breadcrumb" aria-label="Breadcrumb">
                <ol role="list">
                  <li><Link href="/">Home</Link></li>
                  {config.parent ? (
                    <li><Link href={config.parent.path}>{config.parent.name}</Link></li>
                  ) : null}
                  <li aria-current="page">{config.breadcrumb}</li>
                </ol>
              </nav>
              <p className={styles.eyebrow}>
                <span className={styles.eyebrowDot} aria-hidden="true" />
                {config.eyebrow} · {config.readingTime}
              </p>
              <h1 className={styles.title} id="page-title">{config.h1}</h1>
              <p className={styles.lead}>{config.lead}</p>
              {/* `hero__ctas` is the hook StickyCta watches to know the hero CTA has scrolled away. */}
              <div className={`hero__ctas ${styles.heroActions}`}>
                <DownloadButton placement={`${config.analyticsPlacement}_hero`} />
                <a className="btn btn--secondary btn--lg" href="#answer">
                  <span>Read the short answer</span>
                  <Icon name="arrow-right" />
                </a>
              </div>
              <p className={styles.byline}>
                Written by{" "}
                <a href={AUTHOR_URL} rel="author">Gurgen Abagyan</a>
                {modified !== published ? (
                  <>
                    {" "}· Updated <time dateTime={modified}>{formatDisplayDate(modified)}</time>
                    {" "}· First published <time dateTime={published}>{formatDisplayDate(published)}</time>
                  </>
                ) : (
                  <> · Published <time dateTime={published}>{formatDisplayDate(published)}</time></>
                )}
              </p>
              {config.disclosure ? (
                <aside className={styles.disclosure} aria-label="Publisher disclosure">
                  <strong>Publisher disclosure.</strong> {config.disclosure}
                </aside>
              ) : null}
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

          {config.atAGlance ? (
            <section
              className={`${styles.chapter} ${styles.glance}`}
              id="at-a-glance"
              aria-labelledby="at-a-glance-title"
            >
              <div className={`container ${styles.content}`}>
                <h2 className={styles.glanceTitle} id="at-a-glance-title">
                  {config.atAGlance.title ?? "At a glance."}
                </h2>
                <ComparisonTableView table={config.atAGlance} labelledBy="at-a-glance-title" compact />
              </div>
            </section>
          ) : null}

          {config.sections.map((section, index) => (
            <PageSection section={section} index={index} key={section.id} />
          ))}

          {config.comparison ? (
            <section className={`${styles.chapter}${band("comparison")}`} id="comparison" aria-labelledby="comparison-title">
              <div className={`container ${styles.content}`}>
                <header className={styles.chapterHeader}>
                  <p className={styles.sectionLabel}>Side-by-side</p>
                  <h2 className={styles.sectionTitle} id="comparison-title">
                    {config.comparison.title ?? "Compare the practical differences."}
                  </h2>
                </header>
                <ComparisonTableView table={config.comparison} labelledBy="comparison-title" />
              </div>
            </section>
          ) : null}

          {config.faq?.length ? (
            <section className={`${styles.chapter}${band("faq")}`} id="faq" aria-labelledby="faq-title">
              <div className={`container ${styles.content}`}>
                <header className={styles.chapterHeader}>
                  <p className={styles.sectionLabel}>FAQ</p>
                  <h2 className={styles.sectionTitle} id="faq-title">
                    {config.faqTitle ?? "Common questions."}
                  </h2>
                </header>
                <div className={`faq__list ${styles.faqList}`}>
                  {config.faq.map(({ question, answer }) => (
                    <details key={question} className="faq-item">
                      <summary className="faq-item__q">
                        <span>{question}</span>
                        <Icon name="chevron-down" className="faq-item__chevron" />
                      </summary>
                      <p className="faq-item__a">{answer}</p>
                    </details>
                  ))}
                </div>
              </div>
            </section>
          ) : null}

          {config.sources?.length ? (
            <section className={`${styles.chapter}${band("sources")}`} id="sources" aria-labelledby="sources-title">
              <div className={`container ${styles.content}`}>
                <header className={styles.chapterHeader}>
                  <p className={styles.sectionLabel}>Primary sources</p>
                  <h2 className={styles.sectionTitle} id="sources-title">Check the claims at the source.</h2>
                  {sourcesReviewed ? (
                    <p className={styles.sectionIntro}>
                      Product behavior changes. These official pages were reviewed on{" "}
                      <time dateTime={sourcesReviewed}>{formatDisplayDate(sourcesReviewed)}</time>.
                    </p>
                  ) : null}
                </header>
                <ul className={styles.sourceList} role="list">
                  {config.sources.map((source) => (
                    <li className={styles.sourceItem} key={source.href}>
                      <ExternalLink href={source.href}>{source.label}{"\u00a0"}↗</ExternalLink>
                      <p>{source.detail}</p>
                    </li>
                  ))}
                </ul>
              </div>
            </section>
          ) : null}

          <section className={`${styles.chapter}${band("related")}`} aria-labelledby="related-title">
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

          <section className={styles.finalCta} aria-labelledby="final-cta-title" data-final-cta>
            <div className="container">
              <h2 id="final-cta-title">{config.ctaTitle}</h2>
              <p>{config.ctaBody}</p>
              <div className={styles.finalActions}>
                <DownloadButton
                  placement={`${config.analyticsPlacement}_bottom`}
                  label="Download VoiceToText"
                />
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
