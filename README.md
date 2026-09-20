# Murmure

**Dictée vocale globale pour macOS, 100 % locale.**
Un raccourci, vous parlez, le texte s'écrit dans l'application active.

![Murmure en écoute](docs/apercu-ecoute.png)

Pas de compte, pas d'abonnement, pas de clé API, aucune donnée qui sort de votre Mac.
Votre voix est transcrite par [whisper.cpp](https://github.com/ggerganov/whisper.cpp)
tournant en local.

## Pourquoi

Les outils de dictée pour Mac sont soit limités (la dictée système ponctue mal),
soit payants et connectés à un service distant. Murmure fait une seule chose :
il transforme votre voix en texte, partout, sans rien envoyer nulle part.

## Ce qu'il fait

- **Partout** — Mail, Slack, un terminal, un éditeur, un champ de recherche.
- **Local** — Whisper `large-v3-turbo` sur votre machine, hors ligne.
- **Rapide** — environ 2 secondes entre la fin de votre phrase et le texte collé.
- **Discret** — une pastille flottante pendant l'écoute, rien d'autre.
- **Corrigé** — un dictionnaire rattrape le vocabulaire technique que Whisper
  francise (« commis » → « commit », « worktrade » → « worktree »).

![Transcription en cours](docs/apercu-transcription.png)

## Installation

Prérequis : macOS 14 ou plus, [Homebrew](https://brew.sh), et les outils en ligne de
commande Xcode (`xcode-select --install`).

```bash
git clone https://github.com/croustibat/murmure.git
cd murmure
./install.sh
```

L'installeur pose `ffmpeg` et `whisper-cpp`, télécharge le modèle (~550 Mo, une fois),
compile la pastille, crée `~/Applications/Murmure.app` et dépose la règle de raccourci.

### Les deux autorisations

Au premier usage, macOS demande l'accès au **micro** : acceptez.

Pour que le texte se colle tout seul, ajoutez ensuite `Murmure.app` dans
**Réglages > Confidentialité et sécurité > Accessibilité**. Sans cela le texte
arrive dans le presse-papiers et vous faites ⌘V vous-même.

### Le raccourci

Avec [Karabiner-Elements](https://karabiner-elements.pqrs.org), la règle est déposée
automatiquement : activez-la dans **Complex Modifications > Add rule**. Elle utilise
⌘⇧E — et non ⌘E, qui priverait le Finder de « Éjecter ».

Sans Karabiner, associez ce raccourci avec l'outil de votre choix :

```
/usr/bin/open -n -a ~/Applications/Murmure.app
```

## Utilisation

**⌘⇧E** démarre l'écoute — la pastille apparaît. Parlez. **⌘⇧E** à nouveau : le texte
est transcrit puis collé. Vous pouvez aussi cliquer le carré de la pastille pour
arrêter.

Le presse-papiers contient toujours la dernière transcription : si le collage échoue,
⌘V la récupère.

## Configuration

Tout se règle dans `~/.local/share/murmure/` :

| Fichier | Rôle |
|---|---|
| `vocabulaire.txt` | termes soufflés à Whisper avant la transcription |
| `corrections.txt` | remplacements appliqués après, au format `entendu\|voulu` |

`corrections.txt` est l'outil efficace. Une règle par ligne, insensible à la casse,
sur mots entiers :

```
commis|commit
redit|Redis
worktrade|worktree
```

Quelques variables d'environnement permettent d'ajuster le reste :

| Variable | Défaut | Rôle |
|---|---|---|
| `MURMURE_LANG` | `fr` | langue de transcription |
| `MURMURE_DEVICE` | `:0` | index du micro (`ffmpeg -f avfoundation -list_devices true -i ""`) |
| `MURMURE_MAX` | `300` | durée maximale d'un enregistrement, en secondes |
| `MURMURE_SILENCE_DB` | `-70` | seuil en dessous duquel l'audio est jugé muet |

## Comment ça marche

```
⌘⇧E → Murmure.app → murmure.sh
                      ├─ ffmpeg (avfoundation) ──→ WAV 16 kHz mono
                      ├─ overlay (AppKit) ───────→ pastille flottante
                      ├─ whisper-cli ────────────→ texte
                      ├─ corriger.pl ────────────→ vocabulaire rectifié
                      └─ pbcopy + ⌘V ───────────→ application active
```

Le bundle `.app` n'est pas cosmétique : un script nu n'a pas d'identité TCC, macOS ne
propose donc jamais l'autorisation micro et lui livre **un flux muet** au lieu d'une
erreur. Whisper, n'entendant rien, invente alors des génériques de sous-titres.

## Dépannage

Le journal dit toujours ce qui s'est passé :

```bash
tail -20 /tmp/murmure-$(id -u)/murmure.log
```

| Symptôme | Cause probable |
|---|---|
| « Aucun son capté » | autorisation micro refusée, ou mauvais `MURMURE_DEVICE` |
| Texte copié mais pas collé | `Murmure.app` absent de la liste Accessibilité |
| Accents cassés (`Soci√©t√©`) | locale non UTF-8 dans l'environnement du raccourci |
| Première dictée très lente | chargement du modèle et des shaders Metal ; les suivantes sont rapides |

## Désinstallation

```bash
./uninstall.sh
```

## Licence

MIT — voir [LICENSE](LICENSE).
