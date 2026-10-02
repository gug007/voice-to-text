import Link from "next/link";

import { CATALOG_SNAPSHOT, cloudModels, localModels } from "@/lib/app-facts";
import { formatDisplayDate, page } from "@/lib/pages";

import type { SeoLandingConfig } from "./seo-landing";

// Dragon for Mac is discontinued and Nuance no longer publishes its Mac pages,
// so its features come from Nuance's 2016 v6 feature sheet and its history from
// Microsoft (Nuance's owner since 2022) and news reports from the time. Apple's
// features come from its Mac User Guide. All were checked on the
// `sourcesReviewed` date in lib/pages.ts. When you re-check them, update the
// copy and that date together; drop any fact you can no longer source.

const PATH = "/dragon-for-mac-alternative";
const SOURCES_CHECKED = formatDisplayDate(page(PATH).sourcesReviewed ?? page(PATH).published);
const LOCAL_COUNT = localModels().length;
const CLOUD_COUNT = cloudModels().length;

export const dragonForMacAlternativeConfig: SeoLandingConfig = {
  path: PATH,
  title: "Mac Dictation vs Dragon (2026): What Replaced Dragon for Mac",
  description:
    "Dragon for Mac was discontinued in 2018. Compare Apple Dictation, Voice Control and VoiceToText on voice commands, custom vocabulary, privacy and price.",
  breadcrumb: "Dragon for Mac alternative",
  parent: { name: "Compare", path: "/compare" },
  eyebrow: "Balanced comparison",
  readingTime: "11 min",
  h1: "Mac dictation vs. Dragon: what to use now that Dragon for Mac is gone.",
  lead:
    "Nuance stopped selling Dragon for Mac in October 2018, ending the Dragon-branded dictation it brought to the Mac after buying MacSpeech. Nothing replaced it one for one. macOS now has spoken punctuation in Dictation and commands and custom words in Voice Control. VoiceToText, a free app, adds a review step, local speech models and meeting transcripts, but none of Dragon’s voice commands.",
  heroPoints: [
    `Sources checked ${SOURCES_CHECKED}`,
    "Dragon’s and Apple’s wins first",
    "Where VoiceToText falls short",
    "Voice Control for commands",
  ],
  disclosure: (
    <>
      VoiceToText’s developer wrote this page, so read it as a comparison by an interested party. Nuance no
      longer publishes pages for Dragon for Mac, so its features come from Nuance’s 2016 feature sheet and its
      history from Microsoft and news reports at the time. Apple’s features come from its Mac User Guide. All
      were checked on {SOURCES_CHECKED} and are linked under <a href="#sources">Sources</a>. This page is not
      affiliated with or endorsed by Microsoft, Nuance or Apple; the names are used only to identify the
      products being compared.
    </>
  ),
  summaryTitle: "What should a former Dragon user switch to?",
  summary: (
    <>
      It depends on what you used Dragon for. To control the Mac by voice, with commands, custom words and
      editing by voice, turn on Voice Control: it is built into macOS and works offline after a one-time
      download. For dictating prose with spoken punctuation, start with Apple Dictation. Try VoiceToText when
      you want to read and fix the whole transcript before it is pasted, pick a local or cloud speech model,
      or transcribe meetings and recordings. It has none of Dragon’s voice commands, and it is not a medical
      dictation product.
    </>
  ),
  atAGlance: {
    title: "At a glance, as of October 2026.",
    caption: `Dragon for Mac v6 as Nuance described it in 2016, Apple’s features from its Mac User Guide, and VoiceToText as of ${CATALOG_SNAPSHOT}. Checked ${SOURCES_CHECKED}.`,
    columns: ["Dragon for Mac (v6)", "Apple Dictation & Voice Control", "VoiceToText"],
    rows: [
      {
        label: "Status",
        cells: [
          "Discontinued October 22, 2018. Version 6 perpetual licenses still run, with no updates.",
          "Built into macOS. Dictation is in Keyboard settings, Voice Control in Accessibility.",
          "Free download from GitHub for macOS 15 or later on Apple Silicon.",
        ],
      },
      {
        label: "Price",
        cells: [
          "No longer sold. Version 6 launched at $300 in 2016.",
          "Included with macOS.",
          "Free. Cloud models and AI features bill your own OpenAI or ElevenLabs key.",
        ],
      },
      {
        label: "Voice commands",
        cells: [
          "Command and control: the mouse and keys by voice, command sets for Mac apps, custom commands.",
          "Dictation: spoken punctuation, emoji and “new line”. Voice Control: full command and control and custom commands.",
          "None. “Comma” or “new line” is typed as a word unless an optional AI action cleans it up.",
        ],
      },
      {
        label: "Custom vocabulary",
        cells: [
          "Custom word lists you could import and export, plus auto-texts.",
          "Voice Control: up to 1,000 terms per supported language, typed or imported.",
          "None.",
        ],
      },
      {
        label: "Correcting text",
        cells: [
          "By voice, with Full Text Control in apps such as TextEdit, Pages and Word.",
          "Click a blue-underlined word for alternatives; Voice Control edits by voice.",
          "Edit the whole transcript in a review panel before it’s pasted. No editing by voice.",
        ],
      },
      {
        label: "Where speech is processed",
        cells: [
          "On the computer, adapting to your voice as you used it.",
          "Keyboard settings say whether Dictation runs on your Mac. Voice Control works offline after a download.",
          "On the Mac by default (Parakeet or Whisper). Cloud models send audio to their provider.",
        ],
      },
      {
        label: "Recordings and meetings",
        cells: [
          "Transcribed recorded audio.",
          "Not part of Dictation or Voice Control.",
          "Records mic and system audio, imports one file at a time, keeps a searchable history.",
        ],
      },
    ],
  },
  sections: [
    {
      id: "what-happened",
      eyebrow: "What happened to Dragon for Mac",
      title: "From MacSpeech Dictate to a discontinued product.",
      paragraphs: [
        <>
          Dragon reached the Mac through another company. MacSpeech licensed Nuance’s Dragon technology in 2008
          to build MacSpeech Dictate. Nuance bought MacSpeech in February 2010 and that September brought
          Dragon-branded dictation to the Mac with Dragon Dictate for Mac 2.0, offered as an upgrade to
          MacSpeech Dictate.
        </>,
        <>
          The line was later sold as Dragon for Mac 5 and, from September 2016, as Dragon Professional
          Individual for Mac, version 6, for $300. Nuance described v6 as dictation, transcription and
          customization software whose speech engine kept learning from your voice on the computer itself.
        </>,
        <>
          Nuance discontinued Dragon Professional Individual for Mac effective October 22, 2018. Owners of a
          version 6 perpetual license can keep using it, but Nuance stopped releasing updates. Dragon Medical for
          Mac had been discontinued that August. What remained on sale were Windows editions and Dragon Anywhere
          for iOS and Android.
        </>,
        <>
          Microsoft completed its acquisition of Nuance on March 4, 2022, so Dragon is now a Microsoft product
          line.
        </>,
      ],
      note:
        "Still running version 6? Nothing has adapted it to a macOS release since 2018. Dragon could export custom word lists, and Voice Control imports a plain text file with one term per line, so a saved list gives you a head start.",
    },
    {
      id: "apple-wins",
      eyebrow: "Where Apple wins",
      title: "Much of what Dragon did is now built into macOS.",
      intro: (
        <>
          Apple splits it across two features. Dictation turns speech into text, and Voice Control adds
          commands. When Voice Control is on, you dictate through it and standard Dictation isn’t available.
        </>
      ),
      cards: [
        {
          title: "Spoken punctuation and formatting",
          body:
            "Dictation inserts commas, periods and question marks by itself in supported languages. Say “exclamation mark”, an emoji name, “new line” or “new paragraph”, and Apple’s command list adds brackets, symbols and capitalization such as “all caps”.",
        },
        {
          title: "Command and control",
          body:
            "With Voice Control you say “Open Mail”, “Scroll down” or “Click Done”, label items on screen with names, numbers or a grid, and edit text with commands like “Replace cat with dog”. Spelling mode enters characters; Command mode ignores everything but commands.",
        },
        {
          title: "Custom words and commands",
          body:
            "Voice Control’s custom vocabulary takes up to 1,000 terms per supported language, typed or imported from a text file; Apple’s own example is a medical term, “hemianopsia”. Custom commands can paste text, press a keyboard shortcut or run a Shortcut, much like Dragon’s auto-texts and custom commands.",
        },
        {
          title: "Offline and free",
          body:
            "Voice Control needs a one-time download, then works without an internet connection. For Dictation, Keyboard settings say whether your speech is processed on your Mac, and Apple lists the languages with on-device Dictation. Both come with macOS.",
        },
      ],
      note: (
        <>
          On a Mac with Apple silicon you can keep typing while Dictation listens. It takes text of any length
          and stops after 30 seconds without speech. The{" "}
          <Link href="/how-to-use-voice-to-text-on-mac#built-in-dictation">voice to text guide</Link> shows how
          to turn it on and which keys start it.
        </>
      ),
    },
    {
      id: "vtt-fits",
      eyebrow: "Where VoiceToText fits",
      title: "Long dictation you read before it lands, plus recordings.",
      intro: (
        <>
          VoiceToText is a free Mac app that turns speech into text. It doesn’t try to control your Mac.
        </>
      ),
      cards: [
        {
          title: "Review before paste",
          body:
            "Press ⌥Space in any app, speak, and press it again. The whole transcript opens in a panel where you fix names and numbers, add another take at the caret with ⌘R, then press Return to paste. Turn review off to paste straight away.",
        },
        {
          title: "A choice of speech models",
          body: (
            <>
              {LOCAL_COUNT} models run on the Mac: Parakeet TDT v3, the default, for 25 European languages, and
              five Whisper sizes for 99. {CLOUD_COUNT} optional OpenAI and ElevenLabs models use your own API key.{" "}
              <Link href="/whisper-vs-parakeet-mac">Parakeet vs. Whisper</Link> explains the local choice.
            </>
          ),
        },
        {
          title: "Meetings and recordings",
          body: (
            <>
              Conversations records your microphone and the call’s audio with no bot, or transcribes one audio or
              video file at a time, and keeps everything in a searchable history on the Mac. See{" "}
              <Link href="/meeting-recording">meeting recording on Mac</Link>.
            </>
          ),
        },
        {
          title: "Optional AI cleanup",
          body:
            "Off by default. With your OpenAI key, Clean transcript or Fix grammar turns spoken cues like “comma” and “new line” into punctuation and line breaks. Running one sends the transcript text to OpenAI.",
        },
      ],
    },
    {
      id: "not-a-replacement",
      eyebrow: "What VoiceToText can’t replace",
      title: "It is not a Dragon replacement for commands, custom words or medicine.",
      cards: [
        {
          title: "No voice commands",
          body:
            "There is no command and control. You can’t open apps, click, press keys or move the pointer by voice. Voice Control does that.",
        },
        {
          title: "No spoken punctuation",
          body:
            "The model punctuates from how you speak. Saying “comma”, “period” or “new line” types the word, unless you run an optional AI action afterwards.",
        },
        {
          title: "No custom vocabulary",
          body:
            "You can’t add names, jargon or a word list, and there’s no voice profile that learns from you. Check unusual terms in the review panel before you paste.",
        },
        {
          title: "No editing by voice",
          body:
            "There’s no selecting or correcting text by voice. Corrections happen with the keyboard, in the review panel or in the app you pasted into.",
        },
        {
          title: "Not medical software",
          body:
            "No medical vocabulary, no EHR integration and no HIPAA claims. Local models keep audio on the Mac; cloud models send it to their provider. Whether that suits patient information is your organization’s decision.",
        },
        {
          title: "Mac and Apple Silicon only",
          body:
            "It needs macOS 15 or later on an Apple Silicon Mac. There is no Windows, iPhone or Android app, and nothing syncs between devices.",
        },
      ],
      note:
        "On clinical notes: Nuance discontinued Dragon Medical for Mac in August 2018, and Microsoft documents Dragon Medical One as a Windows app that a Mac reaches through Citrix or a Windows virtual machine. If you dictate patient information, use what your organization has approved, and check any transcript against the recording.",
    },
    {
      id: "verdict",
      eyebrow: "Verdict by use case",
      title: "Pick by what you used Dragon for.",
      cards: [
        {
          title: "Controlling the Mac by voice → Voice Control",
          body:
            "Commands, a numbered grid, custom commands and up to 1,000 custom words, built in and offline after one download.",
        },
        {
          title: "Quick dictation with spoken punctuation → Apple Dictation",
          body:
            "No install, the Microphone key or a shortcut to start, and punctuation by voice in supported languages.",
        },
        {
          title: "Long drafts you check first → VoiceToText",
          body:
            "Review the whole transcript before it’s pasted, keep it on the Mac with a local model, and keep meetings and recordings in one history. Free.",
        },
      ],
      note: (
        <>
          Using Voice Control too? Say “Stop listening” before you dictate with VoiceToText, or Voice Control
          will enter the same words as text, and “Start listening” afterwards.{" "}
          <Link href="/apple-dictation-alternative">Apple Dictation vs. VoiceToText</Link> goes deeper on the
          built-in option, and the <Link href="/compare">comparison hub</Link> lists every other app.
        </>
      ),
    },
  ],
  faq: [
    {
      question: "Is Dragon still available for Mac?",
      answer:
        "No. Nuance discontinued Dragon Professional Individual for Mac effective October 22, 2018, and Dragon Medical for Mac that August. Version 6 perpetual licenses keep working but get no updates. Microsoft completed its acquisition of Nuance in March 2022.",
    },
    {
      question: "What happened to MacSpeech Dictate?",
      answer:
        "MacSpeech built MacSpeech Dictate on Dragon technology it licensed from Nuance in 2008. Nuance bought MacSpeech in February 2010 and that September brought Dragon-branded dictation to the Mac with Dragon Dictate for Mac 2.0, offered as an upgrade to MacSpeech Dictate. The line ended as Dragon Professional Individual for Mac, discontinued in 2018.",
    },
    {
      question: "How does Mac dictation compare with Dragon?",
      answer:
        "macOS now covers much of Dragon's command side. Dictation handles spoken punctuation, emoji and new lines, and Voice Control adds commands, custom commands and up to 1,000 custom vocabulary terms per supported language. This page doesn't compare accuracy, so dictate the same paragraph with each tool you're considering.",
    },
    {
      question: "Can VoiceToText replace Dragon?",
      answer:
        "Only for dictating text. It gives you a review step before paste, local or cloud speech models, and meeting and file transcription. It has no voice commands, spoken punctuation, custom vocabulary or command and control, so it can't drive your Mac or edit text by voice. Use macOS Voice Control for that.",
    },
    {
      question: "What is the best medical dictation software for Mac?",
      answer:
        "That is for your organization to decide. Microsoft documents its Dragon Medical One as a Windows app that a Mac can use through Citrix or a Windows virtual machine. VoiceToText is not a medical dictation product: it has no medical vocabulary or EHR integration and makes no HIPAA claims. Local models keep audio on the Mac; cloud models send it to the provider.",
    },
    {
      question: "Does VoiceToText work offline?",
      answer:
        "Yes, with a local model. Parakeet, the default, and the Whisper models transcribe on the Mac with the network off after a one-time download. Cloud models and AI actions are optional and send audio or text to the provider under your own key.",
    },
  ],
  sources: [
    {
      label: "MacRumors: Nuance discontinues Dragon Professional Individual for Mac",
      href: "https://www.macrumors.com/2018/10/24/nuance-discontinues-dragon-mac/",
      detail:
        "October 24, 2018. The October 22 discontinuation, version 6 perpetual licenses that keep working without updates, Dragon Medical for Mac’s discontinuation that August, and the Windows and mobile products left on sale.",
    },
    {
      label: "MacTech: Nuance acquires MacSpeech",
      href: "https://www.mactech.com/2010/02/16/nuance-acquires-macspeech-2/",
      detail:
        "February 16, 2010. The acquisition, and Nuance’s statement that MacSpeech licensed Dragon technology in 2008 to build MacSpeech Dictate.",
    },
    {
      label: "9to5Mac: MacSpeech gets upgraded to Dragon Dictate 2",
      href: "https://9to5mac.com/2010/09/20/macspeech-gets-upgraded-to-dragon-naturally-speaking-2/",
      detail: "September 20, 2010. Dragon Dictate 2 for Mac, with an upgrade price for MacSpeech Dictate owners.",
    },
    {
      label: "audioXpress: Nuance announces new Dragon releases for Windows and Mac",
      href: "https://audioxpress.com/news/speech-recognition-improved-nuance-announces-major-new-releases-of-dragon-for-windows-and-mac-os-x",
      detail:
        "August 2016. Nuance’s announcement of Dragon Professional Individual for Mac, version 6: dictation, transcription and customization, an engine that learns on the computer, and the $300 price from September 1, 2016.",
    },
    {
      label: "Nuance: Dragon Professional Individual for Mac, v6 feature matrix (PDF)",
      href: "https://dragon.nuance.com/shared/resource-library/gb/fm-dragon-professional-individual-for-mac-v6-en-uk.pdf",
      detail:
        "Nuance’s comparison of v6 with Dragon for Mac 5 and Apple Dictation: command and control, app command sets, Full Text Control, custom word lists, auto-texts and custom commands.",
    },
    {
      label: "Microsoft: Microsoft completes acquisition of Nuance",
      href: "https://news.microsoft.com/source/2022/03/04/microsoft-completes-acquisition-of-nuance-ushering-in-new-era-of-outcomes-based-ai/",
      detail: "March 4, 2022. Microsoft’s announcement that the acquisition was complete.",
    },
    {
      label: "Microsoft Learn: Using Dragon Medical One with Mac",
      href: "https://learn.microsoft.com/en-us/industry/healthcare/dragon-medical-one/admin/using-dragon-medical-one-with-mac",
      detail:
        "Dragon Medical One as a native Windows app that can’t be installed on macOS, and the Citrix and virtual-machine setups Microsoft documents for a Mac.",
    },
    {
      label: "Apple: Dictate messages and documents on Mac",
      href: "https://support.apple.com/guide/mac-help/use-dictation-mh40584/mac",
      detail:
        "Turning Dictation on, starting and stopping it, auto-punctuation, spoken punctuation and formatting, the on-device check in Keyboard settings, and how Dictation relates to Voice Control.",
    },
    {
      label: "Apple: Commands for dictating text on Mac",
      href: "https://support.apple.com/guide/mac-help/commands-for-dictating-text-on-mac-mh40695/mac",
      detail: "The punctuation, symbol, formatting and capitalization commands available while dictating.",
    },
    {
      label: "Apple: macOS feature availability",
      href: "https://www.apple.com/macos/feature-availability/",
      detail: "The languages with on-device Dictation, which needs a download of speech models.",
    },
    {
      label: "Apple: Use Voice Control commands",
      href: "https://support.apple.com/guide/mac-help/use-voice-control-commands-mh40719/mac",
      detail: "Navigating and editing by voice, item labels and grids, and the Dictation, Spelling and Command modes.",
    },
    {
      label: "Apple: Turn Voice Control on or off",
      href: "https://support.apple.com/guide/mac-help/turn-voice-control-on-or-off-mchl63d14732/mac",
      detail: "The one-time download, after which Voice Control works without an internet connection.",
    },
    {
      label: "Apple: Customize Voice Control",
      href: "https://support.apple.com/guide/mac-help/customize-voice-control-mchl9899c8a5/mac",
      detail: "Turning commands on or off and creating your own that paste text, press a shortcut or run a Shortcut.",
    },
    {
      label: "Apple: Use a custom vocabulary with Voice Control",
      href: "https://support.apple.com/guide/mac-help/use-a-custom-vocabulary-mchl3eb7b79a/mac",
      detail:
        "Up to 1,000 terms per supported language, typed or imported from a text file, with a medical term as Apple’s example.",
    },
    {
      label: "VoiceToText source repository",
      href: "https://github.com/gug007/voice-to-text",
      detail: "The app’s source and releases, for every VoiceToText claim on this page.",
    },
  ],
  related: [
    {
      href: "/apple-dictation-alternative",
      title: "Apple Dictation alternative",
      description: "When the built-in tool is enough, and what a review step and model choice add.",
    },
    {
      href: "/offline-speech-to-text-mac",
      title: "Offline speech to text on Mac",
      description: "What stays on the Mac with local models, and where cloud features begin.",
    },
    {
      href: "/compare/best-dictation-apps-for-mac",
      title: "Best dictation apps for Mac",
      description: "Seven Mac dictation apps side by side on dictation, files, meetings, privacy, languages and price.",
    },
  ],
  ctaTitle: "Dictate a page the way you did in Dragon, then check it before it lands.",
  ctaBody:
    "Give VoiceToText its own shortcut, dictate the same paragraph with it and with Apple Dictation, and keep whichever needs fewer corrections.",
  analyticsPlacement: "dragon_alternative",
};
