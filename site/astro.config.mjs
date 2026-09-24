// @ts-check
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';
import tailwindcss from '@tailwindcss/vite';

// Adresse publique du site, pour les URL absolues (canonical, hreflang,
// Open Graph, sitemap). Sur Vercel, le domaine de production est fourni au
// build ; SITE_URL permet de l'imposer (domaine personnalisé).
const site =
  process.env.SITE_URL ??
  (process.env.VERCEL_PROJECT_PRODUCTION_URL
    ? `https://${process.env.VERCEL_PROJECT_PRODUCTION_URL}`
    : 'http://localhost:4321');

export default defineConfig({
  site,
  trailingSlash: 'ignore',
  i18n: {
    defaultLocale: 'fr',
    locales: ['fr', 'en'],
    routing: { prefixDefaultLocale: false },
  },
  integrations: [
    sitemap({
      i18n: { defaultLocale: 'fr', locales: { fr: 'fr-FR', en: 'en-US' } },
    }),
  ],
  vite: {
    plugins: [tailwindcss()],
    // Les captures sont prises dans docs/, à la racine du dépôt.
    server: { fs: { allow: ['..'] } },
  },
});
