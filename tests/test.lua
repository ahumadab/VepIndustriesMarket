-- Run: npm test. Fengari + WoW API doubles: checks logic and that UI code runs without nil errors.
-- Does NOT prove in-game rendering.
-- One script, run in order: each M.Ingest is compared with the full scan stored by the previous one. A new scan goes
-- in a block of its own, opened with VepIndustriesMarketDB = {}, so the blocks after it keep their chain of scans.
local fails = 0
local out = print -- print itself is replaced below to read the addon's chat messages
local function ok(cond, name) if not cond then fails = fails + 1; out("FAIL " .. name) else out("ok   " .. name) end end

-- The game's Lua 5.1 cannot yield across pcall, Fengari's 5.3 can: catch it here (checked at the end).
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

-- generic stub: any field is a callable stub returning a stub
local function stub(name)
  local s = {}
  return setmetatable(s, {
    __index = function(t, k) local v = stub(k); rawset(t, k, v); return v end,
    __call = function() return stub(name .. "()") end,
  })
end

time = os.time
unpack = unpack or table.unpack -- a global in the game's Lua 5.1, gone from Fengari's 5.3
date = os.date
DAY0 = os.time({ year = 2020, month = 1, day = 1, hour = 0 })
TODAY = 2516
time = function() return DAY0 + TODAY * 86400 + 3600 end
dofile("fixtures/realdata.lua")
dofile("fixtures/fullscan.lua")
LISTENERS = {}
AUCTIONATOR_CONFIG = { replicate_scan_3 = true, autoscan_2 = true }
Auctionator = {
  Constants = { SCAN_DAY_0 = DAY0 },
  Database = { GetPriceHistory = function(self, key) return FAKE[key] or DATA[key] or {} end },
  EventBus = { Register = function(_, l, events) for _, e in ipairs(events) do LISTENERS[e] = l end end },
  FullScan = { Events = { ScanComplete = "replicate_scan_complete" } },
  IncrementalScan = { Events = { ScanComplete = "full_incremental_scan_complete" } },
  Config = { Options = { REPLICATE_SCAN = "replicate_scan_3", AUTOSCAN = "autoscan_2" },
    Get = function(name) return AUCTIONATOR_CONFIG[name] end },
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

-- full scans: only the latest is kept, the daily summary counts every scan of the day
VepIndustriesMarketDB = {}
local function tier(price, size, count, timeLeft) return { price = price, size = size, count = count, timeLeft = timeLeft } end
M.Ingest({ [900] = { tier(300, 1, 1, 3), tier(120, 20, 2, 2) }, [901] = { tier(5, 1, 1, 1) } }, time() - 60)
M.Ingest({ [900] = { tier(150, 5, 1, 4), tier(130, 1, 2, 3), tier(130, 1, 3, 1), tier(130, 200, 1, 3) },
  [902] = {} }, time())
local scanned = M.Report(900)
local t1, t2, d = scanned.tiers[1], scanned.tiers[2], scanned.daily[TODAY]
ok(#scanned.tiers == 4 and t1.price == 130 and t1.size == 1 and t1.count == 3 and t1.timeLeft == 1
  and t2.price == 130 and t2.size == 1 and t2.count == 2 and t2.timeLeft == 3
  and scanned.tiers[3].size == 200 and scanned.tiers[4].price == 150 and scanned.tiers[4].size == 5,
  "seul le dernier scan est conserve, paliers tries et separes par temps restant")
ok(d and d.scans == 2 and d.price == 120 and d.stock == 210, "resume journalier : 2 scans, prix min et stock max du jour")
ok(#M.Report(902).tiers == 0 and M.Report(902).daily[TODAY] == nil, "objet sans palier ignore")
ok(#M.Report(901).tiers == 0 and M.Report(901).daily[TODAY].scans == 1, "objet absent du dernier scan : pas de palier")
ok(scanned.estimatedSalesPerDay == nil, "pas encore de ventes estimees")
M.Ingest({ [900] = { tier(99, 1, 1, 3) } }, time() + 30 * 86400)
ok(M.Report(900).daily[TODAY] == nil and M.Report(900).daily[TODAY + 30].scans == 1, "resume journalier limite a 21 jours")
local status = M.Status()
ok(status.items == 1 and status.time == time() + 30 * 86400 and status.bytes > 0, "etat du dernier scan")
VepIndustriesMarketDB = nil
ok(#M.Report(900).tiers == 0 and M.Status() == nil, "sans donnees sauvegardees -> rien, sans erreur")

-- estimated sales: auctions gone from a tier (price, lot size) between two scans, except those that may have
-- expired meanwhile (Short; Medium, 30 min to 2 h left, after 30 min)
VepIndustriesMarketDB = { daily = { [910] = { [TODAY - 3] = "100 5 4" } } } -- a day saved before estimated sales
local t0 = time() - 86400 -- yesterday 01:00
M.Ingest({
  [910] = { tier(100, 1, 3, 3), tier(100, 1, 2, 1) }, -- 5 auctions, 2 of them Short
  [911] = { tier(200, 20, 2, 1) },                    -- Short only
  [912] = { tier(100, 1, 1, 3) },
  [913] = { tier(50, 5, 2, 3) },                      -- 2 lots of 5, sold out next scan
  [914] = { tier(100, 1, 2, 4), tier(100, 1, 1, 3) }, -- time left moves down between scans
  [916] = { tier(100, 1, 2, 2) },                     -- Medium
  [918] = { tier(100, 1, 5, 3) },                     -- reposted cheaper
  [919] = { tier(100, 1, 2, 3), tier(120, 1, 3, 3) }, -- dearer tier cancelled
  [920] = { tier(100, 1, 2, 3), tier(110, 1, 3, 3) }, -- cheapest tier bought out
  [921] = { tier(1, 1038, 1, 3), tier(1, 200, 2, 3) }, -- commodity: a partial buy shrinks the lot
}, t0, "PvE", "Horde", "Boris")
M.Ingest({
  [910] = { tier(100, 1, 1, 3) },
  [912] = { tier(100, 1, 1, 3), tier(90, 1, 4, 4) },
  [914] = { tier(100, 1, 2, 3) },
  [915] = { tier(10, 1, 9, 4) },
  [918] = { tier(95, 1, 5, 4) },
  [919] = { tier(100, 1, 1, 3) },
  [920] = { tier(110, 1, 1, 3) },
  [921] = { tier(1, 838, 1, 3), tier(1, 200, 2, 3) },
}, t0 + 3600, "PvE", "Horde", "Boris")
local c = VepIndustriesMarketDB.comparisons and VepIndustriesMarketDB.comparisons[1] or {}
local function has(entry) return ("," .. (c.items or "") .. ","):find("," .. entry .. ",", 1, true) end
ok(#VepIndustriesMarketDB.comparisons == 1 and c.author == "Boris" and c.start == t0 and c.finish == t0 + 3600
  and c.realm == "PvE" and c.faction == "Horde" and has("910 2 1 100") and has("913 10 0 -") and has("915 - 9 10")
  and has("911 0 0 -"), "Comparaison enregistree : auteur, hotel des ventes, debut, fin, vendues stock prix par objet")local function rate(id) return M.Report(id).estimatedSalesPerDay end
ok(near(rate(910), 2 * 24), "palier partiellement vendu : 4 disparues dont 2 Short -> 2 vendues en 1 h")
ok(rate(911) == 0, "encheres Short disparues : expirees, pas vendues")
ok(rate(916) == 0, "encheres Medium disparues en plus de 30 min : expirees, pas vendues")
ok(rate(912) == 0, "nouveau palier : aucune vente")
ok(near(rate(913), 10 * 24), "objet epuise : ses lots disparus comptent")
ok(near(rate(914), 1 * 24), "palier suivi malgre le changement de temps restant")
ok(rate(915) == nil and M.Report(915).confidence == nil, "objet nouveau : pas de ventes")
ok(rate(918) == 0, "remis en vente moins cher : aucune vente")
ok(near(rate(919), 1 * 24), "palier plus cher disparu : annule, pas vendu")
ok(near(rate(920), 4 * 24), "acheteurs du moins cher : palier vide + baisse au nouveau minimum")
ok(near(rate(921), 200 * 24), "marchandise : unites comptees par prix, quelle que soit la taille du lot")
ok(M.Report(910).confidence == "low", "1 jour de comparaison (jour ancien sans ventes ignore) -> non fiable")
local t2 = time() - 3600 -- today 00:00
M.Ingest({ [910] = { tier(100, 1, 1, 3) }, [917] = { tier(100, 1, 2, 2) } }, t2, "PvE", "Horde", "Boris")
ok(near(rate(910), 48) and rate(917) == nil, "plus de 2 h d'ecart : pas compare")
local t3 = t2 + 1200
M.Ingest({ [910] = { tier(100, 1, 1, 3) }, [917] = { tier(100, 1, 1, 2) } }, t3, "PvE", "Horde", "Boris")
ok(near(rate(917), 72), "enchere Medium disparue en 20 min : vendue")
ok(near(rate(910), 36) and M.Report(910).confidence == "high", "2 jours, 3 scans compares : 2 vendues en 80 min, fiable")
M.Ingest({ [910] = { tier(100, 1, 1, 3) }, [917] = { tier(100, 1, 1, 2) } }, t3 + 1800, "PvE", "Horde", "Boris")
ok(near(rate(910), 36) and M.Status().time == t3, "meme scan relu : pas compare, garde son heure")
M.Ingest({}, t3 + 2000, "PvE", "Horde", "Boris")
ok(M.Status().items == 2, "scan vide ignore")
M.Ingest({ [999] = { tier(1, 1, 1, 3) } }, t3 + 60, "PvE", "Horde", "Boris")
ok(near(rate(910), 36) and M.Status().time == t3, "scans tres rapproches : pas compares")
M.Ingest({ [910] = { tier(100, 1, 1, 3) } }, t3 + 3600, "PvE", "Horde", "Boris")
M.Ingest({ [999] = { tier(1, 1, 1, 3) } }, t3 + 4000, "PvE", "Alliance", "Boris")
ok(near(rate(910), 36), "autre faction : pas comparee")
ok(rate(999999) == nil and M.Report(999999).confidence == nil, "objet sans scan complet : pas de ventes, sans erreur")

-- a Comparison over midnight: its sales split between both days, prorata of the time on each
VepIndustriesMarketDB = {}
M.Ingest({ [940] = { tier(100, 1, 5, 3) } }, t2 - 900, "PvE", "Horde", "Boris")
M.Ingest({ [940] = { tier(100, 1, 3, 3) } }, t2 + 600, "PvE", "Horde", "Reroll")
ok(VepIndustriesMarketDB.comparisons[1].author == "Boris",
  "Comparaison finie sur un autre personnage du compte : auteur du compte")
local eve, morn = M.Report(940).daily[TODAY - 1], M.Report(940).daily[TODAY]
ok(near(eve.estimatedSales, 1.2) and eve.seconds == 900 and near(morn.estimatedSales, 0.8) and morn.seconds == 600
  and eve.scans == 1 and morn.scans == 1, "Comparaison a cheval sur minuit : ventes au prorata de chaque jour")

-- Comparisons kept a day at most, and at most M.MAX_COMPARISONS (size of the save)
VepIndustriesMarketDB = {}
for i = 0, M.MAX_COMPARISONS + 2 do
  M.Ingest({ [941] = { tier(100, 1, 50 - i % 2, 3) } }, t2 + i * 900, "PvE", "Horde", "Boris")
end
local kept = VepIndustriesMarketDB.comparisons
ok(#kept == M.MAX_COMPARISONS and kept[1].start == t2 + 2 * 900, "Comparaisons limitees en nombre, les plus anciennes retirees")
ok(near(rate(941), 86400 / 1800), "Comparaisons retirees : resume journalier intact")
M.Ingest({ [941] = { tier(100, 1, 51, 3) } }, t2 + 86400 + (M.MAX_COMPARISONS + 2) * 900, "PvE", "Horde", "Boris")
ok(#VepIndustriesMarketDB.comparisons == 0, "Comparaisons de plus de 24 h retirees")

-- the Sync script's data file (VepIndustriesMarketData): its daily summary already counts the Comparisons it lists,
-- ours absent from that list are merged on top
VepIndustriesMarketDB = {}
M.Ingest({ [942] = { tier(100, 1, 10, 3) } }, t2, "PvE", "Horde", "Boris")
M.Ingest({ [942] = { tier(100, 1, 8, 3) } }, t2 + 1800, "PvE", "Horde", "Boris") -- 2 sold, counted by the server
M.Ingest({ [942] = { tier(100, 1, 7, 3) } }, t2 + 3600, "PvE", "Horde", "Boris") -- 1 sold, not yet
local alone = M.Report(942).daily[TODAY]
ok(alone.estimatedSales == 3 and alone.seconds == 3600 and alone.price == 100, "sans fichier de donnees : nos ventes seules")
VepIndustriesMarketData = { generated = t2 + 3000, counted = { Boris = { [t2] = true } }, daily = { [942] = {
  [TODAY] = "90 12 2 6 3600",    -- ours and a friend's, merged by the server
  [TODAY - 3] = "80 5 1 4 1800", -- a friend's only
} } }
local shared = M.Report(942).daily
ok(near(shared[TODAY].estimatedSales, 7) and shared[TODAY].seconds == 5400 and shared[TODAY].price == 90
  and shared[TODAY].stock == 12, "fichier de donnees : nos Comparaisons comptees une seule fois, les autres ajoutees")
ok(shared[TODAY - 3].estimatedSales == 4 and shared[TODAY - 3].seconds == 1800 and shared[TODAY - 3].price == 80,
  "fichier de donnees : jour d'un ami seul")
ok(M.StaleDays() == nil, "fichier de donnees recent : Script de synchro en marche")
VepIndustriesMarketData.generated = t2 - 4 * 86400
ok(M.StaleDays() == 4, "fichier de donnees vieux de 4 jours, scan plus recent : Script de synchro arrete")
-- days after the file's come from our daily summary, even once their Comparisons are dropped from the save
local saved = VepIndustriesMarketDB.comparisons
VepIndustriesMarketDB.comparisons = {}
local late = M.Report(942).daily[TODAY]
ok(late.estimatedSales == 3 and late.seconds == 3600, "fichier en retard : nos ventes des jours suivants gardees")
VepIndustriesMarketDB.comparisons = saved
-- past the cap, Comparisons the server counted go first
VepIndustriesMarketData.counted = { Boris = { [t2 + 1800] = true } }
local cap = M.MAX_COMPARISONS
M.MAX_COMPARISONS = 2
M.Ingest({ [942] = { tier(100, 1, 6, 3) } }, t2 + 5400, "PvE", "Horde", "Boris")
kept = VepIndustriesMarketDB.comparisons
ok(#kept == 2 and kept[1].start == t2 and kept[2].start == t2 + 3600, "Comparaisons comptees par le serveur retirees d'abord")
M.MAX_COMPARISONS = cap
VepIndustriesMarketData = nil
ok(M.StaleDays() == nil, "sans fichier de donnees : rien a signaler")

-- Comparisons received in game (Exchange.lua): kept and merged by Tranche as ours, once; malformed or old ones refused
VepIndustriesMarketDB = {}
M.Ingest({ [943] = { tier(100, 1, 10, 3) } }, t2, "PvE", "Horde", "Boris")
M.Ingest({ [943] = { tier(100, 1, 8, 3) } }, t2 + 1800, "PvE", "Horde", "Boris") -- 2 sold
local friend = { author = "Ami", realm = "PvE", faction = "Horde", start = t2, finish = t2 + 1800, items = "943 4 6 100" }
ok(M.Receive(friend, t2 + 1800) and not M.Receive(friend, t2 + 1800) and #VepIndustriesMarketDB.comparisons == 2
  and near(M.Report(943).daily[TODAY].estimatedSales, 3) and M.Report(943).daily[TODAY].seconds == 1800,
  "Comparaison recue : gardee une fois, moyenne avec la notre sur la Tranche")
local function refused(changes, now)
  local c = { author = "Autre" }
  for k, v in pairs(friend) do if k ~= "author" then c[k] = v end end
  for k, v in pairs(changes) do c[k] = v end
  return not M.Receive(c, now or t2 + 1800)
end
ok(refused({ items = "943 4 6 100,oops" }) and refused({ items = "" }) and refused({ finish = t2 + 60 })
  and refused({ finish = t2 + 9000 }) and refused({ start = tostring(t2) }) and refused({}, t2 + 1800 + 86400)
  and #VepIndustriesMarketDB.comparisons == 2, "Comparaison recue malformee ou de plus de 24 h refusee")
cap, M.MAX_COMPARISONS = M.MAX_COMPARISONS, 2
M.Ingest({ [943] = { tier(100, 1, 7, 3) } }, t2 + 3600, "PvE", "Horde", "Boris")
kept = VepIndustriesMarketDB.comparisons
ok(#kept == 2 and kept[1].author == "Boris" and kept[2].author == "Boris" and M.Seen()["Ami " .. t2] == t2 + 1800,
  "au-dela du plafond : Comparaisons des autres retirees avant les notres, gardees comme connues")
ok(not M.Receive(friend, t2 + 3600), "Comparaison retiree par le plafond : pas reprise d'un ami")
ok(not M.Receive({ author = "Tiers", realm = "PvE", faction = "Horde", start = t2 + 600, finish = t2 + 1500,
  items = "943 1 6 100" }, t2 + 3600), "Comparaison recue sur la Tranche d'une Comparaison retiree : refusee (pas comptee deux fois)")
M.MAX_COMPARISONS = cap

-- verdict from reliable estimated sales: days the current stock lasts at that pace (provisional thresholds, #7)
VepIndustriesMarketDB = {}
ok(M.Report(14048).verdict == "saturated" and M.Report(14048).source == "trend", "14048 sature par la tendance")
local function twoDays(before, after) -- one comparison of 1 h yesterday, one today: reliable
  M.Ingest(before, t0, "PvE", "Horde", "Boris"); M.Ingest(after, t0 + 3600, "PvE", "Horde", "Boris")
  M.Ingest(before, t2, "PvE", "Horde", "Boris"); M.Ingest(after, t2 + 3600, "PvE", "Horde", "Boris")
end
twoDays({ [14048] = { tier(100, 1, 30, 3) }, [930] = { tier(100, 1, 101, 3) }, [931] = { tier(100, 1, 50, 3) },
    [932] = { tier(100, 1, 2, 3) } },
  { [14048] = { tier(100, 1, 29, 3) }, [930] = { tier(100, 1, 100, 3) }, [931] = { tier(100, 1, 50, 3) } })
local function bySales(id) local res = M.Report(id); return res.source == "sales" and res.confidence == "high" and res.verdict end
ok(bySales(14048) == "demand", "ventes fiables : 24/jour pour 29 en stock (1,2 j) -> demande, malgre la tendance saturee")
ok(bySales(930) == "stable", "ventes fiables : 24/jour pour 100 en stock (4,2 j) -> stable")
ok(bySales(931) == "saturated", "ventes fiables : aucune vente, 50 en stock -> sature")
ok(bySales(932) == "demand", "ventes fiables : objet epuise -> demande")
ok(M.Report(930).estimatedSalesDays == 2, "ventes fiables : nombre de jours compares")
local byTrend = M.Report(14047)
ok(byTrend.source == "trend" and byTrend.verdict == "stable", "sans ventes fiables : verdict de la tendance")

-- real full scans of 2026-11-21 (one item in ten, npm run fixture), compared in pairs; expected units from an
-- independent count over the fixture rows
dofile("fixtures/fullscan-1121-2023.lua")
dofile("fixtures/fullscan-1121-2039.lua")
local function rowsToScan(rows)
  local scan = {}
  for _, r in ipairs(rows) do
    scan[r[1]] = scan[r[1]] or {}
    table.insert(scan[r[1]], tier(math.floor(r[3] / r[2] + 0.5), r[2], r[5], r[4]))
  end
  return scan
end
-- -> units sold over all items, items with sales, units of the given items
local function realPair(before, after, t1, t2, ids)
  VepIndustriesMarketDB = {}
  M.Ingest(rowsToScan(before), t1, "PvE", "Horde", "Boris")
  M.Ingest(rowsToScan(after), t2, "PvE", "Horde", "Boris")
  local function units(id) return math.floor((rate(id) or 0) * (t2 - t1) / 86400 + 0.5) end
  local total, selling, of = 0, 0, {}
  for id in pairs(rowsToScan(before)) do total, selling = total + units(id), selling + (units(id) > 0 and 1 or 0) end
  for i, id in ipairs(ids) do of[i] = units(id) end
  return total, selling, of
end
-- the first scan's time is unknown: compared as if 1 h apart (Short and Medium may expire)
local total, selling, of = realPair(FULLSCAN, FULLSCAN_1121_2023, FULLSCAN_1121_2023_TIME - 3600, FULLSCAN_1121_2023_TIME,
  { 2512, 5479, 3858, 11083 })
ok(total == 7165 and selling == 147 and of[1] == 0 and of[2] == 368 and of[3] == 1022 and of[4] == 863,
  string.format("scans reels, 1 h : %d unites vendues sur %d objets (fleches grossieres 2512 : %d, stock en hausse)",
    total, selling, of[1]))
-- consecutive autoscans 919 s apart (Short only may expire)
total, selling, of = realPair(FULLSCAN_1121_2023, FULLSCAN_1121_2039, FULLSCAN_1121_2023_TIME, FULLSCAN_1121_2039_TIME, { 2512, 4306 })
ok(total == 4227 and selling == 110 and of[1] == 0 and of[2] == 1315,
  string.format("scans reels consecutifs, 919 s : %d unites vendues sur %d objets", total, selling))

-- merge by Tranche: the cases shared with the server (tests/merge-cases.json, read by tests/run.cjs)
local function sameTranches(got, want)
  for id, ks in pairs(want) do
    for k, v in pairs(ks) do
      local g = got[id] and got[id][k]
      if not (g and math.abs(g[1] - v[1]) < 1e-6 and math.abs(g[2] - v[2]) < 1e-6) then return false end
    end
  end
  for id, ks in pairs(got) do
    for k in pairs(ks) do if not (want[id] and want[id][k]) then return false end end
  end
  return true
end
for _, case in ipairs(MERGE_CASES.cases) do ok(sameTranches(M.Merge(case.comparisons, 0), case.tranches), "fusion : " .. case.name) end

-- merge of the real Comparisons: alone, the scans' units; the same one by a second player, no more; a second
-- player 10 min later, between both
local function sold(tranches)
  local units = 0
  for _, ks in pairs(tranches) do for _, v in pairs(ks) do units = units + v[1] end end
  return math.floor(units + 0.5)
end
local real = VepIndustriesMarketDB.comparisons[1] -- 2023 -> 2039, 919 s, 4227 units
local twin = { author = "Ami", start = real.start, finish = real.finish, items = real.items }
local later = { author = "Ami", start = real.start + 600, finish = real.finish + 600, items = real.items }
ok(sold(M.Merge({ real }, DAY0)) == 4227 and sold(M.Merge({ real, twin }, DAY0)) == 4227
  and sameTranches(M.Merge({ real, twin }, DAY0), M.Merge({ real }, DAY0)),
  "fusion des scans reels : seul, 4227 unites ; meme Comparaison chez un ami, pas comptee deux fois")
-- 10 min later the friend's Comparison sits in the second Tranche only: the first keeps our share alone, the second
-- averages our share and all of the friend's units (same pair in tests/merge-cases.json, for the server)
local first = 1800 - (real.start - DAY0) % 1800
local expect = 4227 * (first / 919 + ((919 - first) / 919 + 1) / 2)
ok(sold(M.Merge({ real, later }, DAY0)) == math.floor(expect + 0.5),
  string.format("fusion des scans reels : ami decale de 10 min, moyenne sur la Tranche commune (%.1f)", expect))
-- the same pair as JSON, times from day 0: npm run merge-case writes it as the real case of tests/merge-cases.json
do
  local a = { author = "A", start = real.start - DAY0, finish = real.finish - DAY0, items = real.items }
  local b = { author = "B", start = a.start + 600, finish = a.finish + 600, items = real.items }
  local items = {}
  for id, ks in pairs(M.Merge({ a, b }, 0)) do
    local t = {}
    for k, v in pairs(ks) do t[#t + 1] = string.format('"%d": [%.17g, %.17g]', k, v[1], v[2]) end
    items[#items + 1] = string.format('"%d": { %s }', id, table.concat(t, ", "))
  end
  local function json(c)
    return string.format('{ "author": "%s", "start": %d, "finish": %d, "items": "%s" }', c.author, c.start, c.finish,
      c.items)
  end
  REAL_MERGE_CASE = string.format('{ "comparisons": [%s, %s], "tranches": { %s } }', json(a), json(b),
    table.concat(items, ", "))
end
-- size of a real Comparison, extrapolated to the whole scan: the most kept must fit the save
local kb = #real.items * FULLSCAN_TOTAL_ITEMS / FULLSCAN_ITEMS / 1000
ok(kb * M.MAX_COMPARISONS < 4000, string.format("Comparaison reelle : %d Ko extrapoles, %d Ko pour %d", math.floor(kb),
  math.floor(kb * M.MAX_COMPARISONS), M.MAX_COMPARISONS))

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
local frames, textures = {}, {}
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
  f.CreateTexture = texture
  local shown = false
  f.IsShown = function() return shown end
  f.Show = function() shown = true end
  f.Hide = function() shown = false end
  f.SetScript = function(self, script, fn) rawset(self, script, fn) end
  local events = {}
  f.RegisterEvent = function(_, e) events[e] = true end
  f.UnregisterEvent = function(_, e) events[e] = nil end
  f.IsEventRegistered = function(_, e) return events[e] == true end
  frames[#frames + 1] = f
  return f
end
local said = {}
print = function(s) said[#said + 1] = s end
local function lastSaid() return said[#said] or "" end
-- as the game: only to the frames registered for the event
local function fire(event, ...)
  for _, f in ipairs(frames) do
    local onEvent = rawget(f, "OnEvent")
    if onEvent and f:IsEventRegistered(event) then onEvent(f, event, ...) end
  end
end
local okLoad, err = pcall(function()
  dofile("../src/Libs/ChatThrottleLib.lua")
  local chunk = loadfile("../src/Capture.lua"); chunk("VepIndustriesMarket")
  dofile("../src/Exchange.lua")
  dofile("../src/UI.lua")
end)
ok(okLoad, "chargement ChatThrottleLib + Capture.lua + Exchange.lua + UI.lua " .. tostring(err))
ok(postCall ~= nil, "hook infobulle enregistre")
local lines = {}
local tip = GameTooltip
tip.AddDoubleLine = function(_, a, b) lines[#lines + 1] = a .. " || " .. b end
tip.AddLine = function(_, a) lines[#lines + 1] = a end
local okTip, e2 = pcall(postCall, tip, { id = 14048 })
ok(okTip and lines[1] == "|cffffd100Tendance 7 j|r || |cffff5959Saturé|r  prix |cff66ff66+8%|r  stock "
  .. "|cffff6666+190%|r |cff9d9d9d(2 j)|r", "ligne infobulle " .. tostring(e2) .. " " .. tostring(lines[1]))
local okNone = pcall(postCall, tip, { id = 999999 })
ok(okNone and #lines == 1, "pas de ligne infobulle pour un objet absent")
-- 933: no Auctionator history, sells 1 of 5 then 1 of 4
M.Ingest({ [4338] = { tier(100, 1, 9, 3) }, [933] = { tier(100, 1, 5, 3) } }, t0, "PvE", "Horde", "Boris")
M.Ingest({ [4338] = { tier(100, 1, 6, 3) }, [933] = { tier(100, 1, 4, 3) } }, t0 + 3600, "PvE", "Horde", "Boris")
postCall(tip, { id = 4338 })
ok(lines[2]:find("|cff9d9d9d≈ 72/jour|r", 1, true), "infobulle : ventes estimees grisees sous le seuil " .. lines[2])
M.Ingest({ [4338] = { tier(100, 1, 6, 3) }, [933] = { tier(100, 1, 4, 3) }, [997] = { tier(1, 1, 1, 3) } }, t2,
  "PvE", "Horde", "Boris")
M.Ingest({ [4338] = { tier(100, 1, 6, 3) }, [933] = { tier(100, 1, 3, 3) }, [998] = { tier(1, 1, 1, 3) } }, t3,
  "PvE", "Horde", "Boris")
postCall(tip, { id = 4338 })
ok(lines[3]:find("|cffffffff≈ 54/jour|r", 1, true), "infobulle : ventes estimees fiables " .. lines[3])
-- label colour: TITLE in src/UI.lua
ok(lines[2]:find("^|cffffd100Tendance 7 j|r") and lines[3]:find("^|cffffd100Ventes estimées 7 j|r")
  and lines[3]:find("(2 j)", 1, true), "infobulle : source du verdict et jours de ventes estimees " .. lines[3])
postCall(tip, { id = 933 })
ok(lines[4] and lines[4]:find("^|cffffd100Ventes estimées 7 j|r || |cff4cff4cDemande|r |cff9d9d9d%(2 j%)|r"),
  "infobulle : verdict des ventes sans historique Auctionator, sans tendance " .. tostring(lines[4]))
VepIndustriesMarketDB.fullScan, VepIndustriesMarketDB.daily, VepIndustriesMarketDB.comparisons = nil, nil, nil
local slow = VepIndustriesMarket.TrendText({ verdict = "none", trend = {}, estimatedSalesPerDay = 2.5 })
ok(slow:find("≈ 2,5/jour", 1, true), "infobulle : decimale sous 10/jour " .. slow)
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

-- /vim window: one estimated sales bar per compared day, from the real scan pairs replayed on earlier days; coloured
-- in the window of a reliable estimate, grey elsewhere (colours of src/UI.lua: SALES and COLOR.none)
local SALES, GREY = "0.30 0.90 0.40 0.70", "0.60 0.60 0.60 0.45"
local function salesBars(id)
  VepIndustriesMarket.ShowItem(id, true)
  local n, tallest = { [SALES] = 0, [GREY] = 0 }, 0
  for _, t in ipairs(textures) do
    if t.shown and n[t.color] then n[t.color], tallest = n[t.color] + 1, math.max(tallest, t.height) end
  end
  return { n[SALES], n[GREY], tallest }
end
local function dayAt(day, s) return DAY0 + day * 86400 + s end
local function pair(day, a, b, gap)
  M.Ingest(rowsToScan(a), dayAt(day, 72000), "PvE", "Horde", "Boris")
  M.Ingest(rowsToScan(b), dayAt(day, 72000 + gap), "PvE", "Horde", "Boris")
end
VepIndustriesMarketDB = {}
local okBars, e6 = pcall(function()
  pair(TODAY - 10, FULLSCAN_1121_2023, FULLSCAN_1121_2039, 919) -- consecutive autoscans, out of the 7-day window
  pair(TODAY - 3, FULLSCAN, FULLSCAN_1121_2023, 3600)
end)
local lone = salesBars(4306)
local okBars2 = pcall(pair, TODAY - 1, FULLSCAN, FULLSCAN_1121_2023, 3600)
local partly, none = salesBars(4306), salesBars(14048)
ok(okBars and okBars2 and lone[1] == 0 and lone[2] == 2, string.format(
  "fenetre : 1 jour de ventes estimees dans la fenetre, non fiable -> 2 barres grisees (%d, %d) %s", lone[1], lone[2],
  tostring(e6)))
ok(partly[1] == 2 and partly[2] == 1 and partly[3] == 120 and M.Report(4306).confidence == "high", string.format(
  "fenetre : 3 jours reels, 2 fiables -> 2 barres + 1 grisee hors fenetre, la plus haute a 120 (%d, %d, %s)",
  partly[1], partly[2], tostring(partly[3])))
ok(none[1] == 0 and none[2] == 0, "fenetre : objet sans ventes estimees -> aucune barre")

-- hovering a day of the graph lists its values (4306: Auctionator history on TODAY - 1, not on TODAY - 3 or - 10)
VepIndustriesMarket.ShowItem(4306, true)
local columns = {}
for _, fr in ipairs(frames) do
  if rawget(fr, "OnEnter") then columns[#columns + 1] = fr end
end
local function hover(daysAgo)
  local col = columns[#columns - daysAgo]
  lines = {}
  local okHover, e7 = pcall(function() rawget(col, "OnEnter")(col); rawget(col, "OnLeave")(col) end)
  return okHover and table.concat(lines, "\n") or tostring(e7)
end
local yesterday, older, oldest, empty = hover(1), hover(3), hover(10), hover(20)
ok(#columns == 21, "fenetre : une zone de survol par jour (" .. #columns .. ")")
ok(yesterday:find("il y a 1 j", 1, true) and yesterday:find("Prix minimum || 90|cffeda55fc|r", 1, true)
  and yesterday:find("Stock || 46558", 1, true) and yesterday:find("Ventes estimées || |cffffffff≈ ", 1, true),
  "survol d'hier : prix, stock et ventes estimees fiables\n" .. yesterday)
ok(older:find("Ventes estimées", 1, true) and not older:find("Stock", 1, true),
  "survol sans historique Auctionator : ventes estimees seules\n" .. older)
ok(oldest:find("pas fiable", 1, true), "survol d'un jour hors fenetre : ventes estimees non fiables\n" .. oldest)
ok(empty:find("Aucune donnée", 1, true), "survol d'un jour sans donnees\n" .. empty)
VepIndustriesMarketDB.fullScan, VepIndustriesMarketDB.daily, VepIndustriesMarketDB.comparisons = nil, nil, nil

-- Auctionator adapter, with API doubles
fire("ADDON_LOADED", "VepIndustriesMarket")
fire("PLAYER_LOGIN")
local full, incremental = LISTENERS["replicate_scan_complete"], LISTENERS["full_incremental_scan_complete"]
ok(full and incremental and not lastSaid():find("réglé"), "branche sur les scans d'Auctionator, bien regle")
SlashCmdList.VEPINDUSTRIESMARKET("status")
ok(lastSaid():find("Aucun Scan complet"), "/vim status sans scan : " .. lastSaid())

-- the reduced real scan, in the shape of Auctionator's ScanComplete data
local data = {}
for _, r in ipairs(FULLSCAN) do
  for _ = 1, r[5] do
    data[#data + 1] = { replicateInfo = { [3] = r[2], [10] = r[3], [17] = r[1] }, itemLink = "|Hitem:" .. r[1] .. "|h",
      timeLeft = r[4] }
  end
end
-- one game frame per queued timer, to see the scan spread over frames
local nextFrame = {}
C_Timer = { After = function(_, fn) nextFrame[#nextFrame + 1] = fn end }
local function runFrames()
  local n = 0
  while #nextFrame > 0 do
    n = n + 1
    table.remove(nextFrame, 1)()
  end
  return n
end
local okScan, e4 = pcall(full.ReceiveEvent, full, "replicate_scan_complete", data)
local early, started = M.Status(), lastSaid()
full:ReceiveEvent("replicate_scan_complete", data)
local busy = lastSaid()
local spread = runFrames()
ok(okScan and not early and started:find("en cours %(" .. #data .. " enchères%)") and busy:find("déjà en cours")
  and spread > #data / 2000,
  string.format("scan complet reel ingere sur %d images %s", spread, tostring(e4)))
local checked = { -- itemID = tiers, price, stock, cheapest tier (price, size, count, timeLeft), counted by hand in the raw scan
  [5500] = { 389, 811, 1517, { 811, 1, 3, 3 } },
  [4306] = { 401, 194, 21599, { 194, 20, 1, 2 } },
  [20746] = { 18, 1074, 604, { 1074, 1, 1, 3 } },
}
for id, e in pairs(checked) do
  local r = M.Report(id)
  local t, day = r.tiers[1] or {}, r.daily[TODAY] or {}
  ok(#r.tiers == e[1] and day.price == e[2] and day.stock == e[3] and day.scans == 1 and t.price == e[4][1]
    and t.size == e[4][2] and t.count == e[4][3] and t.timeLeft == e[4][4],
    string.format("%d: %d paliers, prix min %s, stock %s", id, #r.tiers, tostring(day.price), tostring(day.stock)))
end
local mixed = {} -- 20746 at 1088 per unit: 161 auctions of one, 28 Short, 108 Long, 25 Very long
for _, t in ipairs(M.Report(20746).tiers) do
  if t.price == 1088 and t.size == 1 then mixed[t.timeLeft] = t.count end
end
ok(mixed[1] == 28 and mixed[3] == 108 and mixed[4] == 25 and not mixed[2], "palier reel separe par temps restant")
local st = M.Status()
local fullSize = st.bytes * FULLSCAN_TOTAL_ITEMS / FULLSCAN_ITEMS
ok(st.realm == "PvE" and st.faction == "Horde", "scan rattache au royaume et a la faction")
ok(st.items == FULLSCAN_ITEMS and fullSize < 1e6,
  string.format("%d objets, %d Ko extrapoles a %d objets", st.items, math.floor(fullSize / 1000), FULLSCAN_TOTAL_ITEMS))
SlashCmdList.VEPINDUSTRIESMARKET("status")
ok(lastSaid():find(FULLSCAN_ITEMS .. " objets"), "/vim status : " .. lastSaid())

-- /vim relire: the same scan read again from the client's memory counts as a second scan of the day
C_AuctionHouse = {
  GetNumReplicateItems = function() return #data end,
  GetReplicateItemInfo = function(i) return table.unpack(data[i + 1].replicateInfo, 1, 17) end,
  GetReplicateItemTimeLeft = function(i) return data[i + 1].timeLeft end,
}
SlashCmdList.VEPINDUSTRIESMARKET("relire"); runFrames()
local again = M.Report(5500)
ok(lastSaid():find(FULLSCAN_ITEMS .. " objets") and #again.tiers == 389 and again.daily[TODAY].scans == 2
  and again.daily[TODAY].stock == 1517, "/vim relire : scan en memoire enregistre, 2 scans dans la journee")
C_AuctionHouse.GetNumReplicateItems = function() return 0 end
SlashCmdList.VEPINDUSTRIESMARKET("relire")
ok(lastSaid():find("aucun Scan complet en mémoire"), "/vim relire sans scan en memoire")

-- opening the auction house loads the data file (VepIndustriesMarket_Data, load on demand) once, and tells a file
-- that a stopped Sync script left behind
local loads = {}
C_AddOns = { LoadAddOn = function(name)
  loads[#loads + 1] = name
  VepIndustriesMarketData = { generated = time() - 5 * 86400, daily = {}, counted = {} }
  return true
end }
fire("AUCTION_HOUSE_SHOW"); fire("AUCTION_HOUSE_SHOW")
ok(#loads == 1 and loads[1] == "VepIndustriesMarket_Data" and lastSaid():find("5 jours")
  and lastSaid():find("installer.cmd"), "Script de synchro arrete signale a l'ouverture de l'hotel des ventes " .. lastSaid())
local seen = VepIndustriesMarketDB.dataFile
ok(seen and seen.generated == time() - 5 * 86400 and seen.items == 0, "fichier charge note dans la sauvegarde (npm run report)")
ok(M.Report(5500).daily[TODAY].scans == 2, "fichier de donnees vide : notre resume journalier garde")
VepIndustriesMarketData = nil

-- incremental scan: warned once
local before = #said
incremental:ReceiveEvent("full_incremental_scan_complete", {})
incremental:ReceiveEvent("full_incremental_scan_complete", {})
ok(#said == before + 1 and lastSaid():find("incrémental"), "scan incremental : un seul avertissement")

-- Auctionator without autoscan or replicate mode: told at login
AUCTIONATOR_CONFIG.autoscan_2 = false
fire("PLAYER_LOGIN")
ok(lastSaid():find("pas réglé") and lastSaid():find("Run autoscan"), "Auctionator mal regle : prevenu a la connexion")

-- Auctionator not loaded
Auctionator = nil
local okNo, e5 = pcall(fire, "PLAYER_LOGIN")
ok(okNo and lastSaid():find("Auctionator absent"), "sans Auctionator : message sans erreur " .. tostring(e5))
Auctionator = auctionator

-- exchange in game (#24): scripted guild members against our addon, through the real ChatThrottleLib and the doubles
-- of C_ChatInfo. A game frame of 0.05 s runs the timers due, then ChatThrottleLib's OnUpdate.
local X = VepIndustriesMarket.Exchange
local timers = {}
C_Timer = { After = function(delay, fn) timers[#timers + 1] = { at = chat.clock + delay, fn = fn } end }
local function play(seconds)
  local stop = chat.clock + seconds
  while chat.clock < stop do
    chat.clock = chat.clock + 0.05
    local due, later = {}, {}
    for _, t in ipairs(timers) do
      if t.at <= chat.clock then due[#due + 1] = t else later[#later + 1] = t end
    end
    timers = later
    for _, t in ipairs(due) do t.fn() end
    local ctl = ChatThrottleLib.Frame
    if ctl:IsShown() then rawget(ctl, "OnUpdate")(ctl, 0.05) end
  end
end
local function heard(text, channel, sender) fire("CHAT_MSG_ADDON", X.PREFIX, text, channel, sender) end
local function whisper(texts, sender, from, to)
  for k = from or 1, to or #texts do heard(texts[k], "WHISPER", sender) end
end
-- our whispers to `name` since the outbox was emptied, of `kind` and `key` when given: { i, n, key, data, size, at }
local function to(name, kind, key)
  local got = {}
  for _, m in ipairs(chat.outbox) do
    local k, i, n, mkey, data = m.text:match("^(%u)(%d+) (%d+) ([^\t]*)\t(.*)$")
    if m.target == name and (not kind or k == kind) and (not key or mkey == key) then
      got[#got + 1] = { i = tonumber(i), n = tonumber(n), key = mkey, data = data, size = #m.text, at = m.at }
    end
  end
  return got
end
-- the payload of whole messages, in order, nil when one is missing or out of place
local function payload(msgs)
  local data = {}
  for k, m in ipairs(msgs) do
    if m.i ~= k or m.n ~= #msgs then return nil end
    data[k] = m.data
  end
  return #msgs > 0 and X.Unpack(table.concat(data)) or nil
end
local function guild()
  local last
  for _, m in ipairs(chat.outbox) do if m.channel == "GUILD" then last = m.text end end
  return last
end

VepIndustriesMarketDB, VepIndustriesMarketData = {}, nil
M.Ingest(rowsToScan(FULLSCAN_1121_2023), t2, "PvE", "Horde", "Boris")
M.Ingest(rowsToScan(FULLSCAN_1121_2039), t2 + 919, "PvE", "Horde", "Boris")
local mine = VepIndustriesMarketDB.comparisons[1]
local MINE = "Boris " .. t2
local theirs = { author = "Ami", realm = "PvE", faction = "Horde", start = t2 + 600, finish = t2 + 1519, items = mine.items }
local THEIRS = "Ami " .. theirs.start
local packed = X.Pack("C", THEIRS, X.Encode(theirs))
play(10); chat.outbox = {} -- the announces of the tests above

fire("PLAYER_LOGIN"); play(15)
ok(guild() == "A 0 " .. (t2 + 919), "echange : annonce en guilde a la connexion " .. tostring(guild()))
chat.outbox = {}
heard("A 0 " .. theirs.finish, "GUILD", "Ami Epice"); play(1)
ok(payload(to("Ami-Epice", "W")) == "1 0\n" .. MINE, "echange : annonce entendue -> inventaire chuchote, au nom Prenom-Nom")
heard("A 0 0", "GUILD", "Boris"); heard("A 0 " .. theirs.finish, "PARTY", "Ami Epice")
ok(#to("Boris") == 0 and #to("Ami-Epice") == 1, "echange : notre propre annonce et les autres canaux ignores")

-- the friend's inventory lacks ours and lists one of theirs: ours goes, cut into messages, then our inventory
chat.outbox = {}
whisper(X.Pack("W", "", "1 0\n" .. THEIRS), "Ami Epice"); play(60)
local sent, small = to("Ami-Epice", "C", MINE), true
for _, m in ipairs(sent) do small = small and m.size <= 255 end
ok(#sent > 10 and small and payload(sent) == X.Encode(mine),
  string.format("echange : Comparaison decoupee en %d messages de 255 octets au plus, reassemblee a l'identique", #sent))
ok(payload(to("Ami-Epice", "W")) == "0 0\n" .. MINE, "echange : notre inventaire en retour, l'autre ayant ce qui nous manque")
local mineTexts = {}
for k, m in ipairs(chat.outbox) do if m.text:find("^C") then mineTexts[#mineTexts + 1] = m.text end end

-- the same Comparison sent back: already known, ignored; reassembled by a guild member without it, kept and announced
whisper(mineTexts, "Ami Epice"); play(2)
ok(#VepIndustriesMarketDB.comparisons == 1, "echange : Comparaison deja connue ignoree")
local ours = VepIndustriesMarketDB
VepIndustriesMarketDB, chat.outbox = {}, {}
whisper(mineTexts, "Tiers Nom"); play(2)
local got = VepIndustriesMarketDB.comparisons and VepIndustriesMarketDB.comparisons[1] or {}
local early = guild()
play(60)
ok(got.author == "Boris" and got.start == t2 and got.finish == t2 + 919 and got.items == mine.items
  and not early and guild() == "A 0 " .. (t2 + 919),
  "echange : Comparaison reassemblee chez un autre, gardee, annoncee une minute apres la derniere recue")
VepIndustriesMarketDB = ours
-- before the auction house loads the data file, the time of the one the previous session loaded
chat.outbox, VepIndustriesMarketDB.dataGenerated = {}, t2 - 600
heard("A 0 " .. theirs.finish, "GUILD", "Ami Epice"); play(1)
ok(payload(to("Ami-Epice", "W")) == "1 " .. (t2 - 600) .. "\n" .. MINE,
  "echange : fichier de donnees pas encore charge, heure de celui de la session precedente")
VepIndustriesMarketDB.dataGenerated = nil

-- a transfer cut after 5 messages (the friend logged out): our next inventory tells it, the rest completes it
chat.outbox = {}
whisper(packed, "Ami Epice", 1, 5)
heard("A 0 " .. theirs.finish, "GUILD", "Ami Epice"); play(1)
local inv = payload(to("Ami-Epice", "W")) or ""
ok(inv:find("\n" .. THEIRS .. " 5", 1, true), "echange : transfert interrompu, inventaire avec les morceaux recus " .. inv)
chat.outbox = {}
whisper(packed, "Ami Epice", 6); play(61)
ok(#VepIndustriesMarketDB.comparisons == 2 and M.Seen()[THEIRS] == theirs.finish and guild() == "A 0 " .. theirs.finish,
  "echange : transfert repris, Comparaison gardee et annoncee (relais)")
-- our side resumed: the friend got 20 messages of ours
chat.outbox = {}
whisper(X.Pack("W", "", "0 0\n" .. THEIRS .. "\n" .. MINE .. " 20"), "Ami Epice"); play(60)
sent = to("Ami-Epice", "C", MINE)
ok(#sent > 0 and sent[1].i == 21 and sent[#sent].i == sent[1].n and #sent == sent[1].n - 20,
  "echange : notre envoi repris au 21e message")
-- the friend reloaded during our transfer: its new inventory, without the chunks it lost, restarts it
chat.outbox = {}
whisper(X.Pack("W", "", "0 0\n" .. MINE), "Huit Nom"); play(3)
local cut = #to("Huit-Nom", "C", THEIRS)
chat.outbox = {}
whisper(X.Pack("W", "", "0 0\n" .. MINE), "Huit Nom"); play(60)
ok(cut > 0 and cut < #packed and payload(to("Huit-Nom", "C", THEIRS)) == X.Encode(theirs),
  "echange : destinataire relance pendant l'envoi, envoi repris du debut")

-- relay: a member who has none gets ours and the friend's; one whose data file is newer than ours, the friend's only
chat.outbox = {}
whisper(X.Pack("W", "", "0 0"), "Tiers Nom"); whisper(X.Pack("W", "", "0 " .. (t2 + 1000)), "Quatre Nom"); play(120)
ok(payload(to("Tiers-Nom", "C", MINE)) == X.Encode(mine) and payload(to("Tiers-Nom", "C", THEIRS)) == X.Encode(theirs),
  "echange : Comparaison recue retransmise (relais)")
ok(#to("Quatre-Nom", "C", MINE) == 0 and payload(to("Quatre-Nom", "C", THEIRS)) == X.Encode(theirs),
  "echange : seules les Comparaisons posterieures au fichier de donnees de l'autre")

-- refusals: for rate (3, 8), then a lockdown (InChatMessagingLockdown, code 11); sent again later, nothing lost
chat.outbox, chat.refuse = {}, { 3, 3, 3, 8, 8 }
whisper(X.Pack("W", "", "0 0\n" .. MINE), "Cinq Nom"); play(60)
ok(#chat.refuse == 0 and payload(to("Cinq-Nom", "C", THEIRS)) == X.Encode(theirs), "echange : refus pour debit puis reprise")
chat.outbox, chat.locked = {}, true
whisper(X.Pack("W", "", "0 0\n" .. MINE), "Six Nom"); play(20)
local during = #to("Six-Nom")
chat.locked, chat.refuse = false, { 11, 11 }
play(60)
ok(during == 0 and #chat.refuse == 0 and payload(to("Six-Nom", "C", THEIRS)) == X.Encode(theirs),
  "echange : blocage puis reprise")

-- in an instance, a whisper a second at most (prefix allowance, wiki); outside, ChatThrottleLib's pace (~800 bytes/s)
local function gaps(msgs)
  local least, span = math.huge, msgs[#msgs].at - msgs[1].at
  for k = 2, #msgs do least = math.min(least, msgs[k].at - msgs[k - 1].at) end
  return least, span
end
local _, outside = gaps(to("Six-Nom", "C", THEIRS))
chat.outbox, chat.instance = {}, true
whisper(X.Pack("W", "", "0 0\n" .. MINE), "Sept Nom"); play(#packed + 10)
chat.instance = nil
local least = gaps(to("Sept-Nom", "C", THEIRS))
ok(payload(to("Sept-Nom", "C", THEIRS)) and least >= 0.95 and outside < #packed * 0.6,
  string.format("echange : en instance, %.2f s au moins entre deux messages ; hors instance, %d messages en %.1f s",
    least, #packed, outside))

-- the friend left: the game's "No player named ..." is hidden and the transfer stops; other lines stay
chat.outbox = {}
whisper(X.Pack("W", "", "0 0\n" .. MINE), "Parti Loin"); play(3)
local before = #to("Parti-Loin")
local filter = chat.filters.CHAT_MSG_SYSTEM
local hidden = filter and filter(nil, "CHAT_MSG_SYSTEM", ERR_CHAT_PLAYER_NOT_FOUND_S:format("Parti Loin"))
local shown = filter and filter(nil, "CHAT_MSG_SYSTEM", ERR_CHAT_PLAYER_NOT_FOUND_S:format("Inconnu"))
play(30)
ok(before > 0 and hidden and not shown and #to("Parti-Loin") <= before + 1 and #to("Parti-Loin") < #packed,
  "echange : « No player named » filtre pour un destinataire parti, transfert arrete (sauf le message deja confie a ChatThrottleLib)")
ok(not chat.error, "echange : aucune erreur de ChatThrottleLib " .. tostring(chat.error))
print = out

ok(not yieldInPcall, "aucune coroutine ne cede dans un pcall (refuse par le Lua 5.1 du jeu) " .. tostring(yieldInPcall))

if fails > 0 then error(fails .. " echec(s)", 0) end
print("TOUT OK")
