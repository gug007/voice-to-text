"use client";

import { useEffect, useRef, useState } from "react";

import { trackAnalyticsEvent } from "@/components/analytics-events";
import { HotkeyCombo } from "@/components/ui/hotkey-combo";

const PROMPTS = [
  "I'll send the revised proposal before lunch, then we can review it together tomorrow.",
  "running five minutes late to the call — please start without me and I'll catch up",
  "refactor this function so it streams tokens instead of buffering, but keep the public type signature",
];

// DOM level bars matching the app's LevelBars (LiveHUD.swift): 56 centered
// capsules, oldest on the left (faded), newest at the right "write head"
// (brightest). Height springs to the live mic level; a small floor keeps
// silent bars visible as a thin baseline.
const BAR_COUNT = 56;
const MIN_BAR_PCT = 6;
const MAX_BAR_PCT = 100;
const SAMPLE_INTERVAL = 0.07; // seconds between pushed levels

type DictationState = "idle" | "preparing" | "recording" | "finishing";
type DemoSource = "auto" | "manual" | "replay";

export function DictationDemo() {
  const fieldRef = useRef<HTMLDivElement>(null);
  const hudRef = useRef<HTMLDivElement>(null);
  const barsRef = useRef<HTMLDivElement>(null);
  const replayRef = useRef<(source: DemoSource) => void>(() => {});
  const [state, setState] = useState<DictationState>("idle");
  const [text, setText] = useState("");
  const [pasteFlash, setPasteFlash] = useState(false);
  const [timer, setTimer] = useState("0:00");
  const [demoComplete, setDemoComplete] = useState(false);

  // Mutating refs that drive the bar animation without re-rendering. phaseRef
  // is seeded inside the effect (Math.random would be impure during render).
  const historyRef = useRef<number[]>(new Array(BAR_COUNT).fill(0));
  const smoothedRef = useRef(0);
  const phaseRef = useRef(0);
  const accumRef = useRef(0);
  const activeRef = useRef(false);
  const rafRef = useRef<number | null>(null);
  const timerRef = useRef<number | null>(null);
  const lastTickRef = useRef(0);
  const cycleTokenRef = useRef(0);
  const cycleIndexRef = useRef(0);
  const autoRunRef = useRef(false);

  useEffect(() => {
    const field = fieldRef.current;
    const hud = hudRef.current;
    const bars = barsRef.current;
    if (!field || !hud || !bars) return;

    phaseRef.current = Math.random() * 10;
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

    const paintBars = () => {
      const history = historyRef.current;
      const children = bars.children;
      for (let i = 0; i < children.length; i++) {
        const level = Math.min(1, Math.max(0, history[i]));
        const h = MIN_BAR_PCT + (MAX_BAR_PCT - MIN_BAR_PCT) * level;
        (children[i] as HTMLElement).style.height = `${h.toFixed(1)}%`;
      }
    };

    const tick = (now: number) => {
      if (!activeRef.current) return;
      if (!lastTickRef.current) lastTickRef.current = now;
      const dt = Math.min(0.1, (now - lastTickRef.current) / 1000);
      lastTickRef.current = now;
      phaseRef.current += dt;
      accumRef.current += dt;
      let pushed = false;
      while (accumRef.current >= SAMPLE_INTERVAL) {
        accumRef.current -= SAMPLE_INTERVAL;
        const t = phaseRef.current;
        const envelope = 0.55 + 0.45 * Math.sin(t * 0.55);
        const raw =
          0.42 +
          0.34 * Math.sin(t * 1.4) +
          0.18 * Math.sin(t * 3.1 + 1.2) +
          (Math.random() - 0.5) * 0.22;
        const target = Math.max(0, Math.min(1, raw * envelope));
        // Exponential smoothing, matching the app's setLevel.
        smoothedRef.current = smoothedRef.current * 0.6 + target * 0.4;
        historyRef.current.shift();
        historyRef.current.push(smoothedRef.current);
        pushed = true;
      }
      if (pushed) paintBars();
      rafRef.current = window.requestAnimationFrame(tick);
    };

    const startBars = () => {
      if (activeRef.current) return;
      activeRef.current = true;
      lastTickRef.current = 0;
      rafRef.current = window.requestAnimationFrame(tick);
    };

    const stopBars = () => {
      activeRef.current = false;
      if (rafRef.current) window.cancelAnimationFrame(rafRef.current);
      rafRef.current = null;
      historyRef.current = new Array(BAR_COUNT).fill(0);
      paintBars();
    };

    const formatTime = (seconds: number) => {
      const total = Math.floor(seconds);
      const m = Math.floor(total / 60);
      const s = total % 60;
      return `${m}:${s.toString().padStart(2, "0")}`;
    };
    const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));
    const stopTimer = () => {
      if (timerRef.current !== null) window.clearInterval(timerRef.current);
      timerRef.current = null;
    };

    const runCycle = async (source: DemoSource) => {
      const myToken = ++cycleTokenRef.current;
      const prompt = PROMPTS[cycleIndexRef.current % PROMPTS.length];
      cycleIndexRef.current++;

      trackAnalyticsEvent("demo_start", { placement: "primary_demo", source });

      // Reset to an empty field, ready to dictate.
      setText("");
      setPasteFlash(false);
      setDemoComplete(false);
      setTimer("0:00");
      setState("preparing");
      await sleep(900);
      if (myToken !== cycleTokenRef.current) return;

      // Press the hotkey: HUD appears, the level bars come alive. The field
      // stays empty while speaking — with a buffered model, words only land
      // once dictation stops, just like the app.
      setState("recording");
      hud.classList.add("is-visible");
      startBars();
      const startedAt = performance.now();
      timerRef.current = window.setInterval(() => {
        setTimer(formatTime((performance.now() - startedAt) / 1000));
      }, 100);

      // Speak for a beat that scales with the sentence length.
      const speakMs = Math.min(3600, 1000 + prompt.length * 22);
      await sleep(speakMs);
      stopTimer();
      if (myToken !== cycleTokenRef.current) return;

      // Finish on the completed transcript instead of looping forever.
      setText(prompt);
      setPasteFlash(true);
      hud.classList.remove("is-visible");
      setState("finishing");
      stopBars();
      await sleep(700);
      if (myToken === cycleTokenRef.current) {
        setPasteFlash(false);
        setDemoComplete(true);
        setState("idle");
        trackAnalyticsEvent("demo_complete", { placement: "primary_demo", source });
      }
    };

    const stopCycle = () => {
      cycleTokenRef.current++;
      hud.classList.remove("is-visible");
      setState("idle");
      stopTimer();
      stopBars();
    };

    if (reducedMotion.matches) {
      // Show the outcome immediately. Replays switch to another completed
      // example without animating, so reduced-motion users get the same proof
      // and controls without a simulated recording sequence.
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setTimer("0:05");
      setText(PROMPTS[cycleIndexRef.current++]);
      setDemoComplete(true);
      replayRef.current = (source) => {
        const prompt = PROMPTS[cycleIndexRef.current % PROMPTS.length];
        cycleIndexRef.current++;
        trackAnalyticsEvent("demo_start", { placement: "primary_demo", source });
        setText(prompt);
        trackAnalyticsEvent("demo_complete", { placement: "primary_demo", source });
      };
      return () => {
        replayRef.current = () => {};
      };
    }

    replayRef.current = (source) => { void runCycle(source); };

    const runAutoOnce = () => {
      if (autoRunRef.current) return;
      autoRunRef.current = true;
      void runCycle("auto");
    };

    if (!("IntersectionObserver" in window)) {
      runAutoOnce();
      return () => {
        replayRef.current = () => {};
        stopCycle();
      };
    }

    const card = field.closest(".demo-card");
    if (!card) {
      runAutoOnce();
      return () => {
        replayRef.current = () => {};
        stopCycle();
      };
    }

    const io = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) runAutoOnce();
          else stopCycle();
        }
      },
      { threshold: 0.25 },
    );
    io.observe(card);

    const onVis = () => {
      if (document.hidden) stopCycle();
      else {
        const rect = card.getBoundingClientRect();
        if (rect.top < window.innerHeight && rect.bottom > 0) runAutoOnce();
      }
    };
    document.addEventListener("visibilitychange", onVis);

    return () => {
      replayRef.current = () => {};
      io.disconnect();
      document.removeEventListener("visibilitychange", onVis);
      stopCycle();
    };
  }, []);

  const hasText = text.length > 0;

  return (
    <figure
      className="demo-card"
      aria-label="VoiceToText voice-input field with recording HUD"
    >
      <div
        ref={fieldRef}
        className={`demo-field${hasText ? " has-text" : ""}${pasteFlash ? " is-pasted" : ""}`}
        data-dictation-state={state}
      >
        <span className="demo-field__icon" aria-hidden="true">
          <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
            <rect x="7.5" y="2.5" width="5" height="10" rx="2.5" />
            <path d="M4.5 10a5.5 5.5 0 0 0 11 0" />
            <path d="M10 15.5V18" />
          </svg>
        </span>
        <span className="demo-field__content">
          <span className="demo-field__placeholder">
            Press <HotkeyCombo /> to dictate
          </span>
          <span className="demo-field__text">{text}</span>
          <span className="demo-field__caret" aria-hidden="true"></span>
        </span>
      </div>

      <div ref={hudRef} className="demo-hud" aria-hidden="true">
        <div className="demo-hud__trace">
          <div ref={barsRef} className="demo-hud__bars">
            {Array.from({ length: BAR_COUNT }).map((_, i) => (
              <span
                key={i}
                className="demo-hud__bar"
                style={{
                  opacity: 0.22 + 0.68 * (i / (BAR_COUNT - 1)),
                  height: `${MIN_BAR_PCT}%`,
                }}
              />
            ))}
          </div>
        </div>
        <div className="demo-hud__meta">
          <span className="demo-hud__timer">{timer}</span>
          <span className="demo-hud__hint">Press again to finish · Esc cancels</span>
        </div>
      </div>

      <figcaption className="demo-card__caption">
        <span>Press <HotkeyCombo />, speak, press again — words appear at the cursor. Nothing leaves the Mac.</span>
        <button
          type="button"
          className="demo-replay"
          disabled={state !== "idle"}
          onClick={() => replayRef.current(demoComplete ? "replay" : "manual")}
        >
          <span aria-hidden="true">↻</span>
          {state !== "idle" ? "Demo playing…" : demoComplete ? "Replay demo" : "Play demo"}
        </button>
      </figcaption>
    </figure>
  );
}
