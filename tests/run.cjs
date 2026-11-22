// Runs tests/test.lua with Fengari (Lua 5.3 in JS) and WoW API doubles. Exit code 1 on any failure.
const { readdirSync, readFileSync } = require('node:fs');
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

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
if (lauxlib.luaL_dofile(L, to_luastring('test.lua')) !== 0) {
  console.error('✗ ' + lua.lua_tojsstring(L, -1));
  process.exit(1);
}
