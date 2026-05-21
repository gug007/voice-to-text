import { FeatureCard } from "@/components/ui/feature-card";
import type { IconName } from "@/components/ui/icon";

type CloudModel = {
  icon: IconName;
  title: string;
  body: string;
};

const CLOUD_MODELS: CloudModel[] = [
  {
    icon: "sparkle",
    title: "GPT-4o Transcribe",
    body: "Best accuracy available. Use it when correctness matters more than cost — accents, technical jargon, 99+ languages.",
  },
  {
    icon: "bolt",
    title: "GPT-4o Mini Transcribe",
    body: "The everyday cloud pick. Accuracy close to GPT-4o Transcribe at a fraction of the cost — good default for high-volume use.",
  },
  {
    icon: "cloud",
    title: "Whisper-1",
    body: "OpenAI’s original hosted model. Lowest cost per minute — fine for straightforward dictation in major languages.",
  },
];

const BULLETS = [
  "Bring your own OpenAI API key — stored in your Mac’s Keychain, never sent anywhere else.",
  "Audio only leaves your Mac when a cloud model is the active engine. Local models never touch the network.",
  "Swap back to Parakeet or Whisper-large at any time. No account, no lock-in.",
];

export function Cloud() {
  return (
    <section className="section cloud reveal" id="cloud" aria-labelledby="cloud-title">
      <div className="container">
        <p className="section__eyebrow">Optional</p>
        <h2 id="cloud-title" className="section__title">
          Need higher accuracy? Add an OpenAI key and pick a cloud model.
        </h2>
        <p className="section__deck">
          Local models run by default — no key required. Paste an OpenAI API key in{" "}
          <strong>Settings → Cloud</strong> to unlock the models below. Audio only leaves your Mac when a
          cloud model is active.
        </p>
        <ul className="features__grid" role="list">
          {CLOUD_MODELS.map(({ icon, title, body }) => (
            <FeatureCard key={title} icon={icon} title={title}>{body}</FeatureCard>
          ))}
        </ul>
        <ul className="cloud__bullets t-caption" role="list">
          {BULLETS.map((b) => (
            <li key={b}>{b}</li>
          ))}
        </ul>
      </div>
    </section>
  );
}
