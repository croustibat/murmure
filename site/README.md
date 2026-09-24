# Site de Murmure

Page de présentation de Murmure, en français (`/`) et en anglais (`/en/`).
Site statique : [Astro](https://astro.build) et Tailwind CSS v4, sans JavaScript
côté navigateur, sans police distante ni mesure d'audience.

```bash
cd site
npm install
npm run dev       # http://localhost:4321
npm run build     # site statique dans dist/
npm run preview   # sert dist/
```

Node 22.12 ou plus.

## Organisation

| Chemin | Rôle |
|---|---|
| `src/i18n/fr.ts`, `en.ts` | tous les textes ; `fr.ts` fait référence, `en.ts` en suit la structure (vérifié au typage) |
| `src/components/Accueil.astro` | la page, commune aux deux langues |
| `src/components/Pastille.astro` | la pastille animée, en CSS seul, calquée sur `src/overlay.swift` |
| `src/layouts/Base.astro` | `<head>` : titre, description, `hreflang`, Open Graph, Twitter |
| `src/pages/robots.txt.ts` | `robots.txt`, avec l'adresse du sitemap |
| `public/og.png`, `og-en.png` | images de partage 1200×630, régénérées par `npm run og` |
| `public/icone-512.png`, `favicon.png` | icône (provisoire en attendant l'icône définitive, #27) |

Les captures viennent de `docs/` à la racine du dépôt et sont converties en AVIF
et WebP au build (`astro:assets`) : il suffit de mettre à jour `docs/*.png`.

Tout ce que dit la page doit venir du README ou du code de Murmure. Un texte
modifié se change dans les deux fichiers de traduction.

`npm run og` redessine les images de partage (à relancer si l'accroche change)
et crée une icône provisoire seulement si `icone-512.png` ou `favicon.png`
manque : une icône existante n'est jamais écrasée.

## Déploiement sur Vercel

Rien n'est déployé automatiquement tant que le projet n'est pas créé.

1. Sur vercel.com, **Add New… › Project**, importer le dépôt `croustibat/murmure`.
2. **Root Directory** : `site`. Le framework **Astro** est détecté ; commande de
   build (`npm run build`) et dossier de sortie (`dist`) par défaut.
3. Laisser coché **Include files outside the Root Directory in the Build Step**
   (réglage par défaut) : le build lit les captures dans `docs/`.
4. Déployer. Aucun `vercel.json` n'est nécessaire.

Les URL absolues (canonical, `hreflang`, Open Graph, sitemap) utilisent le domaine
de production que Vercel fournit au build (`VERCEL_PROJECT_PRODUCTION_URL`). Avec
un domaine personnalisé, définir la variable d'environnement
`SITE_URL=https://exemple.fr` dans le projet Vercel, puis redéployer.

Pour ne déployer que lorsque le site change, **Settings › Git › Ignored Build
Step** accepte par exemple : `git diff --quiet HEAD^ HEAD -- . ../docs`.
