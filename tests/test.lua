-- Run: npm test. Fengari + WoW API doubles: checks logic and that UI code runs without nil errors.
-- Does NOT prove in-game rendering.
local fails = 0
local function ok(cond, name) if not cond then fails = fails + 1; print("FAIL " .. name) else print("ok   " .. name) end end

-- generic stub: any field is a callable stub returning a stub
local function stub(name)
  local s = {}
  return setmetatable(s, {
    __index = function(t, k) local v = stub(k); rawset(t, k, v); return v end,
    __call = function() return stub(name .. "()") end,
  })
end

time = os.time
date = os.date
DAY0 = os.time({ year = 2020, month = 1, day = 1, hour = 0 })
TODAY = 2516
time = function() return DAY0 + TODAY * 86400 + 3600 end
dofile("fixtures/realdata.lua")
Auctionator = {
  Constants = { SCAN_DAY_0 = DAY0 },
  Database = { GetPriceHistory = function(self, key) return DATA[key] or {} end },
  EventBus = { Register = function() end },
  FullScan = { Events = { ScanComplete = "x" } },
}

dofile("../src/Trend.lua")
local T = VepIndustriesMarket.Trend

-- unit: verdict rules
ok(T.Verdict(0.0, -0.4) == "demand", "stock -40%, prix stable -> demande")
ok(T.Verdict(0.2, 0.0) == "demand", "prix +20% -> demande")
ok(T.Verdict(0.08, 1.9) == "saturated", "stock x3 -> sature")
ok(T.Verdict(-0.2, 0.1) == "saturated", "prix -20% -> sature")
ok(T.Verdict(0.02, 0.05) == "stable", "rien ne bouge -> stable")
ok(T.Verdict(nil, nil) == "none", "pas de prix -> none")
local one = T.Compute({ { day = 2516, price = 100, stock = 5 } }, 2516)
ok(one.verdict == "none" and one.days == 1, "un seul jour -> none")
local old = T.Compute({ { day = 2500, price = 100, stock = 5 }, { day = 2501, price = 90, stock = 5 } }, 2516)
ok(old.verdict == "none" and old.age == 15, "donnees vieilles -> none")
local r = T.Compute({ { day = 2510, price = 100, stock = 100 }, { day = 2515, price = 100, stock = 100 },
  { day = 2516, price = 110, stock = 50 } }, 2516)
ok(r.verdict == "demand" and math.abs(r.stock + 0.5) < 1e-9 and math.abs(r.price - 0.1) < 1e-9, "calcul relatif")

-- real data
local count, n = {}, 0
for id in pairs(DATA) do
  local res = T.ForItem(id)
  n = n + 1
  count[res and res.verdict or "nil"] = (count[res and res.verdict or "nil"] or 0) + 1
end
print(string.format("donnees reelles: %d objets -> demande %d, stable %d, sature %d, none %d", n,
  count.demand or 0, count.stable or 0, count.saturated or 0, count.none or 0))
for _, id in ipairs({ "14048", "4338", "14047", "4306", "14256" }) do
  local res = T.ForItem(id)
  if res then
    print(string.format("  %s: %s prix %+.0f%% stock %+.0f%% (%d j)", id, res.verdict, (res.price or 0) * 100,
      (res.stock or 0) * 100, res.days))
  end
end

-- UI smoke test with API doubles
VepIndustriesMarketDB = {}
UIParent = stub("UIParent"); GameTooltip = stub("GameTooltip"); ItemRefTooltip = stub("ItemRefTooltip")
UISpecialFrames = {}; tinsert = table.insert
SlashCmdList = {}
local postCall
TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) postCall = fn end }
Enum = { TooltipDataType = { Item = 0 } }
C_Item = { GetItemNameByID = function(id) return "Item" .. id end }
C_Timer = { After = function(_, fn) fn() end }
C_AuctionHouse = stub("C_AuctionHouse")
GetCoinTextureString = function(c) return tostring(c) .. "c" end
GetRealmName = function() return "PvE" end
UnitFactionGroup = function() return "Horde" end
hooksecurefunc = function() end
local frames = {}
CreateFrame = function(kind, name)
  local f = stub(name or kind)
  local shown = false
  f.IsShown = function() return shown end
  f.Show = function() shown = true end
  f.Hide = function() shown = false end
  frames[#frames + 1] = f
  return f
end
print = print
local okLoad, err = pcall(function()
  local chunk = loadfile("../src/Probe.lua"); chunk("VepIndustriesMarket")
  dofile("../src/UI.lua")
end)
ok(okLoad, "chargement Probe.lua + UI.lua " .. tostring(err))
ok(postCall ~= nil, "hook infobulle enregistre")
local lines = {}
local tip = GameTooltip
tip.AddDoubleLine = function(_, a, b) lines[#lines + 1] = a .. " || " .. b end
local okTip, e2 = pcall(postCall, tip, { id = 14048 })
ok(okTip and #lines == 1, "ligne infobulle " .. tostring(e2))
print("  " .. (lines[1] or ""))
local okWin, e3 = pcall(function()
  SlashCmdList.VEPINDUSTRIESMARKET("")
  VepIndustriesMarket.ShowItem(14048, true)
  VepIndustriesMarket.ShowItem(4338, true)
  VepIndustriesMarket.ShowItem(999999, true)
  SlashCmdList.VEPINDUSTRIESMARKET("item |cffffffff|Hitem:14047::::|h[Runecloth]|h|r")
  SlashCmdList.VEPINDUSTRIESMARKET("unpin")
  SlashCmdList.VEPINDUSTRIESMARKET("tooltip"); SlashCmdList.VEPINDUSTRIESMARKET("tooltip")
end)
ok(okWin, "fenetre + commandes " .. tostring(e3))

if fails > 0 then error(fails .. " echec(s)", 0) end
print("TOUT OK")
