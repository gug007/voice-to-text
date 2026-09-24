import type { CSSProperties } from "react";

import { ExternalLink } from "@/components/ui/external-link";
import { Icon } from "@/components/ui/icon";
import { ISSUES_URL } from "@/lib/constants";
import { faqEntries } from "@/lib/seo";

const MORE: CSSProperties = { display: "inline-flex", alignItems: "center", gap: "6px", fontSize: "14px" };

// The answers render straight from `faqEntries`, the same array the FAQPage
// JSON-LD serialises, so the visible text and the structured data always match.
export function Faq() {
  return (
    <section className="section section--band" id="faq" aria-labelledby="faq-title">
      <div className="wrap">
        <div className="faq">
          <div className="sec-head">
            <p className="kicker">Aside &middot; the fine print</p>
            <h2 id="faq-title">What to know before installing.</h2>
            <p className="lede">
              Straight answers on privacy, permissions, models, languages, and meetings, including the parts
              that might rule it out for you.
            </p>
            <p className="muted">
              <ExternalLink className="link" href={ISSUES_URL} style={MORE}>
                More questions on GitHub <Icon name="arrow-right" size="sm" />
              </ExternalLink>
            </p>
          </div>

          <div className="qa">
            {faqEntries.map(({ question, answer }, index) => (
              <details key={question} open={index === 0}>
                <summary>{question}</summary>
                <div className="qa__a">{answer}</div>
              </details>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
