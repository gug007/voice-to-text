import Link from "next/link";

import { GUIDE_PATH, REPO_URL } from "@/lib/constants";
import { ExternalLink } from "@/components/ui/external-link";
import { Icon } from "@/components/ui/icon";

export function Proof() {
  return (
    <section className="proof" id="proof" aria-labelledby="proof-title">
      <div className="container proof__inner">
        <h2 id="proof-title" className="sr-only">Trust, privacy, and local transcription</h2>
        <ul className="proof__pills" role="list">
          <li className="chip chip--accent">
            <span className="chip__dot" aria-hidden="true" />
            Signed &amp; notarized
          </li>
          <li className="chip">No app telemetry</li>
          <li className="chip">
            <ExternalLink
              href={REPO_URL}
              className="chip__link"
              data-analytics-event="github_outbound"
              data-analytics-placement="trust_strip"
            >
              Auditable source on GitHub
            </ExternalLink>
          </li>
        </ul>
        <p className="proof__provenance">
          WhisperKit and FluidAudio run speech models locally on the Apple Neural Engine — audio stays on
          your Mac in local mode.
          <Link href={GUIDE_PATH} className="proof__link">
            Read the setup guide <Icon name="arrow-right" size="sm" />
          </Link>
        </p>
      </div>
    </section>
  );
}
