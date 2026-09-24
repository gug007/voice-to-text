import type { ReactNode } from "react";

/**
 * Inline line glyphs for the home page's product mockups and the "Built in"
 * grid. Drawn on the same 20px grid and 1.75 stroke as the sprite in
 * `icon-sprite.tsx`, but inlined so a section can use one without growing the
 * sprite every page ships. Always decorative.
 */
export type GlyphName =
  | "bubble"
  | "summary"
  | "checklist"
  | "sparkles"
  | "search"
  | "versions"
  | "terminal"
  | "menubar"
  | "headphones"
  | "update"
  | "contrast"
  | "play"
  | "star"
  | "person"
  | "clock"
  | "upload"
  | "record";

const PATHS: Record<GlyphName, ReactNode> = {
  bubble: <path d="M4 4.5h12a1 1 0 011 1v7.5a1 1 0 01-1 1H9.5L6 16.5V14H4a1 1 0 01-1-1V5.5a1 1 0 011-1z" />,
  summary: <path d="M4 5h12M4 8.5h8M4 12h12M4 15.5h6" />,
  checklist: <path d="M3.5 6l1.6 1.6L8 4.8M11 6.2h5.5M3.5 13l1.6 1.6L8 11.8M11 13.2h5.5" />,
  sparkles: (
    <>
      <path d="M8.5 3.5l1.3 3.7 3.7 1.3-3.7 1.3-1.3 3.7-1.3-3.7L3.5 8.5l3.7-1.3z" />
      <path d="M15 12.5l.6 1.9 1.9.6-1.9.6-.6 1.9-.6-1.9-1.9-.6 1.9-.6z" />
    </>
  ),
  search: (
    <>
      <circle cx="8.8" cy="8.8" r="5" />
      <path d="M12.5 12.5L16.5 16.5" />
    </>
  ),
  versions: (
    <>
      <rect x="3" y="6.5" width="10.5" height="10.5" rx="2" />
      <path d="M6.5 3.5h8a2 2 0 012 2v8" />
    </>
  ),
  terminal: (
    <>
      <rect x="2.5" y="3.5" width="15" height="13" rx="2" />
      <path d="M6 8.5l2.2 2-2.2 2M10.5 12.5h3.5" />
    </>
  ),
  menubar: (
    <>
      <rect x="2.5" y="3.5" width="15" height="13" rx="2" />
      <path d="M2.5 7.5h15M13 5.5h2" />
    </>
  ),
  headphones: (
    <>
      <path d="M4 13.5V11a6 6 0 0112 0v2.5" />
      <rect x="3" y="12" width="3.5" height="5" rx="1.2" />
      <rect x="13.5" y="12" width="3.5" height="5" rx="1.2" />
    </>
  ),
  update: <path d="M16 10a6 6 0 11-1.9-4.4M16.2 3.8v3.4h-3.4" />,
  contrast: (
    <>
      <circle cx="10" cy="10" r="6.5" />
      <path d="M10 3.5a6.5 6.5 0 010 13z" fill="currentColor" stroke="none" />
    </>
  ),
  play: <path d="M7 5.2v9.6a.6.6 0 00.9.5l7.4-4.8a.6.6 0 000-1L7.9 4.7a.6.6 0 00-.9.5z" fill="currentColor" stroke="none" />,
  star: <path d="M10 3.4l2 4.2 4.5.6-3.3 3.1.8 4.5L10 13.6l-4 2.2.8-4.5-3.3-3.1 4.5-.6z" />,
  person: (
    <>
      <circle cx="10" cy="7" r="3" />
      <path d="M4.5 16.5a5.5 5.5 0 0111 0" />
    </>
  ),
  clock: (
    <>
      <circle cx="10" cy="10" r="6.5" />
      <path d="M10 6.5V10l2.3 1.6" />
    </>
  ),
  upload: <path d="M10 13V4m0 0L6.8 7.2M10 4l3.2 3.2M4 12.5V15a1.5 1.5 0 001.5 1.5h9A1.5 1.5 0 0016 15v-2.5" />,
  record: <circle cx="10" cy="10" r="4.5" fill="currentColor" stroke="none" />,
};

type GlyphProps = {
  name: GlyphName;
  className?: string;
};

export function Glyph({ name, className }: GlyphProps) {
  return (
    <svg
      className={className ? `icon ${className}` : "icon"}
      viewBox="0 0 20 20"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      {PATHS[name]}
    </svg>
  );
}
