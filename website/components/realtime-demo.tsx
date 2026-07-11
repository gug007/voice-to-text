"use client";

import { useEffect, useRef, useState } from "react";

import { HotkeyCombo } from "@/components/ui/hotkey-combo";

// Sentences that read naturally while showing off live, word-by-word
// streaming — the thing a buffered engine can't do.
const SENTENCES = [
  "Watch the words appear live as I speak, with no waiting for the transcript.",
  "Real-time transcription streams straight into whatever app I'm already in.",
  "Pause, keep talking, and the text just keeps flowing at the cursor.",
];

// DOM level bars matching the app's LevelBars: oldest on the left (faded),
// newest at the right "write head" (brightest). Height tracks the live level.
const BAR_COUNT = 48;
const MIN_BAR = 4;
const MAX_BAR = 52;
const SAMPLE_INTERVAL = 0.07; // seconds between pushed levels

type RealtimeState = "idle" | "recording";

export function RealtimeDemo() {
  const fieldRef = useRef<HTMLDivElement>(null);
  const hudRef = useRef<HTMLDivElement>(null);
  const barsRef = useRef<HTMLDivElement>(null);

  const [state, setState] = useState<RealtimeState>("idle");
  const [partial, setPartial] = useState("");
  const [pasted, setPasted] = useState("");
  const [pasteFlash, setPasteFlash] = useState(false);
  const [timer, setTimer] = useState("0:00");

  // Mutating refs that drive the bar animation without re-rendering.
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
        const h = MIN_BAR + (MAX_BAR - MIN_BAR) * level;
        (children[i] as HTMLElement).style.height = `${h.toFixed(1)}px`;
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

    const runCycle = async () => {
      const myToken = ++cycleTokenRef.current;
      const sentence = SENTENCES[cycleIndexRef.current % SENTENCES.length];
      cycleIndexRef.current++;

      // Reset to an empty field, ready to dictate.
      setPasted("");
      setPartial("");
      setPasteFlash(false);
      setTimer("0:00");
      setState("idle");
      await sleep(900);
      if (myToken !== cycleTokenRef.current) return;

      // Start recording: HUD appears, bars come alive, "Listening".
      setState("recording");
      hud.classList.add("is-visible");
      startBars();
      const startedAt = performance.now();
      timerRef.current = window.setInterval(() => {
        setTimer(formatTime((performance.now() - startedAt) / 1000));
      }, 100);

      // Beat of pure "Listening" before the first words land.
      await sleep(750);
      if (myToken !== cycleTokenRef.current) {
        stopTimer();
        return;
      }

      // Stream the transcript word by word — the real-time payoff.
      const words = sentence.split(" ");
      let acc = "";
      for (let w = 0; w < words.length; w++) {
        if (myToken !== cycleTokenRef.current) break;
        acc += (acc ? " " : "") + words[w];
        setPartial(acc);
        await sleep(150 + Math.random() * 130);
      }
      if (myToken !== cycleTokenRef.current) {
        stopTimer();
        return;
      }

      await sleep(550);
      stopTimer();
      if (myToken !== cycleTokenRef.current) return;

      // Finish on the completed transcript instead of looping forever.
      setPasted(sentence);
      setPasteFlash(true);
      hud.classList.remove("is-visible");
      setState("idle");
      setPartial("");
      stopBars();
      await sleep(700);
      if (myToken === cycleTokenRef.current) setPasteFlash(false);
    };

    const stopCycle = () => {
      cycleTokenRef.current++;
      hud.classList.remove("is-visible");
      setState("idle");
      stopTimer();
      stopBars();
    };

    if (reducedMotion.matches) {
      // Static, believable snapshot for reduced-motion users: HUD open,
      // mid-stream, with a frozen level envelope.
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setState("recording");
      setPartial(SENTENCES[0]);
      setTimer("0:04");
      hud.classList.add("is-visible");
      for (let i = 0; i < BAR_COUNT; i++) {
        const t = i / BAR_COUNT;
        historyRef.current[i] = Math.max(0, 0.32 + 0.3 * Math.sin(t * 13) + 0.14 * Math.sin(t * 31));
      }
      paintBars();
      return;
    }

    if (!("IntersectionObserver" in window)) {
      runCycle();
      return () => stopCycle();
    }

    const card = field.closest(".demo-card");
    if (!card) {
      runCycle();
      return () => stopCycle();
    }

    const io = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) runCycle();
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
        if (rect.top < window.innerHeight && rect.bottom > 0) runCycle();
      }
    };
    document.addEventListener("visibilitychange", onVis);

    return () => {
      io.disconnect();
      document.removeEventListener("visibilitychange", onVis);
      stopCycle();
    };
  }, []);

  const hasText = pasted.length > 0;

  return (
    <figure
      className="demo-card rt-card"
      aria-label="VoiceToText real-time dictation with a live transcript HUD"
    >
      <div
        ref={fieldRef}
        className={`demo-field rt-field${hasText ? " has-text" : ""}${pasteFlash ? " is-pasted" : ""}`}
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
          <span className="demo-field__text">{pasted}</span>
          <span className="demo-field__caret" aria-hidden="true"></span>
        </span>
      </div>

      <div ref={hudRef} className="demo-hud rt-hud" aria-hidden="true">
        <div ref={barsRef} className="rt-hud__bars">
          {Array.from({ length: BAR_COUNT }).map((_, i) => (
            <span
              key={i}
              className="rt-hud__bar"
              style={{
                opacity: 0.22 + 0.68 * (i / (BAR_COUNT - 1)),
                height: `${MIN_BAR}px`,
              }}
            />
          ))}
        </div>

        <div className="rt-hud__transcript">
          {partial ? (
            <span className="rt-hud__text">
              {partial}
              <span className="rt-hud__cursor" aria-hidden="true"></span>
            </span>
          ) : (
            <span className="rt-hud__listening">
              <span className="rt-hud__dot"></span>
              <span className="rt-hud__shimmer">Listening</span>
            </span>
          )}
        </div>

        <div className="rt-hud__meta">
          <span className="demo-hud__timer">{timer}</span>
          <span className="demo-hud__hint">Press again to finish · Esc cancels</span>
        </div>
      </div>

      <figcaption className="demo-card__caption">
        Words stream in live as you speak, then paste at the cursor in any Mac app. Streaming sends audio
        to your chosen provider under your own key.
      </figcaption>
    </figure>
  );
}
