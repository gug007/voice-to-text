import type { ReactNode } from "react";

import { FeatureCard } from "@/components/ui/feature-card";
import { HotkeyCombo } from "@/components/ui/hotkey-combo";
import type { IconName } from "@/components/ui/icon";

type Feature = {
  icon: IconName;
  title: ReactNode;
  body: ReactNode;
};

const FEATURES: Feature[] = [
  {
    icon: "lock",
    title: "Your audio never leaves the Mac",
    body: "Local models run on-device by default. Zero network calls. No accounts, no servers, no telemetry.",
  },
  {
    icon: "keyboard",
    title: "Hold to talk. Release to insert.",
    body: <>Press <HotkeyCombo />, speak, let go. Text appears at the cursor. No toggles, no accidental cutoffs, no mode to escape.</>,
  },
  {
    icon: "bolt",
    title: "Instant start, minimal battery",
    body: "Pure SwiftUI, menu-bar only. Cold-starts in under a second and barely registers in Activity Monitor — no Electron overhead.",
  },
  {
    icon: "agent",
    title: "Faster than typing — in any app",
    body: "A long Slack reply, a thoughtful email, a meeting note, a search query, an AI prompt — talking is faster than typing. Hold, speak, release.",
  },
  {
    icon: "box",
    title: "Switch engines without switching apps",
    body: "Parakeet and Whisper run on-device by default. Add an OpenAI key to unlock cloud models. One setting, no reinstall.",
  },
  {
    icon: "apps",
    title: "Works in every app that accepts text",
    body: "Slack, Mail, Notes, browser address bars, terminals, code editors — if macOS puts a cursor there, VoiceToText types into it.",
  },
];

export function Features() {
  return (
    <section className="section features reveal" id="features" aria-labelledby="features-title">
      <div className="container">
        <p className="section__eyebrow">What you get</p>
        <h2 id="features-title" className="section__title">Why VoiceToText for Mac speech to text?</h2>
        <p className="section__deck">
          Everything dictation should be on a Mac — and nothing it shouldn&rsquo;t. Free, offline by default,
          no account, no telemetry.
        </p>
        <ul className="features__grid" role="list">
          {FEATURES.map(({ icon, title, body }, i) => (
            <FeatureCard key={i} icon={icon} title={title}>{body}</FeatureCard>
          ))}
        </ul>
      </div>
    </section>
  );
}
