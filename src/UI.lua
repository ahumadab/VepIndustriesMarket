-- VepIndustriesMarket UI: trend line in item tooltips + a small window with price (line), stock and estimated sales
-- per day (bars, each on its own scale) over the history.
local GM = VepIndustriesMarket
local M = GM.Market

local LABEL = { demand = "Demande", stable = "Stable", saturated = "Saturé", none = "Pas assez de données" }
local COLOR = {
    demand = { 0.30, 1.00, 0.30 },
    stable = { 1.00, 0.85, 0.20 },
    saturated = { 1.00, 0.35, 0.35 },
    none = { 0.60, 0.60, 0.60 },
}
local PRICE, STOCK, SALES = { 1.00, 0.82, 0.00 }, { 0.45, 0.70, 1.00 }, { 0.30, 0.90, 0.40 }
local TITLE = { 1.00, 0.82, 0.00 } -- tooltip label, the game's gold
-- text only: muted (not reliable, day counts), bright (reliable values), a % change (neutral, good, bad), coins
local TEXT = { muted = { 0.616, 0.616, 0.616 }, bright = { 1.00, 1.00, 1.00 }, neutral = { 0.80, 0.80, 0.80 },
    good = { 0.40, 1.00, 0.40 }, bad = { 1.00, 0.40, 0.40 } }
local COIN = { g = { 1.00, 0.844, 0.00 }, s = { 0.781, 0.781, 0.812 }, c = { 0.93, 0.648, 0.373 } }
local function hex(c) return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255), math.floor(c[2] * 255),
        math.floor(c[3] * 255)) end
-- invert: for stock, more is bad for a seller (red)
local function pct(x, invert)
    if not x then return "?" end
    local v = math.floor(x * 100 + (x >= 0 and 0.5 or -0.5))
    local good = invert and v < 0 or (not invert and v > 0)
    local c = hex(v == 0 and TEXT.neutral or (good and TEXT.good or TEXT.bad))
    return string.format("%s%+d%%|r", c, v)
end

-- 2.5 -> "2,5", 72.4 -> "72": one decimal below 10, French comma
local function perDayText(perDay)
    return perDay < 10 and (string.format("%.1f", perDay):gsub("%.0$", ""):gsub("%.", ",")) or
        string.format("%d", math.floor(perDay + 0.5))
end

-- r: a Market.Report
function GM.TrendText(r)
    local v, trend = r.verdict, r.trend
    local txt = hex(COLOR[v]) .. LABEL[v] .. "|r"
    local sales = r.source == "sales"
    if trend.price then -- nil when the trend has no verdict, even under a verdict from the sales
        txt = txt .. "  prix " .. pct(trend.price) .. "  stock " .. pct(trend.stock, true)
    elseif v == "none" and trend.age and trend.age > M.WINDOW then
        txt = hex(COLOR.none) .. "Données vieilles de " .. trend.age .. " j|r"
    end
    txt = txt .. string.format(" %s(%d j)|r", hex(TEXT.muted), (sales and r.estimatedSalesDays or trend.days) or 0)
    local perDay = r.estimatedSalesPerDay
    if perDay then -- grey while not reliable
        txt = txt .. "  " .. hex(r.confidence == "high" and TEXT.bright or TEXT.muted) .. "≈ " .. perDayText(perDay)
            .. "/jour|r"
    end
    return txt
end

---------------------------------------------------------------- window
local W, H, SPAN = 340, 120, 21
local f = CreateFrame("Frame", "VepIndustriesMarketTrendFrame", UIParent, "BackdropTemplate")
f:SetSize(W + 30, H + 154)
f:SetPoint("CENTER", 300, 100)
f:SetFrameStrata("DIALOG")
f:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
})
f:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
local function startMoving() f:StartMoving() end
local function stopMoving()
    f:StopMovingOrSizing()
    local p, _, rp, x, y = f:GetPoint()
    VepIndustriesMarketDB.ui = { p, rp, x, y, shown = true }
end
f:SetScript("OnDragStart", startMoving)
f:SetScript("OnDragStop", stopMoving)
f:Hide()
tinsert(UISpecialFrames, "VepIndustriesMarketTrendFrame")

local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -2, -2)

local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOPLEFT", 14, -12); title:SetText("VepIndustries Market - tendance")
local nameFS = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
nameFS:SetPoint("TOPLEFT", 14, -30); nameFS:SetWidth(W - 20); nameFS:SetJustifyH("LEFT")
local verdictFS = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
verdictFS:SetPoint("TOPLEFT", 14, -52); verdictFS:SetJustifyH("LEFT")
local hintFS = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hintFS:SetPoint("BOTTOMLEFT", 14, 8)
hintFS:SetText("Survole un objet.  /vim item <lien> pour figer, /vim unpin")

local graph = CreateFrame("Frame", nil, f)
graph:SetSize(W, H); graph:SetPoint("TOPLEFT", 15, -100)
local gbg = graph:CreateTexture(nil, "BACKGROUND"); gbg:SetAllPoints(); gbg:SetColorTexture(1, 1, 1, 0.04)
local maxPFS = graph:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); maxPFS:SetPoint("BOTTOMLEFT", graph,
    "TOPLEFT", 0, 2)
local maxSFS = graph:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); maxSFS:SetPoint("BOTTOMRIGHT", graph,
    "TOPRIGHT", 0, 2)
maxSFS:SetTextColor(STOCK[1], STOCK[2], STOCK[3])
local maxSalesFS = graph:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
maxSalesFS:SetPoint("BOTTOM", graph, "TOP", 0, 2); maxSalesFS:SetTextColor(SALES[1], SALES[2], SALES[3])
local legendFS = graph:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
legendFS:SetPoint("TOP", graph, "BOTTOM", 0, -20)
legendFS:SetText(hex(PRICE) .. "Prix minimum|r   " .. hex(STOCK) .. "Stock|r   " .. hex(SALES) .. "Ventes estimées|r   "
    .. hex(COLOR.none) .. "(gris : pas fiables)|r")
local emptyFS = graph:CreateFontString(nil, "OVERLAY", "GameFontDisable"); emptyFS:SetPoint("CENTER")

-- day axis, column i = SPAN - i days ago: a tick under each day, a line and a label every week back from today
local BW = W / SPAN
local function dayLabel(ago) return ago == 0 and "aujourd'hui" or ("il y a " .. ago .. " j") end
for i = 1, SPAN do
    local ago, x = SPAN - i, (i - 1) * BW + BW / 2
    local tick = graph:CreateTexture(nil, "BORDER"); tick:SetColorTexture(1, 1, 1, 0.3)
    tick:SetSize(1, 3); tick:SetPoint("TOP", graph, "BOTTOMLEFT", x, 0)
    if ago % 7 == 0 and ago > 0 then
        local week = graph:CreateTexture(nil, "BORDER"); week:SetColorTexture(1, 1, 1, 0.12)
        week:SetSize(1, H); week:SetPoint("BOTTOM", graph, "BOTTOMLEFT", x, 0)
    end
    if ago % 7 == 0 or i == 1 then
        local label = graph:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); label:SetText(dayLabel(ago))
        if i == 1 then label:SetPoint("TOPLEFT", graph, "BOTTOMLEFT", 0, -5)
        elseif ago == 0 then label:SetPoint("TOPRIGHT", graph, "BOTTOMRIGHT", 0, -5)
        else label:SetPoint("TOP", graph, "BOTTOMLEFT", x, -5) end
    end
end

local bars, salesBars, lines, dots = {}, {}, {}, {}
local function bar(i)
    if not bars[i] then
        bars[i] = graph:CreateTexture(nil, "ARTWORK"); bars[i]:SetColorTexture(STOCK[1], STOCK[2], STOCK[3], 0.45)
    end
    return bars[i]
end
local function salesBar(i)
    if not salesBars[i] then salesBars[i] = graph:CreateTexture(nil, "ARTWORK") end
    return salesBars[i]
end
local function line(i)
    if not lines[i] then
        lines[i] = graph:CreateLine(nil, "OVERLAY"); lines[i]:SetThickness(2); lines[i]:SetColorTexture(PRICE[1], PRICE[2], PRICE[3], 1)
    end
    return lines[i]
end
local function dot(i)
    if not dots[i] then
        dots[i] = graph:CreateTexture(nil, "OVERLAY"); dots[i]:SetColorTexture(1, 0.9, 0.3, 1); dots[i]:SetSize(5, 5)
    end
    return dots[i]
end
local function hideAll()
    for _, t in ipairs(bars) do t:Hide() end
    for _, t in ipairs(salesBars) do t:Hide() end
    for _, t in ipairs(lines) do t:Hide() end
    for _, t in ipairs(dots) do t:Hide() end
end

-- 123456 -> "12|cffffd700g|r 34|cffc7c7cfs|r 56|cffeda55fc|r" (GetCoinTextureString is missing on Forever)
local function money(c)
    if not c then return "?" end
    c = math.floor(c)
    local g, s, cu = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local out = {}
    if g > 0 then out[#out + 1] = g .. hex(COIN.g) .. "g|r" end
    if s > 0 or g > 0 then out[#out + 1] = s .. hex(COIN.s) .. "s|r" end
    if cu > 0 or #out == 0 then out[#out + 1] = cu .. hex(COIN.c) .. "c|r" end
    return table.concat(out, " ")
end

-- hovering a day lists its values: view = { first = Auctionator day of column 1, hist = { [day] = entry }, daily }
local view = { hist = {}, daily = {} }
local function showDay(col)
    local ago = SPAN - col.index
    GameTooltip:SetOwner(col, "ANCHOR_RIGHT")
    GameTooltip:AddLine(date("%d/%m", time() - ago * 86400) .. " (" .. dayLabel(ago) .. ")")
    local day = view.first and view.first + col.index - 1
    local h, d = view.hist[day] or {}, view.daily[day] or {}
    if h.price then GameTooltip:AddDoubleLine("Prix minimum", money(h.price), PRICE[1], PRICE[2], PRICE[3], 1, 1, 1) end
    if h.stock then GameTooltip:AddDoubleLine("Stock", tostring(h.stock), STOCK[1], STOCK[2], STOCK[3], 1, 1, 1) end
    if d.estimatedSalesPerDay then
        GameTooltip:AddDoubleLine("Ventes estimées", hex(d.reliable and TEXT.bright or TEXT.muted) .. "≈ "
            .. perDayText(d.estimatedSalesPerDay) .. "/jour" .. (d.reliable and "" or " (pas fiable)") .. "|r",
            SALES[1], SALES[2], SALES[3])
    end
    if not (h.price or h.stock or d.estimatedSalesPerDay) then
        GameTooltip:AddLine("Aucune donnée ce jour", COLOR.none[1], COLOR.none[2], COLOR.none[3])
    end
    GameTooltip:Show()
end
for i = 1, SPAN do
    local col = CreateFrame("Button", nil, graph)
    col.index = i
    col:SetSize(BW, H); col:SetPoint("BOTTOMLEFT", graph, "BOTTOMLEFT", (i - 1) * BW, 0)
    local hl = col:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
    col:RegisterForDrag("LeftButton") -- the columns cover the graph: dragging them still moves the window
    col:SetScript("OnDragStart", startMoving)
    col:SetScript("OnDragStop", stopMoving)
    col:SetScript("OnEnter", showDay)
    col:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local current, pinned
function GM.ShowItem(itemID, force)
    if not itemID then return end
    if pinned and not force then return end
    current = itemID
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID) or ("item " .. itemID)
    nameFS:SetText((name or "?") .. (pinned and " " .. hex(TEXT.muted) .. "(figé)|r" or ""))
    local r = M.Report(itemID)
    local hist, today = r.history, r.today
    hideAll()
    local first = today and today - SPAN + 1
    view = { first = first, hist = {}, daily = r.daily }
    if #hist == 0 or not today then
        verdictFS:SetText(hex(COLOR.none) .. "Aucune donnée Auctionator pour cet objet.|r")
        emptyFS:SetText("Fais un Full Scan à l'hôtel des ventes"); emptyFS:Show()
        maxPFS:SetText(""); maxSFS:SetText(""); maxSalesFS:SetText("")
        return
    end
    emptyFS:Hide()
    local last = hist[#hist]
    verdictFS:SetText(GM.TrendText(r) .. "\n" .. hex(TEXT.bright) .. "Min actuel|r " .. money(last.price) ..
        "  " .. hex(STOCK) .. "stock|r " .. (last.stock or "?"))

    local pts, maxP, minP, maxS = {}, 0, math.huge, 0
    for _, e in ipairs(hist) do
        if e.day >= first then
            pts[#pts + 1] = e
            view.hist[e.day] = e
            if e.price then
                maxP = math.max(maxP, e.price); minP = math.min(minP, e.price)
            end
            if e.stock then maxS = math.max(maxS, e.stock) end
        end
    end
    local compared, maxSales = {}, 0 -- days with estimated sales
    for day, d in pairs(r.daily) do
        if day >= first and day <= today and d.estimatedSalesPerDay then
            compared[day] = d
            maxSales = math.max(maxSales, d.estimatedSalesPerDay)
        end
    end
    maxPFS:SetText(maxP > 0 and ("max " .. money(maxP)) or "")
    maxSFS:SetText(maxS > 0 and ("stock max " .. maxS) or "")
    maxSalesFS:SetText(next(compared) and ("max " .. perDayText(maxSales) .. "/j") or "")
    local half = math.max(1, (BW - 2) / 2) -- stock bar on the left of the day, estimated sales on the right
    local si = 0
    for day, d in pairs(compared) do
        si = si + 1
        local b, c = salesBar(si), d.reliable and SALES or COLOR.none
        b:SetColorTexture(c[1], c[2], c[3], d.reliable and 0.70 or 0.45)
        b:ClearAllPoints(); b:SetPoint("BOTTOMLEFT", graph, "BOTTOMLEFT", (day - first) * BW + 1 + half, 0)
        b:SetSize(half, math.max(1, maxSales > 0 and d.estimatedSalesPerDay / maxSales * H or 0)); b:Show()
    end
    local function px(day) return (day - first) * BW + BW / 2 end
    -- price axis starts at 0 so a small move does not look like a crash/explosion
    local function py(p)
        if maxP <= 0 then return H / 2 end
        return 4 + p / (maxP * 1.1) * (H - 8)
    end
    local prevX, prevY, li = nil, nil, 0
    for i, e in ipairs(pts) do
        if e.stock and maxS > 0 then
            local b = bar(i)
            b:ClearAllPoints(); b:SetPoint("BOTTOMLEFT", graph, "BOTTOMLEFT", (e.day - first) * BW + 1, 0)
            b:SetSize(half, math.max(1, e.stock / maxS * H)); b:Show()
        end
        if e.price then
            local x, y = px(e.day), py(e.price)
            local d = dot(i); d:ClearAllPoints(); d:SetPoint("CENTER", graph, "BOTTOMLEFT", x, y); d:Show()
            if prevX then
                li = li + 1
                local l = line(li)
                l:SetStartPoint("BOTTOMLEFT", graph, prevX, prevY); l:SetEndPoint("BOTTOMLEFT", graph, x, y); l:Show()
            end
            prevX, prevY = x, y
        end
    end
end

function GM.ToggleWindow(show)
    if show == nil then show = not f:IsShown() end
    if show then
        f:Show(); if current then GM.ShowItem(current, true) end
    else f:Hide() end
    VepIndustriesMarketDB.ui = VepIndustriesMarketDB.ui or {}
    VepIndustriesMarketDB.ui.shown = show
end

---------------------------------------------------------------- tooltip
local function onItemTooltip(tooltip, itemID)
    if not itemID or not tooltip.AddDoubleLine then return end
    if VepIndustriesMarketDB and VepIndustriesMarketDB.tooltip == false then return end
    local r = M.Report(itemID)
    if #r.history > 0 or r.source == "sales" then
        tooltip:AddDoubleLine(hex(TITLE) .. (r.source == "sales" and "Ventes estimées " or "Tendance ") .. M.WINDOW
            .. " j|r", GM.TrendText(r))
    end
    if f:IsShown() and tooltip == GameTooltip then GM.ShowItem(itemID) end
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
        local id = data and data.id
        if not id and tooltip.GetItem then
            local _, link = tooltip:GetItem()
            id = link and tonumber(link:match("item:(%d+)"))
        end
        onItemTooltip(tooltip, id)
    end)
else
    GameTooltip:HookScript("OnTooltipSetItem", function(tt)
        local _, link = tt:GetItem()
        onItemTooltip(tt, link and tonumber(link:match("item:(%d+)")))
    end)
end

---------------------------------------------------------------- restore + slash
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    local ui = VepIndustriesMarketDB and VepIndustriesMarketDB.ui
    if ui and ui[1] then
        f:ClearAllPoints(); f:SetPoint(ui[1], UIParent, ui[2], ui[3], ui[4])
    end
    if ui and ui.shown then f:Show() end
end)

local function status()
    local s = M.Status()
    if not s then
        GM.Say("Aucun Scan complet enregistré : ouvre l'hôtel des ventes (Auctionator en mode replicate).")
        return
    end
    GM.Say(string.format("Dernier Scan complet : %s (%s), %d objets, %d Ko de données.", date("%d/%m %H:%M", s.time),
        tostring(s.faction), s.items, math.floor(s.bytes / 1024 + 0.5)))
end

SLASH_VEPINDUSTRIESMARKET1 = "/vim"
SlashCmdList.VEPINDUSTRIESMARKET = function(arg)
    local cmd, rest = (arg or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "" or cmd == "trend" or cmd == "t" then
        GM.ToggleWindow()
    elseif cmd == "item" then
        local id = tonumber(rest:match("item:(%d+)") or rest)
        if id then
            pinned = id; GM.ToggleWindow(true); GM.ShowItem(id, true)
        else GM.Say("/vim item <lien>") end
    elseif cmd == "unpin" then
        pinned = nil; GM.Say("fenêtre de nouveau liée au survol.")
    elseif cmd == "tooltip" then
        VepIndustriesMarketDB.tooltip = VepIndustriesMarketDB.tooltip == false
        GM.Say("ligne d'infobulle " ..
        (VepIndustriesMarketDB.tooltip and "activée" or "désactivée"))
    elseif cmd == "status" then
        status()
    elseif cmd == "relire" then
        GM.Reread()
    else
        GM.Say("/vim (fenêtre) | /vim item <lien> | /vim unpin | /vim tooltip | /vim status | /vim relire")
    end
end
