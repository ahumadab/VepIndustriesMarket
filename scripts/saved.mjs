// Reads the addon's SavedVariables: VepIndustriesMarket.lua and the game's previous save of it, .bak.
// npm run fixture : writes each of their full scans to tests/fixtures/fullscan-<MMDD>-<HHMM>.lua (local time of the
//                   scan), reduced to the items of fullscan.lua, so that tests compare consecutive real scans; and,
//                   once, the save's Comparisons to tests/fixtures/comparisons.lua, which tests/sync.cjs reads.
// npm run report  : what the addon recorded since the previous save: estimated sales, the items selling most with
//                   their stock and lowest price moves between the two saved scans, errors, the data file loaded,
//                   the Comparisons kept by author, and a reminder to capture the Comparisons fixture while the save holds Comparisons.
// Game folder: env WOW_ADDONS, as for deploy; the first account holding VepIndustriesMarket.lua is read.
import { existsSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const mode = process.argv[2];
const fail = (msg) => { console.error(`✗ ${msg}`); process.exit(1); };
if (!['fixture', 'report'].includes(mode)) fail('usage: saved.mjs fixture|report');

const addons = process.env.WOW_ADDONS || 'C:/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns';
const accounts = join(addons, '..', '..', 'WTF', 'Account');
const saved = readdirSync(accounts).map((a) => join(accounts, a, 'SavedVariables', 'VepIndustriesMarket.lua'))
  .find(existsSync);
if (!saved) fail(`aucun VepIndustriesMarket.lua sous ${accounts}`);

// tiers string (see src/Market.lua) -> [{ price, size, count, timeLeft }], by price
function decode(s) {
  let price = 0, lot = 1;
  return s.split(' ').map((tok) => {
    const [, tl, gap, size, count] = tok.match(/^(\d)(\w*)\.?(\w*)\*?(\w*)$/);
    if (gap !== '') { price += parseInt(gap, 36); lot = size ? parseInt(size, 36) : 1; }
    return { price, size: lot, count: count ? parseInt(count, 36) : 1, timeLeft: Number(tl) };
  });
}

// -> { time, items: { id: tiers }, daily: { id: { day: { sold, seconds } } }, errors: [] }, null without a full scan
function read(file) {
  if (!existsSync(file)) return null;
  const sv = readFileSync(file, 'utf8').replace(/\r\n/g, '\n'); // the game writes CRLF
  const at = sv.indexOf('["fullScan"] = {');
  if (at < 0) return null;
  const from = sv.indexOf('["items"] = {', at);
  const items = {};
  for (const [, id, s] of sv.slice(from, sv.indexOf('\n}', from)).matchAll(/\[(\d+)\] = "([^"]*)"/g)) items[id] = decode(s);
  const daily = {};
  for (const [, id, days] of sv.slice(sv.indexOf('["daily"] = {')).matchAll(/\[(\d+)\] = \{\n([^}]*)\}/g)) {
    daily[id] = {};
    for (const [, day, sold, seconds] of days.matchAll(/\[(\d+)\] = "\S+ \d+ \d+(?: ([\d.]+) ([\d.]+))?"/g)) {
      daily[id][day] = { sold: Number(sold || 0), seconds: Number(seconds || 0) };
    }
  }
  const errorsAt = sv.indexOf('["errors"] = {');
  const errors = errorsAt < 0 ? []
    : [...sv.slice(errorsAt, sv.indexOf('\n}', errorsAt)).matchAll(/^"(.*)",$/gm)].map((m) => m[1]);
  // the data file loaded this session (src/Capture.lua), and the Comparisons: only they hold a "start" key; their
  // authors, ours and those received in game (src/Exchange.lua)
  const loaded = sv.match(/\["dataFile"\] = \{\n([^}]*)\}/);
  const field = (k) => Number(loaded[1].match(new RegExp(`\\["${k}"\\] = (\\d+)`))?.[1]);
  const block = sv.match(/\["comparisons"\] = \{\n(?:\{\n(?:\["\w+"\] = [^\n]*\n)*\},?[^\n]*\n)*\}/);
  const authors = {};
  for (const [, a] of (block ? block[0] : '').matchAll(/\["author"\] = "([^"]*)"/g)) authors[a] = (authors[a] || 0) + 1;
  return { time: Number(sv.slice(at).match(/\["time"\] = (\d+)/)[1]), items, daily, errors,
    dataFile: loaded && { generated: field('generated'), items: field('items') },
    comparisons: (sv.match(/\["start"\] = /g) || []).length, authors };
}

const current = read(saved), previous = read(`${saved}.bak`);
if (!current) fail(`aucun Scan complet dans ${saved}`);
const pad = (n) => String(n).padStart(2, '0');
const local = (t) => { const d = new Date(t * 1000); return `${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}`; };

if (mode === 'fixture') {
  const wanted = new Set([...readFileSync(join(root, 'tests/fixtures/fullscan.lua'), 'utf8').matchAll(/^\{(\d+),/gm)]
    .map((m) => m[1]));
  for (const scan of [previous, current].filter(Boolean)) {
    const name = local(scan.time), file = `tests/fixtures/fullscan-${name}.lua`, v = `FULLSCAN_${name.replace('-', '_')}`;
    if (existsSync(join(root, file))) { console.log(`= ${file} existe déjà`); continue; }
    const rows = [];
    for (const [id, tiers] of Object.entries(scan.items)) {
      if (wanted.has(id)) for (const t of tiers) rows.push(`{${id},${t.size},${t.price * t.size},${t.timeLeft},${t.count}}`);
    }
    writeFileSync(join(root, file),
      `-- Real full scan stored at ${new Date(scan.time * 1000).toISOString()}, reduced to the items of fullscan.lua\n`
      + '-- (npm run fixture). Same rows: { itemID, count (lot size), buyout (whole lot, copper), timeLeft, auctions }\n'
      + `${v}_TIME = ${scan.time}\n${v} = {\n${rows.join(',\n')},\n}\n`);
    console.log(`✓ ${rows.length} paliers de ${new Set(rows.map((r) => r.split(',')[0])).size} objets -> ${file}`);
  }
  // The Comparisons block verbatim, as the game laid it out, reduced to the same items: tests/sync.cjs reads it.
  const file = 'tests/fixtures/comparisons.lua';
  const block = readFileSync(saved, 'utf8')
    .match(/\["comparisons"\] = \{\r?\n(?:\{\r?\n(?:\["\w+"\] = [^\r\n]*\r?\n)*\},?[^\r\n]*\r?\n)*\},?/);
  if (existsSync(join(root, file))) console.log(`= ${file} existe déjà`);
  else if (!block || !block[0].includes('["start"]')) console.log(`- aucune Comparaison dans ${saved}`);
  else {
    const reduced = block[0].replace(/\["items"\] = "([^"]*)"/g,
      (_, items) => `["items"] = "${items.split(',').filter((e) => wanted.has(e.split(' ')[0])).join(',')}"`);
    writeFileSync(join(root, file), reduced + '\n');
    console.log(`✓ ${reduced.split('["start"]').length - 1} Comparaisons -> ${file}`);
  }
} else {
  console.log(`Scan complet enregistré : ${new Date(current.time * 1000).toLocaleString('fr-FR')}`);
  for (const e of current.errors) console.log(`✗ erreur ${e}`);
  const df = current.dataFile;
  console.log(df ? `Fichier de données chargé : produit le ${new Date(df.generated * 1000).toLocaleString('fr-FR')}, `
    + `${df.items} objets` : 'Fichier de données : aucun chargé (hôtel des ventes pas ouvert, ou Data.lua absent)');
  const authors = Object.entries(current.authors).map(([a, n]) => `${a} ${n}`).join(', ');
  console.log(`Comparaisons gardées par auteur (les autres reçues en jeu) : ${authors || 'aucune'}`);
  if (current.comparisons && !existsSync(join(root, 'tests/fixtures/comparisons.lua'))) {
    console.log(`! ${current.comparisons} Comparaisons dans la sauvegarde, pas de tests/fixtures/comparisons.lua : `
      + 'npm run fixture maintenant (l\'addon les retire au bout de 24 h)');
  }
  if (!previous || previous.time === current.time) {
    console.log('Pas de nouveau Scan complet depuis la sauvegarde précédente (.bak) : rien à comparer.');
    process.exit(0);
  }
  const gap = current.time - previous.time;
  console.log(`Scan précédent sauvegardé : ${new Date(previous.time * 1000).toLocaleString('fr-FR')} (${gap} s avant)`);
  // sales recorded since the previous save (every day summed: a comparison can fall on a new day)
  const sum = (days = {}, f) => Object.values(days).reduce((a, d) => a + d[f], 0);
  const stock = (tiers = []) => tiers.reduce((a, t) => a + t.size * t.count, 0);
  const rows = [];
  let compared = 0;
  for (const [id, days] of Object.entries(current.daily)) {
    const sold = Math.round(sum(days, 'sold') - sum(previous.daily[id], 'sold'));
    const seconds = sum(days, 'seconds') - sum(previous.daily[id], 'seconds');
    if (seconds > 0) compared++;
    if (sold > 0) rows.push({ id, sold, perDay: Math.round(sold * 86400 / seconds), before: previous.items[id], after: current.items[id] });
  }
  rows.sort((a, b) => b.sold - a.sold);
  const median = rows.length ? rows[rows.length >> 1].sold : 0;
  console.log(`${compared} objets comparés, ${rows.length} avec des ventes, ${rows.reduce((a, r) => a + r.sold, 0)} unités`
    + ` (médiane ${median} par objet vendu)`);
  console.log('objet    vendues    /jour    stock avant -> après    prix min avant -> après');
  for (const r of rows.slice(0, 20)) {
    const low = (t) => (t && t[0] ? t[0].price : '-');
    console.log(`${r.id.padEnd(8)} ${String(r.sold).padStart(7)} ${String(r.perDay).padStart(8)}    `
      + `${String(stock(r.before)).padStart(7)} -> ${String(stock(r.after)).padEnd(7)}      ${low(r.before)} -> ${low(r.after)}`);
  }
}
