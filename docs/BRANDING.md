# Branding Guidelines

## Logo Assets
- Source vector: `assets/images/lavash_logo.svg`
- Recommended master PNG: 1024×1024 exported from SVG.
- Keep clear space equal to 1/6 of logo width around all sides.

## Colors
Primary palette taken from tile colors:
- Pink: `#FF6EC7`
- Yellow: `#FFD36E`
- Mint: `#72F1B8`
- Cyan: `#00E5FF`
- Purple: `#9B6BFF`

Neutral backgrounds: white (`#FFFFFF`) or near‑black (`#0E0F12`).

## Icon Generation
1. Export PNG: see README architecture section.
2. Ensure file at `assets/images/lavash_logo.png`.
3. Run:
   ```sh
   flutter pub get
   dart run flutter_launcher_icons
   ```
4. Verify web icons in `web/icons/` and mobile icons in platform folders.

## Usage Rules
- Do not alter proportions or shift internal letters beyond approved vertical adjustments.
- Avoid placing on strongly patterned backgrounds without a subtle blur or tint overlay.
- For dark mode, light or colored logo is acceptable; avoid pure black tile fills.

## Accessibility
- Minimum icon size: 48×48 logical px (mobile), 32×32 favicons.
- Maintain contrast ratio > 3:1 against backgrounds.

## Future Extensions
- Provide monochrome variant for embossed or watermark use.
- Provide outline version for very small sizes (<32px).
