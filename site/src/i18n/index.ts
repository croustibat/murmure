import fr from './fr';
import en from './en';

export const langues = { fr, en };
export type Langue = keyof typeof langues;
export type Textes = typeof fr;

// Balise lang et locale Open Graph de chaque langue.
export const codes: Record<Langue, { html: string; og: string }> = {
  fr: { html: 'fr', og: 'fr_FR' },
  en: { html: 'en', og: 'en_US' },
};

export const depot = 'https://github.com/croustibat/murmure';
