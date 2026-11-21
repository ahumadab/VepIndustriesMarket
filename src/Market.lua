-- VepIndustriesMarket market: the single entry point the UI reads. No UI, testable outside the game.
local GM = VepIndustriesMarket
local T = GM.Trend
GM.Market = GM.Market or {}
local M = GM.Market

M.WINDOW = T.WINDOW

-- Full scan: { [itemID] = { { price, size, count, timeLeft }, ... } } at time `now`.
-- Accepted but unused until estimated sales are computed.
function M.Ingest(scan, now) end

-- { verdict, trend = { price, stock, days, age }, salesPerDay, confidence, history, today }
-- price/stock: relative change of the latest day vs the median of the window; history: ascending { day, price, stock }
function M.Report(itemID)
    local hist = T.History(itemID) or {}
    local today = T.Today()
    local r = T.Compute(hist, today) or { verdict = "none", days = 0 }
    return {
        verdict = r.verdict,
        trend = { price = r.price, stock = r.stock, days = r.days, age = r.age },
        history = hist,
        today = today,
    }
end
