# Wisp — the aether.ai mascot

Wisp is the official mascot. The product name and wordmark remain **aether.ai**.

<img src="assets/branding/wisp-light.svg" width="100" alt="White Wisp"><img src="assets/branding/wisp-dark.svg" width="100" alt="Charcoal Wisp">

## Assets

- `assets/logo.svg` and `assets/logo.png`: static white icon, transparent background, compatible with existing packaging.
- `assets/branding/wisp-light.svg` and `wisp-dark.svg`: white for dark surfaces and charcoal for light surfaces.
- `assets/branding/wisp-lockup-light.svg` and `wisp-lockup-dark.svg`: mascot + original product wordmark.
- `assets/branding/wisp-animated-light.svg` and `wisp-animated-dark.svg`: self-contained CSS-animated SVG, no JavaScript. Download and open in a browser; GitHub may not play SVG animation.
- `assets/branding/wisp-body.png`: native renderer input, not a public standalone logo.
- `assets/branding/preview.html`: local browser demo of both themes; open from a checkout.
- `assets/branding/motion.json`: original normalized 18-second keyframe tracks.

## Motion

Wisp rests between natural blinks. Gentle floating and squash/stretch, curious eyes, happy eyes, and a halo take turns. The animated SVG respects prefers-reduced-motion. Native implementations use the same timing and silhouette, with smooth interpolation and a lightweight layered halo rather than SVG blur. The Linux QML component is embedded in shell.qml to keep existing installations and automatic updates compatible. Windows/macOS use native egui textures and drawing. Native eye apertures use the opaque panel colour. Animations are visual only and do not trigger quota refreshes. Appearance → Animate Wisp disables mascot motion; Linux Reduced motion overrides it. Compact OS icons remain static. Tray/menu-bar integration and GitHub social preview settings are not part of the current app.

Keep the proportions and transparent negative space. Avoid altering Wisp into a lettermark, using the retired spiral, or recolouring provider logos. The mascot assets are original project artwork, included under the repository MIT license.
