-- Exchange in game (Exchange.lua, #24): scripted guild members against our addon, through the real ChatThrottleLib
-- and the doubles of C_ChatInfo. A game frame of 0.05 s runs the timers due, then ChatThrottleLib's OnUpdate.
dofile("fixtures/fullscan-1121-2023.lua")
dofile("fixtures/fullscan-1121-2039.lua")
local t2 = time() - 3600 -- today 00:00
local timers = {}
C_Timer = { After = function(delay, fn) timers[#timers + 1] = { at = chat.clock + delay, fn = fn } end }
VepIndustriesMarketDB = {}
loadAddon()
fire("ADDON_LOADED", "VepIndustriesMarket")
local M, X = VepIndustriesMarket.Market, VepIndustriesMarket.Exchange
local function play(seconds)
  local stop = chat.clock + seconds
  while chat.clock < stop do
    chat.clock = chat.clock + 0.05
    local due, later = {}, {}
    for _, t in ipairs(timers) do
      if t.at <= chat.clock then due[#due + 1] = t else later[#later + 1] = t end
    end
    timers = later
    for _, t in ipairs(due) do t.fn() end
    local ctl = ChatThrottleLib.Frame
    if ctl:IsShown() then rawget(ctl, "OnUpdate")(ctl, 0.05) end
  end
end
local function heard(text, channel, sender) fire("CHAT_MSG_ADDON", X.PREFIX, text, channel, sender) end
local function whisper(texts, sender, from, to)
  for k = from or 1, to or #texts do heard(texts[k], "WHISPER", sender) end
end
-- our whispers to `name` since the outbox was emptied, of `kind` and `key` when given: { i, n, key, data, size, at }
local function to(name, kind, key)
  local got = {}
  for _, m in ipairs(chat.outbox) do
    local k, i, n, mkey, data = m.text:match("^(%u)(%d+) (%d+) ([^\t]*)\t(.*)$")
    if m.target == name and (not kind or k == kind) and (not key or mkey == key) then
      got[#got + 1] = { i = tonumber(i), n = tonumber(n), key = mkey, data = data, size = #m.text, at = m.at }
    end
  end
  return got
end
-- the payload of whole messages, in order, nil when one is missing or out of place
local function payload(msgs)
  local data = {}
  for k, m in ipairs(msgs) do
    if m.i ~= k or m.n ~= #msgs then return nil end
    data[k] = m.data
  end
  return #msgs > 0 and X.Unpack(table.concat(data)) or nil
end
local function guild()
  local last
  for _, m in ipairs(chat.outbox) do if m.channel == "GUILD" then last = m.text end end
  return last
end

M.Ingest(rowsToScan(FULLSCAN_1121_2023), t2, "PvE", "Horde", "Boris")
M.Ingest(rowsToScan(FULLSCAN_1121_2039), t2 + 919, "PvE", "Horde", "Boris")
local mine = VepIndustriesMarketDB.comparisons[1]
local MINE = "Boris " .. t2
local theirs = { author = "Ami", realm = "PvE", faction = "Horde", start = t2 + 600, finish = t2 + 1519, items = mine.items }
local THEIRS = "Ami " .. theirs.start
local packed = X.Pack("C", THEIRS, X.Encode(theirs))

fire("PLAYER_LOGIN"); play(15)
ok(guild() == "A 0 " .. (t2 + 919) .. " 0.2.0-dev+abc1234", "echange : annonce en guilde a la connexion " .. tostring(guild()))
chat.outbox = {}
heard("A 0 " .. theirs.finish, "GUILD", "Ami Epice"); play(1)
ok(payload(to("Ami-Epice", "W")) == "1 0\n" .. MINE, "echange : annonce entendue -> inventaire chuchote, au nom Prenom-Nom")
heard("A 0 0", "GUILD", "Boris"); heard("A 0 " .. theirs.finish, "PARTY", "Ami Epice")
ok(#to("Boris") == 0 and #to("Ami-Epice") == 1, "echange : notre propre annonce et les autres canaux ignores")

-- a newer release in a guild member's announce: told once; an older one, the same, or a dev build: nothing
local function news(version)
  local before = #said
  heard("A 9999999999 0 " .. version, "GUILD", "Ami Epice") -- nothing to give: no inventory whispered
  return #said > before and lastSaid() or nil
end
local fresh = news("0.2.1")
ok(fresh and fresh:find("0.2.1", 1, true) and fresh:find("0.2.0", 1, true) and fresh:find("zip"),
  "echange : version plus recente annoncee en guilde -> signalee " .. tostring(fresh))
ok(not news("0.2.1") and not news("0.2.0") and not news("0.1.9") and not news("0.3.0-dev+abc") and not news("x"),
  "echange : meme version deja signalee, plus ancienne, identique ou de developpement -> rien")
ok(news("0.10.0"), "echange : versions comparees nombre par nombre (0.10.0 apres 0.2.1)")
-- the announce of a later version, with fields this one does not know: still understood
chat.outbox = {}
heard("A 0 " .. theirs.finish .. " 0.11.0 champ futur", "GUILD", "Futur Nom"); play(1)
ok(payload(to("Futur-Nom", "W")) == "1 0\n" .. MINE and lastSaid():find("0.11.0", 1, true),
  "echange : annonce d'une version future avec un champ inconnu -> inventaire chuchote, version signalee")

-- the friend's inventory lacks ours and lists one of theirs: ours goes, cut into messages, then our inventory
chat.outbox = {}
whisper(X.Pack("W", "", "1 0\n" .. THEIRS), "Ami Epice"); play(60)
local sent, small = to("Ami-Epice", "C", MINE), true
for _, m in ipairs(sent) do small = small and m.size <= 255 end
ok(#sent > 10 and small and payload(sent) == X.Encode(mine),
  string.format("echange : Comparaison decoupee en %d messages de 255 octets au plus, reassemblee a l'identique", #sent))
ok(payload(to("Ami-Epice", "W")) == "0 0\n" .. MINE, "echange : notre inventaire en retour, l'autre ayant ce qui nous manque")
local mineTexts = {}
for k, m in ipairs(chat.outbox) do if m.text:find("^C") then mineTexts[#mineTexts + 1] = m.text end end

-- the same Comparison sent back: already known, ignored; reassembled by a guild member without it, kept and announced
whisper(mineTexts, "Ami Epice"); play(2)
ok(#VepIndustriesMarketDB.comparisons == 1, "echange : Comparaison deja connue ignoree")
local ours = VepIndustriesMarketDB
VepIndustriesMarketDB, chat.outbox = {}, {}
whisper(mineTexts, "Tiers Nom"); play(2)
local got = VepIndustriesMarketDB.comparisons and VepIndustriesMarketDB.comparisons[1] or {}
local early = guild()
play(60)
ok(got.author == "Boris" and got.start == t2 and got.finish == t2 + 919 and got.items == mine.items
  and not early and guild() == "A 0 " .. (t2 + 919) .. " 0.2.0-dev+abc1234",
  "echange : Comparaison reassemblee chez un autre, gardee, annoncee une minute apres la derniere recue")
VepIndustriesMarketDB = ours
-- before the auction house loads the data file, the time of the one the previous session loaded
chat.outbox, VepIndustriesMarketDB.dataGenerated = {}, t2 - 600
heard("A 0 " .. theirs.finish, "GUILD", "Ami Epice"); play(1)
ok(payload(to("Ami-Epice", "W")) == "1 " .. (t2 - 600) .. "\n" .. MINE,
  "echange : fichier de donnees pas encore charge, heure de celui de la session precedente")
VepIndustriesMarketDB.dataGenerated = nil

-- a transfer cut after 5 messages (the friend logged out): our next inventory tells it, the rest completes it
chat.outbox = {}
whisper(packed, "Ami Epice", 1, 5)
heard("A 0 " .. theirs.finish, "GUILD", "Ami Epice"); play(1)
local inv = payload(to("Ami-Epice", "W")) or ""
ok(inv:find("\n" .. THEIRS .. " 5", 1, true), "echange : transfert interrompu, inventaire avec les morceaux recus " .. inv)
chat.outbox = {}
whisper(packed, "Ami Epice", 6); play(61)
ok(#VepIndustriesMarketDB.comparisons == 2 and M.Seen()[THEIRS] == theirs.finish
  and guild() == "A 0 " .. theirs.finish .. " 0.2.0-dev+abc1234",
  "echange : transfert repris, Comparaison gardee et annoncee (relais)")
-- our side resumed: the friend got 20 messages of ours
chat.outbox = {}
whisper(X.Pack("W", "", "0 0\n" .. THEIRS .. "\n" .. MINE .. " 20"), "Ami Epice"); play(60)
sent = to("Ami-Epice", "C", MINE)
ok(#sent > 0 and sent[1].i == 21 and sent[#sent].i == sent[1].n and #sent == sent[1].n - 20,
  "echange : notre envoi repris au 21e message")
-- the friend reloaded during our transfer: its new inventory, without the chunks it lost, restarts it
chat.outbox = {}
whisper(X.Pack("W", "", "0 0\n" .. MINE), "Huit Nom"); play(3)
local cut = #to("Huit-Nom", "C", THEIRS)
chat.outbox = {}
whisper(X.Pack("W", "", "0 0\n" .. MINE), "Huit Nom"); play(60)
ok(cut > 0 and cut < #packed and payload(to("Huit-Nom", "C", THEIRS)) == X.Encode(theirs),
  "echange : destinataire relance pendant l'envoi, envoi repris du debut")

-- relay: a member who has none gets ours and the friend's; one whose data file is newer than ours, the friend's only
chat.outbox = {}
whisper(X.Pack("W", "", "0 0"), "Tiers Nom"); whisper(X.Pack("W", "", "0 " .. (t2 + 1000)), "Quatre Nom"); play(120)
ok(payload(to("Tiers-Nom", "C", MINE)) == X.Encode(mine) and payload(to("Tiers-Nom", "C", THEIRS)) == X.Encode(theirs),
  "echange : Comparaison recue retransmise (relais)")
ok(#to("Quatre-Nom", "C", MINE) == 0 and payload(to("Quatre-Nom", "C", THEIRS)) == X.Encode(theirs),
  "echange : seules les Comparaisons posterieures au fichier de donnees de l'autre")

-- refusals: for rate (3, 8), then a lockdown (InChatMessagingLockdown, code 11); sent again later, nothing lost
chat.outbox, chat.refuse = {}, { 3, 3, 3, 8, 8 }
whisper(X.Pack("W", "", "0 0\n" .. MINE), "Cinq Nom"); play(60)
ok(#chat.refuse == 0 and payload(to("Cinq-Nom", "C", THEIRS)) == X.Encode(theirs), "echange : refus pour debit puis reprise")
chat.outbox, chat.locked = {}, true
whisper(X.Pack("W", "", "0 0\n" .. MINE), "Six Nom"); play(20)
local during = #to("Six-Nom")
chat.locked, chat.refuse = false, { 11, 11 }
play(60)
ok(during == 0 and #chat.refuse == 0 and payload(to("Six-Nom", "C", THEIRS)) == X.Encode(theirs),
  "echange : blocage puis reprise")

-- in an instance, a whisper a second at most (prefix allowance, wiki); outside, ChatThrottleLib's pace (~800 bytes/s)
local function gaps(msgs)
  local least, span = math.huge, msgs[#msgs].at - msgs[1].at
  for k = 2, #msgs do least = math.min(least, msgs[k].at - msgs[k - 1].at) end
  return least, span
end
local _, outside = gaps(to("Six-Nom", "C", THEIRS))
chat.outbox, chat.instance = {}, true
whisper(X.Pack("W", "", "0 0\n" .. MINE), "Sept Nom"); play(#packed + 10)
chat.instance = nil
local least = gaps(to("Sept-Nom", "C", THEIRS))
ok(payload(to("Sept-Nom", "C", THEIRS)) and least >= 0.95 and outside < #packed * 0.6,
  string.format("echange : en instance, %.2f s au moins entre deux messages ; hors instance, %d messages en %.1f s",
    least, #packed, outside))

-- /vim echange: our Comparisons whispered to ourselves come back, checked
chat.outbox = {}
SlashCmdList.VEPINDUSTRIESMARKET("echange"); play(60)
local back, told = {}, lastSaid()
for _, m in ipairs(chat.outbox) do if m.target == "Boris" then back[#back + 1] = m.text end end
whisper(back, "Boris"); play(1)
ok(told:find("2 Comparaison") and #back > #packed and lastSaid():find("revenue intacte")
  and #VepIndustriesMarketDB.comparisons == 2, "/vim echange : Comparaisons chuchotees a soi-meme, revenues intactes " .. lastSaid())

-- the friend left: the game's "No player named ..." is hidden and the transfer stops; other lines stay
chat.outbox = {}
SlashCmdList.VEPINDUSTRIESMARKET("echange Parti Loin"); play(3)
local before = #to("Parti-Loin")
local filter = chat.filters.CHAT_MSG_SYSTEM
local hidden = filter and filter(nil, "CHAT_MSG_SYSTEM", ERR_CHAT_PLAYER_NOT_FOUND_S:format("Parti Loin"))
local shown = filter and filter(nil, "CHAT_MSG_SYSTEM", ERR_CHAT_PLAYER_NOT_FOUND_S:format("Inconnu"))
play(30)
ok(before > 0 and hidden and not shown and #to("Parti-Loin") <= before + 1 and #to("Parti-Loin") < #packed,
  "echange : « No player named » filtre pour un destinataire parti, transfert arrete (sauf le message deja confie a ChatThrottleLib)")
ok(not chat.error, "echange : aucune erreur de ChatThrottleLib " .. tostring(chat.error))
