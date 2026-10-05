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
    download: 'Télécharger pour Mac',
    downloadNote: 'macOS 14+, Apple Silicon, gratuit',
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
        title: 'Deux requêtes, et c’est tout',
        text: 'Le modèle, téléchargé une seule fois au premier lancement, puis, au plus une fois par jour, la liste des versions publiées sur GitHub. Rien n’est envoyé, ni texte, ni audio, ni identifiant. <code>MURMURE_CHECK_UPDATES=0</code> coupe la seconde.',
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
    dmgTitle: 'Télécharger l’app',
    steps: [
      'Téléchargez <code>Murmure.dmg</code>.',
      'Ouvrez-le et glissez <strong>Murmure</strong> dans <strong>Applications</strong>, puis lancez-la : son icône apparaît dans la barre des menus.',
      'Au premier lancement, Murmure propose de télécharger son modèle de transcription (~550 Mo, une seule fois).',
    ],
    download: 'Télécharger Murmure.dmg',
    dmgNote:
      'Il faut un Mac Apple Silicon sous macOS 14 ou plus. Signée et notarisée par Apple, l’app s’ouvre sans avertissement et embarque tout ce qu’il lui faut : ni Homebrew, ni Xcode, ni terminal.',
    brewTitle: 'Avec Homebrew',
    brewNote: 'La même app que celle du DMG, qui se met à jour toute seule de la même façon.',
    sourceTitle: 'Depuis les sources',
    sourcePrereqs:
      'Pour compiler Murmure vous-même : <a href="https://apps.apple.com/app/xcode/id497799835">Xcode</a> (ouvert une fois), CMake et XcodeGen, que l’installeur pose avec <a href="https://brew.sh">Homebrew</a> s’ils manquent.',
    after:
      'L’installeur télécharge le modèle, compile <code>whisper-cli</code> (whisper.cpp) et l’app <code>/Applications/Murmure.app</code>, puis la lance. Pour mettre à jour : <code>git pull</code> puis <code>./install.sh</code>.',
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
    updateTitle: 'Mises à jour',
    update:
      'Murmure se met à jour toute seule : une fois par jour, elle regarde si une nouvelle version est publiée et l’installe en un clic, en gardant vos réglages, votre vocabulaire, le modèle et les autorisations.',
    migration:
      'Depuis la version 1.1.0 ou une plus ancienne, installée avec <code>./install.sh</code> : quittez Murmure, téléchargez <code>Murmure.dmg</code> et remplacez l’app dans Applications. Vos réglages, votre vocabulaire et le modèle sont conservés ; macOS redemande une fois le micro et l’Accessibilité.',
  },
  faq: {
    title: 'Questions fréquentes',
    items: [
      {
        q: 'Quelles langues ?',
        a: 'Le français par défaut. La fenêtre de réglages propose aussi l’anglais, l’espagnol, l’allemand, l’italien et la détection automatique ; le fichier <code>config</code> accepte d’autres codes de langue de Whisper. L’interface de Murmure est en français.',
      },
      {
        q: 'Faut-il Homebrew ou Xcode ?',
        a: 'Non. L’app du DMG embarque whisper.cpp et tout ce qu’il lui faut. Homebrew n’est qu’une autre façon de l’installer (<code>brew install --cask croustibat/tap/murmure</code>), et Xcode ne sert qu’à compiler Murmure depuis les sources.',
      },
      {
        q: 'Quelle place prend le modèle ?',
        a: 'Environ 550 Mo, téléchargés une fois par l’app au premier lancement et vérifiés par leur empreinte SHA-256. Le modèle n’est chargé en mémoire que le temps d’une dictée.',
      },
      {
        q: 'Comment se fait la mise à jour ?',
        a: 'Toute seule, avec <a href="https://sparkle-project.org">Sparkle</a> : au plus une fois par jour, Murmure lit la liste des versions publiées sur GitHub et propose la nouvelle, qui s’installe en un clic et redémarre l’app, jamais au milieu d’une dictée. « Rechercher les mises à jour… », dans le menu, le fait sur-le-champ. Depuis la 1.1.0, installée avec <code>./install.sh</code> : téléchargez le DMG et remplacez l’app, vos réglages et le modèle sont conservés.',
      },
      {
        q: 'Mac Intel ou Apple Silicon ?',
        a: 'Apple Silicon uniquement (M1 ou plus récent), sous macOS 14 ou plus : l’app et le whisper.cpp qu’elle embarque sont compilés pour ces Mac.',
      },
      {
        q: 'Comment le désinstaller ?',
        a: 'Décochez « Ouvrir au démarrage » dans le menu, quittez Murmure et mettez l’app à la corbeille ; supprimez <code>~/.local/share/murmure</code> pour effacer aussi vos réglages et le modèle. Avec Homebrew : <code>brew uninstall --zap --cask murmure</code>. Depuis les sources : <code>./uninstall.sh</code>. Retirez ensuite l’entrée Murmure de la liste Accessibilité.',
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
