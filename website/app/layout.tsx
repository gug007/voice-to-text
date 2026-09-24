import type { Metadata, Viewport } from "next";
import Script from "next/script";

import { AnalyticsEvents } from "@/components/analytics-events";
import { IconSprite } from "@/components/icon-sprite";
import { AUTHOR_URL, GA_MEASUREMENT_ID, SITE_URL } from "@/lib/constants";
import { themeInitScript } from "@/lib/seo";

import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  // No `title` or `description` here on purpose: every page sets its own, and the
  // 404 page names itself with a React <title>. Home-page copy in the layout would
  // leak into the 404 page's description and social tags.
  applicationName: "VoiceToText",
  authors: [{ name: "Gurgen Abagyan", url: AUTHOR_URL }],
  creator: "Gurgen Abagyan",
  publisher: "Gurgen Abagyan",
  category: "productivity",
  referrer: "origin-when-cross-origin",
  openGraph: {
    type: "website",
    siteName: "VoiceToText",
    locale: "en_US",
  },
  twitter: {
    card: "summary_large_image",
  },
  icons: {
    icon: [
      { url: "/favicon.svg", type: "image/svg+xml" },
      { url: "/icon-64.png", sizes: "64x64", type: "image/png" },
      { url: "/app-icon.png", sizes: "512x512", type: "image/png" },
    ],
    apple: { url: "/app-icon.png", sizes: "512x512", type: "image/png" },
  },
  formatDetection: { telephone: false },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  // The page ground, not the HUD canvas, so the browser chrome matches the page
  // it sits above. ThemeToggle rewrites these when the visitor picks a theme.
  themeColor: [
    { media: "(prefers-color-scheme: dark)", color: "#0E1014" },
    { media: "(prefers-color-scheme: light)", color: "#FFFFFF" },
  ],
  colorScheme: "light dark",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <link rel="dns-prefetch" href="https://github.com" />
        <script dangerouslySetInnerHTML={{ __html: themeInitScript }} />
        {/* Keep content and the compact navigation usable before/without JavaScript. */}
        <noscript>
          <style>{`
            .theme-toggle { display: none !important; }
            @media (max-width: 1180px) {
              .nav__primary, .nav__mobile,
              .nav__in > .btn, .nav__inner > .btn, .nav__right > .btn { display: none !important; }
              .nav__fallback { display: flex !important; }
            }
          `}</style>
        </noscript>
      </head>
      <body>
        <Script
          src={`https://www.googletagmanager.com/gtag/js?id=${GA_MEASUREMENT_ID}`}
          strategy="afterInteractive"
        />
        <Script id="ga-init" strategy="afterInteractive">{`
          window.dataLayer = window.dataLayer || [];
          function gtag(){dataLayer.push(arguments);}
          gtag('js', new Date());
          gtag('config', '${GA_MEASUREMENT_ID}');
        `}</Script>
        <AnalyticsEvents />

        <IconSprite />
        <a className="skip-link" href="#main">Skip to main content</a>
        {children}
      </body>
    </html>
  );
}
