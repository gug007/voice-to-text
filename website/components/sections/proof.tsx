import { REPO_URL } from "@/lib/constants";
import { ExternalLink } from "@/components/ui/external-link";
import { Icon } from "@/components/ui/icon";

export function Proof() {
  return (
    <section className="proof reveal" id="proof" aria-labelledby="proof-title">
      <div className="container proof__inner">
        <h2 id="proof-title" className="sr-only">Open source on GitHub</h2>
        <ul className="proof__pills" role="list">
          <li className="chip chip--accent">
            <span className="chip__dot" aria-hidden="true" />
            100% open source
          </li>
          <li className="chip">
            <ExternalLink href={REPO_URL} className="chip__link">
              Browse the repo on GitHub
            </ExternalLink>
          </li>
          <li className="chip">Built in public</li>
        </ul>
        <p className="proof__provenance">
          Powered by OpenAI Whisper (via WhisperKit) and Parakeet (via FluidAudio), on the Apple Neural Engine.
          <ExternalLink href={REPO_URL} className="proof__link">
            Read the source code <Icon name="arrow-right" size="sm" />
          </ExternalLink>
        </p>
      </div>
    </section>
  );
}
