-- VepIndustriesMarket market: the single entry point the UI reads. No UI, testable outside the game.
-- Saved in VepIndustriesMarketDB: fullScan = { time, items = { [itemID] = tiers string } } (latest full scan only)
-- daily = { [itemID] = { [Auctionator day] = "price stock scans[ estimatedSales seconds]" } } (daily summary, its estimated
-- sales merged by Tranche from the Comparisons) and comparisons = { { author, realm, faction, start, finish, items =
-- "itemID sold stock price,..." }, ... } (the latest, see addComparison and tests/merge-cases.json), author = their
-- author for the whole account.
local GM = VepIndustriesMarket
local T = GM.Trend
GM.Market = GM.Market or {}
local M = GM.Market

M.WINDOW = T.WINDOW
-- verdict from reliable estimated sales, by the days the current stock lasts at that pace: demand below DEMAND_DAYS,
-- saturated above SATURATED_DAYS (stock left without any sale included), stable between.
-- ponytail: provisional, picked on one evening of scans (2026-11-21); calibrate with Boris on 3 days of scans (#7)
M.DEMAND_DAYS, M.SATURATED_DAYS = 2, 7
-- daily summary kept, the span of the /vim window: ~170 KB per day of scans, ~55 KB more with estimated sales,
-- ~5.6 MB in all after 21 days (accepted)
local KEEP_DAYS = 21
-- Comparisons kept until the VPS counts them (#21; a day at most until then), the MAX_COMPARISONS latest only
-- ponytail: count cap for the size of the save, drops uncounted ones past 6 h of scans; drop counted ones first with #21
M.MAX_COMPARISONS = 24
local KEEP_COMPARISONS = 86400
-- Tranche: a fixed half hour of the day, unit of the merge of Comparisons
local TRANCHE = 1800

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
-- Both may hold decimals: they are averages over the authors of each Tranche.
local function readDay(v)
    local p, s, n, u, e = (v or ""):match("^(%S+) (%d+) (%d+) ?([%d.]*) ?([%d.]*)$")
    return { price = tonumber(p), stock = tonumber(s), scans = tonumber(n), estimatedSales = tonumber(u) or 0,
        seconds = tonumber(e) or 0 }
end

-- at most 2 decimals, trailing zeros dropped
local function num(x) return (string.format("%.2f", math.max(0, x)):gsub("%.?0+$", "")) end

local function writeDay(daily, id, day, d)
    daily[id] = daily[id] or {}
    daily[id][day] = string.format("%s %d %d", d.price and string.format("%d", d.price) or "-", d.stock or 0,
            d.scans or 0)
        .. (d.seconds >= 0.005 and " " .. num(d.estimatedSales) .. " " .. num(d.seconds) or "")
end

-- adds one scan of item `id` to its day (price nil: sold out)
local function addDay(daily, id, day, price, stock)
    local d = readDay(daily[id] and daily[id][day])
    if price and not (d.price and d.price <= price) then d.price = price end
    d.stock, d.scans = math.max(d.stock or 0, stock), (d.scans or 0) + 1
    writeDay(daily, id, day, d)
end

local function addSales(daily, id, day, units, seconds)
    local d = readDay(daily[id] and daily[id][day])
    d.estimatedSales, d.seconds = d.estimatedSales + units, d.seconds + seconds
    writeDay(daily, id, day, d)
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

-- first and last Tranche (half hours from day0) Comparison `c` covers
local function tranches(c, day0)
    return math.floor((c.start - day0) / TRANCHE), math.floor((c.finish - 1 - day0) / TRANCHE)
end

-- Merge by Tranche of `comparisons` (the Tranches first..last only, when given), day0 the start of day 0:
-- { [itemID] = { [tranche] = { units, seconds } } }. Each Comparison spreads an item's units over the Tranches it
-- covers, prorata of its time in each; an author's Comparisons in a Tranche add up (they never overlap), and authors
-- average out, units and seconds alike: players scanning at once see the same purchases. Items not compared ignored.
-- Same rule on the server: tests/merge-cases.json.
function M.Merge(comparisons, day0, first, last)
    local byAuthor, done = {}, 0 -- [itemID][tranche][author] = { units, seconds }
    for _, c in ipairs(comparisons) do
        local from, to = tranches(c, day0)
        for k = math.max(from, first or from), math.min(to, last or to) do
            local at = day0 + k * TRANCHE
            local share = math.min(c.finish, at + TRANCHE) - math.max(c.start, at)
            for id, sold in c.items:gmatch("(%d+) (%S+) %d+ [^,]+") do
                done = done + 1
                if done % 200 == 0 then pause() end
                sold, id = tonumber(sold), tonumber(id)
                if sold then
                    byAuthor[id] = byAuthor[id] or {}
                    byAuthor[id][k] = byAuthor[id][k] or {}
                    local a = byAuthor[id][k][c.author] or { 0, 0 }
                    byAuthor[id][k][c.author] = a
                    a[1], a[2] = a[1] + sold * share / (c.finish - c.start), a[2] + share
                end
            end
        end
    end
    local merged = {}
    for id, ks in pairs(byAuthor) do
        merged[id] = {}
        for k, authors in pairs(ks) do
            local n, units, seconds = 0, 0, 0
            for _, a in pairs(authors) do n, units, seconds = n + 1, units + a[1], seconds + a[2] end
            merged[id][k] = { units / n, seconds / n }
        end
    end
    return merged
end

-- Keeps Comparison `c` (once per author and start) and adds to the daily summary what it changes in the merge of
-- the Tranches it covers, against the kept Comparisons of the same auction house.
local function addComparison(db, c, day0)
    local kept, near = db.comparisons or {}, {}
    local first, last = tranches(c, day0)
    for _, o in ipairs(kept) do
        if o.author == c.author and o.start == c.start then return end
        if o.realm == c.realm and o.faction == c.faction and o.finish > day0 + first * TRANCHE
            and o.start < day0 + (last + 1) * TRANCHE then near[#near + 1] = o end
    end
    local before = M.Merge(near, day0, first, last)
    near[#near + 1] = c
    for id, ks in pairs(M.Merge(near, day0, first, last)) do
        for k, v in pairs(ks) do
            local b = before[id] and before[id][k] or { 0, 0 }
            addSales(db.daily, id, math.floor(k * TRANCHE / 86400), v[1] - b[1], v[2] - b[2])
        end
    end
    kept[#kept + 1] = c
    db.comparisons = kept
end

local function byPrice(a, b)
    if a.price ~= b.price then return a.price < b.price end
    if a.size ~= b.size then return a.size < b.size end
    return a.timeLeft < b.timeLeft
end

-- Full scan: { [itemID] = { { price (unit, integer copper), size, count, timeLeft }, ... } } taken at time `now`
-- by character `author` on the auction house of `realm` and `faction` (one per faction: scans to compare must share
-- both). The account's Comparisons all take the first author's name (db.author).
-- Replaces the stored full scan and adds it to the daily summary (lowest price, highest stock of the day). Compared
-- with the stored scan when it is from the same auction house, at most MAX_GAP older: a Comparison, kept and merged
-- by Tranche into the estimated sales of the daily summary. A scan
-- without any auction is ignored; one less than MIN_GAP newer, or holding the same data (/vim relire), is not
-- compared and keeps the stored scan's time, so that the next comparison spans the real time.
function M.Ingest(scan, now, realm, faction, author)
    local db, day, day0 = VepIndustriesMarketDB, T.Today(now), T.Day0()
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
    -- the account's author: its full scans form one chain whatever the character scanning
    db.author = db.author or author
    db.daily = db.daily or {}
    local prev, daily = db.fullScan, db.daily
    local gap = prev and prev.realm == realm and prev.faction == faction and now - prev.time
    if gap and (gap < MIN_GAP or sameItems(prev.items, items)) then now, gap = prev.time, nil end
    if gap and gap > MAX_GAP then gap = nil end
    local before, entries = gap and prev.items or {}, {}
    local function entry(id, sold, stock, price)
        entries[#entries + 1] = string.format("%d %s %d %s", id, sold and string.format("%d", sold) or "-", stock,
            price and string.format("%d", price) or "-")
    end
    done = 0
    for id in pairs(items) do
        done = done + 1
        if done % 200 == 0 then pause() end
        local tiers = scan[id]
        addDay(daily, id, day, tiers[1].price, stocks[id])
        if gap then entry(id, before[id] and estimatedSales(decode(before[id]), tiers, gap), stocks[id], tiers[1].price) end
    end
    for id, encoded in pairs(before) do -- sold out
        if not items[id] then
            addDay(daily, id, day, nil, 0)
            entry(id, estimatedSales(decode(encoded), {}, gap), 0, nil)
        end
    end
    if gap then
        addComparison(db, { author = db.author, realm = realm, faction = faction, start = prev.time, finish = now,
            items = table.concat(entries, ",") }, day0)
    end
    local kept = {}
    for _, c in ipairs(db.comparisons or {}) do
        if c.finish > now - KEEP_COMPARISONS then kept[#kept + 1] = c end
    end
    while #kept > M.MAX_COMPARISONS do table.remove(kept, 1) end
    db.comparisons = kept
    for id, days in pairs(daily) do
        for d in pairs(days) do
            if d <= day - KEEP_DAYS then days[d] = nil end
        end
        if next(days) == nil then daily[id] = nil end
    end
    db.fullScan = { time = now, realm = realm, faction = faction, items = items }
end

-- { time, realm, faction, items, bytes } of the stored full scan (bytes: rough size on disk, daily summary and
-- Comparisons included), nil without one
function M.Status()
    local fs = VepIndustriesMarketDB and VepIndustriesMarketDB.fullScan
    if not fs then return nil end
    local items, bytes = 0, 0
    for _, s in pairs(fs.items) do items, bytes = items + 1, bytes + #s + 16 end
    for _, days in pairs(VepIndustriesMarketDB.daily or {}) do
        bytes = bytes + 16
        for _, v in pairs(days) do bytes = bytes + #v + 14 end
    end
    for _, c in ipairs(VepIndustriesMarketDB.comparisons or {}) do bytes = bytes + #c.items + 120 end
    return { time = fs.time, realm = fs.realm, faction = fs.faction, items = items, bytes = bytes }
end

-- { verdict, source, trend = { price, stock, days, age }, estimatedSalesPerDay, estimatedSalesDays (compared days in
-- the window), confidence, history, today, tiers, daily }. verdict from the estimated sales when their confidence is "high" (source "sales"), from the trend otherwise
-- (source "trend"); the stock they are set against is the item's in the latest full scan, 0 when absent.
-- price/stock: relative change of the latest day vs the median of the window; history: ascending { day, price, stock }
-- tiers: the item in the latest full scan, by price, lot size, time left; daily: { [day] = { price, stock, scans,
-- estimatedSales, seconds, estimatedSalesPerDay, reliable } }, the last two on compared days only. estimatedSalesPerDay
-- over the window, nil before two compared scans; confidence "high" from 2 days of comparisons in the window (so at
-- least 3 scans), "low" below; a day is reliable when it is in the window of a "high" confidence.
function M.Report(itemID)
    local hist = T.History(itemID) or {}
    local today = T.Today()
    local r = T.Compute(hist, today) or { verdict = "none", days = 0 }
    local db = VepIndustriesMarketDB or {}
    local encoded = db.fullScan and db.fullScan.items[itemID]
    local daily, days, units, seconds = {}, 0, 0, 0
    local function inWindow(d) return today and d > today - M.WINDOW end
    for d, v in pairs(db.daily and db.daily[itemID] or {}) do
        daily[d] = readDay(v)
        if inWindow(d) and daily[d].seconds > 0 then
            days, units, seconds = days + 1, units + daily[d].estimatedSales, seconds + daily[d].seconds
        end
    end
    local perDay, reliable = seconds > 0 and units * 86400 / seconds or nil, days >= 2
    for d, e in pairs(daily) do
        if e.seconds > 0 then
            e.estimatedSalesPerDay, e.reliable = e.estimatedSales * 86400 / e.seconds, reliable and inWindow(d)
        end
    end
    local tiers, verdict, source = encoded and decode(encoded) or {}, r.verdict, "trend"
    if perDay and reliable then
        local stock = 0
        for _, t in ipairs(tiers) do stock = stock + t.size * t.count end
        verdict, source = stock < M.DEMAND_DAYS * perDay and "demand"
            or stock > M.SATURATED_DAYS * perDay and "saturated" or "stable", "sales"
    end
    return {
        verdict = verdict,
        source = source,
        trend = { price = r.price, stock = r.stock, days = r.days, age = r.age },
        estimatedSalesPerDay = perDay,
        estimatedSalesDays = days,
        confidence = perDay and (reliable and "high" or "low") or nil,
        history = hist,
        today = today,
        tiers = tiers,
        daily = daily,
    }
end
