-- VepIndustriesMarket market: the single entry point the UI reads. No UI, testable outside the game.
-- Saved in VepIndustriesMarketDB: fullScan = { time, items = { [itemID] = tiers string } } (latest full scan only)
-- and daily = { [itemID] = { [Auctionator day] = "price stock scans[ estimatedSales seconds]" } } (daily summary, mergeable
-- between players).
local GM = VepIndustriesMarket
local T = GM.Trend
GM.Market = GM.Market or {}
local M = GM.Market

M.WINDOW = T.WINDOW
-- daily summary kept, the span of the /vim window: ~170 KB per day of scans, ~55 KB more with estimated sales,
-- ~5.6 MB in all after 21 days (accepted)
local KEEP_DAYS = 21

-- A tier (one per price, lot size and time left) is one token "<timeLeft><price>[.<size>][*<count>]", numbers in
-- base 36, size and count omitted when 1, price as the gap from the previous tier of the item (sorted by price),
-- price and size both omitted when equal to the previous tier's: the real full scan (136 222 tiers) takes
-- ~0.95 MB with its daily summary, ~1.6 MB in plain decimal.
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function b36(n)
    local s = ""
    repeat
        local d = n % 36
        s = DIGITS:sub(d + 1, d + 1) .. s
        n = (n - d) / 36
    until n == 0
    return s
end

local function encode(t, prev)
    local same = prev and prev.price == t.price and prev.size == t.size
    return t.timeLeft .. (same and "" or b36(t.price - (prev and prev.price or 0))
            .. (t.size > 1 and "." .. b36(t.size) or ""))
        .. (t.count > 1 and "*" .. b36(t.count) or "")
end

local function decode(s)
    local tiers, price, lot = {}, 0, 1
    for tok in s:gmatch("%S+") do
        local tl, gap, size, count = tok:match("^(%d)(%w*)%.?(%w*)%*?(%w*)$")
        if gap ~= "" then price, lot = price + tonumber(gap, 36), tonumber(size, 36) or 1 end
        tiers[#tiers + 1] = { timeLeft = tonumber(tl), price = price, size = lot, count = tonumber(count, 36) or 1 }
    end
    return tiers
end

-- daily summary of one day: "price stock scans[ estimatedSales seconds]" <-> { price, stock, scans, estimatedSales,
-- seconds }. price "-" when the item sold out (absent from a scan after being in the previous one); estimatedSales:
-- units bought over `seconds` of compared scans, both 0 (omitted) when no scan of the day was compared.
local function readDay(v)
    local p, s, n, u, e = (v or ""):match("^(%S+) (%d+) (%d+) ?(%d*) ?(%d*)$")
    return { price = tonumber(p), stock = tonumber(s), scans = tonumber(n), estimatedSales = tonumber(u) or 0,
        seconds = tonumber(e) or 0 }
end

-- adds one scan of item `id` to its day; sales nil when this scan was not compared
local function addDay(daily, id, day, price, stock, sales, seconds)
    daily[id] = daily[id] or {}
    local d = readDay(daily[id][day])
    local p = math.min(d.price or math.huge, price or math.huge)
    local units, secs = d.estimatedSales + (sales or 0), d.seconds + (sales and seconds or 0)
    daily[id][day] = string.format("%s %d %d", p < math.huge and string.format("%d", p) or "-",
            math.max(d.stock or 0, stock), (d.scans or 0) + 1)
        .. (secs > 0 and string.format(" %d %d", units, secs) or "")
end

-- least time left of each band (1 Short, 2 Medium, 3 Long, 4 Very long), in seconds: retail's values, assumed on
-- Forever. An auction of a band whose least time left is below the gap between two scans may have expired meanwhile.
local BAND_MIN = { 0, 1800, 7200, 43200 }
-- scans closer than this are the same data read again (the server allows one every 15 min): not compared
local MIN_GAP = 600
-- scans further apart than this are not compared: Long auctions could expire in between and pass for sold
local MAX_GAP = 7200

-- Units bought over `gap` seconds between two scans of an item, buyers taking the cheapest first: per unit price
-- up to the new lowest one, the units gone beyond those of auctions that may have expired. Dearer units gone were
-- cancelled, and a seller reposting cheaper lowers the new lowest price: neither counts (real scan of 2026-11-21:
-- 38 897 arrows "sold" in 17 min, counting every tier gone). Lot sizes are ignored: buying part of a commodity
-- auction shrinks its lot.
local function estimatedSales(before, after, gap)
    local low, left, gone, units = after[1] and after[1].price or math.huge, {}, {}, 0 -- after: by price
    for _, t in ipairs(after) do left[t.price] = (left[t.price] or 0) + t.size * t.count end
    for _, t in ipairs(before) do
        if t.price <= low then
            local g = gone[t.price] or { units = 0, expired = 0 }
            gone[t.price] = g
            g.units = g.units + t.size * t.count
            if (BAND_MIN[t.timeLeft] or 0) < gap then g.expired = g.expired + t.size * t.count end
        end
    end
    for price, g in pairs(gone) do units = units + math.max(0, g.units - (left[price] or 0) - g.expired) end
    return units
end

local function sameItems(a, b)
    for id, s in pairs(a) do if b[id] ~= s then return false end end
    for id in pairs(b) do if not a[id] then return false end end
    return true
end

-- Inside a coroutine (the capture spreading a big scan over frames), hand control back; no-op otherwise.
-- Lua 5.1: running() is nil on the main thread; 5.3 (tests): it returns the main thread and true.
local function pause()
    local co, main = coroutine.running()
    if co and not main then coroutine.yield() end
end

local function byPrice(a, b)
    if a.price ~= b.price then return a.price < b.price end
    if a.size ~= b.size then return a.size < b.size end
    return a.timeLeft < b.timeLeft
end

-- Full scan: { [itemID] = { { price (unit, integer copper), size, count, timeLeft }, ... } } taken at time `now`
-- on the auction house of `realm` and `faction` (one per faction: scans to compare must share both).
-- Replaces the stored full scan and adds it to the daily summary (lowest price, highest stock of the day, and the
-- estimated sales since the stored scan when it is from the same auction house, at most MAX_GAP older). A scan
-- without any auction is ignored; one less than MIN_GAP newer, or holding the same data (/vim relire), is not
-- compared and keeps the stored scan's time, so that the next comparison spans the real time.
function M.Ingest(scan, now, realm, faction)
    local db, day = VepIndustriesMarketDB, T.Today(now)
    if not db or not day then return end
    local items, stocks, done = {}, {}, 0
    for id, tiers in pairs(scan) do
        done = done + 1
        if done % 200 == 0 then pause() end
        if tiers[1] then
            table.sort(tiers, byPrice)
            local tokens, stock = {}, 0
            for i, t in ipairs(tiers) do
                tokens[i] = encode(t, tiers[i - 1])
                stock = stock + t.size * t.count
            end
            items[id], stocks[id] = table.concat(tokens, " "), stock
        end
    end
    if next(items) == nil then return end
    local prev, daily = db.fullScan, db.daily or {}
    local gap = prev and prev.realm == realm and prev.faction == faction and now - prev.time
    if gap and (gap < MIN_GAP or sameItems(prev.items, items)) then now, gap = prev.time, nil end
    if gap and gap > MAX_GAP then gap = nil end
    local before = gap and prev.items or {}
    done = 0
    for id in pairs(items) do
        done = done + 1
        if done % 200 == 0 then pause() end
        local tiers = scan[id]
        addDay(daily, id, day, tiers[1].price, stocks[id],
            before[id] and estimatedSales(decode(before[id]), tiers, gap), gap)
    end
    for id, encoded in pairs(before) do -- sold out
        if not items[id] then addDay(daily, id, day, nil, 0, estimatedSales(decode(encoded), {}, gap), gap) end
    end
    for id, days in pairs(daily) do
        for d in pairs(days) do
            if d <= day - KEEP_DAYS then days[d] = nil end
        end
        if next(days) == nil then daily[id] = nil end
    end
    db.fullScan = { time = now, realm = realm, faction = faction, items = items }
    db.daily = daily
end

-- { time, realm, faction, items, bytes } of the stored full scan (bytes: rough size on disk, daily summary included), nil without one
function M.Status()
    local fs = VepIndustriesMarketDB and VepIndustriesMarketDB.fullScan
    if not fs then return nil end
    local items, bytes = 0, 0
    for _, s in pairs(fs.items) do items, bytes = items + 1, bytes + #s + 16 end
    for _, days in pairs(VepIndustriesMarketDB.daily or {}) do
        bytes = bytes + 16
        for _, v in pairs(days) do bytes = bytes + #v + 14 end
    end
    return { time = fs.time, realm = fs.realm, faction = fs.faction, items = items, bytes = bytes }
end

-- { verdict, trend = { price, stock, days, age }, estimatedSalesPerDay, confidence, history, today, tiers, daily }
-- price/stock: relative change of the latest day vs the median of the window; history: ascending { day, price, stock }
-- tiers: the item in the latest full scan, by price, lot size, time left; daily: { [day] = { price, stock, scans,
-- estimatedSales, seconds } }. estimatedSalesPerDay over the window, nil before two compared scans; confidence
-- "high" from 2 days of comparisons in the window (so at least 3 scans), "low" below.
function M.Report(itemID)
    local hist = T.History(itemID) or {}
    local today = T.Today()
    local r = T.Compute(hist, today) or { verdict = "none", days = 0 }
    local db = VepIndustriesMarketDB or {}
    local encoded = db.fullScan and db.fullScan.items[itemID]
    local daily, days, units, seconds = {}, 0, 0, 0
    for d, v in pairs(db.daily and db.daily[itemID] or {}) do
        daily[d] = readDay(v)
        if today and d > today - M.WINDOW and daily[d].seconds > 0 then
            days, units, seconds = days + 1, units + daily[d].estimatedSales, seconds + daily[d].seconds
        end
    end
    local perDay = seconds > 0 and units * 86400 / seconds or nil
    return {
        verdict = r.verdict,
        trend = { price = r.price, stock = r.stock, days = r.days, age = r.age },
        estimatedSalesPerDay = perDay,
        confidence = perDay and (days >= 2 and "high" or "low") or nil,
        history = hist,
        today = today,
        tiers = encoded and decode(encoded) or {},
        daily = daily,
    }
end
