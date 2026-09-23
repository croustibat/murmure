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

Pour mettre à jour, `git pull` puis `./install.sh` à nouveau. L'installeur ne remplace
que ce qui a changé et l'annonce en fin d'installation : tant que `Murmure.app` est
inchangée, elle n'est ni recréée ni re-signée et macOS conserve les autorisations.
Le modèle est vérifié par son empreinte SHA-256 ; un téléchargement interrompu reprend
au lancement suivant. `./install.sh --verify` recalcule l'empreinte d'un modèle déjà
présent et le retélécharge s'il est corrompu.

### Les deux autorisations

Au premier usage, macOS demande l'accès au **micro** : acceptez.

Pour que le texte se colle tout seul, ajoutez ensuite `Murmure.app` dans
**Réglages > Confidentialité et sécurité > Accessibilité**. Sans cela le texte
arrive dans le presse-papiers et vous faites ⌘V vous-même.

### Le raccourci

Avec [Karabiner-Elements](https://karabiner-elements.pqrs.org), la règle est déposée
automatiquement : activez-la dans **Complex Modifications > Add rule**. Elle utilise
⌘⇧E — et non ⌘E, qui priverait le Finder de « Éjecter ». Après une mise à jour,
supprimez l'ancienne règle Murmure puis ajoutez la nouvelle.

Sans Karabiner, associez ce raccourci avec l'outil de votre choix :

```
/usr/bin/open -n -a ~/Applications/Murmure.app
```

Sans argument, Murmure bascule (un appui démarre, le suivant arrête). Pour le
maintien et l'annulation, l'outil doit appeler `--args press` à l'appui,
`--args release` au relâchement et `--args cancel` pour annuler.

## Utilisation

Deux modes, sans réglage :

- **Appui bref : bascule.** **⌘⇧E** démarre l'écoute — la pastille apparaît. Parlez.
  **⌘⇧E** à nouveau : le texte est transcrit puis collé.
- **Appui maintenu : parler.** Gardez **⌘⇧E** enfoncé le temps de parler ; le
  relâchement lance la transcription. Le seuil entre les deux est de 600 ms
  (`MURMURE_HOLD_MS`).

Vous pouvez aussi cliquer le carré de la pastille pour arrêter et transcrire.

**Annuler** une dictée ratée : **Échap** pendant l'écoute (règle Karabiner), ou le ✕ de la pastille.
L'enregistrement est jeté, rien n'est collé. Échap n'est intercepté que pendant
l'écoute : le reste du temps, il garde son rôle normal dans toutes les applications.

Le presse-papiers contient toujours la dernière transcription : si le collage échoue,
⌘V la récupère.

## Configuration

Tout se règle dans `~/.local/share/murmure/` :

| Fichier | Rôle |
|---|---|
| `config` | réglages : langue, micro, durées… |
| `vocabulaire.txt` | termes soufflés à Whisper avant la transcription |
| `corrections.txt` | remplacements appliqués après, au format `entendu\|voulu` |

### Le fichier `config`

L'installeur le dépose avec toutes les clés en commentaire, à leur valeur par défaut,
et ne l'écrase jamais ensuite. Pour changer un réglage, retirez le `#` et modifiez la
valeur ; il s'applique à la dictée suivante, sans rien relancer :

```
MURMURE_LANG=en
MURMURE_DEVICE=MacBook Pro Microphone
MURMURE_HOLD_MS=800
```

Une ligne par réglage, `CLE=valeur`, sans guillemets (tolérés et retirés) ; `#` en
début de ligne pour commenter. Le fichier est lu, jamais exécuté : une clé inconnue,
une ligne malformée ou une valeur invalide (durée qui n'est pas un nombre, langue
autre qu'un code comme `fr` ou `auto`) est ignorée et signalée dans le journal.

| Clé | Défaut | Rôle |
|---|---|---|
| `MURMURE_LANG` | `fr` | langue de transcription |
| `MURMURE_DEVICE` | `:0` | micro : index ou nom (voir ci-dessous) |
| `MURMURE_MAX` | `300` | durée maximale d'un enregistrement, en secondes |
| `MURMURE_HOLD_MS` | `600` | au-delà, relâcher ⌘⇧E arrête l'écoute (appui maintenu) |
| `MURMURE_SILENCE_DB` | `-70` | seuil en dessous duquel l'audio est jugé muet |
| `MURMURE_WHISPER_ARGS` | _(vide)_ | options ajoutées à `whisper-cli`, par exemple `-bs 1 -bo 1` |

`MURMURE_SHORTCUT`, `MURMURE_HISTORY` et `MURMURE_RESTORE_CLIPBOARD` sont réservées
aux versions à venir et encore sans effet.

À l'approche de `MURMURE_MAX` (30 dernières secondes, ou le dernier quart d'une
durée plus courte), la pastille affiche un compte à rebours ; à la limite, la
transcription part d'elle-même, comme sur un second appui.

![Compte à rebours avant la durée maximale](docs/apercu-compte-a-rebours.png)

**Le micro** se désigne par son index ou, plus sûrement, par son nom : l'index change
quand on branche un casque. La liste figure sous « AVFoundation audio devices » :

```bash
ffmpeg -f avfoundation -list_devices true -i ""
```

Le nom exact est cherché d'abord (casse ignorée), puis un nom qui le contient. S'il
n'est pas trouvé, Murmure prend le micro `:0` et le note dans le journal.

Une variable d'environnement du même nom l'emporte sur le fichier, pratique pour un
essai depuis le terminal : `MURMURE_LANG=en ~/.local/share/murmure/murmure.sh`.
Lancé par le raccourci, Murmure ne reçoit aucune variable : seul le fichier compte.

### Corrections

`corrections.txt` est l'outil efficace. Une règle par ligne, insensible à la casse,
sur mots entiers :

```
commis|commit
redit|Redis
worktrade|worktree
```

### Vitesse de transcription

Les options par défaut de `whisper-cli` sont conservées : sur une dictée courte,
l'encodeur traite toujours une fenêtre de 30 s et représente l'essentiel du temps.
Réduire cette fenêtre (`-ac`) fait répéter le texte à Whisper, et les autres options
(décodage glouton, `--no-fallback`, threads, VAD) gagnent moins de 10 % ou abîment
la transcription. Pour mesurer sur votre machine, avec vos propres enregistrements
(un `.txt` de référence à côté de chaque `.wav` active le calcul du taux d'erreur) :

```bash
scripts/bench.sh -n 5 dictee1.wav dictee2.wav
scripts/bench.sh -c 'défaut|' -c 'glouton|-bs 1 -bo 1' dictee1.wav
```

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

La sortie technique de `whisper-cli` n'y figure que lorsqu'il échoue. Au-delà
d'environ 1 Mo, le journal est renommé `murmure.log.1` et repart de zéro.

| Symptôme | Cause probable |
|---|---|
| « Aucun son capté » | autorisation micro refusée, ou mauvais `MURMURE_DEVICE` |
| Texte copié mais pas collé | `Murmure.app` absent de la liste Accessibilité |
| Accents cassés (`Soci√©t√©`) | locale non UTF-8 dans l'environnement du raccourci |
| Première dictée très lente | chargement du modèle et des shaders Metal ; les suivantes sont rapides |
| ⌘⇧E lance une autre app, ou une ancienne version | une autre règle ⌘⇧E active dans Karabiner : `./install.sh` la signale, retirez-la dans Complex Modifications |
| Autorisations à redonner après une mise à jour | `Murmure.app` a changé (l'installeur l'indique) : macOS voit une nouvelle signature |
| Erreur de modèle au lancement de Whisper | fichier abîmé : `./install.sh --verify` |

## Désinstallation

```bash
./uninstall.sh
```

## Licence

MIT — voir [LICENSE](LICENSE).
