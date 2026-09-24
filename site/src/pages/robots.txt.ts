import type { APIRoute } from 'astro';

// Généré au build pour pointer vers le sitemap avec l'adresse du site.
export const GET: APIRoute = ({ site }) =>
  new Response(`User-agent: *\nAllow: /\n\nSitemap: ${new URL('sitemap-index.xml', site).href}\n`);
