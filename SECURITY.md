# Security Policy

## Supported versions

Only the latest release of Murmure receives security fixes. Murmure updates itself
(Sparkle), so the fix reaches users through the normal update channel.

| Version | Supported |
|---------|-----------|
| 1.2.x   | Yes       |
| < 1.2   | No (update to the latest DMG) |

## Reporting a vulnerability

Please **do not open a public issue** for a security problem.

Report it privately through GitHub:
**[Report a vulnerability](https://github.com/croustibat/murmure/security/advisories/new)**
(Security tab > Report a vulnerability).

Please include the Murmure version, your macOS version, and steps to reproduce.
I'll acknowledge the report within a few days, keep you informed, and credit you in
the release notes if you wish.

## Scope

Murmure transcribes audio locally and only makes two kinds of network requests
(see the README, "Réseau" / "Network"). Things especially worth reporting:

- the update channel: `appcast.xml` and the DMG downloaded from GitHub Releases,
  and their signature checks (Sparkle EdDSA, Apple Developer ID and notarization);
- the one-time model download and its SHA-256 verification;
- anything that would send audio, text or identifiers off the Mac;
- the use of the Microphone and Accessibility permissions, and the paste into the
  active app;
- `install.sh` / `uninstall.sh` when building from source.

---

**En français** : pour signaler une faille, merci de ne pas ouvrir d'issue publique
mais d'utiliser [le signalement privé de GitHub](https://github.com/croustibat/murmure/security/advisories/new).
Seule la dernière version est corrigée.
