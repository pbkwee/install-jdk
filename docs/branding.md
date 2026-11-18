# install-jdk branding

Use **install-jdk** in lowercase with a hyphen. The logo shows a green
download arrow inside a terminal window. The banner pairs it with CartoGothic
Std lettering and the RimuHosting lockup used by DistroRejuve and S2I.

| Asset | Use |
| --- | --- |
| Light-surface logo ([SVG](../assets/branding/logo.svg) · [PNG](../assets/branding/logo.png)) | Transparent mark for light backgrounds. |
| Dark-surface logo ([SVG](../assets/branding/logo-dark.svg) · [PNG](../assets/branding/logo-dark.png)) | Transparent mark with lighter Clay and Leaf tones for dark backgrounds. |
| README banner ([SVG](../assets/branding/readme-banner.svg) · [PNG](../assets/branding/readme-banner.png)) | 2172 × 724 masthead with an opaque Warm Surface background for either GitHub theme. |
| Social preview ([SVG](../assets/branding/social-preview.svg) · [PNG](../assets/branding/social-preview.png)) | 1280 × 640 PNG for the repository's Social preview setting. [GitHub upload instructions](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/customizing-your-repositorys-social-media-preview) |

The masthead uses Warm Surface `#F4EEDB`, Warm Ink `#251D18`, and Bark
`#452008`. Use Clay `#996444` for the terminal, Green Text `#587200` for
the arrow, and Leaf `#88AA00` for decorative indicators. Use at least 48 px
for the standalone logo and preserve the clear space.

The SVG files are the editable sources. Lettering is outlined so the artwork
renders without font files. After editing an SVG, regenerate its PNG with
CairoSVG from the repository root.

```bash
cairosvg assets/branding/logo.svg -s 2 -o assets/branding/logo.png
cairosvg assets/branding/logo-dark.svg -s 2 -o assets/branding/logo-dark.png
cairosvg assets/branding/readme-banner.svg -o assets/branding/readme-banner.png
cairosvg assets/branding/social-preview.svg -W 1280 -H 640 -o assets/branding/social-preview.png
```

Keep the RimuHosting lockup in its original colours and proportions. The
project mark and company lockup identify the installer and its maintainer.
