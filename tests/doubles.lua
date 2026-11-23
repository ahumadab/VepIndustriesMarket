-- WoW API doubles and shared test helpers, run by tests/run.cjs in a fresh Lua state before each tests/*.test.lua,
-- then done() after it. Fengari + doubles: checks logic and that UI code runs without nil errors. Does NOT prove
-- in-game rendering.
fails = 0
out = print -- print itself is replaced below to read the addon's chat messages
function ok(cond, name) if not cond then fails = fails + 1; out("FAIL " .. name) else out("ok   " .. name) end end

-- The game's Lua 5.1 cannot yield across pcall, Fengari's 5.3 can: catch it here (checked by done()).
local rawPcall, rawYield, protected, yieldInPcall = pcall, coroutine.yield, {}, nil
local function unprotect(co, ...) protected[co] = protected[co] - 1; return ... end
pcall = function(...)
  local co = coroutine.running()
  protected[co] = (protected[co] or 0) + 1
  return unprotect(co, rawPcall(...))
end
coroutine.yield = function(...)
  if (protected[coroutine.running()] or 0) > 0 then yieldInPcall = debug.traceback("yield inside pcall", 2) end
  return rawYield(...)
end

function done()
  ok(not yieldInPcall, "aucune coroutine ne cede dans un pcall (refuse par le Lua 5.1 du jeu) " .. tostring(yieldInPcall))
  if fails > 0 then error(fails .. " echec(s)", 0) end
end

-- generic stub: any field is a callable stub returning a stub
function stub(name)
  local s = {}
  return setmetatable(s, {
    __index = function(t, k) local v = stub(k); rawset(t, k, v); return v end,
    __call = function() return stub(name .. "()") end,
  })
end

-- the clock: today is day TODAY of Auctionator, 01:00
unpack = unpack or table.unpack -- a global in the game's Lua 5.1, gone from Fengari's 5.3
date = os.date
DAY0 = os.time({ year = 2020, month = 1, day = 1, hour = 0 })
TODAY = 2516
time = function() return DAY0 + TODAY * 86400 + 3600 end

-- Auctionator: price history from FAKE, then DATA (fixtures/realdata.lua, when the test file loads it)
LISTENERS = {}
AUCTIONATOR_CONFIG = { replicate_scan_3 = true, autoscan_2 = true }
FAKE = {}
Auctionator = {
  Constants = { SCAN_DAY_0 = DAY0 },
  Database = { GetPriceHistory = function(self, key) return FAKE[key] or DATA and DATA[key] or {} end },
  EventBus = { Register = function(_, l, events) for _, e in ipairs(events) do LISTENERS[e] = l end end },
  FullScan = { Events = { ScanComplete = "replicate_scan_complete" } },
  IncrementalScan = { Events = { ScanComplete = "full_incremental_scan_complete" } },
  Config = { Options = { REPLICATE_SCAN = "replicate_scan_3", AUTOSCAN = "autoscan_2" },
    Get = function(name) return AUCTIONATOR_CONFIG[name] end },
}

-- interface
UIParent = stub("UIParent"); GameTooltip = stub("GameTooltip"); ItemRefTooltip = stub("ItemRefTooltip")
UISpecialFrames = {}; tinsert = table.insert
SlashCmdList = {}
TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) TOOLTIP_POST_CALL = fn end }
Enum = { TooltipDataType = { Item = 0 } }
C_Item = { GetItemNameByID = function(id) return "Item" .. id end }
C_Timer = { After = function(_, fn) fn() end }
C_AuctionHouse = stub("C_AuctionHouse")
GetCoinTextureString = function(c) return tostring(c) .. "c" end
GetRealmName = function() return "PvE" end
UnitFactionGroup = function() return "Horde" end
UnitName = function() return "Boris" end
hooksecurefunc = function() end
-- chat doubles for Exchange.lua and ChatThrottleLib: a clock, and sends recorded in outbox, or refused with the codes
-- queued in refuse
chat = { clock = 0, outbox = {}, refuse = {}, filters = {} }
GetTime = function() return chat.clock end
GetFramerate = function() return 60 end
securecallfunction = function(fn, ...) return fn(...) end
geterrorhandler = function() return function(e) chat.error = e end end
table.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
IsInInstance = function() return chat.instance end
IsInGuild = function() return true end
-- our addon's version as the .toc of a deploy writes it (a release has no "-dev+...")
C_AddOns = { GetAddOnMetadata = function(name, field)
  return name == "VepIndustriesMarket" and field == "Version" and "0.2.0-dev+abc1234" or nil
end }
ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
ChatFrameUtil = { AddMessageEventFilter = function(event, fn) chat.filters[event] = fn end }
-- compression double: the text behind a \0, so that escaping shows
C_EncodingUtil = {
  CompressString = function(s) return "\0" .. s end,
  DecompressString = function(s) assert(s:sub(1, 1) == "\0", "corrupted"); return s:sub(2) end,
}
C_ChatInfo = {
  RegisterAddonMessagePrefix = function() end,
  InChatMessagingLockdown = function() return chat.locked end,
  SendAddonMessage = function(prefix, text, channel, target)
    local code = table.remove(chat.refuse, 1) or 0
    if code == 0 then
      chat.outbox[#chat.outbox + 1] = { prefix = prefix, text = text, channel = channel, target = target, at = chat.clock }
    end
    return code
  end,
}
frames, textures = {}, {}
-- texture double recording its color, height and visibility, to count the bars drawn
local function texture()
  local t = stub("texture")
  t.SetColorTexture = function(self, r, g, b, a) self.color = string.format("%.2f %.2f %.2f %.2f", r, g, b, a or 1) end
  t.SetSize = function(self, w, h) self.height = h end
  t.Show = function(self) self.shown = true end
  t.Hide = function(self) self.shown = false end
  textures[#textures + 1] = t
  return t
end
CreateFrame = function(kind, name)
  local f = stub(name or kind)
  rawset(f, "frameName", name)
  f.CreateTexture = texture
  local shown = false
  f.IsShown = function() return shown end
  f.Show = function() shown = true end
  f.Hide = function() shown = false end
  f.SetScript = function(self, script, fn) rawset(self, script, fn) end
  f.SetSize = function(self, w, h) self.width, self.height = w, h end
  -- font strings measuring their text: 6 px per visible character, 14 px per line
  f.CreateFontString = function()
    local fs = stub("fontstring")
    fs.SetText = function(self, s) self.text = s end
    local function lines(self)
      local visible = (self.text or ""):gsub("|T[^|]*|t", "xx"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
      local t = {}
      for l in (visible .. "\n"):gmatch("(.-)\n") do t[#t + 1] = l end
      return t
    end
    fs.GetStringWidth = function(self)
      local w = 0
      for _, l in ipairs(lines(self)) do w = math.max(w, utf8 and utf8.len(l) or #l) end
      return w * 6
    end
    fs.GetStringHeight = function(self) return #lines(self) * 14 end
    return fs
  end
  local events = {}
  f.RegisterEvent = function(_, e) events[e] = true end
  f.UnregisterEvent = function(_, e) events[e] = nil end
  f.IsEventRegistered = function(_, e) return events[e] == true end
  frames[#frames + 1] = f
  return f
end
said = {}
print = function(s) said[#said + 1] = s end
function lastSaid() return said[#said] or "" end
-- as the game: only to the frames registered for the event
function fire(event, ...)
  for _, f in ipairs(frames) do
    local onEvent = rawget(f, "OnEvent")
    if onEvent and f:IsEventRegistered(event) then onEvent(f, event, ...) end
  end
end

-- a file of src/ run as the game runs it: `...` is the addon's name
function loadAddonFile(file) return assert(loadfile("../src/" .. file))("VepIndustriesMarket") end
-- the files of src/VepIndustriesMarket.toc, in its order (ADDON_FILES, read by tests/run.cjs)
function loadAddon()
  for _, file in ipairs(ADDON_FILES) do loadAddonFile(file) end
end

-- a tier of a full scan, and fixture rows { itemID, size, buyout, timeLeft, count } as a full scan
function tier(price, size, count, timeLeft) return { price = price, size = size, count = count, timeLeft = timeLeft } end
function rowsToScan(rows)
  local scan = {}
  for _, r in ipairs(rows) do
    scan[r[1]] = scan[r[1]] or {}
    table.insert(scan[r[1]], tier(math.floor(r[3] / r[2] + 0.5), r[2], r[5], r[4]))
  end
  return scan
end
