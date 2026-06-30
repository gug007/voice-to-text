import Link from "next/link";

import { FeatureCard } from "@/components/ui/feature-card";
import { Icon, type IconName } from "@/components/ui/icon";

type Capability = {
  icon: IconName;
  title: string;
  body: string;
};

const CAPABILITIES: Capability[] = [
  {
    icon: "mic",
    title: "Record meetings & calls",
    body: "Capture your mic and your Mac’s system audio together — the whole Zoom, Meet, or Teams call — and keep recording in the background while you work.",
  },
  {
    icon: "apps",
    title: "A searchable history",
    body: "Every dictation and meeting is saved on-device with its audio and transcript. Play it back, search it, copy it, favorite it, or delete it.",
  },
  {
    icon: "sparkle",
    title: "Regenerate & compare",
    body: "Re-transcribe any recording with a different model — say, swap Parakeet for GPT-4o Transcribe — and keep both versions side by side to compare.",
  },
];

export function Meetings() {
  return (
    <section className="section meetings reveal" id="meetings" aria-labelledby="meetings-title">
      <div className="container">
        <p className="section__eyebrow">Beyond dictation</p>
        <h2 id="meetings-title" className="section__title">
          Record meetings and conversations — transcribed on your Mac.
        </h2>
        <p className="section__deck">
          The same app that types your voice into any field can also record a full meeting. Capture both sides
          of the call, keep working while it runs, and get an on-device transcript saved to a searchable
          history. You can even import an existing audio or video file to transcribe.
        </p>
        <ul className="features__grid" role="list">
          {CAPABILITIES.map(({ icon, title, body }) => (
            <FeatureCard key={title} icon={icon} title={title}>{body}</FeatureCard>
          ))}
        </ul>
        <div className="ai__cta">
          <Link className="btn btn--secondary btn--lg" href="/meeting-recording">
            <span>How meeting recording works</span>
            <Icon name="arrow-right" />
          </Link>
        </div>
      </div>
    </section>
  );
}
