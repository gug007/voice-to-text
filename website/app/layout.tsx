import type { Metadata, Viewport } from "next";
import Script from "next/script";

import { IconSprite } from "@/components/icon-sprite";
import { GA_MEASUREMENT_ID, SITE_URL } from "@/lib/constants";
import {
  faqPageJsonLd,
  personJsonLd,
  softwareApplicationJsonLd,
  themeInitScript,
} from "@/lib/seo";

import "./globals.css";

const TITLE = "Voice to Text for Mac — Free, Offline · VoiceToText";
const DESCRIPTION =
  "Free voice to text for Mac. Hold a hotkey in any app — Slack, Notes, Mail, ChatGPT — and your words type at the cursor. Offline. No account. Free download.";
const TWITTER_DESCRIPTION =
  "Free push-to-talk voice to text for Mac. Words type at the cursor in Slack, Notes, Mail, ChatGPT, or any app. Offline on the Apple Neural Engine.";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: TITLE,
  description: DESCRIPTION,
  keywords: [
    "voice to text mac",
    "speech to text mac",
    "voice to text macbook",
    "how to use voice to text on mac",
    "voice to text app for mac",
    "speak to text app for mac",
    "free speech to text mac",
    "mac dictation",
    "offline speech recognition mac",
    "push to talk dictation",
  ],
  authors: [{ name: "Gurgen Abagyan", url: "https://github.com/gug007" }],
  robots: {
    index: true,
    follow: true,
    googleBot: { index: true, follow: true, "max-image-preview": "large" },
  },
  alternates: { canonical: "/" },
  openGraph: {
    type: "website",
    siteName: "VoiceToText",
    url: SITE_URL,
    title: TITLE,
    description: DESCRIPTION,
    locale: "en_US",
  },
  twitter: {
    card: "summary_large_image",
    title: TITLE,
    description: TWITTER_DESCRIPTION,
  },
  icons: {
    icon: [
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
  themeColor: [
    { media: "(prefers-color-scheme: dark)", color: "#0A0A0B" },
    { media: "(prefers-color-scheme: light)", color: "#FFFFFF" },
  ],
  colorScheme: "dark light",
};

function JsonLdScript({ data }: { data: object }) {
  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{ __html: JSON.stringify(data) }}
    />
  );
}

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <link rel="dns-prefetch" href="https://github.com" />
        <script dangerouslySetInnerHTML={{ __html: themeInitScript }} />
        <JsonLdScript data={softwareApplicationJsonLd} />
        <JsonLdScript data={faqPageJsonLd} />
        <JsonLdScript data={personJsonLd} />
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

        <IconSprite />
        <a className="skip-link" href="#main">Skip to main content</a>
        {children}
      </body>
    </html>
  );
}
