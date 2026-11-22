-- VepIndustriesMarket exchange: guild members' addons share their Comparisons in game, by addon messages (#24).
-- - Announce, on GUILD, at login and after every new Comparison (ours or received): "A <generated> <finish>", the time
--   of our data file (0 without one) and the end of our latest Comparison.
-- - Who hears it and may give or take whispers back its inventory, payload "W": "<ask> <generated>", then a line per
--   Comparison it knows that ends after its data file ("author start", see Market.Id), and one per Comparison it got
--   part of from that player ("author start chunks").
-- - Who gets an inventory whispers each Comparison the other lacks and ending after the other's data file (payload "C",
--   from the chunk the other stopped at), and, when asked (ask 1) and the other knows some it lacks, its own inventory
--   (ask 0, not answered in kind).
-- A received Comparison is kept as ours (Market.Receive), then announced: friends who log in later get it by relay. The
-- data file counts those the Sync script sent, whoever their author.
-- Whispers: payload compressed (C_EncodingUtil), \0 escaped, cut into messages of 255 bytes "<kind><i> <n> <key>\t
-- <data>", sent one at a time through ChatThrottleLib (BULK, shared with every addon embedding it): a refusal for
-- rate (3, 8) or a chat lockdown (11, InChatMessagingLockdown, during some fights) sends the same chunk again RETRY s
-- later, nothing is lost. Measured on Forever (#19): outside instances, no whisper refused at 1 250 bytes/s, above
-- ChatThrottleLib's 800; in instances (not measured), the wiki puts whispers under the prefix allowance (10, then 1 a
-- second): one whisper per INSTANCE_GAP. The game answers a whisper to a player gone with "No player named ...": that
-- line is hidden and that player's transfers dropped. Received chunks wait, per sender, until the end of the session.
-- ponytail: every announce costs each listener an inventory whisper (~1 KB), even with nothing to give; send the
-- latest Comparison's id in the announce if a big guild makes that traffic matter.
local GM = VepIndustriesMarket
local M = GM.Market
GM.Exchange = {}
local X = GM.Exchange

X.PREFIX = "VepIndMarket"
local MAX = 255         -- bytes per addon message
local RETRY = 2         -- seconds before a refused or locked chunk goes again (DungeonForever's wait)
local INSTANCE_GAP = 1  -- seconds between two whispers in an instance
local LOGIN_DELAY = 10  -- seconds after login before announcing (ChatThrottleLib holds back the first 5)
local GONE_WAIT = 30    -- seconds a "No player named" line may follow our whisper
local PASS = { [3] = true, [8] = true, [11] = true } -- refusals that pass: rate, channel rate, lockdown

local function secret(v) return issecretvalue and issecretvalue(v) end
-- a restricted answer counts as yes
local function yes(v) return secret(v) or v == true end
-- a sender as the game writes it ("First Surname" on Forever, whose realms have no name), as a whisper must address it
local function whisperName(name) return (name:gsub(" ", "-")) end
local function me()
    local name, surname = UnitName("player")
    return whisperName(type(surname) == "string" and surname ~= "" and name .. " " .. surname or name)
end
local function generated()
    return VepIndustriesMarketData and VepIndustriesMarketData.generated or 0
end
local function comparisons() return VepIndustriesMarketDB and VepIndustriesMarketDB.comparisons or {} end

-- Comparison <-> payload "author\nrealm\nfaction\nstart\nfinish\nitems"
function X.Encode(c)
    return string.format("%s\n%s\n%s\n%d\n%d\n%s", c.author, c.realm, c.faction, c.start, c.finish, c.items)
end
local function decodeComparison(text)
    local a, r, f, s, e, items = text:match("^([^\n]*)\n([^\n]*)\n([^\n]*)\n(%d+)\n(%d+)\n(.*)$")
    if a then return { author = a, realm = r, faction = f, start = tonumber(s), finish = tonumber(e), items = items } end
end

-- payload -> the messages carrying it; and the data of those messages, joined, -> payload (errors when corrupted)
local ESCAPE, UNESCAPE = { ["\0"] = "\1\2", ["\1"] = "\1\1" }, { ["\1"] = "\1", ["\2"] = "\0" }
function X.Pack(kind, key, text)
    local data = C_EncodingUtil.CompressString(text):gsub("[%z\1]", ESCAPE)
    local size = MAX - #string.format("%s%d %d %s\t", kind, 99999, 99999, key)
    local n, out = math.max(1, math.ceil(#data / size)), {}
    for i = 1, n do
        out[i] = string.format("%s%d %d %s\t", kind, i, n, key) .. data:sub((i - 1) * size + 1, i * size)
    end
    return out
end
function X.Unpack(data) return C_EncodingUtil.DecompressString((data:gsub("\1(.)", UNESCAPE))) end

-- Sending: jobs = { { to, slot (kind .. key), chunks, i (next chunk) } }, one chunk in flight at a time.
local jobs, busy, whispered = {}, false, {} -- whispered: [name] = GetTime() of our last whisper to them
local pump
local function sent(j, ok, result)
    if jobs[1] == j then
        if ok then
            j.i = j.i + 1
            if j.i > #j.chunks then table.remove(jobs, 1) end
        elseif PASS[result] then
            return C_Timer.After(RETRY, pump)
        else
            table.remove(jobs, 1) -- refused for good
        end
    end
    C_Timer.After(yes(IsInInstance()) and INSTANCE_GAP or 0, pump)
end
function pump()
    local j = jobs[1]
    busy = j ~= nil
    if not j then return end
    if C_ChatInfo.InChatMessagingLockdown and yes(C_ChatInfo.InChatMessagingLockdown()) then
        return C_Timer.After(RETRY, pump)
    end
    whispered[j.to] = GetTime()
    ChatThrottleLib:SendAddonMessage("BULK", X.PREFIX, j.chunks[j.i], "WHISPER", j.to, nil, sent, j)
end

-- whispers payload `text` to `to` from chunk `first` (1 by default), unless it is already on its way there
local function send(to, kind, key, text, first)
    for _, j in ipairs(jobs) do
        if j.to == to and j.slot == kind .. key then return end
    end
    local chunks = X.Pack(kind, key, text)
    jobs[#jobs + 1] = { to = to, slot = kind .. key, chunks = chunks, i = math.min(first or 1, #chunks) }
    if not busy then pump() end
end

-- Receiving: parts[sender .. "\t" .. kind .. key] = { n = chunks announced, data of the first ones }
local parts = {}

local function inventory(to, ask)
    local gen = generated()
    local lines, from = { ask .. " " .. gen }, to .. "\tC"
    for id, finish in pairs(M.Seen()) do
        if finish > gen then lines[#lines + 1] = id end
    end
    for slot, p in pairs(parts) do
        if slot:sub(1, #from) == from then lines[#lines + 1] = slot:sub(#from + 1) .. " " .. #p end
    end
    return table.concat(lines, "\n")
end

local function latest()
    local finish = 0
    for _, c in ipairs(comparisons()) do finish = math.max(finish, c.finish) end
    return finish
end

local function handle(from, kind, key, text)
    if kind == "C" then
        local c = decodeComparison(text)
        if c and c.start and M.Id(c) == key then
            GM.Run("échange", function()
                if M.Receive(c, time()) then X.Announce() end
            end)
        end
    elseif kind == "W" then
        local ask, gen = text:match("^(%d) (%d+)")
        if not ask then return end
        gen = tonumber(gen)
        local has, partial, unknown, seen = {}, {}, false, M.Seen()
        for line in text:gmatch("\n([^\n]+)") do
            local id, k = line:match("^(.- %d+) ?(%d*)$")
            if id and k ~= "" then
                partial[id] = tonumber(k)
            elseif id then
                has[id] = true
                unknown = unknown or not seen[id]
            end
        end
        for _, c in ipairs(comparisons()) do
            local id = M.Id(c)
            if c.finish > gen and not has[id] then send(from, "C", id, X.Encode(c), (partial[id] or 0) + 1) end
        end
        if ask == "1" and unknown then send(from, "W", "", inventory(from, 0)) end
    end
end

local function chunk(from, msg)
    local kind, i, n, key, data = msg:match("^(%u)(%d+) (%d+) ([^\t]*)\t(.*)$")
    if not kind then return end
    i, n = tonumber(i), tonumber(n)
    local slot = from .. "\t" .. kind .. key
    local p = parts[slot]
    if i == 1 then
        if kind == "C" and M.Seen()[key] then return end -- already known: ignored
        p = { n = n }
        parts[slot] = p
    elseif not (p and p.n == n and i == #p + 1) then
        return
    end
    p[i] = data
    if i < n then return end
    parts[slot] = nil
    local ok, text = pcall(X.Unpack, table.concat(p))
    if ok and type(text) == "string" then handle(from, kind, key, text) end
end

-- announces on GUILD: after login, and after each Comparison recorded (ours or received)
function X.Announce()
    if IsInGuild() then
        ChatThrottleLib:SendAddonMessage("NORMAL", X.PREFIX, string.format("A %d %d", generated(), latest()), "GUILD")
    end
end

-- the chat windows' filter: "No player named ..." just after our whisper to that name (in the client's language,
-- naming the player as whispered or by the first name only) is hidden, and that player's transfers dropped
local function gone(_, _, text)
    local g = ERR_CHAT_PLAYER_NOT_FOUND_S
    if secret(text) or type(text) ~= "string" or type(g) ~= "string" then return false end
    local name = text:match("^" .. g:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("%%%%s", "(.+)") .. "$")
    if not name then return false end
    name = whisperName(name)
    for to, at in pairs(whispered) do
        if GetTime() - at <= GONE_WAIT and (to == name or to:match("^[^-]+") == name) then
            for k = #jobs, 1, -1 do
                if jobs[k].to == to then table.remove(jobs, k) end
            end
            return true
        end
    end
    return false
end
local addFilter = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
if addFilter then addFilter("CHAT_MSG_SYSTEM", gone) end

C_ChatInfo.RegisterAddonMessagePrefix(X.PREFIX)
local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, prefix, text, channel, sender)
    if event == "PLAYER_LOGIN" then
        return C_Timer.After(LOGIN_DELAY, X.Announce)
    end
    if secret(prefix) or secret(text) or secret(sender) or prefix ~= X.PREFIX or type(sender) ~= "string" then return end
    local from = whisperName(sender)
    if from == me() then return end -- our own announce, back from GUILD
    if channel == "WHISPER" then return chunk(from, text) end
    local gen, finish = text:match("^A (%d+) (%d+)$")
    if channel == "GUILD" and gen and (tonumber(finish) > generated() or latest() > tonumber(gen)) then
        send(from, "W", "", inventory(from, 1))
    end
end)
