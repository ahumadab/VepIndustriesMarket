-- Sales under a new lower minimum: infer only what visible reposts and possible expiry cannot explain.
loadAddonFile("Trend.lua")
loadAddonFile("Market.lua")
local M = VepIndustriesMarket.Market
local function sold(before, after, gap)
    VepIndustriesMarketDB = {}
    gap = gap or 1200
    M.Ingest({ [950] = before }, time(), "PvE", "Horde", "Boris")
    -- Keep the second full scan nonempty even when the item sold out.
    M.Ingest({ [950] = after, [951] = { tier(1, 1, 1, 3) } }, time() + gap, "PvE", "Horde", "Boris")
    return M.Report(950).daily[TODAY].estimatedSales
end

ok(sold({ tier(100, 1, 10, 3) }, { tier(100, 1, 4, 3), tier(90, 1, 2, 4) }) == 4,
    "prix en baisse : 6 disparues, 2 nouvelles moins cher -> 4 ventes estimees au lieu de 0")

ok(sold({ tier(100, 1, 10, 3) }, { tier(90, 1, 10, 4) }) == 0,
    "republication moins cher de toute la quantite : pas une vente")
ok(sold({ tier(100, 1, 10, 3) }, { tier(90, 1, 15, 4) }) == 0,
    "stock en hausse au nouveau prix : pas de vente ajoutee")
ok(sold({ tier(100, 1, 10, 3) }, { tier(90, 1, 1, 4), tier(110, 1, 9, 4) }) == 0,
    "republications reparties moins ET plus cher : toutes les hausses deduites")
ok(sold({ tier(100, 1, 10, 3) }, { tier(90, 1, 1, 4), tier(100, 1, 4, 3), tier(110, 1, 2, 4) }) == 3,
    "6 disparues, 3 reapparues a plusieurs prix : 3 estimees")
ok(sold({ tier(100, 1, 10, 3), tier(200, 1, 100, 3) }, { tier(100, 1, 10, 3), tier(90, 1, 2, 4) }) == 0,
    "annulation chere sous un nouveau minimum : toujours ignoree")
ok(sold({ tier(100, 1, 10, 1) }, { tier(100, 1, 4, 1), tier(90, 1, 2, 4) }) == 0,
    "disparitions pouvant etre des expirations : pas de vente ajoutee")
ok(sold({ tier(100, 1, 10, 2) }, { tier(100, 1, 4, 1), tier(90, 1, 2, 4) }, 3600) == 0,
    "Medium sur une heure : expiration possible, pas de vente ajoutee")
ok(sold({ tier(100, 1, 10, 3), tier(100, 1, 4, 1) }, { tier(100, 1, 4, 3), tier(90, 1, 2, 4) }) == 4,
    "4 expirations possibles deduites avant les 2 republications : 4 estimees")
ok(sold({ tier(100, 5, 2, 3) }, { tier(100, 1, 10, 3), tier(90, 1, 2, 4) }) == 0,
    "changement de taille de pile au meme prix : pas une vente")
ok(sold({ tier(90, 1, 5, 3), tier(100, 1, 10, 3) },
    { tier(80, 1, 1, 4), tier(90, 1, 2, 3), tier(100, 1, 5, 3) }) == 2,
    "seul l'ancien minimum est ajoute, pas les disparitions plus cher")
ok(sold({ tier(90, 1, 5, 3), tier(100, 1, 10, 3) },
    { tier(80, 1, 1, 4), tier(100, 1, 10, 3) }) == 4,
    "ancien minimum epuise, une unite reapparue sous ce prix : 4 estimees")
ok(sold({ tier(80, 1, 5, 3), tier(100, 1, 10, 3) },
    { tier(90, 1, 100, 4), tier(100, 1, 10, 3) }) == 5,
    "minimum en hausse : calcul existant conserve meme avec de nouvelles annonces")
ok(sold({ tier(100, 1, 10, 3) }, {}) == 10,
    "objet epuise : calcul existant conserve")
