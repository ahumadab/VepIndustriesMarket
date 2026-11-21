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
  Database = { GetPriceHistory = function(self, key) return FAKE[key] or DATA[key] or {} end },
  EventBus = { Register = function() end },
  FullScan = { Events = { ScanComplete = "x" } },
}

dofile("../src/Trend.lua")
dofile("../src/Market.lua")
local M = VepIndustriesMarket.Market

-- fabricated histories: { {day, price, stock}, ... } in Auctionator's shape, under a fake itemID
FAKE = {}
local nextID = 900000
local function report(days)
  nextID = nextID + 1
  local h = {}
  for _, d in ipairs(days) do h[#h + 1] = { rawDay = tostring(d[1]), minSeen = d[2], available = d[3] } end
  FAKE[tostring(nextID)] = h
  return M.Report(nextID)
end
-- yesterday at price/stock 100, today moved by relative p and s
local function moved(p, s) return report({ { 2515, 100, 100 }, { 2516, 100 * (1 + p), 100 * (1 + s) } }).verdict end
local function near(a, b) return a and math.abs(a - b) < 1e-9 end

-- verdict rules
ok(moved(0.0, -0.4) == "demand", "stock -40%, prix stable -> demande")
ok(moved(0.2, 0.0) == "demand", "prix +20% -> demande")
ok(moved(0.08, 1.9) == "saturated", "stock x3 -> sature")
ok(moved(-0.2, 0.1) == "saturated", "prix -20% -> sature")
ok(moved(0.02, 0.05) == "stable", "rien ne bouge -> stable")
ok(report({ { 2515, nil, 100 }, { 2516, nil, 50 } }).verdict == "none", "pas de prix -> none")
local one = report({ { 2516, 100, 5 } })
ok(one.verdict == "none" and one.trend.days == 1, "un seul jour -> none")
local old = report({ { 2500, 100, 5 }, { 2501, 90, 5 } })
ok(old.verdict == "none" and old.trend.age == 15, "donnees vieilles -> none")
local r = report({ { 2510, 100, 100 }, { 2515, 100, 100 }, { 2516, 110, 50 } })
ok(r.verdict == "demand" and near(r.trend.stock, -0.5) and near(r.trend.price, 0.1) and r.trend.days == 3,
  "calcul relatif")
ok(report({ { 2512, 100, 10 }, { 2513, 1, 10 }, { 2515, 100, 10 }, { 2516, 100, 10 } }).verdict == "stable",
  "enchere aberrante neutralisee par la mediane")
ok(r.estimatedSalesPerDay == nil and r.confidence == nil, "pas de ventes estimees sans scan complet")

-- item missing from the history
local okMiss, miss = pcall(M.Report, 999999)
ok(okMiss and miss.verdict == "none" and miss.trend.days == 0 and #miss.history == 0, "objet absent -> none")

-- Auctionator not loaded
local auctionator = Auctionator
Auctionator = nil
local okNoAuc, noAuc = pcall(M.Report, 14048)
ok(okNoAuc and noAuc.verdict == "none" and #noAuc.history == 0, "sans Auctionator -> none sans erreur")
Auctionator = auctionator

-- a full scan is accepted but not used yet
local okIngest = pcall(M.Ingest, { [14048] = { { price = 100, size = 1, count = 3, timeLeft = 2 } } }, time())
ok(okIngest and M.Report(14048).estimatedSalesPerDay == nil, "Ingest accepte un scan complet")

-- real data: same verdicts as before the Market module
local count, n = {}, 0
for id in pairs(DATA) do
  local v = M.Report(id).verdict
  n = n + 1
  count[v] = (count[v] or 0) + 1
end
print(string.format("donnees reelles: %d objets -> demande %d, stable %d, sature %d, none %d", n,
  count.demand or 0, count.stable or 0, count.saturated or 0, count.none or 0))
ok(n == 2097 and count.demand == 524 and count.stable == 1115 and count.saturated == 458 and not count.none,
  "repartition des verdicts sur l'historique reel")
local expected = { -- itemID = verdict, price %, stock %, days
  [14048] = { "saturated", 8, 190, 2 }, [4338] = { "stable", 4, -19, 8 }, [14047] = { "stable", 72, 68, 2 },
  [4306] = { "stable", 0, -24, 4 }, [14256] = { "demand", -2, -57, 2 },
}
for id, e in pairs(expected) do
  local res = M.Report(id)
  local p, s = math.floor(res.trend.price * 100 + 0.5), math.floor(res.trend.stock * 100 + 0.5)
  ok(res.verdict == e[1] and p == e[2] and s == e[3] and res.trend.days == e[4],
    string.format("%d: %s prix %+d%% stock %+d%% (%d j)", id, res.verdict, p, s, res.trend.days))
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
ok(okTip and lines[1] == "|cffffd100Tendance 7 j|r || |cffff5959Saturé|r  prix |cff66ff66+8%|r  stock "
  .. "|cffff6666+190%|r |cff9d9d9d(2 j)|r", "ligne infobulle " .. tostring(e2) .. " " .. tostring(lines[1]))
local okNone = pcall(postCall, tip, { id = 999999 })
ok(okNone and #lines == 1, "pas de ligne infobulle pour un objet absent")
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
