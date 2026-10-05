# Changelog

Nouveautés de chaque version publiée de Murmure. `script/release.sh` reprend la
section de la version publiée dans la release GitHub et dans la fenêtre de mise
à jour (Sparkle) ; sans section, il reprend les sujets des commits.

## 1.2.0

- Murmure s'installe depuis un DMG signé et notarisé par Apple : ouvrez `Murmure.dmg` et glissez Murmure dans Applications. Plus besoin de Homebrew, de Xcode ni du terminal.
- Tout est dans l'app : whisper.cpp, compilé pour les Mac Apple Silicon, et un enregistreur natif qui remplace ffmpeg. Le signal de départ attend que le micro soit prêt : le début de la phrase n'est plus coupé.
- Mises à jour automatiques : Murmure cherche une nouvelle version une fois par jour et l'installe à votre demande, sans jamais interrompre une dictée. « Rechercher les mises à jour… » est dans le menu ; une case des Réglages désactive la vérification. Les autorisations Micro et Accessibilité sont conservées d'une version à l'autre.
- Le modèle de transcription (550 Mo) se télécharge depuis l'app au premier lancement, reprend après une coupure et est vérifié avant usage. « J'ai déjà le fichier… » reprend un modèle déjà téléchargé.
- Première dictée rapide : Murmure se prépare en arrière-plan après l'installation et après chaque mise à jour.
- Un casque débranché pendant une dictée ne la coupe plus : l'écoute continue sur un autre micro.
- Les longues dictées gardent mieux votre vocabulaire, et une étiquette de bruit comme « *sad* » ne remplace plus le texte dicté.
- Nouvelle icône dans la barre des menus : une bulle, qui ne se confond plus avec celle de Sillage.
- Compiler Murmure soi-même reste possible : `git clone` puis `./install.sh` (Xcode requis).

### Vous avez la 1.1.0 ?

La 1.1.0 ne se met pas à jour seule : téléchargez Murmure.dmg et remplacez l'app ; vos réglages, votre vocabulaire et le modèle sont conservés. Les versions suivantes arriveront d'elles-mêmes.

L'app change de signature : macOS redemande l'accès au micro à la première dictée. Pour le collage automatique, dans Réglages Système > Confidentialité et sécurité > Accessibilité, supprimez l'ancienne entrée Murmure (–), puis ajoutez la nouvelle (+) et cochez-la.

## 1.1.0 — 24 septembre 2026

- Première version publique : app de la barre des menus avec raccourci global, maintenir pour parler, Échap pour annuler.
- Pastille avec une onde qui suit la voix et une jauge de transcription.
- Collage dans l'application active au début de la dictée, restauration du presse-papiers en option.
- Réglages, historique des dernières dictées, détection des autorisations manquantes.
- Installation par `git clone` et `./install.sh`, modèle vérifié par SHA-256.
