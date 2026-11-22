// Runs src/Sync.ps1 (the Sync script) with Windows PowerShell 5.1 against a fake server, in a fake game folder whose
// save holds the real Comparison of merge-cases.json, and against a real scheduled task (VepIndustriesMarketTest,
// removed at the end). Windows only: skipped elsewhere (CI runs on Linux).
const assert = require('node:assert/strict');
const { execFile } = require('node:child_process');
const { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, utimesSync, writeFileSync }
  = require('node:fs');
const { createServer } = require('node:http');
const { tmpdir } = require('node:os');
const { join } = require('node:path');

if (process.platform !== 'win32') {
  console.log('- Script de synchro : non testé hors de Windows');
  process.exit(0);
}

const TASK = 'VepIndustriesMarketTest';
const CODE = 'good-code';
const root = mkdtempSync(join(tmpdir(), 'vim-sync-'));
const addon = join(root, 'Interface', 'AddOns', 'VepIndustriesMarket');
const savedDir = join(root, 'WTF', 'Account', '123#1', 'SavedVariables');
const saved = join(savedDir, 'VepIndustriesMarket.lua');
const state = join(root, 'LocalAppData', 'VepIndustriesMarket');
const data = join(addon, 'Data.lua');
mkdirSync(addon, { recursive: true });
mkdirSync(savedDir, { recursive: true });
copyFileSync(join(__dirname, '..', 'src', 'Sync.ps1'), join(addon, 'Sync.ps1'));

// The save, laid out as the game writes it, with the real Comparison's items under several authors and starts.
const real = JSON.parse(readFileSync(join(__dirname, 'merge-cases.json'), 'utf8')).cases.at(-1).comparisons[0].items;
const comparison = (author, start) => ({ author, realm: '', faction: 'Horde', start, finish: start + 919, items: real });
const save = (comparisons, eol = '\n') => [
  '', 'VepIndustriesMarketDB = {', '["daily"] = {', '[15347] = {', '[2516] = "1100 22 10 0 7970",', '},', '},',
  '["author"] = "Vép",', '["comparisons"] = {',
  ...comparisons.flatMap((c) => ['{', `["start"] = ${c.start},`, `["faction"] = "${c.faction}",`,
    `["items"] = "${c.items}",`, `["realm"] = "${c.realm}",`, `["author"] = "${c.author}",`,
    `["finish"] = ${c.finish},`, '},']),
  '},', '["errors"] = {', '},', '["fullScan"] = {', '["items"] = {', '[15347] = "2uk 3*5 4*2",', '},',
  '["realm"] = "",', '["time"] = 1795347859,', '["faction"] = "Horde",', '},', '}', '',
].join(eol);
const T0 = 1795340000;
const first = [...Array(6)].map((_, i) => comparison('Vép', T0 + i * 1000)).concat(comparison('Ami', T0));
// Written a second after the data file at least, so that the script sees a newer save.
const writeSave = (comparisons, eol) => {
  writeFileSync(saved, save(comparisons, eol));
  const t = existsSync(data) ? statSync(data).mtimeMs / 1000 + 2 : Date.now() / 1000;
  utimesSync(saved, t, t);
};

// Fake server: Sync-Code checked, comparisons answered 204 (500 while failing), addon data answered with a Lua file.
const DATA = 'VepIndustriesMarketData = {\ngenerated = 1795350000,\ncounted = {\n["Vép"] = { [1795340000] = true },\n},\n}\n';
let requests = [], failing = false;
const server = createServer((req, res) => {
  const chunks = [];
  req.on('data', (c) => chunks.push(c));
  req.on('end', () => {
    const body = Buffer.concat(chunks).toString('utf8');
    requests.push({ method: req.method, url: req.url, code: req.headers['sync-code'], body: body && JSON.parse(body) });
    if (req.headers['sync-code'] !== CODE) res.writeHead(401).end();
    else if (req.method === 'POST' && req.url === '/v1/comparisons') res.writeHead(failing ? 500 : 204).end();
    else if (req.method === 'GET' && req.url.startsWith('/v1/addon-data?')) {
      res.writeHead(200, { 'content-type': 'text/plain' }).end(DATA);
    } else res.writeHead(404).end();
  });
});

const run = (file, args = []) => new Promise((resolve) => {
  execFile('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', file, ...args],
    { env: { ...process.env, LOCALAPPDATA: join(root, 'LocalAppData') } },
    (error, stdout, stderr) => resolve({ ok: !error, out: stdout + stderr }));
});
const sync = (args) => run(join(addon, 'Sync.ps1'), args);
const ps = (command) => new Promise((resolve) => {
  execFile('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', command], (e, out) => resolve(out.trim()));
});
const task = () => ps(`$t = Get-ScheduledTask -TaskName ${TASK} -ErrorAction SilentlyContinue; `
  + 'if ($t) { "$($t.Principal.LogonType) $($t.Principal.RunLevel)" }');
const posted = () => requests.filter((r) => r.method === 'POST').map((r) => r.body.comparisons);
const step = (name) => { console.log(`  ${name}`); requests = []; };

async function main() {
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const api = `http://127.0.0.1:${server.address().port}`;
  const install = (args = []) => sync(['-Install', '-Api', api, '-TaskName', TASK, ...args]);

  step('installation : code refusé, pas de tâche');
  assert.equal((await install(['-Code', 'bad-code'])).ok, false);
  assert.equal(await task(), '');

  step('installation sans droits d\'administrateur : tâche de la session, code chiffré');
  const installed = await install(['-Code', CODE]);
  assert.ok(installed.ok, installed.out);
  assert.equal(await task(), 'Interactive Limited');
  assert.ok(!readFileSync(join(state, 'config.json'), 'utf8').includes(CODE), 'code en clair');

  step('réinstallation : le code enregistré sert, rien n\'est demandé');
  const again = await install();
  assert.ok(again.ok, again.out);

  step('premier passage : Comparaisons envoyées par lots de 5, fichier de données écrit');
  writeSave(first);
  const firstRun = await sync();
  assert.ok(firstRun.ok, firstRun.out);
  const batches = posted();
  assert.deepEqual(batches.map((b) => b.length), [5, 2]);
  assert.deepEqual(batches.flat(), first);
  assert.ok(requests.every((r) => r.code === CODE));
  const dayZero = new Date(2020, 0, 1).getTime() / 1000;
  assert.deepEqual(requests.filter((r) => r.method === 'GET').map((r) => r.url),
    [`/v1/addon-data?realm=&faction=Horde&dayZero=${dayZero}`]);
  assert.equal(readFileSync(data, 'utf8'), DATA);

  step('sauvegarde inchangée : rien envoyé');
  assert.ok((await sync()).ok);
  assert.deepEqual(requests, []);

  step('envoi idempotent : seule la nouvelle Comparaison part, réessayée après un échec du serveur');
  const added = comparison('Vép', T0 + 6000);
  writeSave([...first, added], '\r\n');
  const before = statSync(data).mtimeMs;
  failing = true;
  assert.equal((await sync()).ok, false);
  assert.equal(statSync(data).mtimeMs, before, 'fichier de données réécrit malgré l\'échec');
  assert.match(readFileSync(join(state, 'sync.log'), 'utf8'), /500/);
  failing = false;
  requests = [];
  assert.ok((await sync()).ok);
  assert.deepEqual(posted(), [[added]]);
  assert.ok(statSync(data).mtimeMs > before);

  step('30 jours sans nouvelle sauvegarde : tâche retirée');
  const old = Date.now() / 1000 - 31 * 86400;
  writeSave(first);
  for (const f of [saved, join(state, 'config.json')]) utimesSync(f, old, old);
  assert.ok((await sync()).ok);
  assert.equal(await task(), '');

  step('dossier de l\'addon disparu : la tâche se retire en se lançant');
  assert.ok((await install()).ok);
  rmSync(addon, { recursive: true });
  await ps(`Start-ScheduledTask -TaskName ${TASK}`);
  for (let i = 0; i < 40 && await task(); i++) await new Promise((r) => setTimeout(r, 500));
  assert.equal(await task(), '');
}

main().then(() => console.log('✓ Script de synchro'), (e) => {
  console.error('✗ Script de synchro : ' + (e.stack || e));
  process.exitCode = 1;
}).finally(async () => {
  server.close();
  await ps(`Unregister-ScheduledTask -TaskName ${TASK} -Confirm:$false -ErrorAction SilentlyContinue`);
  rmSync(root, { recursive: true, force: true });
});
