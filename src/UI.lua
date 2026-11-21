-- VepIndustriesMarket UI: trend line in item tooltips + a small window with price (line) and stock (bars) over the history.
local GM = VepIndustriesMarket
local T = GM.Trend

local LABEL = { demand = "Demande", stable = "Stable", saturated = "Saturé", none = "Pas assez de données" }
local COLOR = {
  demand = { 0.30, 1.00, 0.30 }, stable = { 1.00, 0.85, 0.20 },
  saturated = { 1.00, 0.35, 0.35 }, none = { 0.60, 0.60, 0.60 },
}
local function hex(c) return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255)) end
-- invert: for stock, more is bad for a seller (red)
local function pct(x, invert)
  if not x then return "?" end
  local v = math.floor(x * 100 + (x >= 0 and 0.5 or -0.5))
  local good = invert and v < 0 or (not invert and v > 0)
  local c = v == 0 and "|cffcccccc" or (good and "|cff66ff66" or "|cffff6666")
  return string.format("%s%+d%%|r", c, v)
end

function GM.TrendText(r)
  if not r then return nil end
  local v = r.verdict
  local txt = hex(COLOR[v]) .. LABEL[v] .. "|r"
  if v ~= "none" then
    txt = txt .. "  prix " .. pct(r.price) .. "  stock " .. pct(r.stock, true)
  elseif r.age and r.age > T.WINDOW then
    txt = hex(COLOR.none) .. "Données vieilles de " .. r.age .. " j|r"
  end
  return txt .. string.format(" |cff9d9d9d(%d j)|r", r.days or 0)
end

---------------------------------------------------------------- window
local W, H, SPAN = 340, 120, 21
local f = CreateFrame("Frame", "VepIndustriesMarketTrendFrame", UIParent, "BackdropTemplate")
f:SetSize(W + 30, H + 135)
f:SetPoint("CENTER", 300, 100)
f:SetFrameStrata("DIALOG")
f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
f:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local p, _, rp, x, y = self:GetPoint()
  VepIndustriesMarketDB.ui = { p, rp, x, y, shown = true }
end)
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
local maxPFS = graph:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); maxPFS:SetPoint("BOTTOMLEFT", graph, "TOPLEFT", 0, 2)
local maxSFS = graph:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); maxSFS:SetPoint("BOTTOMRIGHT", graph, "TOPRIGHT", 0, 2)
maxSFS:SetTextColor(0.45, 0.70, 1)
local d0FS = graph:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); d0FS:SetPoint("TOPLEFT", graph, "BOTTOMLEFT", 0, -2)
local d1FS = graph:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); d1FS:SetPoint("TOPRIGHT", graph, "BOTTOMRIGHT", 0, -2)
d1FS:SetText("aujourd'hui")
local emptyFS = graph:CreateFontString(nil, "OVERLAY", "GameFontDisable"); emptyFS:SetPoint("CENTER")

local bars, lines, dots = {}, {}, {}
local function bar(i)
  if not bars[i] then bars[i] = graph:CreateTexture(nil, "ARTWORK"); bars[i]:SetColorTexture(0.25, 0.55, 1, 0.45) end
  return bars[i]
end
local function line(i)
  if not lines[i] then
    lines[i] = graph:CreateLine(nil, "OVERLAY"); lines[i]:SetThickness(2); lines[i]:SetColorTexture(1, 0.82, 0, 1)
  end
  return lines[i]
end
local function dot(i)
  if not dots[i] then dots[i] = graph:CreateTexture(nil, "OVERLAY"); dots[i]:SetColorTexture(1, 0.9, 0.3, 1); dots[i]:SetSize(5, 5) end
  return dots[i]
end
local function hideAll()
  for _, t in ipairs(bars) do t:Hide() end
  for _, t in ipairs(lines) do t:Hide() end
  for _, t in ipairs(dots) do t:Hide() end
end

-- 123456 -> "12|cffffd700g|r 34|cffc7c7cfs|r 56|cffeda55fc|r" (GetCoinTextureString is missing on Forever)
local function money(c)
  if not c then return "?" end
  c = math.floor(c)
  local g, s, cu = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local out = {}
  if g > 0 then out[#out + 1] = g .. "|cffffd700g|r" end
  if s > 0 or g > 0 then out[#out + 1] = s .. "|cffc7c7cfs|r" end
  if cu > 0 or #out == 0 then out[#out + 1] = cu .. "|cffeda55fc|r" end
  return table.concat(out, " ")
end

local current, pinned
function GM.ShowItem(itemID, force)
  if not itemID then return end
  if pinned and not force then return end
  current = itemID
  local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID) or ("item " .. itemID)
  nameFS:SetText((name or "?") .. (pinned and " |cff9d9d9d(figé)|r" or ""))
  local today = T.Today()
  local r, hist = T.ForItem(itemID)
  hideAll()
  if not hist or #hist == 0 or not today then
    verdictFS:SetText(hex(COLOR.none) .. "Aucune donnée Auctionator pour cet objet.|r")
    emptyFS:SetText("Fais un Full Scan à l'hôtel des ventes"); emptyFS:Show()
    maxPFS:SetText(""); maxSFS:SetText(""); d0FS:SetText("")
    return
  end
  emptyFS:Hide()
  local last = hist[#hist]
  verdictFS:SetText((GM.TrendText(r) or "") .. "\n|cffffffffMin actuel|r " .. money(last.price) ..
    "  |cff74b4ffstock|r " .. (last.stock or "?"))

  local first = today - SPAN + 1
  local pts, maxP, minP, maxS = {}, 0, math.huge, 0
  for _, e in ipairs(hist) do
    if e.day >= first then
      pts[#pts + 1] = e
      if e.price then maxP = math.max(maxP, e.price); minP = math.min(minP, e.price) end
      if e.stock then maxS = math.max(maxS, e.stock) end
    end
  end
  d0FS:SetText("il y a " .. (SPAN - 1) .. " j")
  maxPFS:SetText(maxP > 0 and ("max " .. money(maxP)) or "")
  maxSFS:SetText(maxS > 0 and ("stock max " .. maxS) or "")
  local bw = W / SPAN
  local function px(day) return (day - first) * bw + bw / 2 end
  -- price axis starts at 0 so a small move does not look like a crash/explosion
  local function py(p)
    if maxP <= 0 then return H / 2 end
    return 4 + p / (maxP * 1.1) * (H - 8)
  end
  local prevX, prevY, li = nil, nil, 0
  for i, e in ipairs(pts) do
    if e.stock and maxS > 0 then
      local b = bar(i)
      b:ClearAllPoints(); b:SetPoint("BOTTOMLEFT", graph, "BOTTOMLEFT", (e.day - first) * bw + 1, 0)
      b:SetSize(math.max(1, bw - 2), math.max(1, e.stock / maxS * H)); b:Show()
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
  if show then f:Show(); if current then GM.ShowItem(current, true) end else f:Hide() end
  VepIndustriesMarketDB.ui = VepIndustriesMarketDB.ui or {}
  VepIndustriesMarketDB.ui.shown = show
end

---------------------------------------------------------------- tooltip
local function onItemTooltip(tooltip, itemID)
  if not itemID or not tooltip.AddDoubleLine then return end
  if VepIndustriesMarketDB and VepIndustriesMarketDB.tooltip == false then return end
  local r = T.ForItem(itemID)
  if r then
    tooltip:AddDoubleLine("|cffffd100Tendance " .. T.WINDOW .. " j|r", GM.TrendText(r))
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
  if ui and ui[1] then f:ClearAllPoints(); f:SetPoint(ui[1], UIParent, ui[2], ui[3], ui[4]) end
  if ui and ui.shown then f:Show() end
end)

local probe = SlashCmdList.VEPINDUSTRIESMARKET
SlashCmdList.VEPINDUSTRIESMARKET = function(arg)
  local cmd, rest = (arg or ""):match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()
  if cmd == "" or cmd == "trend" or cmd == "t" then
    GM.ToggleWindow()
  elseif cmd == "item" then
    local id = tonumber(rest:match("item:(%d+)") or rest)
    if id then pinned = id; GM.ToggleWindow(true); GM.ShowItem(id, true) else print("|cff33ff99VepIndustries Market|r /vim item <lien>") end
  elseif cmd == "unpin" then
    pinned = nil; print("|cff33ff99VepIndustries Market|r fenêtre de nouveau liée au survol.")
  elseif cmd == "tooltip" then
    VepIndustriesMarketDB.tooltip = VepIndustriesMarketDB.tooltip == false
    print("|cff33ff99VepIndustries Market|r ligne d'infobulle " .. (VepIndustriesMarketDB.tooltip and "activée" or "désactivée"))
  elseif cmd == "scan" or cmd == "grab" then
    probe(arg)
  else
    print("|cff33ff99VepIndustries Market|r /vim (fenêtre) | /vim item <lien> | /vim unpin | /vim tooltip | /vim scan")
  end
end
