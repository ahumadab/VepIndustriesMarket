// npm run fixture : writes the full scan stored in the game's SavedVariables to tests/fixtures/fullscan-later.lua,
// reduced to the items of tests/fixtures/fullscan.lua, so that tests compare two real scans.
// Game folder: env WOW_ADDONS, as for deploy; the first account holding VepIndustriesMarket.lua is read.
import { existsSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const addons = process.env.WOW_ADDONS || 'C:/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns';
const accounts = join(addons, '..', '..', 'WTF', 'Account');
const saved = readdirSync(accounts).map((a) => join(accounts, a, 'SavedVariables', 'VepIndustriesMarket.lua'))
  .find(existsSync);
if (!saved) { console.error(`✗ aucun VepIndustriesMarket.lua sous ${accounts}`); process.exit(1); }

const sv = readFileSync(saved, 'utf8');
const scan = sv.slice(sv.indexOf('["fullScan"]'));
const time = Number(scan.match(/\["time"\] = (\d+)/)[1]);
const wanted = new Set([...readFileSync(join(root, 'tests/fixtures/fullscan.lua'), 'utf8').matchAll(/^\{(\d+),/gm)]
  .map((m) => m[1]));

// tiers string (see src/Market.lua) -> rows { itemID, lot size, buyout of the whole lot, timeLeft, auctions }
const rows = [];
for (const [, id, tiers] of scan.matchAll(/\[(\d+)\] = "([^"]*)"/g)) {
  if (!wanted.has(id)) continue;
  let price = 0, lot = 1;
  for (const tok of tiers.split(' ')) {
    const [, tl, gap, size, count] = tok.match(/^(\d)(\w*)\.?(\w*)\*?(\w*)$/);
    if (gap !== '') { price += parseInt(gap, 36); lot = size ? parseInt(size, 36) : 1; }
    rows.push(`{${id},${lot},${price * lot},${tl},${count ? parseInt(count, 36) : 1}}`);
  }
}
writeFileSync(join(root, 'tests/fixtures/fullscan-later.lua'),
  `-- Real full scan stored at ${new Date(time * 1000).toISOString()}, reduced to the items of fullscan.lua\n`
  + '-- (npm run fixture). Same rows: { itemID, count (lot size), buyout (whole lot, copper), timeLeft, auctions }\n'
  + `FULLSCAN_LATER_TIME = ${time}\nFULLSCAN_LATER = {\n${rows.join(',\n')},\n}\n`);
console.log(`✓ ${rows.length} paliers de ${new Set(rows.map((r) => r.split(',')[0])).size} objets -> tests/fixtures/fullscan-later.lua`);
