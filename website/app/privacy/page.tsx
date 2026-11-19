import type { Metadata } from "next";
import Link from "next/link";
import type { ReactNode } from "react";

import { ScrollEffects } from "@/components/scroll-effects";
import { Footer } from "@/components/sections/footer";
import { Nav } from "@/components/sections/nav";
import { ExternalLink } from "@/components/ui/external-link";
import { ISSUES_URL, REPO_URL } from "@/lib/constants";
import { formatDisplayDate, page, pageUrl } from "@/lib/pages";
import { INDEXABLE_ROBOTS } from "@/lib/seo";

import styles from "./privacy.module.css";

/* Every statement here was checked against the source when the date in
   lib/pages.ts was set. Re-check it when these change:
   - iPhone: Mobile/VoiceToTextMobile/Model/{Library,Transcriber,Insights,OpenAIKey,MacRemote,MacLink}.swift
   - Mac: VoiceToText/VoiceToText/{Engine,History,Remote}/, Support/AppUpdater.swift,
     Support/KeychainAPIKeyStore.swift
   - Website: app/layout.tsx (Google Analytics) and ANALYTICS.md (events). */

const PATH = "/privacy";
const PAGE_URL = pageUrl(PATH);
const { published: PUBLISHED, modified: UPDATED } = page(PATH);

const TITLE = "VoiceToText Privacy Policy";
const DESCRIPTION =
  "What the VoiceToText Mac app, iPhone app and website collect, what leaves your device, when, and who receives it. No account and no analytics in the apps.";

const POLICY_URLS = {
  huggingFace: "https://huggingface.co/privacy",
  github: "https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement",
  openAI: "https://openai.com/policies/privacy-policy/",
  groq: "https://groq.com/privacy-policy/",
  elevenLabs: "https://elevenlabs.io/privacy-policy",
  tailscale: "https://tailscale.com/privacy-policy",
  google: "https://policies.google.com/privacy",
} as const;
const GA_OPT_OUT_URL = "https://tools.google.com/dlpage/gaoptout";

export const metadata: Metadata = {
  title: TITLE,
  description: DESCRIPTION,
  alternates: { canonical: PATH },
  robots: INDEXABLE_ROBOTS,
  // The layout credits a person; this page speaks for the project.
  authors: [{ name: "VoiceToText", url: REPO_URL }],
  creator: "VoiceToText",
  publisher: "VoiceToText",
  openGraph: {
    type: "article",
    url: PAGE_URL,
    siteName: "VoiceToText",
    title: TITLE,
    description: DESCRIPTION,
    locale: "en_US",
    publishedTime: PUBLISHED,
    modifiedTime: UPDATED,
  },
  twitter: {
    card: "summary_large_image",
    title: TITLE,
    description: DESCRIPTION,
  },
};

type Recipient = {
  name: string;
  policy: string;
  receives: ReactNode;
};

const RECIPIENTS: Recipient[] = [
  {
    name: "Hugging Face",
    policy: POLICY_URLS.huggingFace,
    receives:
      "Both apps, when a speech model downloads. A download request from your device, with your IP address. No audio or text.",
  },
  {
    name: "GitHub",
    policy: POLICY_URLS.github,
    receives:
      "Mac app: the update check, and the update itself when you install one. No audio or text.",
  },
  {
    name: "OpenAI",
    policy: POLICY_URLS.openAI,
    receives:
      "Only with your own API key. Mac app: your audio when you use an OpenAI model, and text for AI actions, summaries, action items and custom prompts. iPhone app: transcript text for Summary and Action Items.",
  },
  {
    name: "Groq",
    policy: POLICY_URLS.groq,
    receives: "Mac app, only with your own API key: your audio when you use a Groq model.",
  },
  {
    name: "ElevenLabs",
    policy: POLICY_URLS.elevenLabs,
    receives:
      "Mac app, only with your own API key: your audio, streamed as you speak, when you use Scribe v2 Realtime.",
  },
  {
    name: "Tailscale",
    policy: POLICY_URLS.tailscale,
    receives:
      "Both apps, only after you sign in to Tailscale: your sign-in, device names, network addresses and connection logs. Not your recordings or transcripts, which travel encrypted between your own devices.",
  },
  {
    name: "Google",
    policy: POLICY_URLS.google,
    receives: "This website only, through Google Analytics.",
  },
];

export default function PrivacyPage() {
  return (
    <>
      <Nav linkPrefix="/" />
      <main id="main" tabIndex={-1}>
        <article>
          <header className="section guide-hero" id="top" aria-labelledby="privacy-title">
            <div className="container guide-hero__inner">
              <nav className="breadcrumb" aria-label="Breadcrumb">
                <ol role="list">
                  <li><Link href="/">Home</Link></li>
                  <li aria-current="page">Privacy Policy</li>
                </ol>
              </nav>
              <p className="hero__eyebrow">
                <span className="hero__eyebrow-dot" aria-hidden="true" />
                Mac app · iPhone app · Website
              </p>
              <h1 id="privacy-title" className="hero__title guide-hero__title">
                Privacy Policy
              </h1>
              <p className="hero__lead guide-hero__lead">
                What the VoiceToText apps and this website collect, what leaves your device, when, and who
                receives it.
              </p>
              <p className="guide__meta">
                <time dateTime={UPDATED}>Last updated: {formatDisplayDate(UPDATED)}</time>
              </p>
            </div>
          </header>

          <div className="section">
            <div className="container guide__container">
              <div className={styles.policy}>
                <h2 id="summary">In short</h2>
                <ul>
                  <li>Neither app needs an account.</li>
                  <li>
                    The developer runs no servers for the apps. Your recordings, transcripts and API keys never
                    reach the developer.
                  </li>
                  <li>The apps contain no analytics, crash reporting, advertising or tracking code.</li>
                  <li>Recordings and transcripts are stored on your own device.</li>
                  <li>
                    In the apps, data leaves your device only to download speech models, to check for Mac app
                    updates, and for optional features you set up with your own accounts. Each connection goes
                    straight to the company listed under <a className="link" href="#recipients">Who receives what</a>.
                  </li>
                  <li>This website uses Google Analytics.</li>
                  <li>The developer does not sell data and shows no ads.</li>
                </ul>

                <h2 id="iphone">iPhone app</h2>
                <p>
                  On the Home Screen the app is called “Voice to Text”. This section also applies to it on iPad.
                </p>

                <h3>Recordings and transcripts</h3>
                <p>
                  The app uses the microphone only while you record. Recordings, audio files you import, and their
                  transcripts are saved in the app’s private storage on your device. The app does not upload them.
                  Like other app data, they are part of your device backup if you back up to iCloud or a computer.
                </p>

                <h3>Transcription</h3>
                <p>
                  Speech is transcribed on the device with the Parakeet TDT v3 speech model. When you tap Download,
                  the app fetches the model (about 470 MB) once from Hugging Face (huggingface.co). The download
                  carries no audio or text. After that, transcription works offline.
                </p>

                <h3>Summary and Action Items (optional)</h3>
                <p>
                  These use your own OpenAI API key. When you tap Summary or Action Items, the app sends that
                  recording’s transcript text to OpenAI (api.openai.com) and saves the answer with the recording.
                  Nothing is sent until you add a key and tap one of them. OpenAI bills your account and handles the
                  text under its own terms.
                </p>
                <p>Your key is stored in the device’s Keychain and is sent only to OpenAI, with these requests.</p>

                <h3>Connecting to your Mac (optional)</h3>
                <p>
                  You can control VoiceToText on your Macs from the iPhone. To do that, you sign in to Tailscale in
                  the app’s settings. Tailscale is a separate company, and its networking software is built into the
                  app. Until you sign in, the app makes no Tailscale connections.
                </p>
                <p>
                  Tailscale’s servers handle the sign-in and tell your devices how to reach each other. Tailscale
                  receives your account sign-in, the device name <code>voicetotext-iphone</code>, network addresses
                  and its standard connection logs, under{" "}
                  <ExternalLink className="link" href={POLICY_URLS.tailscale}>Tailscale’s privacy policy</ExternalLink>.
                </p>
                <p>
                  The iPhone then connects only to Macs signed in to the same Tailscale account with Control from
                  iPhone turned on. It can start and stop a conversation recording, show the Mac’s conversations and
                  transcripts, play their audio, and listen live if the Mac allows it. This traffic is encrypted end
                  to end. It goes directly between your devices when possible; otherwise Tailscale relays it without
                  being able to read it. The developer runs no server in this path.
                </p>
                <p>Audio you play from a Mac is cached on the iPhone and deleted when you sign out of Tailscale.</p>
                <p>Apart from the connections above, the iPhone app makes no network connections.</p>

                <h2 id="mac">Mac app</h2>

                <h3>Recordings and transcripts</h3>
                <p>
                  Dictation uses the microphone. Conversations also record the Mac’s system audio, which macOS
                  allows through the Screen Recording permission; the app captures audio only, never the screen.
                  The Accessibility permission lets the app run its shortcut and paste the text.
                </p>
                <p>
                  Recordings and transcripts are saved on your Mac, in{" "}
                  <code>~/Library/Application Support/VoiceToText</code>. They stay there until you delete them,
                  except that the app removes the oldest routine dictations once there are more than 200. To stop
                  saving dictations, turn off History → History Options → Save New Dictations.
                </p>

                <h3>Speech models</h3>
                <p>
                  Local models (Parakeet and Whisper) run on the Mac. Speech models are downloaded once from Hugging
                  Face (huggingface.co); at launch, the app downloads the selected model if it isn’t installed yet.
                  These downloads carry no audio or text. With a local model, your audio never leaves the Mac.
                </p>

                <h3>Cloud transcription (optional)</h3>
                <p>
                  The app can also use cloud models from OpenAI, Groq and ElevenLabs, each with your own API key.
                  When you choose one, the app sends your audio straight to that provider (api.openai.com,
                  api.groq.com or api.elevenlabs.io): after you stop recording, or streamed as you speak for live
                  models. A request can also include the language, optional wording hints, and the end of the
                  previous part’s transcript so that a long recording stays consistent. Adding a key sends one
                  request to the provider to check that the key works.
                </p>

                <h3>AI actions, summaries and action items (optional)</h3>
                <p>
                  These use your own OpenAI key. When you run one, the app sends the text and the instruction to
                  OpenAI (api.openai.com): the dictated text for an AI action, or a recording’s transcript, with any
                  speaker names you assigned, for a summary, action items or a custom prompt. Nothing is sent until
                  you run one.
                </p>

                <h3>API keys</h3>
                <p>
                  Keys are stored in your Mac’s login Keychain and sent only to the provider they belong to. A copy
                  of the app you build yourself without code signing keeps them in its preferences file instead.
                </p>

                <h3>Updates</h3>
                <p>
                  At launch and once a day, the app asks GitHub (api.github.com) for the latest release. You can turn
                  this off with Updates → Check for updates automatically. An update is downloaded from GitHub only
                  after you choose to install it.
                </p>

                <h3>Control from iPhone (optional, off by default)</h3>
                <p>
                  If you turn on Control from iPhone in the iPhone pane and sign in to Tailscale, the Mac joins your
                  Tailscale network under the name <code>voicetotext-mac-</code> followed by your Mac’s name. It
                  accepts connections only from devices signed in to the same Tailscale account. Letting the iPhone
                  listen live is a separate switch, also off by default. Tailscale’s role is the same as for the
                  iPhone app. Until you turn this on, the Mac app makes no Tailscale connections.
                </p>
                <p>Apart from the connections above, the Mac app makes no network connections. It has no telemetry.</p>

                <h2 id="website">This website</h2>
                <p>
                  voicetotext.cc uses Google Analytics 4. Google Analytics records the pages you view and, under its
                  standard settings, interactions such as scrolling and clicks on links to other sites. The site
                  also reports four named events: download clicks, the demo video starting, taps on “Send to your
                  Mac”, and clicks on links to GitHub, each labelled with where on the page it happened.
                </p>
                <p>
                  With these, Google Analytics collects the referring site, browser and device type, and an
                  approximate location that Google derives from your IP address. It sets first-party cookies
                  (<code>_ga</code> and <code>_ga_…</code>) to tell visits apart. Google handles this data under{" "}
                  <ExternalLink className="link" href={POLICY_URLS.google}>its privacy policy</ExternalLink>. You can
                  block it with{" "}
                  <ExternalLink className="link" href={GA_OPT_OUT_URL}>Google’s opt-out browser add-on</ExternalLink>{" "}
                  or a content blocker; the site works without it.
                </p>
                <p>
                  The site stores your light or dark theme choice in your browser’s local storage, and remembers for
                  the current session that you closed the download bar. Neither leaves your browser.
                </p>
                <p>
                  The site has no other third-party scripts, no ads and no forms. As with any website, the server
                  that delivers these pages receives your IP address and browser details with each request.
                </p>

                <h2 id="recipients">Who receives what</h2>
                <p>
                  Each of these is a separate company. The apps and the site connect to them directly, never through
                  the developer. OpenAI, Groq, ElevenLabs and Tailscale receive data under your own account with
                  them, so their terms and privacy policies apply to it.
                </p>
                <dl className={styles.recipients}>
                  {RECIPIENTS.map(({ name, policy, receives }) => (
                    <div key={name} className={styles.recipient}>
                      <dt>
                        {name}
                        <br />
                        <ExternalLink className="link" href={policy}>
                          Privacy policy<span className="sr-only"> of {name}</span>
                        </ExternalLink>
                      </dt>
                      <dd>{receives}</dd>
                    </div>
                  ))}
                </dl>

                <h2 id="delete">Deleting your data</h2>

                <h3>iPhone app</h3>
                <ul>
                  <li>Delete a recording from the list or its detail screen. Its audio and transcript go with it.</li>
                  <li>
                    Settings → Remove key deletes your OpenAI key. Do this before deleting the app, because iOS can
                    keep Keychain items after an app is removed.
                  </li>
                  <li>Settings → Delete model removes the speech model.</li>
                  <li>
                    Settings → Sign out disconnects Tailscale and deletes audio downloaded from your Macs. To remove
                    the iPhone from your Tailscale account, use Tailscale’s admin console.
                  </li>
                  <li>Deleting the app deletes everything else it stored on the device.</li>
                </ul>

                <h3>Mac app</h3>
                <ul>
                  <li>Delete recordings in History, or all of them with History Options → Clear All.</li>
                  <li>Cloud → Remove Key deletes a provider’s key from the Keychain.</li>
                  <li>Models → Delete Model removes a downloaded model.</li>
                  <li>
                    To remove everything, quit the app, move it to the Trash, and delete the <code>VoiceToText</code>{" "}
                    and <code>FluidAudio</code> folders in <code>~/Library/Application Support</code>.
                  </li>
                </ul>

                <h3>Data held by others</h3>
                <p>
                  Anything you sent to OpenAI, Groq, ElevenLabs or Tailscale is kept under your account with that
                  company. Delete it, or close the account, there. For this website, clear the site’s cookies and
                  storage in your browser.
                </p>

                <h2 id="changes">Changes</h2>
                <p>
                  When the apps or the site change what they collect or send, this page is updated, along with the
                  date at the top. The source code of both apps is{" "}
                  <ExternalLink className="link" href={REPO_URL}>public on GitHub</ExternalLink>, so you can check
                  what they do.
                </p>

                <h2 id="contact">Contact</h2>
                <p>
                  For questions or requests,{" "}
                  <ExternalLink className="link" href={ISSUES_URL}>open an issue on GitHub</ExternalLink>. Issues are
                  public, so don’t include anything private.
                </p>
              </div>
            </div>
          </div>
        </article>
      </main>
      <Footer linkPrefix="/" />
      <ScrollEffects />
    </>
  );
}
