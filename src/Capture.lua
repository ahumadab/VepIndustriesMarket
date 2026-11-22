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
-- get(k) -> replicateInfo, timeLeft of auction k (1..n). Pauses every BATCH auctions (see ingest).
local BATCH = 2000
local function toFullScan(n, get)
    local scan, byKey = {}, {}
    for k = 1, n do
        local info, timeLeft = get(k)
        timeLeft = timeLeft or 0
        local id, size, buyout = info[17], info[3], info[10]
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
        if k % BATCH == 0 then coroutine.yield() end
    end
    return scan
end

local SETUP = "les Ventes estimées demandent un Scan complet à l'ouverture de l'hôtel des ventes. Dans les options "
    .. "d'Auctionator, coche « Run autoscan when Auction House is opened » et, dans Advanced, « Use alternate slower "
    .. "scan mode by default »."

-- A full scan (~300k auctions) freezes the game for seconds in one go, merging a received Comparison for a fraction
-- of one: each job runs in a coroutine resumed once per frame (conversion and Market yield every few thousand
-- auctions or hundred items), one job after the other, so that no two change the save at once.
local jobs = {}
local function step()
    local job = jobs[1]
    local ok, e = coroutine.resume(job.co)
    if ok and coroutine.status(job.co) ~= "dead" then return C_Timer.After(0, step) end
    if not ok then logErr(job.where, e) end
    table.remove(jobs, 1)
    if jobs[1] then C_Timer.After(0, step) end
end
-- runs fn() after the jobs queued before it, errors logged under `where`
function GM.Run(where, fn)
    jobs[#jobs + 1] = { where = where, co = coroutine.create(fn) }
    if #jobs == 1 then step() end
end

-- "25 min", "3 h 05"
local function duration(s)
    local m = math.floor(s / 60 + 0.5)
    return m < 120 and string.format("%d min", m) or string.format("%d h %02d", math.floor(m / 60), m % 60)
end

local NOT_COMPARED = {
    first = function() return "premier scan, rien à comparer" end,
    otherHouse = function() return "autre hôtel des ventes que le précédent, ventes non mesurées" end,
    tooSoon = function() return "moins de 10 min après le précédent, ventes non mesurées" end,
    same = function() return "identique au précédent, ventes non mesurées" end,
    tooLate = function(s) return duration(s) .. " après le précédent (2 h au plus), ventes non mesurées" end,
}

-- one line after a full scan: what it gave, and when the next one would be compared
local function outcome(compared, reason, seconds)
    local what = compared and "ventes mesurées sur " .. duration(seconds) or NOT_COMPARED[reason](seconds)
    local from, to = M.NextScan()
    local when = from <= time() and string.format("Prochain scan utile avant %s.", date("%H:%M", to))
        or string.format("Prochain scan utile entre %s et %s.", date("%H:%M", from), date("%H:%M", to))
    return string.format("Scan complet enregistré : %d objets, %s. %s", M.Status().items, what, when)
end

local function ingest(n, get)
    for _, job in ipairs(jobs) do
        if job.where == "scan" then return GM.Say("un Scan complet est déjà en cours d'enregistrement.") end
    end
    GM.Say(string.format("enregistrement du Scan complet en cours (%d enchères)…", n))
    GM.Run("scan", function()
        local compared, reason, seconds = M.Ingest(toFullScan(n, get), time(), GetRealmName(),
            UnitFactionGroup("player"), UnitName("player"))
        if compared == nil then return GM.Say("Scan complet vide : ignoré.") end
        GM.Say(outcome(compared, reason, seconds))
        if compared then GM.Exchange.Announce() end
    end)
end

local warned = false -- incremental scans: once per session
local listener = {}
function listener:ReceiveEvent(event, data)
    if event == Auctionator.FullScan.Events.ScanComplete then
        data = type(data) == "table" and data or {}
        ingest(#data, function(k) return data[k].replicateInfo, data[k].timeLeft end)
    elseif not warned then
        warned = true
        GM.Say("Auctionator a fait un scan incrémental : " .. SETUP)
    end
end

-- Dev: ingest again the last full scan the client keeps in memory, the server allowing one every 15 minutes
function GM.Reread()
    local AH = C_AuctionHouse
    local n = AH and AH.GetNumReplicateItems and AH.GetNumReplicateItems() or 0
    if n < 1 then
        return GM.Say("aucun Scan complet en mémoire (il est perdu à chaque /reload) : ouvre l'hôtel des ventes et attends un scan d'Auctionator.")
    end
    ingest(n, function(k) -- the replicate API is 0-based
        return { AH.GetReplicateItemInfo(k - 1) }, AH.GetReplicateItemTimeLeft(k - 1)
    end)
end

-- The Sync script's data file lives in an addon of its own, loaded on demand: the game reads its file when it loads,
-- so loading it when the auction house first opens catches a file written after the game started (#19).
local DATA_ADDON = ADDON .. "_Data"

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("AUCTION_HOUSE_SHOW")
f:SetScript("OnEvent", function(_, event, arg)
    if event == "AUCTION_HOUSE_SHOW" then
        f:UnregisterEvent(event) -- once a session: the game loads an addon once
        C_AddOns.LoadAddOn(DATA_ADDON) -- false when missing (no Sync script): nothing to do
        local file, items = VepIndustriesMarketData, 0
        for _ in pairs(file and file.daily or {}) do items = items + 1 end
        -- the file loaded, if any, for npm run report
        VepIndustriesMarketDB.dataFile = file and { generated = file.generated, items = items } or nil
        -- kept across sessions: until the auction house opens, the in-game exchange's data file time (Exchange.lua)
        VepIndustriesMarketDB.dataGenerated = file and file.generated or VepIndustriesMarketDB.dataGenerated
        local days = M.StaleDays()
        if days then
            GM.Say(string.format("les données partagées n'ont pas été renouvelées depuis %d jours : réinstalle le "
                .. "Script de synchro (double-clic sur installer.cmd, dans le dossier Interface\\AddOns\\%s).", days, ADDON))
        end
    elseif event == "ADDON_LOADED" and arg == ADDON then
        VepIndustriesMarketDB = VepIndustriesMarketDB or {}
        VepIndustriesMarketDB.errors = {}
        VepIndustriesMarketDB.dataFile = nil -- this session's, set when the auction house opens
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
