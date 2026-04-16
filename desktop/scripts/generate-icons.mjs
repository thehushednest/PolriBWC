import fs from 'node:fs/promises';
import path from 'node:path';
import sharp from 'sharp';
import pngToIco from 'png-to-ico';

const rootDir = path.resolve(process.cwd());
const assetsDir = path.join(rootDir, 'assets');
const buildDir = path.join(rootDir, 'build');
const svgPath = path.join(assetsDir, 'icon.svg');
const pngPath = path.join(buildDir, 'icon.png');
const icoPath = path.join(buildDir, 'icon.ico');

await fs.mkdir(buildDir, { recursive: true });

const svgBuffer = await fs.readFile(svgPath);
await sharp(svgBuffer).resize(512, 512).png().toFile(pngPath);
const icoBuffer = await pngToIco([pngPath]);
await fs.writeFile(icoPath, icoBuffer);

console.log(`Generated ${path.relative(rootDir, pngPath)} and ${path.relative(rootDir, icoPath)}`);
