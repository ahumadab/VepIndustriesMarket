// One-off in-game probe of ticket #19 (tools/probe). Game folder: env WOW_ADDONS, as for deploy.
// npm run probe install : copies VimProbe and VimProbeLod (LoadOnDemand) into the game, Data.lua stamped now
// npm run probe stamp   : rewrites VimProbeLod/Data.lua with a new stamp; run it game open, before /vimprobe lod
// npm run probe results : the probe's log from its SavedVariables (written on /reload or logout)
// npm run probe remove  : deletes both addons from the game folder
import { cpSync, existsSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const addons = process.env.WOW_ADDONS || 'C:/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns';
const ADDONS = ['VimProbe', 'VimProbeLod'];
const mode = process.argv[2];
const fail = (msg) => { console.error(`✗ ${msg}`); process.exit(1); };
if (!existsSync(addons)) fail(`dossier AddOns introuvable : ${addons} (variable WOW_ADDONS)`);

function stamp() {
  const now = new Date().toLocaleTimeString('fr-FR');
  writeFileSync(join(addons, 'VimProbeLod', 'Data.lua'), `VimProbeLodStamp = "${now}"\n`);
  console.log(`✓ Data.lua horodaté ${now}`);
}

if (mode === 'install') {
  for (const a of ADDONS) cpSync(join(root, 'tools', 'probe', a), join(addons, a), { recursive: true });
  stamp();
  console.log('✓ VimProbe et VimProbeLod installés : relancer le jeu (nouveaux addons), puis /vimprobe');
} else if (mode === 'stamp') {
  stamp();
} else if (mode === 'results') {
  const accounts = join(addons, '..', '..', 'WTF', 'Account');
  const saved = readdirSync(accounts).map((a) => join(accounts, a, 'SavedVariables', 'VimProbe.lua')).find(existsSync);
  if (!saved) fail(`aucun VimProbe.lua sous ${accounts} : /reload ou déconnexion d'abord`);
  for (const [, line] of readFileSync(saved, 'utf8').matchAll(/^\s*"(.*)",(?: -- \[\d+\])?\r?$/gm)) console.log(line);
} else if (mode === 'remove') {
  for (const a of ADDONS) rmSync(join(addons, a), { recursive: true, force: true });
  console.log('✓ VimProbe et VimProbeLod retirés');
} else {
  fail('usage : npm run probe install|stamp|results|remove');
}
