#!/usr/bin/env node
// Rasterize the official SVGs without changing geometry or colors. Requires sharp.
const path = require('node:path');
const sharp = require('sharp');
const root = path.resolve(__dirname, '..');

(async () => {
  // Upstream light/dark names describe the glyph, not the UI background.
  for (const [theme, glyph] of [['light', 'dark'], ['dark', 'light']]) {
    await sharp(path.join(root, `Resources/IconSources/cmdsymbol-${glyph}.svg`))
      .resize(640, 640)
      .png()
      .toFile(path.join(root, `Resources/icons/${theme}/commandcode.png`));
  }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
