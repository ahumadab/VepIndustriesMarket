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
-- each tooltip: "Conseil" (the advice) then the trend line, or the sales figures alone once there is a time to sell
local function tooltipOf(id)
  for k in pairs(lines) do lines[k] = nil end
  local okCall, e = pcall(postCall, tip, { id = id })
  return okCall and lines or { tostring(e) }
end
local t1 = tooltipOf(14048)
ok(t1[1] == "|cffffd100Conseil|r || |cff9d9d9dPas encore assez de scans pour conseiller|r"
  and t1[2] == "|cffffd100Tendance 7 j|r || |cffff5959Saturé|r  prix |cff66ff66+8%|r  stock "
  .. "|cffff6666+190%|r |cff9d9d9d(2 j)|r", "infobulle sans ventes : conseil d'attendre, ligne de tendance " .. tostring(t1[2]))
ok(#tooltipOf(999999) == 0, "pas de ligne infobulle pour un objet absent")
-- 933: no Auctionator history, sells 1 of 5 then 1 of 4
M.Ingest({ [4338] = { tier(100, 1, 9, 3) }, [933] = { tier(100, 1, 5, 3) } }, t0, "PvE", "Horde", "Boris")
M.Ingest({ [4338] = { tier(100, 1, 6, 3) }, [933] = { tier(100, 1, 4, 3) } }, t0 + 3600, "PvE", "Horde", "Boris")
local t2l = tooltipOf(4338)
ok(t2l[1]:find("^|cffffd100Conseil|r") and t2l[1]:find("à confirmer", 1, true)
  and t2l[2]:find("^|cffffd100Tendance 7 j|r || |cff9d9d9d≈ 72/jour|r"),
  "infobulle : conseil a confirmer, ventes estimees grisees sous le seuil " .. t2l[1] .. " / " .. t2l[2])
M.Ingest({ [4338] = { tier(100, 1, 6, 3) }, [933] = { tier(100, 1, 4, 3) }, [997] = { tier(1, 1, 1, 3) } }, t2,
  "PvE", "Horde", "Boris")
M.Ingest({ [4338] = { tier(100, 1, 6, 3) }, [933] = { tier(100, 1, 3, 3) }, [998] = { tier(1, 1, 1, 3) } }, t3,
  "PvE", "Horde", "Boris")
local t3l = tooltipOf(4338)
-- label colour: TITLE in src/UI.lua
ok(t3l[1]:find("^|cffffd100Conseil|r || ") and not t3l[1]:find("confirmer", 1, true)
  and t3l[2] == "|cffffd100Ventes estimées 7 j|r || |cffffffff≈ 54/jour|r|cffffffff · ≈ 54"
  .. "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t/jour|r",
  "infobulle : conseil fiable, puis ventes estimees seules " .. t3l[1] .. " / " .. t3l[2])
local t4 = tooltipOf(933)
ok(t4[2] and t4[2]:find("^|cffffd100Ventes estimées 7 j|r || |cffffffff≈ "),
  "infobulle : ventes estimees sans historique Auctionator " .. tostring(t4[2]))
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
-- advice sentence (VepIndustriesMarket.AdviceText): one case each
local A = VepIndustriesMarket.AdviceText
local fast = { { price = 449, ahead = 0, seconds = 600 }, { price = 472, ahead = 700, seconds = 2 * 3600 },
  { price = 495, ahead = 4200, seconds = 11 * 3600 } }
local slow3 = { { price = 197, ahead = 0, seconds = 600 }, { price = 207, ahead = 14000, seconds = 36 * 3600 },
  { price = 217, ahead = 15000, seconds = 40 * 3600 } }
local demand = A({ verdict = "demand", selling = fast, confidence = "high", estimatedSalesPerDay = 18000 })
ok(demand:find("Bonne vente", 1, true) and demand:find("vends à 4", 1, true) and demand:find("95", 1, true)
  and demand:find("parti en ~11 h", 1, true) and not demand:find("confirmer", 1, true),
  "conseil demande : le prix le plus haut qui part en 12 h " .. demand)
local stable = A({ verdict = "stable", selling = slow3, confidence = "high", estimatedSalesPerDay = 1500 })
ok(stable:find("Vente correcte", 1, true) and stable:find("parti en < 1 h", 1, true),
  "conseil stable : au plus bas quand +5 % attend plus de 12 h " .. stable)
local sat = A({ verdict = "saturated", selling = slow3, confidence = "high", estimatedSalesPerDay = 1000,
  tiers = { { price = 197, size = 20, count = 450 } } })
ok(sat:find("Marché saturé", 1, true) and sat:find("> 7 j de stock devant toi", 1, true),
  "conseil sature : jours de stock " .. sat)
local dead = A({ verdict = "saturated", selling = slow3, confidence = "high", estimatedSalesPerDay = 0, tiers = {} })
ok(dead:find("rien ne se vend", 1, true), "conseil sature sans vente " .. dead)
ok(A({ verdict = "demand", trend = {} }):find("Pas encore assez de scans", 1, true), "conseil sans temps pour vendre")
local unsure = A({ verdict = "stable", selling = fast, confidence = "low", estimatedSalesSeconds = 5 * 3600 })
ok(unsure:find("(5 h de mesures, à confirmer)", 1, true), "conseil non fiable : duree mesuree " .. unsure)
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

