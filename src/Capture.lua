-- VepIndustriesMarket capture: turns each Auctionator replicate full scan into tiers and hands it to Market.Ingest.
-- Forever = WOW_PROJECT_CAMELOT, treated as mainline by Auctionator (Source_ModernAH, replicate API).
local ADDON = ...
local GM = VepIndustriesMarket
local M = GM.Market

function GM.Say(s) print("|cff33ff99VepIndustries Market|r " .. s) end
local function logErr(where, e)
    VepIndustriesMarketDB.errors = VepIndustriesMarketDB.errors or {}
    table.insert(VepIndustriesMarketDB.errors, date("%H:%M:%S") .. " " .. where .. ": " .. tostring(e))
    GM.Say("|cffff5555erreur|r " .. where .. ": " .. tostring(e))
end

-- Auctionator's ScanComplete data: { { replicateInfo = { C_AuctionHouse.GetReplicateItemInfo(i) }, itemLink, timeLeft }, ... }
-- replicateInfo[3] = lot size, [10] = buyout of the whole lot, [17] = itemID. Bid-only auctions (no buyout) are skipped.
-- timeLeft is kept as the API gives it: 1 (Short) to 4 (Very long) on Forever over the real scan of 2026-11-21.
-- A tier is split by time left, so that estimated sales can tell its Short auctions apart.
local function toFullScan(data)
    local scan, byKey = {}, {}
    for _, a in ipairs(data) do
        local info = a.replicateInfo
        local id, size, buyout, timeLeft = info[17], info[3], info[10], a.timeLeft or 0
        if id and size and size > 0 and buyout and buyout > 0 then
            local price = math.floor(buyout / size + 0.5)
            local key = id .. ":" .. price .. ":" .. size .. ":" .. timeLeft
            local t = byKey[key]
            if not t then
                t = { price = price, size = size, count = 0, timeLeft = timeLeft }
                byKey[key] = t
                scan[id] = scan[id] or {}
                table.insert(scan[id], t)
            end
            t.count = t.count + 1
        end
    end
    return scan
end

local SETUP = "les Ventes estimées demandent un Scan complet à l'ouverture de l'hôtel des ventes. Dans les options "
    .. "d'Auctionator, coche « Run autoscan when Auction House is opened » et, dans Advanced, « Use alternate slower "
    .. "scan mode by default »."
local warned = false -- incremental scans: once per session
local listener = {}
function listener:ReceiveEvent(event, data)
    if event ~= Auctionator.FullScan.Events.ScanComplete then
        if not warned then GM.Say("Auctionator a fait un scan incrémental : " .. SETUP) end
        warned = true
        return
    end
    -- ponytail: whole scan in one frame (~300k auctions), batch it over frames if the hitch shows in game
    local ok, e = pcall(M.Ingest, toFullScan(type(data) == "table" and data or {}), time(), GetRealmName(),
        UnitFactionGroup("player"))
    if not ok then logErr("scan", e) end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" and arg == ADDON then
        VepIndustriesMarketDB = VepIndustriesMarketDB or {}
        VepIndustriesMarketDB.errors = {}
        VepIndustriesMarketDB.snaps = nil -- raw probe snapshots of 0.1.0 (~14 MB each)
    elseif event == "PLAYER_LOGIN" then
        local A = Auctionator
        if A and A.EventBus and A.FullScan and A.FullScan.Events then
            local events = { A.FullScan.Events.ScanComplete }
            if A.IncrementalScan and A.IncrementalScan.Events then
                events[2] = A.IncrementalScan.Events.ScanComplete
            end
            local ok, e = pcall(A.EventBus.Register, A.EventBus, listener, events)
            if not ok then logErr("auctionator", e) end
            local c = A.Config
            if c and c.Get and c.Options and not (c.Get(c.Options.REPLICATE_SCAN) and c.Get(c.Options.AUTOSCAN)) then
                GM.Say("Auctionator n'est pas réglé pour les Scans complets : " .. SETUP)
            end
        else
            GM.Say("Auctionator absent : ni Tendance ni Ventes estimées.")
        end
    end
end)
