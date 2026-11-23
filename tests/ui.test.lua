-- Interface (UI.lua): tooltip line, /vim window and its commands, estimated sales bars, hovering a day of the graph.
dofile("fixtures/realdata.lua")
dofile("fixtures/fullscan.lua")
dofile("fixtures/fullscan-1121-2023.lua")
dofile("fixtures/fullscan-1121-2039.lua")
local t0, t2 = time() - 86400, time() - 3600 -- yesterday 01:00, today 00:00
local t3 = t2 + 1200
VepIndustriesMarketDB = {}
local okLoad, err = pcall(loadAddon)
ok(okLoad, "chargement des fichiers de l'addon " .. tostring(err))
local M, postCall = VepIndustriesMarket.Market, TOOLTIP_POST_CALL
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
ok(lines[4]:find("|cffffffff≈ 54/jour|r", 1, true), "infobulle : ventes estimees fiables " .. lines[4])
-- label colour: TITLE in src/UI.lua
ok(lines[2]:find("^|cffffd100Tendance 7 j|r") and lines[4]:find("^|cffffd100Ventes estimées 7 j|r")
  and lines[4]:find("(2 j)", 1, true), "infobulle : source du verdict et jours de ventes estimees " .. lines[4])
local COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"
ok(lines[3]:find("|cffffd100Vendu en|r || 99" .. COPPER .. "|cff9d9d9d  ", 1, true) and lines[5]
  and lines[5]:find("|cffffd100Vendu en|r || 99" .. COPPER .. "|cffffffff  ", 1, true) ~= nil,
  "infobulle : temps pour vendre sous la ligne du verdict, grise puis fiable " .. tostring(lines[5]))
postCall(tip, { id = 933 })
ok(lines[6] and lines[6]:find("^|cffffd100Ventes estimées 7 j|r || |cff4cff4cDemande|r |cff9d9d9d%(2 j%)|r"),
  "infobulle : verdict des ventes sans historique Auctionator, sans tendance " .. tostring(lines[6]))
VepIndustriesMarketDB.fullScan, VepIndustriesMarketDB.daily, VepIndustriesMarketDB.comparisons = nil, nil, nil
local slow = VepIndustriesMarket.TrendText({ verdict = "none", trend = {}, estimatedSalesPerDay = 2.5 })
ok(slow:find("≈ 2,5/jour", 1, true), "infobulle : decimale sous 10/jour " .. slow)
local busy = VepIndustriesMarket.TrendText({ verdict = "demand", trend = {}, estimatedSalesPerDay = 18000,
  goldPerDay = 18000 * 450, confidence = "high" })
ok(busy:find("|cffffffff · ≈ 810|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t/jour|r", 1, true), "infobulle : valeur vendue par jour en or, fiable " .. busy)
local small = VepIndustriesMarket.TrendText({ verdict = "none", trend = {}, estimatedSalesPerDay = 30, goldPerDay = 4500 })
ok(small:find("|cff9d9d9d · ≈ 45|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t/jour|r", 1, true), "infobulle : sous 1g en argent, grisee si non fiable " .. small)
local twoLines = VepIndustriesMarket.TrendText({ verdict = "demand", trend = {}, estimatedSalesPerDay = 18000,
  goldPerDay = 18000 * 450, confidence = "high" }, "\n")
ok(twoLines:find("|r\n|cffffffff≈ 18000/jour|r", 1, true), "fenetre : ventes estimees sur leur propre ligne " .. twoLines)
local selling = { { price = 449, ahead = 0, seconds = 600 }, { price = 472, ahead = 700, seconds = 3 * 3600 },
  { price = 495, ahead = 4200, seconds = 9 * 86400 } }
local tipSell = VepIndustriesMarket.SellText({ selling = selling, confidence = "high" })
ok(tipSell and tipSell:find("< 1 h", 1, true) and not tipSell:find("~3 h", 1, true), "infobulle : temps au plus bas " .. tostring(tipSell))
local winSell = VepIndustriesMarket.SellText({ selling = selling, confidence = "low" }, true)
ok(winSell and winSell:find("< 1 h", 1, true) and winSell:find("~3 h", 1, true) and winSell:find("> 7 j", 1, true)
  and winSell:find("|cff9d9d9d", 1, true), "fenetre : trois prix, grises si non fiable " .. tostring(winSell))
ok(select(2, winSell:gsub("\n", "")) == 2 and winSell:sub(1, 6) == "    - ", "fenetre : un prix par ligne, indente")
ok(VepIndustriesMarket.SellText({}) == nil, "sans temps pour vendre : rien")
local none = VepIndustriesMarket.TrendText({ verdict = "none", trend = {}, estimatedSalesPerDay = 0, goldPerDay = 0,
  scarce = true })
ok(not none:find("/jour", 1, true), "infobulle : pas de valeur vendue sous pas assez de scans " .. none)
local scarce = VepIndustriesMarket.TrendText({ verdict = "none", trend = {}, estimatedSalesPerDay = 0, scarce = true })
ok(scarce:find("pas assez de scans", 1, true) and not scarce:find("≈", 1, true),
  "infobulle : moins d'une heure comparee -> pas assez de scans, pas de 0/jour " .. scarce)
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
ok(yesterday:find("il y a 1 j", 1, true) and yesterday:find("Prix minimum || 90|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t", 1, true)
  and yesterday:find("Stock || 46558", 1, true) and yesterday:find("Ventes estimées || |cffffffff≈ ", 1, true),
  "survol d'hier : prix, stock et ventes estimees fiables\n" .. yesterday)
ok(older:find("Ventes estimées", 1, true) and not older:find("Stock", 1, true),
  "survol sans historique Auctionator : ventes estimees seules\n" .. older)
ok(oldest:find("pas assez de scans", 1, true) and not oldest:find("≈", 1, true),
  "survol d'un jour de 15 min comparees : pas assez de scans\n" .. oldest)
ok(empty:find("Aucune donnée", 1, true), "survol d'un jour sans donnees\n" .. empty)
VepIndustriesMarketDB.fullScan, VepIndustriesMarketDB.daily, VepIndustriesMarketDB.comparisons = nil, nil, nil

