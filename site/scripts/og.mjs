// Génère les images de partage (1200×630) dans public/, une par langue :
//   npm run og
// Les PNG produits sont versionnés : le build n'en dépend pas et ne rend
// aucun texte (les polices de la machine de build importent peu).
// Crée aussi une icône provisoire (icone-512.png, favicon.png) si elle manque ;
// une icône existante n'est jamais remplacée.
import { existsSync } from 'node:fs';
import sharp from 'sharp';

const pub = new URL('../public/', import.meta.url);
const police = "'Avenir Next', -apple-system, 'SF Pro Display', 'Helvetica Neue', Helvetica, Arial, sans-serif";

// Pastille de l'app (src/overlay.swift) à l'échelle k, coin haut-gauche en x, y.
function pastille(x, y, k, libelle, largeurLibelle) {
  const h = 44 * k;
  const bombes = [0.64, 0.8, 0.92, 0.99, 0.99, 0.92, 0.8, 0.64];
  const niveaux = [0.5, 0.85, 0.6, 1, 0.75, 0.95, 0.55, 0.4];
  const barres = bombes
    .map((b, i) => {
      const bh = (3 + 13 * b * niveaux[i]) * k;
      return `<rect x="${x + (18 + i * 6.5) * k}" y="${y + h / 2 - bh / 2}" width="${3 * k}" height="${bh}" rx="${1.5 * k}" fill="#fff" fill-opacity="0.92"/>`;
    })
    .join('');
  const tx = x + (18 + 8 * 6.5 + 10) * k;
  const sep = tx + largeurLibelle + 14 * k;
  const stop = sep + 14 * k;
  const croix = stop + 11 * k + 14 * k;
  const w = croix + 9 * k + 16 * k - x;
  const c = 9 * k;
  const cy = y + h / 2;
  return {
    largeur: w,
    svg: `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${h / 2}" fill="#1c1c1c"/>
      <rect x="${x + 0.5}" y="${y + 0.5}" width="${w - 1}" height="${h - 1}" rx="${h / 2}" fill="none" stroke="#fff" stroke-opacity="0.1"/>
      ${barres}
      <text x="${tx}" y="${cy}" dominant-baseline="central" font-family="${police}" font-weight="500" font-size="${13 * k}" fill="#fff" fill-opacity="0.95">${libelle}</text>
      <rect x="${sep}" y="${cy - 9 * k}" width="${k}" height="${18 * k}" fill="#fff" fill-opacity="0.18"/>
      <rect x="${stop}" y="${cy - 5.5 * k}" width="${11 * k}" height="${11 * k}" rx="${2.5 * k}" fill="#fff" fill-opacity="0.92"/>
      <path d="M${croix} ${cy - c / 2}l${c} ${c}M${croix} ${cy + c / 2}l${c} ${-c}" stroke="#fff" stroke-opacity="0.6" stroke-width="${1.8 * k}" stroke-linecap="round"/>`,
  };
}

const langues = [
  {
    fichier: 'og.png',
    accroche: 'Dictée vocale pour macOS, 100 % locale.',
    detail: 'Rien ne quitte votre Mac.',
    libelle: 'Vous parlez',
    largeurLibelle: 76,
  },
  {
    fichier: 'og-en.png',
    accroche: 'Fully local voice dictation for macOS.',
    detail: 'Nothing leaves your Mac.',
    libelle: 'Listening',
    largeurLibelle: 60,
  },
];

for (const l of langues) {
  const k = 2.6;
  const p = pastille(0, 0, k, l.libelle, l.largeurLibelle * k);
  const px = (1200 - p.largeur) / 2;
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630">
    <defs>
      <radialGradient id="halo" cx="50%" cy="100%" r="75%">
        <stop offset="0" stop-color="#6d28d9" stop-opacity="0.45"/>
        <stop offset="1" stop-color="#6d28d9" stop-opacity="0"/>
      </radialGradient>
    </defs>
    <rect width="1200" height="630" fill="#110b22"/>
    <rect width="1200" height="630" fill="url(#halo)"/>
    <text x="600" y="190" text-anchor="middle" font-family="${police}" font-weight="700" font-size="96" fill="#f3f0fb">Murmure</text>
    <text x="600" y="268" text-anchor="middle" font-family="${police}" font-weight="500" font-size="40" fill="#f3f0fb">${l.accroche}</text>
    <text x="600" y="322" text-anchor="middle" font-family="${police}" font-size="32" fill="#b8afd4">${l.detail}</text>
    <g transform="translate(${px} 400)">${p.svg}</g>
  </svg>`;
  await sharp(Buffer.from(svg)).png().toFile(new URL(l.fichier, pub).pathname);
  console.log(`public/${l.fichier}`);
}

// Icône provisoire, en attendant l'icône définitive (#27).
const icone = `<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512">
  <rect width="512" height="512" rx="112" fill="#1c1c1c"/>
  ${[0.45, 0.75, 1, 0.75, 0.45]
    .map((f, i) => {
      const h = 60 + 220 * f;
      return `<rect x="${136 + i * 52}" y="${256 - h / 2}" width="32" height="${h}" rx="16" fill="#fff"/>`;
    })
    .join('')}
</svg>`;
for (const [fichier, taille] of [
  ['icone-512.png', 512],
  ['favicon.png', 64],
]) {
  const cible = new URL(fichier, pub).pathname;
  if (existsSync(cible)) continue;
  await sharp(Buffer.from(icone)).resize(taille, taille).png().toFile(cible);
  console.log(`public/${fichier} (provisoire)`);
}
