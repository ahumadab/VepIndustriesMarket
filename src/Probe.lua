-- VepIndustriesMarket probe: capture every auction of a full (replicate) scan to see what Forever really returns.
-- Forever = WOW_PROJECT_CAMELOT, treated as mainline by Auctionator -> modern C_AuctionHouse replicate API.
-- Rows: "itemID|count|buyout|minBid|bidAmount|owner|timeLeft|itemString"
local ADDON = ...
local KEEP = 2 -- ~14 MB per raw snapshot
local BATCH = 400
local AH = C_AuctionHouse

local function msg(s) print("|cff33ff99VepIndustries Market|r " .. s) end
local function logErr(where, e)
  VepIndustriesMarketDB.errors = VepIndustriesMarketDB.errors or {}
  table.insert(VepIndustriesMarketDB.errors, date("%H:%M:%S") .. " " .. where .. ": " .. tostring(e))
  msg("|cffff5555erreur|r " .. where .. ": " .. tostring(e))
end

local busy = false
-- getRow(k) -> info(table), link, timeLeft
local function capture(source, total, getRow)
  if busy then return end
  if not total or total < 1 then msg("rien a capturer (" .. tostring(total) .. ")") return end
  busy = true
  local snap = { t = time(), source = source, n = total, realm = GetRealmName(), faction = UnitFactionGroup("player"),
    rows = {}, noOwner = 0, noTime = 0, sample = {} }
  local i = 1
  local function step()
    local ok, e = pcall(function()
      local last = math.min(i + BATCH - 1, total)
      for k = i, last do
        local info, link, tl = getRow(k)
        if info then
          local owner = info[14]
          if not owner or owner == "" then snap.noOwner = snap.noOwner + 1 end
          if tl == nil then snap.noTime = snap.noTime + 1 end
          local istr = link and link:match("item:([%-%d:]+)") or ""
          snap.rows[#snap.rows + 1] = table.concat({ info[17] or 0, info[3] or 0, info[10] or 0, info[8] or 0,
            info[11] or 0, owner or "", tl or "", istr }, "|")
          if #snap.sample < 5 then
            local s = {}
            for j = 1, 20 do s[j] = tostring(info[j]) end
            snap.sample[#snap.sample + 1] = table.concat(s, " ; ")
          end
        end
      end
      i = last + 1
    end)
    if not ok then busy = false; logErr("capture", e); return end
    if i <= total then
      C_Timer.After(0, step)
    else
      VepIndustriesMarketDB.snaps = VepIndustriesMarketDB.snaps or {}
      table.insert(VepIndustriesMarketDB.snaps, snap)
      while #VepIndustriesMarketDB.snaps > KEEP do table.remove(VepIndustriesMarketDB.snaps, 1) end
      busy = false
      msg(string.format("%d encheres capturees (%s). Sans vendeur: %d, sans temps restant: %d. /reload pour sauver.",
        #snap.rows, source, snap.noOwner, snap.noTime))
    end
  end
  step()
end

-- Passive: Auctionator's full scan hands over { replicateInfo, itemLink, timeLeft } per auction
local listener = {}
function listener:ReceiveEvent(event, data)
  if type(data) ~= "table" then logErr("auctionator", "pas de donnees de scan") return end
  capture("auctionator", #data, function(k)
    local d = data[k]
    return d.replicateInfo, d.itemLink, d.timeLeft
  end)
end

local function captureReplicate(source)
  capture(source, AH.GetNumReplicateItems(), function(k)
    local idx = k - 1 -- replicate API is 0-based
    return { AH.GetReplicateItemInfo(idx) }, AH.GetReplicateItemLink(idx), AH.GetReplicateItemTimeLeft(idx)
  end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self, event, arg)
  if event == "ADDON_LOADED" and arg == ADDON then
    VepIndustriesMarketDB = VepIndustriesMarketDB or {}
    VepIndustriesMarketDB.errors = {}
  elseif event == "PLAYER_LOGIN" then
    local ok, e = pcall(function()
      if Auctionator and Auctionator.EventBus and Auctionator.FullScan and Auctionator.FullScan.Events then
        Auctionator.EventBus:Register(listener, { Auctionator.FullScan.Events.ScanComplete })
        msg("branche sur le Full Scan d'Auctionator.")
      else
        msg("Auctionator absent : utilise /vim scan.")
      end
    end)
    if not ok then logErr("login", e) end
  elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
    self:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    C_Timer.After(2, function() captureReplicate("gm") end)
  end
end)

SLASH_VEPINDUSTRIESMARKET1 = "/vim"
SlashCmdList.VEPINDUSTRIESMARKET = function(arg)
  arg = (arg or ""):lower()
  if arg == "scan" then
    f:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    local ok, e = pcall(AH.ReplicateItems)
    if ok then msg("scan complet lance (si rien dans ~1 min : delai de 15 min pas ecoule).") else logErr("scan", e) end
  elseif arg == "grab" then
    captureReplicate("grab")
  else
    msg("/vim scan (scan complet) | /vim grab (relire le dernier scan en memoire)")
  end
end
