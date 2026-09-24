"use client";

import { useEffect, useRef, useState, useSyncExternalStore } from "react";
import type { ReactNode } from "react";

import { DMG_URL, SITE_URL } from "@/lib/constants";
import { Icon } from "@/components/ui/icon";

type DownloadButtonProps = {
  /** Analytics placement, e.g. "home_hero". Sent with both download_click and send_to_mac. */
  placement: string;
  size?: "md" | "lg";
  /** Label for the download link. The phone/PC variant always reads "Send to your Mac". */
  label?: ReactNode;
  className?: string;
  variant?: "primary" | "ghost";
  /** Leading icon. Off only where width is tight, e.g. the desktop nav bar. */
  icon?: boolean;
};

const SHARE_URL = `${SITE_URL}/`;
const COPIED = "Link copied — open it on your Mac";

/* A .dmg is useless on a phone, a PC or an iPad, so those visitors get a way to
 * move the link to their Mac instead. iPadOS reports itself as a Mac, but no Mac
 * has a multi-touch screen. Crawlers keep the real download link. */
function canInstallHere(): boolean {
  const ua = navigator.userAgent;
  if (/bot|crawl|spider|slurp|lighthouse/i.test(ua)) return true;
  const platform =
    (navigator as Navigator & { userAgentData?: { platform?: string } }).userAgentData?.platform ??
    navigator.platform ??
    "";
  const mac = /mac/i.test(platform) || /Macintosh/.test(ua);
  return mac && navigator.maxTouchPoints <= 1;
}

const subscribe = () => () => {};

/** The site-wide primary download CTA. Server HTML is always the plain DMG link,
 *  so it works without JavaScript and hydrates without a mismatch; the
 *  "Send to your Mac" variant only replaces it on the client. */
export function DownloadButton({
  placement,
  size = "lg",
  label = "Download for Mac — free",
  className,
  variant = "primary",
  icon = true,
}: DownloadButtonProps) {
  const installable = useSyncExternalStore(subscribe, canInstallHere, () => true);
  const [status, setStatus] = useState("");
  const resetTimer = useRef<number | undefined>(undefined);

  useEffect(() => () => window.clearTimeout(resetTimer.current), []);

  const classes = [
    "btn",
    variant === "ghost" ? "btn--ghost" : "btn--primary",
    size === "lg" ? "btn--lg" : null,
    className,
  ]
    .filter(Boolean)
    .join(" ");

  if (installable) {
    return (
      <a
        className={classes}
        href={DMG_URL}
        data-analytics-event="download_click"
        data-analytics-placement={placement}
      >
        {icon ? <Icon name="download" /> : null}
        <span>{label}</span>
      </a>
    );
  }

  const announce = (message: string) => {
    setStatus(message);
    window.clearTimeout(resetTimer.current);
    resetTimer.current = window.setTimeout(() => setStatus(""), 5000);
  };

  const send = async () => {
    if (navigator.share) {
      try {
        await navigator.share({
          title: "VoiceToText — voice to text for Mac",
          text: "Free dictation app for Mac. Open this link on your Mac to download it.",
          url: SHARE_URL,
        });
        return;
      } catch (error) {
        // The visitor closed the share sheet; copying behind their back would be a surprise.
        if (error instanceof DOMException && error.name === "AbortError") return;
      }
    }
    try {
      await navigator.clipboard.writeText(SHARE_URL);
      announce(COPIED);
    } catch {
      announce("Open voicetotext.cc on your Mac to download");
    }
  };

  return (
    <>
      <button
        type="button"
        className={classes}
        onClick={send}
        data-analytics-event="send_to_mac"
        data-analytics-placement={placement}
      >
        {icon ? <SendIcon /> : null}
        <span className="dl-btn__label">{status || "Send to your Mac"}</span>
      </button>
      <span className="sr-only" role="status" aria-live="polite">
        {status}
      </span>
    </>
  );
}

function SendIcon() {
  return (
    <svg
      className="icon"
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M8 10V2M5 4.8 8 1.8l3 3" />
      <path d="M5.5 7H4.2A1.2 1.2 0 0 0 3 8.2v4.6A1.2 1.2 0 0 0 4.2 14h7.6a1.2 1.2 0 0 0 1.2-1.2V8.2A1.2 1.2 0 0 0 11.8 7h-1.3" />
    </svg>
  );
}
