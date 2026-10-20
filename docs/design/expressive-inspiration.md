# Design research — from "correct M3" to Material 3 Expressive

Context: the first Material 3 pass was technically compliant but read as a plain
settings app ("太丑了"). This note records the references and the resulting
direction. Sources are external design references, used as inspiration only.

## References

| Source | What we took |
|---|---|
| [Start building with Material 3 Expressive — m3.material.io](https://m3.material.io/blog/building-with-m3-expressive) | Expressive color, 35-shape library + shape morph, emphasized typography, spring physics, hero moments. This is Google's own current visual language, so it stays "Google style". |
| [Get started — Material Design 3](https://m3.material.io/get-started) | Emphasized type styles (expanded scale, variable-font editorial moments), expanded shape library. |
| [Motion — Material Design 3](https://m3.material.io/styles/motion/overview/how-it-works) | Springs described by stiffness + damping; overshoot is allowed for expressive transitions, damped for utility ones. |
| [m3-expressive-design-skill (GitHub, abhixv)](https://skillsmp.com/zh/creators/abhixv/m3-expressive-design-skill) / [Flutter material-3-expressive-migration skill](https://chromium.googlesource.com/external/github.com/flutter/packages/+/df4d7129d95c646bd88bd0c9648366995b249656) | Checklist framing: color roles, motion springs, shape morph, emphasized type, adaptive layouts. |
| [verve-tokens](https://www.npmjs.com/package/verve-tokens) | Confirms the 35-shape expressive catalog (cookie, clover, burst, pill, heart) and shape-morph as a token-level concern. |
| [Finexia VPN UI kit — Dribbble](https://dribbble.com/shots/27377803-Finexia-UI-Kit-VPN-Mobile-App) | VPN convention: one-tap connect, big status, dark calm surfaces, simple navigation. |
| [VPN Mobile App UI — Dribbble](https://dribbble.com/shots/26960106-VPN-Mobile-App-UI-Design) | Dark gradients + vibrant security accents, real-time status, clear hierarchy, micro-interactions. |
| [VPN Mobile App secure & fast — Dribbble](https://dribbble.com/shots/26367679-VPN-Mobile-App-Secure-Fast-Connection) | Neon/green connected accent, traffic routing, stats dashboard, device management. |
| Google Photos / Weather / Phone (M3 Expressive rollout, 2025) | Hero-first screens, large friendly shapes, one dominant control, editorial type. |

## Direction: "Expressive instrument"

Keep: Material 3 semantic color roles, Google system fonts, Material Symbols,
one primary action per screen, accessibility (contrast, reduced motion, 48dp).

Change (the part that looked ugly):
1. **Hero instead of card stack.** Home is dominated by one large 32dp-radius
   gradient hero (aurora of primary → tertiary → success), with a connection orb,
   pulsing rings while connecting/connected, the latency as a display numeral,
   and the single connect action inside the hero.
2. **Bento stats.** Peers / routes / traffic become three tonal tiles
   (primaryContainer, tertiaryContainer, successContainer) instead of one gray row.
3. **Expressive color.** More of the palette participates: secondary/tertiary
   containers color-code information (traffic = tertiary, peers = primary,
   success = green), while surfaces stay calm.
4. **Expressive type.** System font at display sizes, bold + tight tracking for
   the hero number (45/52), title 22, labels 12; mono only for machine data.
5. **Expressive shape + motion.** Cards 24dp (hero 32), stadium buttons/chips,
   spring-overshoot curve for state changes, pulse/breathe loops that stop under
   reduce-motion. No hard shadows; ambient tonal layering.
6. **Chrome.** Taller expressive navigation bar (76dp) with a larger pill
   indicator, larger icons, comfortable touch padding.

Anti-patterns kept out: decorative gradients outside the hero, multiple primary
CTAs, neon glow everywhere, pure black, icon-only actions without labels.
