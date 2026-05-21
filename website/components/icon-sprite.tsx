/**
 * Single SVG sprite included once in the document. Every <Icon name="..."/>
 * references one of these symbols via <use href="#i-NAME"/>.
 */
export function IconSprite() {
  return (
    <svg
      aria-hidden="true"
      width="0"
      height="0"
      style={{ position: "absolute" }}
      focusable="false"
    >
      <defs>
        <symbol id="i-download" viewBox="0 0 16 16">
          <path d="M8 1v9m0 0l-3-3m3 3l3-3M2 13h12" stroke="currentColor" strokeWidth="1.5" fill="none" strokeLinecap="round" strokeLinejoin="round" />
        </symbol>
        <symbol id="i-github" viewBox="0 0 16 16">
          <path fill="currentColor" d="M8 .2a8 8 0 00-2.53 15.59c.4.07.55-.17.55-.38v-1.34c-2.22.48-2.7-1.07-2.7-1.07-.36-.92-.89-1.17-.89-1.17-.73-.5.06-.49.06-.49.8.06 1.23.83 1.23.83.72 1.23 1.88.87 2.34.67.07-.52.28-.88.51-1.08-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.58.82-2.14-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82a7.65 7.65 0 014 0c1.53-1.03 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.14 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48v2.2c0 .21.15.46.55.38A8 8 0 008 .2" />
        </symbol>
        <symbol id="i-chevron-down" viewBox="0 0 16 16">
          <path d="M4 6l4 4 4-4" stroke="currentColor" strokeWidth="1.5" fill="none" strokeLinecap="round" strokeLinejoin="round" />
        </symbol>
        <symbol id="i-lock" viewBox="0 0 20 20">
          <rect x="4" y="9" width="12" height="9" rx="2" stroke="currentColor" strokeWidth="1.75" fill="none" />
          <path d="M7 9V6a3 3 0 016 0v3" stroke="currentColor" strokeWidth="1.75" fill="none" strokeLinecap="round" />
        </symbol>
        <symbol id="i-bolt" viewBox="0 0 20 20">
          <path d="M11 2L4 11h5l-1 7 7-9h-5l1-7z" stroke="currentColor" strokeWidth="1.75" fill="none" strokeLinecap="round" strokeLinejoin="round" />
        </symbol>
        <symbol id="i-box" viewBox="0 0 20 20">
          <path d="M10 2L3 6v8l7 4 7-4V6l-7-4zM3 6l7 4 7-4M10 10v8" stroke="currentColor" strokeWidth="1.75" fill="none" strokeLinecap="round" strokeLinejoin="round" />
        </symbol>
        <symbol id="i-mic" viewBox="0 0 20 20">
          <rect x="7" y="2" width="6" height="11" rx="3" stroke="currentColor" strokeWidth="1.75" fill="none" />
          <path d="M4 10a6 6 0 0012 0M10 16v3" stroke="currentColor" strokeWidth="1.75" fill="none" strokeLinecap="round" />
        </symbol>
        <symbol id="i-keyboard" viewBox="0 0 20 20">
          <rect x="2" y="5" width="16" height="10" rx="2" stroke="currentColor" strokeWidth="1.75" fill="none" />
          <path d="M5 9h.01M8 9h.01M11 9h.01M14 9h.01M6 12h8" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" />
        </symbol>
        <symbol id="i-sparkle" viewBox="0 0 20 20">
          <path d="M10 2v5M10 13v5M2 10h5M13 10h5M5 5l3 3M12 12l3 3M15 5l-3 3M8 12l-3 3" stroke="currentColor" strokeWidth="1.75" fill="none" strokeLinecap="round" />
        </symbol>
        <symbol id="i-agent" viewBox="0 0 20 20">
          <rect x="3" y="4" width="14" height="10" rx="2" stroke="currentColor" strokeWidth="1.75" fill="none" />
          <path d="M7 8h.01M13 8h.01M7 11h6M10 14v3M7 17h6" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" />
        </symbol>
        <symbol id="i-apps" viewBox="0 0 20 20">
          <rect x="2" y="2" width="6" height="6" rx="1.5" stroke="currentColor" strokeWidth="1.75" fill="none" />
          <rect x="12" y="2" width="6" height="6" rx="1.5" stroke="currentColor" strokeWidth="1.75" fill="none" />
          <rect x="2" y="12" width="6" height="6" rx="1.5" stroke="currentColor" strokeWidth="1.75" fill="none" />
          <rect x="12" y="12" width="6" height="6" rx="1.5" stroke="currentColor" strokeWidth="1.75" fill="none" />
        </symbol>
        <symbol id="i-arrow-right" viewBox="0 0 16 16">
          <path d="M3 8h10M9 4l4 4-4 4" stroke="currentColor" strokeWidth="1.5" fill="none" strokeLinecap="round" strokeLinejoin="round" />
        </symbol>
        <symbol id="i-cloud" viewBox="0 0 20 20">
          <path d="M14.5 15H6a4 4 0 01-.4-7.98A5 5 0 0115.5 8a3.5 3.5 0 01-1 7z" stroke="currentColor" strokeWidth="1.75" fill="none" strokeLinecap="round" strokeLinejoin="round" />
        </symbol>
      </defs>
    </svg>
  );
}
