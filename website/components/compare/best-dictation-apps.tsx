import Link from "next/link";

import { JsonLd } from "@/components/json-ld";
import { ScrollEffects } from "@/components/scroll-effects";
import { Footer } from "@/components/sections/footer";
import { Nav } from "@/components/sections/nav";
import { StickyCta } from "@/components/sticky-cta";
import { ExternalLink } from "@/components/ui/external-link";
import { Icon } from "@/components/ui/icon";
import { products, REVIEW_DATE, sourceGroups, type Product } from "@/lib/best-dictation-apps-data";
import { AUTHOR_URL, DMG_URL, REPO_URL, SITE_URL } from "@/lib/constants";
import { PERSON_ID, WEBSITE_ID, personJsonLd } from "@/lib/seo";

import styles from "./best-dictation-apps.module.css";

const PATH = "/compare/best-dictation-apps-for-mac";
const PAGE_URL = `${SITE_URL}${PATH}`;
const ARTIFACT_ROOT = `${PATH}`;

const dimensions: Array<{ key: keyof Product; label: string }> = [
  { key: "dictation", label: "Dictation" },
  { key: "files", label: "File transcription" },
  { key: "meetings", label: "Meetings" },
  { key: "correction", label: "Correction time / workflow" },
  { key: "privacy", label: "Privacy path" },
  { key: "languages", label: "Languages" },
  { key: "price", label: "Price" },
];

const artifacts = [
  {
    href: `${ARTIFACT_ROOT}/methodology-v1.md`,
    title: "Methodology v1",
    detail: "The complete protocol, timing boundaries, settings rules, privacy checks, and release gate.",
  },
  {
    href: `${ARTIFACT_ROOT}/benchmark-manifest-v1.json`,
    title: "Fixture manifest",
    detail: "Machine-readable fixture inventory, protocol settings, file paths, and SHA-256 hashes.",
  },
  {
    href: `${ARTIFACT_ROOT}/results-template.csv`,
    title: "Results template",
    detail: "The required raw-data shape. Blank or not-tested cells are excluded from every ranking.",
  },
  {
    href: `${REPO_URL}/blob/main/website/scripts/score-dictation-benchmark.mjs`,
    title: "Scoring script",
    detail: "A dependency-free reference implementation for normalization, WER, CER, and edit distance.",
  },
] as const;

function schemas() {
  const breadcrumb = {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    "@id": `${PAGE_URL}#breadcrumb`,
    itemListElement: [
      { "@type": "ListItem", position: 1, name: "Home", item: `${SITE_URL}/` },
      { "@type": "ListItem", position: 2, name: "Best dictation apps for Mac", item: PAGE_URL },
    ],
  };

  const article = {
    "@context": "https://schema.org",
    "@type": "Article",
    "@id": `${PAGE_URL}#article`,
    headline: "The best dictation apps for Mac in 2026",
    description:
      "A source-backed comparison of Mac dictation apps across dictation, files, meetings, correction workflow, privacy, languages, and price.",
    url: PAGE_URL,
    datePublished: REVIEW_DATE,
    dateModified: REVIEW_DATE,
    inLanguage: "en",
    author: { "@id": PERSON_ID },
    publisher: { "@id": PERSON_ID },
    isPartOf: { "@id": WEBSITE_ID },
    breadcrumb: { "@id": `${PAGE_URL}#breadcrumb` },
    mainEntity: { "@id": `${PAGE_URL}#products` },
  };

  const itemList = {
    "@context": "https://schema.org",
    "@type": "ItemList",
    "@id": `${PAGE_URL}#products`,
    name: "Dictation apps for Mac compared",
    numberOfItems: products.length,
    itemListElement: products.map((product, index) => ({
      "@type": "ListItem",
      position: index + 1,
      item: {
        "@type": "SoftwareApplication",
        name: product.name,
        applicationCategory: "ProductivityApplication",
        operatingSystem: "macOS",
        url: product.sourceHref,
      },
    })),
  };

  return { breadcrumb, article, itemList };
}

function PickCard({ product, index }: { product: Product; index: number }) {
  return (
    <article className={styles.pickCard} id={`pick-${product.id}`}>
      <div className={styles.pickTopline}>
        <span className={styles.pickIndex}>{String(index + 1).padStart(2, "0")}</span>
        <span className={styles.pickLabel}>{product.label}</span>
      </div>
      <h3>{product.name}</h3>
      <p className={styles.pickVerdict}>{product.verdict}</p>
      <dl className={styles.pickNotes}>
        <div>
          <dt>Where {product.name} wins</dt>
          <dd>{product.wins}</dd>
        </div>
        <div>
          <dt>What you give up</dt>
          <dd>{product.tradeoff}</dd>
        </div>
      </dl>
      <ExternalLink className={styles.vendorLink} href={product.sourceHref}>
        Check the official source ↗
      </ExternalLink>
    </article>
  );
}

export function BestDictationAppsPage() {
  const { breadcrumb, article, itemList } = schemas();

  return (
    <>
      <JsonLd data={breadcrumb} />
      <JsonLd data={article} />
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
                  <li><span>Compare</span></li>
                  <li aria-current="page">Best dictation apps for Mac</li>
                </ol>
              </nav>
              <p className={styles.eyebrow}>
                <span className={styles.eyebrowDot} aria-hidden="true" />
                Seven apps · seven decision points · 18 min
              </p>
              <h1 className={styles.title} id="page-title">
                The best Mac dictation app depends on what happens after you speak.
              </h1>
              <p className={styles.lead}>
                We compared VoiceToText, Apple Dictation, Wispr Flow, Superwhisper, MacWhisper,
                Aqua Voice, and VoiceInk across live dictation, files, meetings, correction workflow,
                privacy path, languages, and price.
              </p>
              <div className={styles.heroActions}>
                <a className="btn btn--primary btn--lg" href="#picks">See the category picks</a>
                <a className="btn btn--secondary btn--lg" href="#methodology">
                  <span>Audit the methodology</span>
                  <Icon name="arrow-right" />
                </a>
              </div>
              <p className={styles.byline}>
                Written by <a href={AUTHOR_URL} rel="author">Gurgen Abagyan</a>
                {" "}· Published and source-checked <time dateTime={REVIEW_DATE}>August 12, 2026</time>
              </p>
              <aside className={styles.disclosure} aria-label="Publisher disclosure">
                <strong>Publisher disclosure.</strong>{" "}This is VoiceToText&apos;s project website, so the
                publisher has an obvious stake. There are no affiliate links, placements, or sponsorships.
                Every competitor gets a named win, official sources are linked, and unrun measurements stay unranked.
              </aside>
            </div>
          </header>

          <section className={styles.section} aria-labelledby="short-answer-title">
            <div className={`container ${styles.content}`}>
              <div className={styles.answer}>
                <div>
                  <p className={styles.sectionLabel}>The short answer</p>
                  <h2 id="short-answer-title">There is no honest universal winner.</h2>
                </div>
                <div className={styles.answerCopy}>
                  <p>
                    Try <strong>Apple Dictation</strong> first for zero setup. Choose <strong>MacWhisper</strong>
                    for production file work, <strong>Wispr Flow</strong> for managed cloud dictation and meeting
                    intelligence, <strong>Aqua Voice</strong> for voice-driven edits, <strong>Superwhisper</strong>
                    for model choice, and <strong>VoiceInk</strong> for GPL-licensed local control.
                  </p>
                  <p>
                    VoiceToText is our pick only for the narrower combination it actually wins: free local
                    dictation plus review-before-paste, file import, and bot-free meeting capture on Apple silicon.
                  </p>
                </div>
              </div>
            </div>
          </section>

          <section className={`${styles.section} ${styles.sectionAlt}`} id="picks" aria-labelledby="picks-title">
            <div className={`container ${styles.wideContent}`}>
              <header className={styles.sectionHeader}>
                <p className={styles.sectionLabel}>Best by job</p>
                <h2 id="picks-title">Seven products, seven defensible reasons to choose one.</h2>
                <p>
                  These are editorial fit picks based on current documented capabilities—not an accuracy
                  leaderboard. Product order is not a score.
                </p>
              </header>
              <div className={styles.pickGrid}>
                {products.map((product, index) => (
                  <PickCard key={product.id} product={product} index={index} />
                ))}
              </div>
            </div>
          </section>

          <section className={styles.section} id="matrix" aria-labelledby="matrix-title">
            <div className={`container ${styles.wideContent}`}>
              <header className={styles.sectionHeader}>
                <p className={styles.sectionLabel}>Full comparison</p>
                <h2 id="matrix-title">Compare the whole workflow, not one demo sentence.</h2>
                <p>
                  “Not documented/tested” means exactly that. It is not silently converted to “no,” and a
                  vendor language count is not treated as proof of equal accuracy in every language.
                </p>
              </header>
              <p className={styles.scrollHint} id="matrix-hint">Scroll horizontally to see all seven dimensions.</p>
              <div className={styles.tableWrap} tabIndex={0} role="region" aria-labelledby="matrix-title" aria-describedby="matrix-hint">
                <table className={styles.matrix}>
                  <caption>
                    Documented product behavior and public pricing checked August 12, 2026. Correction time is
                    intentionally unranked until every app completes the published benchmark.
                  </caption>
                  <thead>
                    <tr>
                      <th scope="col">App</th>
                      {dimensions.map((dimension) => <th scope="col" key={dimension.key}>{dimension.label}</th>)}
                    </tr>
                  </thead>
                  <tbody>
                    {products.map((product) => (
                      <tr key={product.id}>
                        <th scope="row">
                          <a href={`#pick-${product.id}`}>{product.name}</a>
                          <span>{product.label}</span>
                        </th>
                        {dimensions.map((dimension) => (
                          <td key={dimension.key}>{product[dimension.key]}</td>
                        ))}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          </section>

          <section className={`${styles.section} ${styles.sectionAlt}`} id="correction-time" aria-labelledby="correction-title">
            <div className={`container ${styles.content}`}>
              <div className={styles.metricCallout}>
                <div className={styles.metricStatus}>
                  <span>Correction-time benchmark</span>
                  <strong>Protocol ready · results not run</strong>
                </div>
                <div>
                  <p className={styles.sectionLabel}>The metric vendors skip</p>
                  <h2 id="correction-title">We will not guess which app saves the most correction time.</h2>
                  <p>
                    A low word-error rate can still produce slow cleanup, while an app that rewrites speech can
                    look accurate by changing meaning. The protocol therefore scores raw recognition and polished
                    output separately, then times one editor correcting each final output to an exact published target.
                  </p>
                  <p>
                    Until every app is run on the same fixtures, hardware, release, privacy mode, and randomized
                    order, this page reports correction workflows—not invented seconds. Blank and
                    <code> not_tested </code> rows are rejected by the ranking script.
                  </p>
                </div>
              </div>
            </div>
          </section>

          <section className={styles.section} id="privacy" aria-labelledby="privacy-title">
            <div className={`container ${styles.content}`}>
              <header className={styles.sectionHeader}>
                <p className={styles.sectionLabel}>Privacy path</p>
                <h2 id="privacy-title">“Private” is four separate questions.</h2>
                <p>
                  A zero-retention cloud request is not on-device. Local speech followed by cloud rewriting is
                  not fully local. Training consent and transcript storage are different controls.
                </p>
              </header>
              <ol className={styles.privacySteps}>
                <li><span>01</span><div><h3>Where is audio transcribed?</h3><p>On this Mac, the vendor&apos;s cloud, or a provider selected with your own key?</p></div></li>
                <li><span>02</span><div><h3>Where is text rewritten?</h3><p>A local LLM, a vendor proxy, your own provider account, or nowhere?</p></div></li>
                <li><span>03</span><div><h3>What is retained?</h3><p>Audio, raw text, polished text, history, context, and telemetry can follow different rules.</p></div></li>
                <li><span>04</span><div><h3>What happens offline?</h3><p>The release gate verifies the chosen path with outbound traffic blocked after model setup.</p></div></li>
              </ol>
              <aside className={styles.note}>
                The local-first choices in this set are VoiceToText, Superwhisper, MacWhisper, and VoiceInk when
                configured with local speech and local/no rewriting. Apple Dictation may be on-device depending on
                language and settings. Wispr Flow and Aqua Voice transcribe in the cloud.
              </aside>
            </div>
          </section>

          <section className={`${styles.section} ${styles.sectionAlt}`} id="methodology" aria-labelledby="methodology-title">
            <div className={`container ${styles.content}`}>
              <header className={styles.sectionHeader}>
                <p className={styles.sectionLabel}>Reproducible methodology</p>
                <h2 id="methodology-title">The test plan is part of the page, not a private spreadsheet.</h2>
                <p>
                  Version 1 freezes the fixtures, reference text, normalization, timing boundaries, app settings,
                  repetitions, privacy checks, and missing-data policy. Anyone can rerun it or challenge the choices.
                </p>
              </header>

              <ol className={styles.protocol}>
                <li><span>1</span><div><h3>Freeze the environment</h3><p>Record Mac model, macOS, microphone/input route, app build, plan, model, language, account state, network state, and every cleanup setting.</p></div></li>
                <li><span>2</span><div><h3>Separate raw from polished</h3><p>Run literal transcription without AI cleanup, then run the app&apos;s recommended polished mode as a different condition. Never compare one with the other.</p></div></li>
                <li><span>3</span><div><h3>Repeat in a published order</h3><p>Warm each model once, run three measured blocks in the exact manifest order across at least two days, and report medians plus every raw output.</p></div></li>
                <li><span>4</span><div><h3>Measure what users repair</h3><p>Publish WER/CER, final-text latency, deterministic edit distance, and human correction seconds to an exact target. Preserve names, numbers, and negations as critical errors.</p></div></li>
                <li><span>5</span><div><h3>Verify privacy and price</h3><p>Test the declared local mode with outbound traffic denied, retain the network log, and archive a dated official pricing snapshot in the run record.</p></div></li>
              </ol>

              <div className={styles.artifactGrid}>
                {artifacts.map((artifact) => (
                  <a className={styles.artifactCard} href={artifact.href} key={artifact.href}>
                    <span>Public artifact</span>
                    <h3>{artifact.title}</h3>
                    <p>{artifact.detail}</p>
                    <strong>Open file →</strong>
                  </a>
                ))}
              </div>

              <aside className={styles.releaseGate}>
                <div>
                  <span className={styles.gateDot} aria-hidden="true" />
                  <strong>Methodology publication gate: passed</strong>
                </div>
                <p>
                  The protocol, references, manifest, blank results schema, and scoring code must validate before
                  the site can build. A future measured ranking remains blocked until all seven apps have complete,
                  reviewable rows and raw outputs.
                </p>
              </aside>
            </div>
          </section>

          <section className={styles.section} id="sources" aria-labelledby="sources-title">
            <div className={`container ${styles.content}`}>
              <header className={styles.sectionHeader}>
                <p className={styles.sectionLabel}>Official evidence</p>
                <h2 id="sources-title">Check every capability and price at the source.</h2>
                <p>
                  All product claims above were reviewed against official vendor documentation on August 12,
                  2026. Vendor benchmarks are not treated as independent results.
                </p>
              </header>
              <div className={styles.sourceGrid}>
                {sourceGroups.map((group) => (
                  <section className={styles.sourceGroup} key={group.name} aria-labelledby={`source-${group.name.toLowerCase().replaceAll(" ", "-")}`}>
                    <h3 id={`source-${group.name.toLowerCase().replaceAll(" ", "-")}`}>{group.name}</h3>
                    <ul role="list">
                      {group.links.map(([label, href]) => (
                        <li key={href}><ExternalLink href={href}>{label} ↗</ExternalLink></li>
                      ))}
                    </ul>
                  </section>
                ))}
              </div>
            </div>
          </section>

          <section className={styles.finalCta} aria-labelledby="final-cta-title">
            <div className="container">
              <p className={styles.sectionLabel}>Our stake in the comparison</p>
              <h2 id="final-cta-title">Test VoiceToText. Keep the competitor that beats it for your work.</h2>
              <p>
                Use the same sample and privacy path in both. If another app needs fewer repairs, handles your
                meetings better, or supports the language and platform you need, that is the right result.
              </p>
              <div className={styles.finalActions}>
                <a className="btn btn--primary btn--lg" href={DMG_URL} data-analytics-event="download_click" data-analytics-placement="best_dictation_apps_bottom">
                  <Icon name="download" />
                  <span>Download VoiceToText — free</span>
                </a>
                <ExternalLink className="btn btn--secondary btn--lg" href={REPO_URL} data-analytics-event="github_outbound" data-analytics-placement="best_dictation_apps_bottom">
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
