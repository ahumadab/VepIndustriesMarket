-- VepIndustriesMarket market: the single entry point the UI reads. No UI, testable outside the game.
-- Saved in VepIndustriesMarketDB: fullScan = { time, items = { [itemID] = tiers string } } (latest full scan only)
-- and daily = { [itemID] = { [Auctionator day] = "price stock scans" } } (daily summary, mergeable between players).
local GM = VepIndustriesMarket
local T = GM.Trend
GM.Market = GM.Market or {}
local M = GM.Market

M.WINDOW = T.WINDOW
-- daily summary kept, the span of the /vim window: ~170 KB per day of scans, ~4.4 MB in all after 21 days (accepted)
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

-- daily summary of one day: "price stock scans" <-> numbers
local function readDay(v)
    local p, s, n = (v or ""):match("^(%d+) (%d+) (%d+)$")
    return tonumber(p), tonumber(s), tonumber(n)
end

local function byPrice(a, b)
    if a.price ~= b.price then return a.price < b.price end
    if a.size ~= b.size then return a.size < b.size end
    return a.timeLeft < b.timeLeft
end

-- Full scan: { [itemID] = { { price (unit, integer copper), size, count, timeLeft }, ... } } taken at time `now`.
-- Replaces the stored full scan and adds it to the daily summary (lowest price, highest stock of the day).
function M.Ingest(scan, now)
    local db, day = VepIndustriesMarketDB, T.Today(now)
    if not db or not day then return end
    local items, daily = {}, db.daily or {}
    for id, tiers in pairs(scan) do
        if tiers[1] then
            table.sort(tiers, byPrice)
            local tokens, stock = {}, 0
            for i, t in ipairs(tiers) do
                tokens[i] = encode(t, tiers[i - 1])
                stock = stock + t.size * t.count
            end
            items[id] = table.concat(tokens, " ")
            daily[id] = daily[id] or {}
            local p, s, n = readDay(daily[id][day])
            daily[id][day] = string.format("%d %d %d", math.min(p or math.huge, tiers[1].price),
                math.max(s or 0, stock), (n or 0) + 1)
        end
    end
    for id, days in pairs(daily) do
        for d in pairs(days) do
            if d <= day - KEEP_DAYS then days[d] = nil end
        end
        if next(days) == nil then daily[id] = nil end
    end
    db.fullScan = { time = now, items = items }
    db.daily = daily
end

-- { time, items, bytes } of the stored full scan (bytes: rough size on disk, daily summary included), nil without one
function M.Status()
    local fs = VepIndustriesMarketDB and VepIndustriesMarketDB.fullScan
    if not fs then return nil end
    local items, bytes = 0, 0
    for _, s in pairs(fs.items) do items, bytes = items + 1, bytes + #s + 16 end
    for _, days in pairs(VepIndustriesMarketDB.daily or {}) do
        bytes = bytes + 16
        for _, v in pairs(days) do bytes = bytes + #v + 14 end
    end
    return { time = fs.time, items = items, bytes = bytes }
end

-- { verdict, trend = { price, stock, days, age }, estimatedSalesPerDay, confidence, history, today, tiers, daily }
-- price/stock: relative change of the latest day vs the median of the window; history: ascending { day, price, stock }
-- tiers: the item in the latest full scan, by price, lot size, time left; daily: { [day] = { price, stock, scans } }
function M.Report(itemID)
    local hist = T.History(itemID) or {}
    local today = T.Today()
    local r = T.Compute(hist, today) or { verdict = "none", days = 0 }
    local db = VepIndustriesMarketDB or {}
    local encoded = db.fullScan and db.fullScan.items[itemID]
    local daily = {}
    for d, v in pairs(db.daily and db.daily[itemID] or {}) do
        local p, s, n = readDay(v)
        daily[d] = { price = p, stock = s, scans = n }
    end
    return {
        verdict = r.verdict,
        trend = { price = r.price, stock = r.stock, days = r.days, age = r.age },
        history = hist,
        today = today,
        tiers = encoded and decode(encoded) or {},
        daily = daily,
    }
end
