// Runs tests/test.lua with Fengari (Lua 5.3 in JS) and WoW API doubles. Exit code 1 on any failure.
const { lua, lauxlib, lualib, to_luastring } = require('fengari');
process.chdir(__dirname);
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
if (lauxlib.luaL_dofile(L, to_luastring('test.lua')) !== 0) {
  console.error('✗ ' + lua.lua_tojsstring(L, -1));
  process.exit(1);
}
