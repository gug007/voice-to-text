"use client";

import { useEffect, useRef, useState } from "react";

const PROMPTS = [
  "refactor this function so it streams tokens instead of buffering, keep the type signature",
  "add a dark-mode toggle to the settings sheet and persist the choice",
  "write a quick benchmark comparing parakeet vs whisper-large",
];

const SAMPLES = 140;
const SAMPLE_INTERVAL = 0.07;

type DictationState = "idle" | "recording";

export function DictationDemo() {
  const fieldRef = useRef<HTMLDivElement>(null);
  const hudRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [state, setState] = useState<DictationState>("idle");
  const [text, setText] = useState("");
  const [timer, setTimer] = useState("0:00");

  // Refs that mutate without re-rendering.
  const traceRef = useRef<number[]>(new Array(SAMPLES).fill(0));
  const smoothedRef = useRef(0);
  const phaseRef = useRef(Math.random() * 10);
  const accumRef = useRef(0);
  const activeRef = useRef(false);
  const rafRef = useRef<number | null>(null);
  const dprRef = useRef(1);
  const lastTickRef = useRef(0);
  const cycleTokenRef = useRef(0);

  useEffect(() => {
    const canvas = canvasRef.current;
    const field = fieldRef.current;
    const hud = hudRef.current;
    if (!canvas || !field || !hud) return;

    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

    const resizeCanvas = () => {
      const rect = canvas.getBoundingClientRect();
      dprRef.current = Math.min(window.devicePixelRatio || 1, 2);
      canvas.width = Math.max(1, Math.round(rect.width * dprRef.current));
      canvas.height = Math.max(1, Math.round(rect.height * dprRef.current));
      ctx.setTransform(dprRef.current, 0, 0, dprRef.current, 0, 0);
    };

    const drawTrace = () => {
      const w = canvas.width / dprRef.current;
      const h = canvas.height / dprRef.current;
      ctx.clearRect(0, 0, w, h);
      const midY = h / 2;
      const amp = h * 0.48;
      const floor = 1.2;
      const stepX = w / (SAMPLES - 1);
      const trace = traceRef.current;

      ctx.beginPath();
      for (let i = 0; i < SAMPLES; i++) {
        const off = Math.max(floor, trace[i] * amp);
        const x = i * stepX;
        const y = midY - off;
        if (i === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      }
      for (let i = SAMPLES - 1; i >= 0; i--) {
        const off = Math.max(floor, trace[i] * amp);
        ctx.lineTo(i * stepX, midY + off);
      }
      ctx.closePath();
      ctx.fillStyle = "rgba(255,255,255,0.85)";
      ctx.fill();
    };

    const tickTrace = (now: number) => {
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
        traceRef.current.shift();
        traceRef.current.push(smoothedRef.current);
        pushed = true;
      }
      if (pushed) drawTrace();
      rafRef.current = window.requestAnimationFrame(tickTrace);
    };

    const startTrace = () => {
      if (activeRef.current) return;
      activeRef.current = true;
      resizeCanvas();
      lastTickRef.current = 0;
      rafRef.current = window.requestAnimationFrame(tickTrace);
    };

    const stopTrace = () => {
      activeRef.current = false;
      if (rafRef.current) window.cancelAnimationFrame(rafRef.current);
      rafRef.current = null;
      for (let i = 0; i < traceRef.current.length; i++) traceRef.current[i] *= 0.4;
      drawTrace();
    };

    const onResize = () => {
      if (activeRef.current) resizeCanvas();
    };
    window.addEventListener("resize", onResize, { passive: true });

    const formatTime = (seconds: number) => {
      const total = Math.floor(seconds);
      const m = Math.floor(total / 60);
      const s = total % 60;
      return `${m}:${s.toString().padStart(2, "0")}`;
    };
    const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

    const runCycle = async () => {
      const myToken = ++cycleTokenRef.current;
      let i = 0;
      while (myToken === cycleTokenRef.current) {
        const prompt = PROMPTS[i % PROMPTS.length];
        setText("");
        setTimer("0:00");
        setState("idle");
        await sleep(900);
        if (myToken !== cycleTokenRef.current) break;

        setState("recording");
        hud.classList.add("is-visible");
        startTrace();
        const startedAt = performance.now();
        const timerHandle = window.setInterval(() => {
          setTimer(formatTime((performance.now() - startedAt) / 1000));
        }, 100);

        await sleep(320);
        if (myToken !== cycleTokenRef.current) {
          clearInterval(timerHandle);
          break;
        }

        let typed = "";
        const baseDelay = 32;
        for (let k = 0; k < prompt.length; k++) {
          if (myToken !== cycleTokenRef.current) break;
          typed += prompt[k];
          setText(typed);
          const ch = prompt[k];
          const jitter = ch === " " ? 60 : ch === "," ? 140 : Math.random() * 30;
          await sleep(baseDelay + jitter);
        }
        clearInterval(timerHandle);
        if (myToken !== cycleTokenRef.current) break;

        await sleep(650);
        hud.classList.remove("is-visible");
        setState("idle");
        stopTrace();

        await sleep(1700);
        i++;
      }
    };

    const stopCycle = () => {
      cycleTokenRef.current++;
      hud.classList.remove("is-visible");
      setState("idle");
      stopTrace();
    };

    if (reducedMotion.matches) {
      setText(PROMPTS[0]);
      setTimer("0:05");
      setState("recording");
      hud.classList.add("is-visible");
      resizeCanvas();
      for (let i = 0; i < SAMPLES; i++) {
        const t = i / SAMPLES;
        traceRef.current[i] = 0.35 + 0.25 * Math.sin(t * 14) + 0.12 * Math.sin(t * 38);
      }
      drawTrace();
      return () => {
        window.removeEventListener("resize", onResize);
      };
    }

    if (!("IntersectionObserver" in window)) {
      runCycle();
      return () => {
        stopCycle();
        window.removeEventListener("resize", onResize);
      };
    }

    const card = fieldRef.current?.closest(".demo-card");
    if (!card) {
      runCycle();
      return () => {
        stopCycle();
        window.removeEventListener("resize", onResize);
      };
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
      else if (card.getBoundingClientRect().top < window.innerHeight) runCycle();
    };
    document.addEventListener("visibilitychange", onVis);

    return () => {
      io.disconnect();
      document.removeEventListener("visibilitychange", onVis);
      window.removeEventListener("resize", onResize);
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
        className={`demo-field${hasText ? " has-text" : ""}`}
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
            Hold{" "}
            <span className="kbd-combo">
              <span className="sr-only">Option plus Space</span>
              <kbd className="keycap keycap--inline" aria-hidden="true">
                &#8997;
              </kbd>
              <kbd className="keycap keycap--inline" aria-hidden="true">
                Space
              </kbd>
            </span>{" "}
            to dictate
          </span>
          <span className="demo-field__text">{text}</span>
          <span className="demo-field__caret" aria-hidden="true"></span>
        </span>
      </div>

      <div ref={hudRef} className="demo-hud" aria-hidden="true">
        <div className="demo-hud__trace">
          <canvas
            ref={canvasRef}
            className="demo-hud__canvas"
            width={480}
            height={60}
            aria-hidden="true"
          />
        </div>
        <div className="demo-hud__meta">
          <span className="demo-hud__timer">{timer}</span>
          <span className="demo-hud__hint">Release to finish &middot; Esc cancels</span>
        </div>
      </div>

      <figcaption className="demo-card__caption">
        Hold{" "}
        <span className="kbd-combo">
          <span className="sr-only">Option plus Space</span>
          <kbd className="keycap keycap--inline" aria-hidden="true">
            &#8997;
          </kbd>
          <kbd className="keycap keycap--inline" aria-hidden="true">
            Space
          </kbd>
        </span>
        , speak, release &mdash; words appear at the cursor. Nothing leaves the Mac.
      </figcaption>
    </figure>
  );
}
