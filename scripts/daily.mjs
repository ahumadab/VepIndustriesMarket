// The daily summary per day, for npm run report (scripts/saved.mjs): the basis of the verdict thresholds (#7).
// Day values as src/Market.lua writes them: "price stock scans[ estimatedSales seconds]", price "-" when sold out.
// The save lays out one item per block ([id] = {, then one [day] = "..." per line); the data file of vepindustries-api,
// one item per line ([id] = { [day] = "...", ... }).
const DAY0 = new Date(2020, 0, 1); // Auctionator's day 0, local midnight

const value = (v) => {
  const [price, stock, scans, sold, seconds] = v.split(' ');
  return { price: price === '-' ? null : Number(price), stock: Number(stock), scans: Number(scans),
    sold: Number(sold || 0), seconds: Number(seconds || 0) };
};
const days = (text) => Object.fromEntries([...text.matchAll(/\[(\d+)\] = "([^"]*)"/g)].map(([, d, v]) => [d, value(v)]));

// -> { [itemID]: { [day]: { price, stock, scans, sold, seconds } } }
export function readSaveDaily(text) {
  const sv = text.replace(/\r\n/g, '\n');
  const at = sv.indexOf('["daily"] = {\n');
  if (at < 0) return {};
  const daily = {};
  // its items' blocks follow each other, up to the line closing it
  const item = /\[(\d+)\] = \{\n((?:\[\d+\] = "[^"]*",?[^\n]*\n)*)\},?[^\n]*\n/y;
  item.lastIndex = at + 14;
  for (let m; (m = item.exec(sv));) daily[m[1]] = days(m[2]);
  return daily;
}

export function readDataDaily(text) {
  const daily = {};
  for (const [, id, line] of text.matchAll(/^\[(\d+)\] = \{ (.*) \},?\r?$/gm)) daily[id] = days(line);
  return daily;
}

// -> [{ day, compared (items with compared time), seconds (the longest compared time of an item), soldOut (compared,
// stock 0), noSale (compared, in stock, none sold), ratios (ascending: estimated sales per day / stock, items in
// stock) }], by day
export function dailyReport(daily) {
  const byDay = {};
  for (const item of Object.values(daily)) {
    for (const [day, d] of Object.entries(item)) {
      const row = byDay[day] ??= { day: Number(day), compared: 0, seconds: 0, soldOut: 0, noSale: 0, ratios: [] };
      if (!(d.seconds > 0)) continue;
      row.compared++;
      row.seconds = Math.max(row.seconds, d.seconds);
      if (!(d.stock > 0)) { row.soldOut++; continue; }
      if (d.sold === 0) row.noSale++;
      row.ratios.push(d.sold * 86400 / d.seconds / d.stock);
    }
  }
  return Object.values(byDay).sort((a, b) => a.day - b.day)
    .map((r) => ({ ...r, ratios: r.ratios.sort((a, b) => a - b) }));
}

// days of stock left at the pace of the estimated sales: stock / sales per day = 1 / ratio
export const BANDS = [
  ['< 1 j', (r) => r >= 1], ['1-2 j', (r) => r >= 1 / 2], ['2-4 j', (r) => r >= 1 / 4], ['4-7 j', (r) => r >= 1 / 7],
  ['7-14 j', (r) => r >= 1 / 14], ['> 14 j', (r) => r > 0], ['aucune vente', () => true],
];

const pad = (n) => String(n).padStart(2, '0');
const date = (day) => {
  const d = new Date(DAY0);
  d.setDate(d.getDate() + day);
  return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()}`;
};
const duration = (s) => { const m = Math.round(s / 60); return `${Math.floor(m / 60)} h ${pad(m % 60)}`; };
const num = (x) => String(Math.round(x * 100) / 100);
const quantile = (sorted, p) => sorted[Math.min(sorted.length - 1, Math.floor(p * sorted.length))];

export function formatDailyReport(rows, source = 'de la sauvegarde') {
  const lines = [`Résumé journalier ${source} : ventes estimées par jour / stock du jour, `
    + 'réparties en jours de stock (stock / ventes par jour)'];
  for (const r of rows) {
    if (!r.compared) { lines.push(`${date(r.day)} : aucun objet comparé`); continue; }
    lines.push(`${date(r.day)} : ${r.compared} objets comparés sur ${duration(r.seconds)}`
      + ` (${r.soldOut} épuisés, ${r.ratios.length} en stock)`);
    if (!r.ratios.length) continue;
    const q = [['p10', 0.1], ['p25', 0.25], ['médiane', 0.5], ['p75', 0.75], ['p90', 0.9]];
    lines.push(`  rapport ventes/stock : ${q.map(([k, p]) => `${k} ${num(quantile(r.ratios, p))}`).join(', ')}`);
    const counts = BANDS.map(() => 0);
    for (const x of r.ratios) counts[BANDS.findIndex(([, inBand]) => inBand(x))]++;
    BANDS.forEach(([label], i) => {
      lines.push(`  ${label.padEnd(13)} ${counts[i]} (${Math.round(counts[i] * 100 / r.ratios.length)} %)`);
    });
  }
  return lines;
}
