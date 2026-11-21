-- VepIndustriesMarket market: the single entry point the UI reads. No UI, testable outside the game.
-- Saved in VepIndustriesMarketDB: fullScan = { time, items = { [itemID] = tiers string } } (latest full scan only)
-- and daily = { [itemID] = { [Auctionator day] = "price stock scans[ sold seconds]" } } (daily summary, mergeable
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

-- daily summary of one day: "price stock scans[ sold seconds]" <-> numbers. price "-" when the item sold out
-- (absent from a scan after being in the previous one); sold: estimated units bought over `seconds` of scan pairs.
local function readDay(v)
    local p, s, n, u, e = (v or ""):match("^(%S+) (%d+) (%d+) ?(%d*) ?(%d*)$")
    return tonumber(p), tonumber(s), tonumber(n), tonumber(u) or 0, tonumber(e) or 0
end

local function addDay(days, day, price, stock, sold, seconds)
    local p, s, n, u, e = readDay(days[day])
    p, s, n, u, e = math.min(p or math.huge, price or math.huge), math.max(s or 0, stock), (n or 0) + 1,
        u + (sold or 0), e + (sold and seconds or 0)
    days[day] = string.format("%s %d %d", p < math.huge and string.format("%d", p) or "-", s, n)
        .. (e > 0 and string.format(" %d %d", u, e) or "")
end

local SHORT = 1 -- time left band of auctions about to expire
-- scans closer than this are the same data read again (the server allows one every 15 min): not compared
local MIN_GAP = 600

-- Units bought between two scans of an item: per tier (price, lot size, any time left), the auctions gone beyond
-- those that were Short, which count as expired. Cancellations and reposts are accepted noise.
local function sold(before, after)
    local left, groups, units = {}, {}, 0
    for _, t in ipairs(after) do
        local k = t.price .. ":" .. t.size
        left[k] = (left[k] or 0) + t.count
    end
    for _, t in ipairs(before) do
        local k = t.price .. ":" .. t.size
        local g = groups[k] or { size = t.size, count = 0, short = 0 }
        groups[k] = g
        g.count = g.count + t.count
        if t.timeLeft == SHORT then g.short = g.short + t.count end
    end
    for k, g in pairs(groups) do units = units + math.max(0, g.count - (left[k] or 0) - g.short) * g.size end
    return units
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
-- estimated sales since the stored scan when it is from the same auction house and at least MIN_GAP older).
function M.Ingest(scan, now, realm, faction)
    local db, day = VepIndustriesMarketDB, T.Today(now)
    if not db or not day then return end
    local items, daily, done = {}, db.daily or {}, 0
    local prev = db.fullScan
    local gap = prev and prev.realm == realm and prev.faction == faction and now - prev.time
    local before = gap and gap >= MIN_GAP and prev.items or {}
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
            items[id] = table.concat(tokens, " ")
            daily[id] = daily[id] or {}
            addDay(daily[id], day, tiers[1].price, stock, before[id] and sold(decode(before[id]), tiers), gap)
        end
    end
    for id, encoded in pairs(before) do
        if not items[id] then -- sold out
            daily[id] = daily[id] or {}
            addDay(daily[id], day, nil, 0, sold(decode(encoded), {}), gap)
        end
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
-- sold, seconds } }. estimatedSalesPerDay over the window, nil before two comparable scans; confidence "high" from
-- 2 days and 3 scans in the window, "low" below.
function M.Report(itemID)
    local hist = T.History(itemID) or {}
    local today = T.Today()
    local r = T.Compute(hist, today) or { verdict = "none", days = 0 }
    local db = VepIndustriesMarketDB or {}
    local encoded = db.fullScan and db.fullScan.items[itemID]
    local daily, days, scans, units, seconds = {}, 0, 0, 0, 0
    for d, v in pairs(db.daily and db.daily[itemID] or {}) do
        local p, s, n, u, e = readDay(v)
        daily[d] = { price = p, stock = s, scans = n, sold = u, seconds = e }
        if today and d > today - M.WINDOW then
            days, scans, units, seconds = days + 1, scans + n, units + u, seconds + e
        end
    end
    local perDay = seconds > 0 and units * 86400 / seconds or nil
    return {
        verdict = r.verdict,
        trend = { price = r.price, stock = r.stock, days = r.days, age = r.age },
        estimatedSalesPerDay = perDay,
        confidence = perDay and (days >= 2 and scans >= 3 and "high" or "low") or nil,
        history = hist,
        today = today,
        tiers = encoded and decode(encoded) or {},
        daily = daily,
    }
end
