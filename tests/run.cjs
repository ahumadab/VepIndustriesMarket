// Runs tests/test.lua with Fengari (Lua 5.3 in JS) and WoW API doubles. Exit code 1 on any failure.
// With "merge-case" (npm run merge-case), also rewrites the real case of merge-cases.json from Market.Merge, after a
// change of the merge rule: the server replays the new expectations, from its copy in vepindustries-api, which
// merge-case refreshes when that repo is cloned next to this one (AGENTS.md) and every run compares.
const { copyFileSync, existsSync, readdirSync, readFileSync, writeFileSync } = require('node:fs');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');
process.chdir(__dirname);

// The game runs Lua 5.1: reject 5.3-only syntax and libraries that Fengari would accept.
// Comments and strings are blanked first (keeping newlines), so "|cff" color codes and "--" in text don't match.
const LUA53 = /\/\/|[&|]|~(?!=)|<<|>>|\bgoto\b|::\w+::|\butf8\.|\btable\.move\b|\bmath\.(type|tointeger)\b|\bstring\.(pack|unpack|packsize)\b/;
const NOISE = /--\[(=*)\[[\s\S]*?\]\1\]|--[^\n]*|\[(=*)\[[\s\S]*?\]\2\]|"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'/g;
const lua53 = [];
for (const f of readdirSync('../src').filter((f) => f.endsWith('.lua'))) {
  const code = readFileSync(`../src/${f}`, 'utf8').replace(NOISE, (m) => m.replace(/[^\n]/g, ' '));
  code.split('\n').forEach((line, i) => { if (LUA53.test(line)) lua53.push(`src/${f}:${i + 1}: ${line.trim()}`); });
}
if (lua53.length) {
  console.error('✗ Lua 5.3 absent du jeu (5.1) :\n' + lua53.join('\n'));
  process.exit(1);
}

// CODING_STANDARDS.md, interface constants: every |cff colour code of src/UI.lua comes from hex() and a named colour.
// Comments are blanked, strings kept; hex()'s own "|cff%02x..." template is the one allowed literal.
const COMMENT = /("(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*')|--\[(=*)\[[\s\S]*?\]\2\]|--[^\n]*/g;
const ui = readFileSync('../src/UI.lua', 'utf8').replace(COMMENT, (m, str) => str || m.replace(/[^\n]/g, ' '));
const literals = ui.split('\n').flatMap((line, i) => (/\|cff(?!%02x)/.test(line) ? [`src/UI.lua:${i + 1}: ${line.trim()}`] : []));
if (literals.length) {
  console.error('✗ code couleur écrit en dur, à passer par hex() et une constante :\n' + literals.join('\n'));
  process.exit(1);
}

// The Sync script's files: Windows PowerShell 5.1 reads a .ps1 without BOM in the ANSI code page (accents broken),
// and cmd misreads a .cmd without CRLF. .editorconfig and .gitattributes set both; this catches an editor that didn't.
const BOM = Buffer.from([0xef, 0xbb, 0xbf]);
const layout = readdirSync('../src').flatMap((f) => {
  const bytes = readFileSync(`../src/${f}`);
  if (f.endsWith('.ps1') && !bytes.subarray(0, 3).equals(BOM)) return [`src/${f} : BOM UTF-8 manquant`];
  if (f.endsWith('.cmd') && /(^|[^\r])\n/.test(bytes.toString('latin1'))) return [`src/${f} : fin de ligne sans CR`];
  return [];
});
if (layout.length) {
  console.error('✗ fichiers du Script de synchro mal enregistrés :\n' + layout.join('\n'));
  process.exit(1);
}

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
// merge-cases.json, shared with the server, handed to test.lua as the global MERGE_CASES (numeric keys as numbers)
const toLua = (v) => (Array.isArray(v) ? `{${v.map(toLua).join(',')}}`
  : v && typeof v === 'object' ? `{${Object.entries(v).map(([k, x]) => `[${/^\d+$/.test(k) ? k : JSON.stringify(k)}]=${toLua(x)}`).join(',')}}`
    : JSON.stringify(v));
lauxlib.luaL_dostring(L, to_luastring(`MERGE_CASES = ${toLua(JSON.parse(readFileSync('merge-cases.json', 'utf8')))}`));
const failure = lauxlib.luaL_dofile(L, to_luastring('test.lua')) !== 0 && lua.lua_tojsstring(L, -1);
if (process.argv[2] === 'merge-case') {
  // the real case, last of the file, rewritten in its layout: one comparison per line, one item per line
  const REAL = '    {\n      "name": "Comparaison réelle';
  const text = readFileSync('merge-cases.json', 'utf8');
  const at = text.indexOf(REAL);
  lua.lua_getglobal(L, 'REAL_MERGE_CASE');
  if (at < 0 || !lua.lua_isstring(L, -1)) {
    console.error('✗ cas réel introuvable dans merge-cases.json ou non construit par test.lua');
    process.exit(1);
  }
  const real = JSON.parse(lua.lua_tojsstring(L, -1));
  const name = text.slice(at).match(/"name": "([^"]*)"/)[1];
  const tranches = Object.entries(real.tranches)
    .map(([id, ks]) => `"${id}": { ${Object.entries(ks).map(([k, v]) => `"${k}": [${v.join(', ')}]`).join(', ')} }`);
  writeFileSync('merge-cases.json', `${text.slice(0, at)}    {
      "name": ${JSON.stringify(name)},
      "comparisons": [
        ${real.comparisons.map((c) => `{ "author": "${c.author}", "start": ${c.start}, "finish": ${c.finish}, "items": ${JSON.stringify(c.items)} }`).join(',\n        ')}
      ],
      "tranches": {
        ${tranches.join(',\n        ')}
      }
    }
  ]
}
`);
  console.log('✓ cas réel de merge-cases.json réécrit');
}
const SERVER_CASES = '../../vepindustries/api/apps/api/tests/modules/market/application/merge-cases.json';
if (process.argv[2] === 'merge-case' && existsSync(SERVER_CASES)) {
  copyFileSync('merge-cases.json', SERVER_CASES);
  console.log('✓ copié dans vepindustries-api, à y committer');
} else if (!existsSync(SERVER_CASES) || readFileSync(SERVER_CASES, 'utf8') !== readFileSync('merge-cases.json', 'utf8')) {
  console.warn(`! merge-cases.json diffère de la copie du serveur ou elle est introuvable : ${SERVER_CASES}`);
}
if (failure) {
  console.error('✗ ' + failure);
  process.exit(1);
}
