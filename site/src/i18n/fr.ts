// Textes de la page en français (langue par défaut). Toute affirmation vient du
// README ou du code de Murmure : ne rien ajouter qui n'y figure pas.
// Les chaînes peuvent contenir un peu de HTML (<code>, <kbd>, <strong>).

export default {
  meta: {
    title: 'Murmure — dictée vocale 100 % locale pour macOS',
    description:
      "Un raccourci, vous parlez, le texte s'écrit dans l'application active. Whisper tourne sur votre Mac : pas de compte, pas d'abonnement, rien ne sort de votre machine.",
    ogAlt: 'Murmure, dictée vocale 100 % locale pour macOS, et sa pastille d’écoute',
  },
  nav: {
    skip: 'Aller au contenu',
    home: 'Murmure, accueil',
    install: 'Installer',
    github: 'GitHub',
    otherLang: 'English',
    otherLangLabel: 'Read this page in English',
  },
  hero: {
    eyebrow: 'Dictée vocale pour macOS',
    title: 'Vous parlez, le texte s’écrit.<br>Rien ne quitte votre Mac.',
    lead:
      'Un raccourci, vous parlez, le texte se colle dans l’application active. Votre voix est transcrite par Whisper, sur votre machine, hors ligne.',
    install: 'Installer',
    github: 'Voir sur GitHub',
    promises: ['Pas de compte', 'Pas d’abonnement', 'Pas de clé API', 'Open source'],
  },
  pill: {
    label:
      'Animation de la pastille de Murmure : l’onde suit la voix, puis ses points s’allument un à un pendant la transcription.',
    listening: 'Vous parlez',
    transcribing: 'Transcription…',
  },
  privacy: {
    title: 'Local et privé, vraiment',
    lead:
      'Murmure transforme votre voix en texte, partout, sans rien envoyer nulle part.',
    items: [
      {
        title: 'Votre voix reste sur le Mac',
        text: 'L’enregistrement est transcrit sur place puis collé. Ni audio ni texte ne part sur Internet.',
      },
      {
        title: 'Whisper tourne en local',
        text: '<a href="https://github.com/ggerganov/whisper.cpp">whisper.cpp</a> et le modèle <code>large-v3-turbo</code> fonctionnent sur votre machine, hors ligne.',
      },
      {
        title: 'Une seule requête, désactivable',
        text: 'Au plus une fois par jour, l’app lit le numéro de la dernière version publiée sur GitHub. Rien n’est envoyé, ni texte, ni audio, ni identifiant. <code>MURMURE_CHECK_UPDATES=0</code> la coupe.',
      },
      {
        title: 'Rien à créer, rien à payer',
        text: 'Pas de compte, pas d’abonnement, pas de clé API. Le code est ouvert, sous licence MIT.',
      },
    ],
  },
  features: {
    title: 'Ce qu’il fait',
    items: [
      {
        title: 'Partout',
        text: 'Mail, Slack, un terminal, un éditeur, un champ de recherche : n’importe quelle application.',
      },
      {
        title: 'Environ 2 secondes',
        text: 'C’est le temps entre la fin de votre phrase et le texte collé.',
      },
      {
        title: 'Appui bref ou maintenu',
        text: '<kbd>⌘⇧E</kbd> démarre l’écoute, un second appui transcrit. Ou gardez la touche enfoncée le temps de parler.',
      },
      {
        title: 'Échap pour annuler',
        text: 'Une dictée ratée ? <kbd>Échap</kbd> ou le ✕ de la pastille, et rien n’est collé. Hors écoute, Échap garde son rôle habituel.',
      },
      {
        title: 'Collé là où vous étiez',
        text: 'Changé d’application pendant la transcription ? Le texte retourne dans celle où la dictée a commencé.',
      },
      {
        title: 'Historique',
        text: 'Les 10 dernières dictées dans le menu ; un clic recopie le texte. Gardé sur ce Mac, désactivable.',
      },
      {
        title: 'Réglages',
        text: 'Raccourci, micro, langue, durées, historique : une fenêtre, appliquée dès la dictée suivante.',
      },
      {
        title: 'Vocabulaire et corrections',
        text: 'Soufflez vos termes à Whisper et rattrapez ce qu’il francise : « commis » devient « commit ».',
      },
      {
        title: 'Presse-papiers restauré',
        text: 'En option, Murmure remet ce que vous aviez copié juste après avoir collé la dictée.',
      },
    ],
  },
  shots: {
    title: 'En images',
    items: {
      ecoute: {
        alt: 'La pastille de Murmure pendant l’écoute : une onde, « Vous parlez », un bouton stop.',
        caption: 'Pendant l’écoute, l’onde suit votre voix.',
      },
      transcription: {
        alt: 'La pastille pendant la transcription : une rangée de points et « Transcription… ».',
        caption: 'Pendant la transcription, les points servent de jauge.',
      },
      compteARebours: {
        alt: 'La pastille affiche « Encore 9 s » à l’approche de la durée maximale.',
        caption: 'Un compte à rebours prévient avant la durée maximale.',
      },
      reglages: {
        alt: 'La fenêtre Réglages de Murmure : raccourci, micro, langue, appui maintenu, durée maximale, historique, presse-papiers, démarrage.',
        caption: 'La fenêtre de réglages.',
      },
    },
  },
  install: {
    title: 'Installation',
    prereqTitle: 'Prérequis',
    prereqs: [
      'macOS 14 ou plus',
      '<a href="https://brew.sh">Homebrew</a>',
      'les outils en ligne de commande Xcode : <code>xcode-select --install</code>',
    ],
    commandsTitle: 'Dans un terminal',
    after:
      'L’installeur pose <code>ffmpeg</code> et <code>whisper-cpp</code>, télécharge le modèle (~550 Mo, une fois), compile la pastille et l’app <code>/Applications/Murmure.app</code>, puis la lance : son icône apparaît dans la barre des menus.',
    permissionsTitle: 'Deux autorisations',
    permissions: [
      {
        title: 'Micro',
        text: 'Au premier usage, macOS demande l’accès au micro : acceptez.',
      },
      {
        title: 'Accessibilité',
        text: 'Pour que le texte se colle tout seul, ajoutez <code>Murmure.app</code> dans <strong>Réglages Système › Confidentialité et sécurité › Accessibilité</strong>. Sans cela, le texte arrive dans le presse-papiers et vous faites <kbd>⌘V</kbd> vous-même. Tant qu’une autorisation manque, le menu de Murmure le signale et ouvre le bon panneau des Réglages.',
      },
    ],
    ready: 'C’est prêt : <kbd>⌘⇧E</kbd>, parlez, <kbd>⌘⇧E</kbd>.',
    update:
      'Pour mettre à jour : <code>git pull</code> puis <code>./install.sh</code>. Le menu signale quand une nouvelle version est publiée.',
  },
  faq: {
    title: 'Questions fréquentes',
    items: [
      {
        q: 'Quelles langues ?',
        a: 'Le français par défaut. La fenêtre de réglages propose aussi l’anglais, l’espagnol, l’allemand, l’italien et la détection automatique ; le fichier <code>config</code> accepte d’autres codes de langue de Whisper. L’interface de Murmure est en français.',
      },
      {
        q: 'Quelle place prend le modèle ?',
        a: 'Environ 550 Mo, téléchargés une fois par l’installeur et vérifiés par leur empreinte SHA-256. Le modèle n’est chargé en mémoire que le temps d’une dictée.',
      },
      {
        q: 'Mac Intel ou Apple Silicon ?',
        a: 'Murmure est conçu pour les Mac Apple Silicon : le script cherche <code>whisper-cli</code> et <code>ffmpeg</code> dans <code>/opt/homebrew</code>, là où Homebrew les installe sur ces Mac. Sur un Mac Intel, Homebrew les place ailleurs et la dictée ne fonctionne pas telle quelle.',
      },
      {
        q: 'Comment le désinstaller ?',
        a: '<code>./uninstall.sh</code> dans le dossier cloné : il quitte Murmure, retire le lancement au démarrage, l’app, le modèle et les fichiers de <code>~/.local/share/murmure</code>. Retirez ensuite l’entrée Murmure de la liste Accessibilité. <code>ffmpeg</code> et <code>whisper-cpp</code> restent installés par Homebrew.',
      },
      {
        q: 'Pourquoi pas la dictée de macOS ?',
        a: 'La dictée du système ponctue mal, et les autres outils sont souvent payants et connectés à un service distant. Murmure s’appuie sur Whisper <code>large-v3-turbo</code>, vous laisse corriger le vocabulaire qu’il francise, et ne fait qu’une chose : votre voix en texte, partout, sans rien envoyer nulle part.',
      },
    ],
  },
  family: {
    title: 'Aussi par Ultraviolettes',
    lead: 'Des outils macOS qui travaillent sur votre Mac, pas dans le cloud.',
    sillage: {
      name: 'Sillage',
      text: 'Vos réunions laissent une trace : enregistrement, transcription et compte rendu. Sur votre Mac.',
      link: 'Découvrir Sillage',
      href: 'https://sillage-mac.vercel.app/',
    },
  },
  footer: {
    license: 'Licence MIT',
    by: 'Par',
    author: 'Baptiste Bouillot',
    source: 'Code source sur GitHub',
  },
};
