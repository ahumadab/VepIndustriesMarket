// npm run deploy  : tests -> dist/VepIndustriesMarket and dist/VepIndustriesMarket_Data (version "x.y.z-dev+sha") ->
//                   copied into the game AddOns folder
// npm run release : same, with version "x.y.z", plus dist/VepIndustriesMarket-x.y.z.zip and git tag vx.y.z
// Game folder: env WOW_ADDONS, default C:/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns
import { execSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ADDON = 'VepIndustriesMarket';
const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const mode = process.argv[2];
const addons = process.env.WOW_ADDONS || 'C:/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns';
const sh = (cmd) => execSync(cmd, { cwd: root, stdio: 'pipe' }).toString().trim();
const fail = (msg) => { console.error(`✗ ${msg}`); process.exit(1); };

if (!['deploy', 'release'].includes(mode)) fail('usage: build.mjs deploy|release');

// 1. tests gate everything
try { execSync('npm test', { cwd: root, stdio: 'inherit' }); } catch { fail('tests en échec, rien n\'est déployé'); }

// 2. version
const pkg = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'));
let version = pkg.version;
if (mode === 'release') {
  const branch = sh('git rev-parse --abbrev-ref HEAD');
  if (branch !== 'main') fail(`release : uniquement sur main (gitflow), branche actuelle ${branch}`);
  if (sh('git status --porcelain')) fail('release : commit tes changements d\'abord');
  if (sh(`git tag -l v${version}`)) fail(`release : le tag v${version} existe déjà, monte la version dans package.json`);
} else {
  let sha = 'nogit';
  try { sha = sh('git rev-parse --short HEAD') + (sh('git status --porcelain') ? '.dirty' : ''); } catch {}
  version = `${version}-dev+${sha}`;
}

// 3. build dist/<ADDON>, and dist/<ADDON>_Data from src/<ADDON>_Data: the addon loaded on demand that holds the Sync
// script's data file (its Data.lua, written by the script only)
const DATA = `${ADDON}_Data`;
const build = (from, name) => {
  const out = join(root, 'dist', name);
  rmSync(out, { recursive: true, force: true });
  mkdirSync(out, { recursive: true });
  for (const f of readdirSync(from).filter((f) => f !== DATA)) {
    const src = join(from, f);
    if (f.endsWith('.toc')) writeFileSync(join(out, f), readFileSync(src, 'utf8').replace('@version@', version));
    else cpSync(src, join(out, f), { recursive: true });
  }
};
build(join(root, 'src'), ADDON);
build(join(root, 'src', DATA), DATA);

// 4. copy into the game, keeping the data file the Sync script wrote; a new addon folder shows in the game only after
// a restart, not on /reload
if (!existsSync(addons)) fail(`dossier AddOns introuvable : ${addons} (variable WOW_ADDONS)`);
const added = [ADDON, DATA].filter((name) => !existsSync(join(addons, name)));
rmSync(join(addons, ADDON), { recursive: true, force: true });
for (const name of [ADDON, DATA]) cpSync(join(root, 'dist', name), join(addons, name), { recursive: true });
console.log(`✓ ${ADDON} ${version} -> ${addons}  `
  + (added.length ? `(nouveau dossier ${added.join(', ')} : relance le jeu, /reload ne suffit pas)` : '(/reload en jeu)'));

// 5. release artefacts
if (mode === 'release') {
  const zip = join(root, 'dist', `${ADDON}-${version}.zip`);
  rmSync(zip, { force: true });
  execSync(`tar -a -c -f "${zip}" ${ADDON} ${DATA}`, { cwd: join(root, 'dist'), stdio: 'inherit' });
  sh(`git tag -a v${version} -m "${ADDON} ${version}"`);
  console.log(`✓ ${zip}\n✓ tag v${version} (git push --tags pour publier)`);
}
