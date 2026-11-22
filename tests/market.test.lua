-- Market (Trend.lua, Market.lua): verdicts, full scans and Comparisons (M.Ingest), the Sync script's data file,
-- Comparisons received in game, merge by Tranche. Run in order: each M.Ingest is compared with the full scan stored
-- by the previous one. A new scan goes in a block of its own, opened with VepIndustriesMarketDB = {}, so the blocks
-- after it keep their chain of scans.
dofile("fixtures/realdata.lua")
dofile("fixtures/fullscan.lua")
dofile("fixtures/fullscan-1121-2023.lua")
dofile("fixtures/fullscan-1121-2039.lua")
loadAddonFile("Trend.lua")
loadAddonFile("Market.lua")
local M = VepIndustriesMarket.Market

-- fabricated histories: { {day, price, stock}, ... } in Auctionator's shape, under a fake itemID
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
-- a day the file holds no sales for (scans before the Sync script, their Comparisons dropped since) keeps ours:
-- the real case of Runecloth on 2026-11-22, 1 037 units over 7 970 s the day before the file's only day
VepIndustriesMarketDB.daily[942][TODAY - 1] = "500 22006 10 1037 7970"
VepIndustriesMarketDB.daily[942][TODAY - 2] = "500 20000 2 5 1200"
VepIndustriesMarketData.daily[942][TODAY - 2] = "450 21000 1" -- price and stock only, no compared time
local before = M.Report(942).daily
ok(before[TODAY - 1].estimatedSales == 1037 and before[TODAY - 1].seconds == 7970,
  "fichier de donnees sans ce jour : nos ventes gardees")
ok(before[TODAY - 2].estimatedSales == 5 and before[TODAY - 2].seconds == 1200 and before[TODAY - 2].price == 450,
  "fichier de donnees sans ventes ce jour : nos ventes gardees, son prix pris")
ok(near(before[TODAY].estimatedSales, 7) and before[TODAY].seconds == 5400, "jour du fichier : inchange")
VepIndustriesMarketDB.daily[942][TODAY - 1], VepIndustriesMarketDB.daily[942][TODAY - 2] = nil, nil
VepIndustriesMarketData.daily[942][TODAY - 2] = nil
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
out(string.format("donnees reelles: %d objets -> demande %d, stable %d, sature %d, none %d", n,
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
