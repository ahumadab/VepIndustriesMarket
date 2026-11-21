-- VepIndustriesMarket trend: reads Auctionator's daily history (min price + max quantity per day) and turns it into a verdict.
-- Pure logic (no UI) so it can be tested outside the game.
VepIndustriesMarket = VepIndustriesMarket or {}
local GM = VepIndustriesMarket
GM.Trend = GM.Trend or {}
local T = GM.Trend

T.WINDOW = 7 -- days compared against the latest scan day

-- Auctionator scan day (days since 2020-01-01)
function T.Today()
    local c = Auctionator and Auctionator.Constants
    if c and c.SCAN_DAY_0 then return math.floor((time() - c.SCAN_DAY_0) / 86400) end
end

-- Ascending list { day, price, stock } for an item, from Auctionator's database.
function T.History(itemID)
    local db = Auctionator and Auctionator.Database
    if not db or not db.GetPriceHistory or not itemID then return nil end
    local ok, h = pcall(db.GetPriceHistory, db, tostring(itemID))
    if not ok or type(h) ~= "table" then return nil end
    local out = {}
    for _, e in ipairs(h) do
        local d = tonumber(e.rawDay)
        if d then out[#out + 1] = { day = d, price = e.minSeen, stock = e.available } end
    end
    table.sort(out, function(a, b) return a.day < b.day end)
    return out
end

-- median, not mean: one stray cheap auction (e.g. 1s18 on a 4s item) must not swing the verdict
local function avg(list, field)
    local v = {}
    for _, e in ipairs(list) do
        if e[field] then v[#v + 1] = e[field] end
    end
    if #v == 0 then return nil end
    table.sort(v)
    local m = math.floor((#v + 1) / 2)
    if #v % 2 == 1 then return v[m] end
    return (v[m] + v[m + 1]) / 2
end

-- demand    : stock falls while price holds, or price climbs without more stock
-- saturated : stock piles up without the price following, or price drops
function T.Verdict(p, s)
    if not p then return "none" end
    s = s or 0
    if (s <= -0.25 and p >= -0.05) or (p >= 0.15 and s <= 0.10) then return "demand" end
    if (s >= 1.0 and p < 0.15) or (s >= 0.40 and p <= 0.05) or (p <= -0.15 and s >= 0) then return "saturated" end
    return "stable"
end

-- Latest day vs the average of the earlier days inside the window.
-- Returns { verdict, price, stock (relative changes), days (points used), last, age (days since last data) }
function T.Compute(hist, today, window)
    window = window or T.WINDOW
    if not hist or #hist == 0 then return nil end
    local last = hist[#hist]
    today = today or last.day
    local from = today - window
    local prev = {}
    for i = 1, #hist - 1 do
        if hist[i].day >= from then prev[#prev + 1] = hist[i] end
    end
    local r = { last = last, days = #prev + 1, age = today - last.day }
    if #prev == 0 or r.age > window then
        r.verdict = "none"; return r
    end
    local pp, ps = avg(prev, "price"), avg(prev, "stock")
    if pp and pp > 0 and last.price then r.price = (last.price - pp) / pp end
    if ps and ps > 0 and last.stock then r.stock = (last.stock - ps) / ps end
    r.verdict = T.Verdict(r.price, r.stock)
    return r
end

function T.ForItem(itemID)
    local hist = T.History(itemID)
    return T.Compute(hist, T.Today()), hist
end
