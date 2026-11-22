-- One-off in-game measurements for ticket #19. Every result is printed and kept in VimProbeDB.log,
-- read back after logout with `npm run probe results`. Throwaway: removed with `npm run probe remove`.
local PREFIX = "VIMPROBE"
local PAYLOAD = 250             -- bytes per message, as the future transfer will use
local BURST = 12                -- sent at once: the wiki announces an allowance of 10 per prefix
local DURATION, TICKS = 20, 100 -- then TICKS tries over DURATION seconds (1 250 bytes/s, under ChatThrottleLib's burst)
local LATE = 3                  -- seconds left for the last messages to come back before the summary
local COMBAT_TRY = 5            -- seconds between two sends during a fight in an instance

local me = UnitName("player")

local function safe(v)
  if issecret and issecret(v) then return "secret" end
  return v
end

local function log(fmt, ...)
  local line = date("%d/%m %H:%M:%S ") .. string.format(fmt, ...)
  table.insert(VimProbeDB.log, line)
  print("|cff33ccffVIM Probe|r " .. line)
end

local function where()
  local inInstance, kind = IsInInstance()
  if safe(inInstance) == true then return "en instance " .. tostring(safe(kind)) end
  return "hors instance"
end

local function lockdown()
  if not C_ChatInfo.InChatMessagingLockdown then return "absent" end
  return tostring(safe(C_ChatInfo.InChatMessagingLockdown()))
end

local function send(text, channel, target)
  local code = safe(C_ChatInfo.SendAddonMessage(PREFIX, text, channel, target))
  if code == true then return 0 end -- older clients answered true for a success
  return code
end

local function tally(counts)
  local parts = {}
  for code, n in pairs(counts) do table.insert(parts, n .. " x code " .. code) end
  table.sort(parts)
  return #parts > 0 and table.concat(parts, ", ") or "aucun"
end

-- Rate: BURST messages at once, then one try per INTERVAL. Own GUILD and WHISPER-to-self messages come back,
-- so "reçus" tells whether the server delivered what the client accepted.
local run
local function rate(channel, target)
  if run then return log("une mesure est déjà en cours") end
  run = { received = 0 }
  local codes, refused, burst, later, seq = {}, {}, 0, 0, 0
  local function try()
    seq = seq + 1
    local code = send(string.format("%04d", seq) .. ("x"):rep(PAYLOAD - 4), channel, target)
    if code ~= 0 then refused[tostring(code)] = (refused[tostring(code)] or 0) + 1 end
    return code
  end
  for i = 1, BURST do
    codes[i] = tostring(try())
    if codes[i] == "0" then burst = burst + 1 end
  end
  local tick = 0
  C_Timer.NewTicker(DURATION / TICKS, function()
    tick = tick + 1
    if try() == 0 then later = later + 1 end
    if tick < TICKS then return end
    C_Timer.After(LATE, function()
      log("débit %s%s (%s, blocage %s) : %d/%d acceptés d'un coup (codes %s), puis %d/%d en %d s (%.1f/s) ; refus : %s ; reçus %d/%d",
        channel, target and (" vers " .. target) or "", where(), lockdown(), burst, BURST, table.concat(codes, " "),
        later, TICKS, DURATION, later / DURATION, tally(refused), run.received, BURST + TICKS)
      run = nil
    end)
  end, TICKS)
end

-- Offline recipient: the send code, and any system message shown in the chat within LATE seconds.
local system
local function absent(name)
  system = {}
  local code = send("absent", "WHISPER", name)
  C_Timer.After(LATE, function()
    log("chuchotement d'addon vers %s : code %s ; message système : %s", name, tostring(code),
      #system > 0 and table.concat(system, " | ") or "aucun")
    system = nil
  end)
end

-- Fights in an instance: a whisper to self every COMBAT_TRY seconds. Boss fights are always logged,
-- other fights only when a send was refused or a lockdown was seen.
local fight
local function startFight(boss)
  if fight then
    fight.boss = fight.boss or boss
    return
  end
  fight = { boss = boss, tries = 0, refused = {}, locked = {} }
  local function try()
    fight.tries = fight.tries + 1
    local code = send("combat", "WHISPER", me)
    if code ~= 0 then fight.refused[tostring(code)] = (fight.refused[tostring(code)] or 0) + 1 end
    fight.locked[lockdown()] = true
  end
  try()
  fight.ticker = C_Timer.NewTicker(COMBAT_TRY, try)
end

local function endFight()
  if not fight then return end
  fight.ticker:Cancel()
  local seen = {}
  for state in pairs(fight.locked) do table.insert(seen, state) end
  if fight.boss or next(fight.refused) or fight.locked["true"] then
    log("combat %s (%s) : %d envois, refus : %s ; blocage vu : %s", fight.boss and ("contre " .. fight.boss) or "sans boss",
      where(), fight.tries, tally(fight.refused), table.concat(seen, "/"))
  end
  fight = nil
end

local function api()
  local enc = C_EncodingUtil
  log("API : C_EncodingUtil %s (CompressString %s, SerializeCBOR %s, EncodeBase64 %s), C_BattleNet.SendGameData %s, "
    .. "InChatMessagingLockdown %s, AreOutgoingAddonChatMessagesRestricted %s",
    tostring(enc ~= nil), tostring(enc ~= nil and enc.CompressString ~= nil), tostring(enc ~= nil and enc.SerializeCBOR ~= nil),
    tostring(enc ~= nil and enc.EncodeBase64 ~= nil), tostring(C_BattleNet ~= nil and C_BattleNet.SendGameData ~= nil), lockdown(),
    C_ChatInfo.AreOutgoingAddonChatMessagesRestricted
      and tostring(safe(C_ChatInfo.AreOutgoingAddonChatMessagesRestricted())) or "absent")
end

local function lod()
  local loaded, reason = C_AddOns.LoadAddOn("VimProbeLod")
  log("chargement à la demande : %s %s ; horodatage lu dans Data.lua : %s", tostring(loaded), tostring(reason),
    tostring(VimProbeLodStamp))
end

local frame = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "CHAT_MSG_ADDON", "CHAT_MSG_SYSTEM", "ENCOUNTER_START", "ENCOUNTER_END",
  "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
  frame:RegisterEvent(e)
end
frame:SetScript("OnEvent", function(_, event, a, b)
  if event == "ADDON_LOADED" and a == "VimProbe" then
    VimProbeDB = VimProbeDB or {}
    VimProbeDB.log = VimProbeDB.log or {}
  elseif event == "CHAT_MSG_ADDON" then
    if a == PREFIX and run then run.received = run.received + 1 end
  elseif event == "CHAT_MSG_SYSTEM" then
    if system then table.insert(system, tostring(safe(a))) end
  elseif event == "ENCOUNTER_START" then
    startFight(tostring(safe(b)))
  elseif event == "PLAYER_REGEN_DISABLED" then
    if safe(IsInInstance()) == true then startFight(nil) end
  elseif event == "ENCOUNTER_END" or event == "PLAYER_REGEN_ENABLED" then
    endFight()
  end
end)
C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

SLASH_VIMPROBE1 = "/vimprobe"
SlashCmdList.VIMPROBE = function(msg)
  local cmd, arg = msg:match("^(%S*)%s*(.-)$")
  if cmd == "guilde" then rate("GUILD")
  elseif cmd == "chuchot" then rate("WHISPER", arg ~= "" and arg or me)
  elseif cmd == "absent" and arg ~= "" then absent(arg)
  elseif cmd == "api" then api()
  elseif cmd == "lod" then lod()
  else
    print("|cff33ccffVIM Probe|r /vimprobe guilde | chuchot [Nom] | absent Nom | api | lod"
      .. " — les combats en instance sont mesurés d'eux-mêmes")
  end
end
