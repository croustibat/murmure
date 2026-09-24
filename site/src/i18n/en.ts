// English copy. Same structure as fr.ts, which is the reference: every claim
// must come from Murmure's README or code.
import type fr from './fr';

const en: typeof fr = {
  meta: {
    title: 'Murmure — fully local voice dictation for macOS',
    description:
      'Press a shortcut, speak, and your words appear in the app you’re using. Whisper runs on your Mac: no account, no subscription, nothing leaves your machine.',
    ogAlt: 'Murmure, fully local voice dictation for macOS, with its listening pill',
  },
  nav: {
    skip: 'Skip to content',
    home: 'Murmure, home',
    install: 'Install',
    github: 'GitHub',
    otherLang: 'Français',
    otherLangLabel: 'Lire cette page en français',
  },
  hero: {
    eyebrow: 'Voice dictation for macOS',
    title: 'Speak, and it’s typed.<br>Nothing leaves your Mac.',
    lead:
      'Press a shortcut, talk, and the text is pasted into the app in front of you. Your voice is transcribed by Whisper, on your own machine, offline.',
    install: 'Install',
    github: 'View on GitHub',
    promises: ['No account', 'No subscription', 'No API key', 'Open source'],
  },
  pill: {
    label:
      'Animation of Murmure’s pill: the waveform follows your voice, then its dots light up one by one while transcribing.',
    listening: 'Listening',
    transcribing: 'Transcribing…',
  },
  privacy: {
    title: 'Local and private, for real',
    lead: 'Murmure turns your voice into text, anywhere, without sending anything anywhere.',
    items: [
      {
        title: 'Your voice stays on your Mac',
        text: 'Recordings are transcribed right there, then pasted. No audio and no text ever goes online.',
      },
      {
        title: 'Whisper runs locally',
        text: '<a href="https://github.com/ggerganov/whisper.cpp">whisper.cpp</a> and the <code>large-v3-turbo</code> model run on your machine, offline.',
      },
      {
        title: 'One request, and you can turn it off',
        text: 'At most once a day, the app reads the latest release number from GitHub. Nothing is sent: no text, no audio, no identifier. <code>MURMURE_CHECK_UPDATES=0</code> disables it.',
      },
      {
        title: 'Nothing to sign up for or pay',
        text: 'No account, no subscription, no API key. The code is open, under the MIT license.',
      },
    ],
  },
  features: {
    title: 'What it does',
    items: [
      {
        title: 'Works everywhere',
        text: 'Mail, Slack, a terminal, an editor, a search field: any app at all.',
      },
      {
        title: 'About 2 seconds',
        text: 'That’s how long it takes from the end of your sentence to the pasted text.',
      },
      {
        title: 'Tap or hold',
        text: 'Tap <kbd>⌘⇧E</kbd> to start listening and again to transcribe. Or hold it down while you talk.',
      },
      {
        title: 'Esc to cancel',
        text: 'Botched it? Press <kbd>Esc</kbd> or the pill’s ✕ and nothing gets pasted. When Murmure isn’t listening, Esc works as usual.',
      },
      {
        title: 'Pasted where you started',
        text: 'Switched apps while it was transcribing? The text goes back to the one where you started dictating.',
      },
      {
        title: 'History',
        text: 'Your last 10 dictations in the menu; click one to copy it again. Kept on this Mac, and you can turn it off.',
      },
      {
        title: 'Settings',
        text: 'Shortcut, microphone, language, timings, history: one window, applied from your next dictation.',
      },
      {
        title: 'Vocabulary and corrections',
        text: 'Give Whisper your jargon up front, and fix the words it keeps mishearing afterwards.',
      },
      {
        title: 'Clipboard restored',
        text: 'Optionally, Murmure puts back whatever you had copied right after pasting your dictation.',
      },
    ],
  },
  shots: {
    title: 'Screenshots',
    items: {
      ecoute: {
        alt: 'Murmure’s pill while listening: a waveform, “Vous parlez” (you’re speaking), and a stop button.',
        caption: 'While listening, the waveform follows your voice.',
      },
      transcription: {
        alt: 'The pill while transcribing: a row of dots and “Transcription…”.',
        caption: 'While transcribing, the dots work as a progress bar.',
      },
      compteARebours: {
        alt: 'The pill showing “Encore 9 s” (9 s left) as the maximum length approaches.',
        caption: 'A countdown warns you before the maximum length.',
      },
      reglages: {
        alt: 'Murmure’s Settings window: shortcut, microphone, language, hold threshold, maximum length, history, clipboard, launch at login.',
        caption: 'The Settings window (the app’s interface is in French).',
      },
    },
  },
  install: {
    title: 'Install',
    prereqTitle: 'Requirements',
    prereqs: [
      'macOS 14 or later',
      '<a href="https://brew.sh">Homebrew</a>',
      'Xcode Command Line Tools: <code>xcode-select --install</code>',
    ],
    commandsTitle: 'In a terminal',
    after:
      'The installer sets up <code>ffmpeg</code> and <code>whisper-cpp</code>, downloads the model (~550 MB, once), builds the pill and <code>/Applications/Murmure.app</code>, then launches it: its icon shows up in the menu bar.',
    permissionsTitle: 'Two permissions',
    permissions: [
      {
        title: 'Microphone',
        text: 'The first time you use it, macOS asks for microphone access: allow it.',
      },
      {
        title: 'Accessibility',
        text: 'For the text to paste itself, add <code>Murmure.app</code> under <strong>System Settings › Privacy &amp; Security › Accessibility</strong>. Without it, the text lands on the clipboard and you press <kbd>⌘V</kbd> yourself. While a permission is missing, Murmure’s menu says so and opens the right Settings pane.',
      },
    ],
    ready: 'You’re set: <kbd>⌘⇧E</kbd>, talk, <kbd>⌘⇧E</kbd>.',
    update:
      'To update, run <code>git pull</code> then <code>./install.sh</code>. The menu tells you when a new version is out.',
  },
  faq: {
    title: 'FAQ',
    items: [
      {
        q: 'Which languages?',
        a: 'French by default. The Settings window also offers English, Spanish, German, Italian and automatic detection, and the <code>config</code> file accepts other Whisper language codes. Murmure’s own interface is in French.',
      },
      {
        q: 'How big is the model?',
        a: 'About 550 MB, downloaded once by the installer and checked against its SHA-256 hash. It’s only loaded into memory for the length of a dictation.',
      },
      {
        q: 'Intel or Apple Silicon?',
        a: 'Murmure is built for Apple Silicon Macs: the script looks for <code>whisper-cli</code> and <code>ffmpeg</code> in <code>/opt/homebrew</code>, where Homebrew installs them on those Macs. On an Intel Mac, Homebrew puts them elsewhere, so dictation won’t work out of the box.',
      },
      {
        q: 'How do I uninstall it?',
        a: 'Run <code>./uninstall.sh</code> from the cloned folder: it quits Murmure and removes launch at login, the app, the model and the files in <code>~/.local/share/murmure</code>. Then remove Murmure from the Accessibility list. <code>ffmpeg</code> and <code>whisper-cpp</code> stay installed through Homebrew.',
      },
      {
        q: 'Why not use macOS dictation?',
        a: 'The built-in dictation is poor at punctuation, and most alternatives are paid and tied to a remote service. Murmure relies on Whisper <code>large-v3-turbo</code>, lets you fix the vocabulary it gets wrong, and does just one thing: voice to text, everywhere, without sending anything anywhere.',
      },
    ],
  },
  footer: {
    license: 'MIT license',
    by: 'By',
    author: 'Baptiste Bouillot',
    source: 'Source code on GitHub',
  },
};

export default en;
