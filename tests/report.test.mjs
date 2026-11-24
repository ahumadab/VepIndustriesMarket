// npm run report, per day of the daily summary (scripts/daily.mjs): items compared, time covered, and the spread of
// the estimated sales per day over the stock, the basis of the verdict thresholds (#7). Plain Node, no game files.
import assert from 'node:assert/strict';
import { dailyReport, formatDailyReport, readDataDaily, readSaveDaily } from '../scripts/daily.mjs';

const failures = [];
const test = (name, fn) => {
  try {
    fn();
    console.log(`ok   ${name}`);
  } catch (e) {
    failures.push(`${name} : ${e.message}`);
    console.log(`FAIL ${name}`);
  }
};

// The save's daily summary, as the game writes it (Market.lua: "price stock scans[ estimatedSales seconds]")
const SAVE = [
  'VepIndustriesMarketDB = {', '["daily"] = {',
  '[14047] = {', '[2518] = "1190 1000 5 500 7200",', '[2519] = "1100 900 2",', '},',
  '[2589] = {', '[2518] = "50 100 5 0 7200",', '},',
  '[2592] = {', '[2518] = "80 10 5 30 3600",', '},',
  '[4306] = {', '[2518] = "- 0 5 6 7200",', '},',
  '},', '["fullScan"] = {', '["items"] = {', '[15347] = "2uk 3*5 4*2",', '},', '["time"] = 1795347859,', '},', '}', '',
].join('\r\n');

// The data file (vepindustries-api): one line per item, the same day values
const DATA = [
  'VepIndustriesMarketData = {', 'generated = 1795544383,', 'daily = {',
  '[14047] = { [2518] = "1190 1000 5 200 8920.5", [2519] = "1100 900 1 1.5 900" },',
  '[2589] = { [2519] = "50 100 1" },', '},', 'counted = {', '},', '}', '',
].join('\n');

test('resume journalier de la sauvegarde lu', () => {
  const daily = readSaveDaily(SAVE);
  assert.deepEqual(daily['14047']['2518'], { price: 1190, stock: 1000, scans: 5, sold: 500, seconds: 7200 });
  assert.deepEqual(daily['14047']['2519'], { price: 1100, stock: 900, scans: 2, sold: 0, seconds: 0 });
  assert.equal(daily['4306']['2518'].price, null);
});

test('resume journalier du fichier de donnees lu', () => {
  const daily = readDataDaily(DATA);
  assert.deepEqual(daily['14047']['2518'], { price: 1190, stock: 1000, scans: 5, sold: 200, seconds: 8920.5 });
  assert.equal(daily['14047']['2519'].sold, 1.5);
  assert.equal(daily['2589']['2519'].seconds, 0);
});

test('par jour : objets compares, duree couverte, ventes par jour rapportees au stock', () => {
  const rows = dailyReport(readSaveDaily(SAVE));
  assert.deepEqual(rows.map((r) => r.day), [2518, 2519]);
  const [d] = rows;
  assert.equal(d.compared, 4);
  assert.equal(d.seconds, 7200);
  // 14047: 500 in 2 h = 6000/day for 1000 in stock -> 6; 2592: 30 in 1 h = 720/day for 10 -> 72; 2589: 0;
  // 4306 sold out (stock 0): no ratio
  assert.equal(d.soldOut, 1);
  assert.equal(d.noSale, 1);
  assert.deepEqual(d.ratios, [0, 6, 72]);
  assert.deepEqual(rows[1], { day: 2519, compared: 0, seconds: 0, soldOut: 0, noSale: 0, ratios: [] });
});

test('repartition par tranche de jours de stock, et quantiles', () => {
  const daily = { 1: {}, 2: {}, 3: {}, 4: {}, 5: {} };
  // ratios 2, 0.6, 0.3, 0.1, 0 (sales per day / stock): < 1 day, 1-2 days, 2-4 days, 7-14 days, no sale
  [[2, 100], [0.6, 100], [0.3, 100], [0.1, 100], [0, 100]].forEach(([r, stock], i) => {
    daily[i + 1][2518] = { price: 1, stock, scans: 2, sold: r * stock, seconds: 86400 };
  });
  const text = formatDailyReport(dailyReport(daily)).join('\n');
  assert.match(text, /^Résumé journalier/m);
  assert.match(text, /23\/11\/2026 : 5 objets comparés sur 24 h 00/);
  assert.match(text, /< 1 j\s+1 \(20 %\)/);
  assert.match(text, /1-2 j\s+1 \(20 %\)/);
  assert.match(text, /2-4 j\s+1 \(20 %\)/);
  assert.match(text, /4-7 j\s+0 \(0 %\)/);
  assert.match(text, /7-14 j\s+1 \(20 %\)/);
  assert.match(text, /aucune vente\s+1 \(20 %\)/);
  assert.match(text, /médiane 0\.3/);
});

if (failures.length) {
  console.error(`✗ ${failures.join('\n✗ ')}`);
  process.exit(1);
}
console.log('✓ rapport du résumé journalier');
