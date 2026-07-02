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
    body: "Local models run on-device by default — your voice never touches the network. No accounts, no servers, no telemetry. The app only connects to fetch models and check for updates.",
  },
  {
    icon: "keyboard",
    title: "Tap to talk — or hold",
    body: <>Press <HotkeyCombo /> to start, again to stop — or switch to hold-to-record push-to-talk. Esc cancels. Rebind to any shortcut, even Right Control alone.</>,
  },
  {
    icon: "bolt",
    title: "Native speed, minimal battery",
    body: "Pure SwiftUI with no Electron overhead — quick to launch, light in Activity Monitor, kind to your battery.",
  },
  {
    icon: "agent",
    title: "Faster than typing — in any app",
    body: "A long Slack reply, a thoughtful email, a meeting note, a search query, an AI prompt — talking is faster than typing. Press, speak, paste.",
  },
  {
    icon: "box",
    title: "Switch engines without switching apps",
    body: "Six local models run on-device by default. Add an OpenAI or ElevenLabs key to unlock cloud accuracy and live streaming. One setting, no reinstall.",
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
