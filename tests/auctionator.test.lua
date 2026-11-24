-- Branching on Auctionator (Capture.lua): its full scans ingested over game frames, /vim status and /vim relire,
-- the data file loaded when the auction house opens, Auctionator's settings checked at login.
dofile("fixtures/fullscan.lua")
VepIndustriesMarketDB = {}
loadAddon()
local M = VepIndustriesMarket.Market
fire("ADDON_LOADED", "VepIndustriesMarket")
fire("PLAYER_LOGIN")
local full, incremental = LISTENERS["replicate_scan_complete"], LISTENERS["full_incremental_scan_complete"]
ok(full and incremental and not lastSaid():find("réglé"), "branche sur les scans d'Auctionator, bien regle")
SlashCmdList.VEPINDUSTRIESMARKET("status")
ok(lastSaid():find("Aucun Scan complet"), "/vim status sans scan : " .. lastSaid())

-- the reduced real scan, in the shape of Auctionator's ScanComplete data; item links as the English client gives them
-- (the fixture holds no name: "Item <id>" stands for it)
local data = {}
for _, r in ipairs(FULLSCAN) do
  for _ = 1, r[5] do
    data[#data + 1] = { replicateInfo = { [3] = r[2], [10] = r[3], [17] = r[1] },
      itemLink = "|cffffffff|Hitem:" .. r[1] .. "::::::::60:::::::|h[Item " .. r[1] .. "]|h|r", timeLeft = r[4] }
  end
end
-- a real link of the English client, with a quote and an apostrophe; and a link without a name, ignored
data[1].itemLink = "|cff1eff00|Hitem:" .. FULLSCAN[1][1] .. "::::::::60:::::::|h[Smith's \"Best\" Hammer]|h|r"
data[#data + 1] = { replicateInfo = { [3] = 1, [10] = 100, [17] = 999999 }, itemLink = "|Hitem:999999|h", timeLeft = 4 }
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
ok(lastSaid():find("premier scan, rien à comparer") and lastSaid():find("Prochain scan utile entre %d%d:%d%d et %d%d:%d%d"),
  "fin de scan : resultat et plage du prochain scan utile " .. lastSaid())
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
ok(st.items == FULLSCAN_ITEMS + 1 and fullSize < 1e6,
  string.format("%d objets, %d Ko extrapoles a %d objets", st.items, math.floor(fullSize / 1000), FULLSCAN_TOTAL_ITEMS))
local names, named = VepIndustriesMarketDB.names or {}, 0
for _ in pairs(names) do named = named + 1 end
ok(named == FULLSCAN_ITEMS and names[5500] == "Item 5500" and names[FULLSCAN[1][1]] == "Smith's \"Best\" Hammer"
  and not names[999999], string.format("noms anglais lus dans les liens : %d objets nommes", named))
SlashCmdList.VEPINDUSTRIESMARKET("status")
ok(lastSaid():find(FULLSCAN_ITEMS + 1 .. " objets"), "/vim status : " .. lastSaid())

-- /vim relire: the same scan read again from the client's memory counts as a second scan of the day, names included
VepIndustriesMarketDB.names = nil
C_AuctionHouse = {
  GetNumReplicateItems = function() return #data end,
  GetReplicateItemInfo = function(i) return table.unpack(data[i + 1].replicateInfo, 1, 17) end,
  GetReplicateItemLink = function(i) return data[i + 1].itemLink end,
  GetReplicateItemTimeLeft = function(i) return data[i + 1].timeLeft end,
}
SlashCmdList.VEPINDUSTRIESMARKET("relire"); runFrames()
local again = M.Report(5500)
ok(lastSaid():find(FULLSCAN_ITEMS + 1 .. " objets, identique au précédent") and #again.tiers == 389
  and again.daily[TODAY].scans == 2 and again.daily[TODAY].stock == 1517
  and (VepIndustriesMarketDB.names or {})[5500] == "Item 5500",
  "/vim relire : scan en memoire enregistre, 2 scans dans la journee, noms repris")
C_AuctionHouse.GetNumReplicateItems = function() return 0 end
SlashCmdList.VEPINDUSTRIESMARKET("relire")
ok(lastSaid():find("aucun Scan complet en mémoire"), "/vim relire sans scan en memoire")

-- opening the auction house loads the data file (VepIndustriesMarket_Data, load on demand) once, and tells a file
-- that a stopped Sync script left behind
local loads = {}
C_AddOns.LoadAddOn = function(name)
  loads[#loads + 1] = name
  VepIndustriesMarketData = { generated = time() - 5 * 86400, daily = {}, counted = {} }
  return true
end
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
local auctionator = Auctionator
Auctionator = nil
local okNo, e5 = pcall(fire, "PLAYER_LOGIN")
ok(okNo and lastSaid():find("Auctionator absent"), "sans Auctionator : message sans erreur " .. tostring(e5))
Auctionator = auctionator

