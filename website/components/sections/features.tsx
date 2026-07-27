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
    title: "Your audio stays local in local mode",
    body: "Parakeet and Whisper run on-device, so those recordings are not sent to a speech provider. There is no VoiceToText account or app telemetry; model downloads, update checks, optional cloud engines, and AI actions use the network.",
  },
  {
    icon: "keyboard",
    title: "Tap to talk — or hold",
    body: <>Press <HotkeyCombo /> to start, again to stop — or switch to hold-to-record push-to-talk. Esc cancels. Rebind to any shortcut, even Right Control alone.</>,
  },
  {
    icon: "bolt",
    title: "Native Mac speed",
    body: "Pure SwiftUI with no Electron overhead — quick to launch, light in Activity Monitor, and built for Apple Silicon.",
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
        <h2 id="features-title" className="section__title">Private dictation, designed for the Mac.</h2>
        <p className="section__deck">
          The essentials stay simple. Local transcription is the default; cloud models and AI actions are
          optional when you explicitly add your own provider key.
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
