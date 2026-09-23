# Contribuer à Murmure

## Publier une version

Les versions sont des **GitHub Releases** étiquetées `vX.Y.Z`. `Murmure.app` lit la
dernière (`/repos/croustibat/murmure/releases/latest`) au plus une fois par jour et
la compare à son propre numéro, tiré du fichier `VERSION` par `install.sh`
(`CFBundleShortVersionString`). Une release plus récente fait apparaître « Version
X.Y.Z disponible » dans le menu, qui ouvre sa page.

L'app ne voit que les releases publiées : ni un simple tag, ni un brouillon, ni une
pré-version ne la déclenchent. La comparaison est numérique (`1.10.0` > `1.9.2`), le
`v` initial est retiré.

1. Mettre à jour `VERSION` sur `main` (`1.2.0`, sans `v`) :
   - correctif : `1.1.0` → `1.1.1` ;
   - fonctionnalité : `1.1.0` → `1.2.0` ;
   - changement qui oblige à réinstaller ou à reconfigurer : `1.1.0` → `2.0.0`.

   Committer (« Version 1.2.0 ») et pousser.

2. Vérifier que l'installation part bien de ce commit :

   ```bash
   git pull && ./install.sh
   ```

   Le menu de Murmure affiche « Murmure 1.2.0 ».

3. Étiqueter ce commit et publier la release :

   ```bash
   v=$(tr -d '[:space:]' < VERSION)
   git tag -a "v$v" -m "Murmure $v"
   git push origin "v$v"
   gh release create "v$v" --title "Murmure $v" --notes-file notes.md
   ```

   L'étiquette doit correspondre exactement au contenu de `VERSION` : une release
   `v1.2.0` pour un `VERSION` resté à `1.1.0` signalerait la mise à jour indéfiniment,
   même après `./install.sh`.

4. Les notes de release disent quoi faire, puisque rien n'est installé
   automatiquement. Modèle de `notes.md` :

   ```markdown
   ## Nouveautés
   - …

   ## Mettre à jour
   Dans le dossier où vous avez cloné Murmure :

       git pull && ./install.sh

   L'installeur indique en fin d'installation si `Murmure.app` a changé : dans ce
   cas, macOS redemande les autorisations Micro et Accessibilité.
   ```

La vérification se teste sans rien publier, avec un faux JSON servi en local
(`MURMURE_RELEASES_URL` remplace l'adresse de l'API). Quitter d'abord Murmure : une
seule instance tourne à la fois.

```bash
mkdir -p /tmp/rel && echo '{"tag_name":"v9.9.9","html_url":"https://github.com/croustibat/murmure/releases"}' > /tmp/rel/latest
(cd /tmp/rel && python3 -m http.server 8765) &
rm -f ~/.local/share/murmure/.mises-a-jour   # oublie la vérification du jour
MURMURE_RELEASES_URL=http://127.0.0.1:8765/latest ~/Applications/Murmure.app/Contents/MacOS/Murmure
```

`$MURMURE_HOME/.mises-a-jour` garde la date de la dernière requête et la version
trouvée ; le supprimer autorise une nouvelle vérification immédiate.
