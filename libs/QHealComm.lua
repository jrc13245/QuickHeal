--[[ QHealComm.lua
     Standalone heal communication library for QuickHeal.
     Based on pfUI libpredict - delegates to it when available,
     otherwise uses an identical standalone clone.
     Compatible with HealComm addon message protocol.
]]--

HealComm = {}

---------- STATE ----------
local player -- set lazily (UnitName may not be ready at load time)

local function getPlayerName()
    if not player then player = UnitName("player") end
    return player
end

-- Pending heal (set by QuickHeal before CastSpell, consumed by SPELLCAST_START)
local myPendingTarget = nil
local myPendingAmount = 0
local myPendingTime = 0

-- Current heal (set when SPELLCAST_START fires, cleared on cast end)
local myCurrentTarget = nil
local myCurrentAmount = 0
local myCurrentSpell = nil -- spell name of current cast
local isHealing = false
local isResurrecting = false

-- Standalone data tables (used when pfUI is not available)
local heals = {}       -- [targetName][senderName] = { [1]=amount, [2]=timeout }
local hots = {}        -- [targetName][spell] = { duration=N, start=T, rank=R }
local ress = {}        -- [targetName][senderName] = true
local ress_timers = {} -- [target][sender] = expiry_timestamp
local evts = {}        -- [timestamp] = { target1, ... }
local RESS_TIMEOUT = 60

-- Spell cache (keyed by "SpellNameRank N", value = { [1]=amount, [2]=stale_or_crit })
local cache = {}
local gear_string = ""

-- Nampower / SuperWoW checks
local has_nampower = GetCastInfo and true or false

-- HoT durations (updated by set bonus detection)
local rejuvDuration = 12
local renewDuration = 15

-- Spell queue (mirrors libpredict's spell_queue for target resolution)
local spell_queue = { "DUMMY", "DUMMYRank 9", "TARGET" }

-- Regrowth timer tracking (mirrors libpredict's regrowth_timer)
local regrowth_target = nil
local regrowth_rank = nil
local regrowth_start = nil
local regrowth_timer = nil

-- Duplicate HoT detection
local recentHots = {}
local DUPLICATE_WINDOW = 0.5

-- Instant HoT cooldown (prevents spam on click-to-cast)
local instantHotCooldown = {}
local INSTANT_HOT_COOLDOWN = 1.0

---------- pfUI DETECTION ----------

local function getLibpredict()
    return pfUI and pfUI.api and pfUI.api.libpredict
end

---------- HELPERS ----------

local function SendHealCommMsg(msg)
    if getLibpredict() then return end -- pfUI handles sending
    if GetNumRaidMembers() > 0 then
        SendAddonMessage("HealComm", msg, "RAID")
    elseif GetNumPartyMembers() > 0 then
        SendAddonMessage("HealComm", msg, "PARTY")
    end
end

local function SendResCommMsg(msg)
    if getLibpredict() then return end
    if GetNumRaidMembers() > 0 then
        SendAddonMessage("CTRA", msg, "RAID")
    elseif GetNumPartyMembers() > 0 then
        SendAddonMessage("CTRA", msg, "PARTY")
    end
end

-- Resolve unit argument to player name (accepts unit ID or name)
local function resolveName(unit)
    if not unit then return nil end
    local ok, name = pcall(UnitName, unit)
    if ok and name and name ~= UNKNOWNOBJECT and name ~= UKNOWNBEING then
        return name
    end
    -- Already a name (or unknown unit ID)
    if unit ~= UNKNOWNOBJECT and unit ~= UKNOWNBEING then
        return unit
    end
    return nil
end

---------- TOOLTIP SCANNER ----------
-- Hidden tooltip for set bonus detection and UseAction spell info
local tooltipScanner = CreateFrame("GameTooltip", "QHealCommTooltip", nil, "GameTooltipTemplate")
tooltipScanner:SetOwner(WorldFrame, "ANCHOR_NONE")

-- Get spell name and rank from a spell ID + book type
local function ParseSpellInfo(nameOrId, bookType)
    local name, rank
    if type(nameOrId) == "number" then
        name, rank = GetSpellName(nameOrId, bookType or "spell")
    else
        -- Parse "Healing Touch(Rank 4)" or "Healing Touch"
        local _, _, n, r = string.find(nameOrId, "^(.-)%s*%((.+)%)$")
        if n then
            name, rank = n, r
        else
            name = nameOrId
        end
    end
    if rank == "" then rank = nil end
    return name, rank
end

---------- SET BONUS DETECTION ----------
-- Detect Stormrage 8/8 (Rejuv +3s) and Vestments of Faith 5/5 (Renew +3s)

local function CheckSetBonuses()
    if getLibpredict() then return end
    local rejuvCount = 0
    local renewCount = 0
    for i = 1, 10 do
        tooltipScanner:ClearLines()
        tooltipScanner:SetInventoryItem("player", i)
        for j = 1, tooltipScanner:NumLines() do
            local line = getglobal("QHealCommTooltipTextLeft" .. j)
            if line then
                local text = line:GetText()
                if text then
                    if string.find(text, "Rejuvenation") then
                        rejuvCount = rejuvCount + 1
                        break
                    end
                    if string.find(text, "Renew") then
                        renewCount = renewCount + 1
                        break
                    end
                end
            end
        end
    end
    rejuvDuration = rejuvCount >= 8 and 15 or 12
    renewDuration = renewCount >= 5 and 18 or 15
end

---------- STANDALONE: INTERNAL TRACKING ----------

local function AddEvent(time, target)
    evts[time] = evts[time] or {}
    table.insert(evts[time], target)
end

local function ProcessHeal(sender, target, amount, duration)
    if not sender or not target or not amount or not duration then return end
    amount = tonumber(amount) or 0
    duration = tonumber(duration) or 0

    local now = GetTime()
    local timeout = duration / 1000 + now
    heals[target] = heals[target] or {}
    heals[target][sender] = { amount, timeout }
    AddEvent(timeout, target)
end

local function ProcessHealStop(sender)
    for target, senders in pairs(heals) do
        for s in pairs(senders) do
            if sender == s then
                heals[target][s] = nil
            end
        end
    end
end

local function ProcessHealDelay(sender, delay)
    delay = (tonumber(delay) or 0) / 1000
    for target, senders in pairs(heals) do
        for s, amount in pairs(senders) do
            if sender == s then
                amount[2] = amount[2] + delay
                AddEvent(amount[2], target)
            end
        end
    end
end

local function ProcessHot(sender, target, spell, duration, startTime, rank)
    hots[target] = hots[target] or {}
    hots[target][spell] = hots[target][spell] or {}

    if spell == "Regr" then duration = 20 end
    duration = tonumber(duration) or duration

    -- Rank protection: don't overwrite higher rank HoT with lower rank
    local existing = hots[target][spell]
    if existing and existing.rank and rank then
        local existingRank = tonumber(existing.rank) or 0
        local newRank = tonumber(rank) or 0
        local now = GetTime()
        local timeleft = ((existing.start or 0) + (existing.duration or 0)) - now
        if timeleft > 0 and newRank > 0 and newRank < existingRank then
            return -- don't overwrite
        end
    end

    local now = GetTime()
    hots[target][spell].duration = duration
    hots[target][spell].start = startTime or now
    hots[target][spell].rank = rank
end

local function ProcessRess(sender, target)
    ress[target] = ress[target] or {}
    ress[target][sender] = true
end

local function ProcessRessStop(sender)
    local now = GetTime()
    for target, senders in pairs(ress) do
        for s in pairs(senders) do
            if sender == s then
                local expiry = ress_timers[target] and ress_timers[target][s]
                if not expiry or now >= expiry then
                    ress[target][s] = nil
                    if ress_timers[target] then ress_timers[target][s] = nil end
                end
            end
        end
    end
end

---------- SPELL CACHE ----------
-- Cache heal amounts from SPELL_HEAL_BY_SELF for non-QuickHeal casts
-- (mirrors libpredict's UpdateCache)

local function UpdateCache(spell, heal, crit)
    heal = heal and tonumber(heal)
    if not spell or not heal then return end

    if not cache[spell] then
        cache[spell] = {}
        cache[spell][1] = crit and heal * 2 / 3 or heal
        cache[spell][2] = crit
    elseif cache[spell][2] == true then
        -- Flagged as stale (gear/skill change): always overwrite
        cache[spell][1] = crit and heal * 2 / 3 or heal
        cache[spell][2] = crit
    elseif crit then
        -- Don't overwrite non-crit with crit value
    else
        if cache[spell][1] < heal then
            cache[spell][1] = heal
        end
        cache[spell][2] = false
    end
end

-- Flag all cached heals for renewal (gear/skill change)
local function FlagCacheStale()
    for k in pairs(cache) do
        if type(cache[k]) == "number" or type(cache[k]) == "string" then
            local oldval = cache[k]
            cache[k] = { [1] = oldval }
        end
        cache[k][2] = true
    end
end

---------- STANDALONE: MESSAGE PARSING (identical to libpredict) ----------

local function ParseComm(sender, msg)
    local msgtype, target, heal, time, rank

    if msg == "HealStop" or msg == "Healstop" or msg == "GrpHealstop" then
        msgtype = "Stop"
    elseif msg == "Resurrection/stop/" then
        msgtype = "RessStop"
    elseif msg then
        local msgobj
        if strsplit then
            msgobj = { strsplit("/", msg) }
        else
            msgobj = {}
            for part in string.gfind(msg .. "/", "([^/]*)/") do
                if part ~= "" then table.insert(msgobj, part) end
            end
        end

        if msgobj and msgobj[1] and msgobj[2] then
            if msgobj[1] == "GrpHealdelay" or msgobj[1] == "Healdelay" then
                msgtype, time = "Delay", msgobj[2]
            end

            if msgobj[1] == "Resurrection" and msgobj[2] then
                msgtype, target = "Ress", msgobj[2]
            end

            if msgobj[1] == "Heal" and msgobj[2] then
                msgtype, target, heal, time = "Heal", msgobj[2], msgobj[3], msgobj[4]
            end

            if msgobj[1] == "GrpHeal" and msgobj[2] then
                msgtype, heal, time = "Heal", msgobj[2], msgobj[3]
                target = {}
                for i = 4, 8 do
                    if msgobj[i] then table.insert(target, msgobj[i]) end
                end
            end

            if msgobj[1] == "Reju" or msgobj[1] == "Renew" or msgobj[1] == "Regr" then
                msgtype, target, heal, time = "Hot", msgobj[2], msgobj[1], msgobj[3]
                local rankStr = msgobj[4]
                if rankStr and rankStr ~= "" and rankStr ~= "/" and rankStr ~= "0" then
                    rank = tonumber(rankStr)
                end
            end
        elseif select and pfGetCastInfo then
            -- Latest healcomm format (SuperWoW pfGetCastInfo)
            msgtype = tonumber(string.sub(msg, 1, 3))
            if not msgtype then return end

            if msgtype == 0 then
                msgtype = "Heal"
                heal = tonumber(string.sub(msg, 4, 8))
                target = string.sub(msg, 9, -1)
                local starttime = select(5, pfGetCastInfo(sender))
                local endtime = select(6, pfGetCastInfo(sender))
                if not starttime or not endtime then return end
                time = endtime - starttime
            elseif msgtype == 1 then
                msgtype = "Stop"
            elseif msgtype == 2 then
                msgtype = "Heal"
                heal = tonumber(string.sub(msg, 4, 8))
                target = { strsplit(":", string.sub(msg, 9, -1)) }
                local starttime = select(5, pfGetCastInfo(sender))
                local endtime = select(6, pfGetCastInfo(sender))
                if not starttime or not endtime then return end
                time = endtime - starttime
            end
        end
    end

    return msgtype, target, heal, time, rank
end

local function ParseChatMessage(sender, msg, comm)
    local msgtype, target, heal, time, rank

    if comm == "HealComm" then
        msgtype, target, heal, time, rank = ParseComm(sender, msg)
    elseif comm == "CTRA" then
        local _, _, cmd, ctratarget = string.find(msg, "(%a+)%s?([^#]*)")
        if cmd and ctratarget and cmd == "RES" and ctratarget ~= "" and ctratarget ~= UNKNOWN then
            msgtype = "Ress"
            target = ctratarget
        end
    end

    if msgtype == "Stop" and sender then
        ProcessHealStop(sender)
        return
    elseif (msg == "RessStop" or msg == "RESNO") and sender then
        ProcessRessStop(sender)
        return
    elseif msgtype == "Delay" and time then
        ProcessHealDelay(sender, time)
    elseif msgtype == "Heal" and target and heal and time then
        if type(target) == "table" then
            for _, name in pairs(target) do
                ProcessHeal(sender, name, heal, time)
            end
        else
            ProcessHeal(sender, target, heal, time)
        end
    elseif msgtype == "Ress" then
        if sender ~= getPlayerName() then
            ProcessRess(sender, target)
        end
    elseif msgtype == "Hot" then
        local now = GetTime()
        local key = sender .. target .. heal
        if recentHots[key] and (now - recentHots[key]) < DUPLICATE_WINDOW then
            return
        end
        recentHots[key] = now

        -- Cleanup old entries periodically
        if not HealComm._lastCleanup or (now - HealComm._lastCleanup) > 10 then
            for k, v in pairs(recentHots) do
                if (now - v) > DUPLICATE_WINDOW then
                    recentHots[k] = nil
                end
            end
            HealComm._lastCleanup = now
        end

        -- For own HoTs: correct the startTime
        if sender == getPlayerName() then
            local existing = hots[target] and hots[target][heal]
            if existing and existing.start and existing.duration
               and (existing.start + existing.duration) > now then
                return -- don't overwrite active timer
            end
            local delay = (heal == "Regr") and 0.3 or 0
            ProcessHot(sender, target, heal, time, now - delay, rank)
            return
        end
        ProcessHot(sender, target, heal, time, nil, rank)
    end
end

---------- PUBLIC API ----------

function HealComm:getHeal(unit)
    local lp = getLibpredict()
    if lp then
        -- pfUI's UnitGetIncomingHeals expects a unit ID
        -- Try as unit ID first (pcall in case it's a name, not a valid unit ID)
        local ok, name = pcall(UnitName, unit)
        if ok and name then
            return lp:UnitGetIncomingHeals(unit) or 0
        end
        -- Got a name instead of unit ID - find the matching unit
        if unit == getPlayerName() then
            return lp:UnitGetIncomingHeals("player") or 0
        end
        for i = 1, GetNumRaidMembers() do
            if UnitName("raid" .. i) == unit then
                return lp:UnitGetIncomingHeals("raid" .. i) or 0
            end
        end
        for i = 1, GetNumPartyMembers() do
            if UnitName("party" .. i) == unit then
                return lp:UnitGetIncomingHeals("party" .. i) or 0
            end
        end
        return 0
    end

    -- Standalone path
    local name = resolveName(unit)
    if not name then return 0 end

    local sumheal = 0
    if not heals[name] then return 0 end

    local now = GetTime()
    for sender, amount in pairs(heals[name]) do
        if amount[2] <= now then
            heals[name][sender] = nil
        else
            sumheal = sumheal + amount[1]
        end
    end
    return sumheal
end

function HealComm:GetMyPendingHeal(unitName)
    if not myCurrentTarget then return 0 end
    local name = resolveName(unitName)
    if name and myCurrentTarget == name then return myCurrentAmount end
    return 0
end

function HealComm:getRejuTime(unit)
    local lp = getLibpredict()
    if lp then return lp:GetHotDuration(unit, "Reju") end

    local name = resolveName(unit)
    if not name then return end
    local data = hots[name] and hots[name]["Reju"]
    if data and data.start and data.duration then
        local timeleft = (data.start + data.duration) - GetTime()
        if timeleft > 0 then return data.start, data.duration, timeleft end
    end
end

function HealComm:getRenewTime(unit)
    local lp = getLibpredict()
    if lp then return lp:GetHotDuration(unit, "Renew") end

    local name = resolveName(unit)
    if not name then return end
    local data = hots[name] and hots[name]["Renew"]
    if data and data.start and data.duration then
        local timeleft = (data.start + data.duration) - GetTime()
        if timeleft > 0 then return data.start, data.duration, timeleft end
    end
end

function HealComm:getRegrTime(unit)
    local lp = getLibpredict()
    if lp then return lp:GetHotDuration(unit, "Regr") end

    local name = resolveName(unit)
    if not name then return end
    local data = hots[name] and hots[name]["Regr"]
    if data and data.start and data.duration then
        local timeleft = (data.start + data.duration) - GetTime()
        if timeleft > 0 then return data.start, data.duration, timeleft end
    end
end

function HealComm:UnitisResurrecting(unit)
    local lp = getLibpredict()
    if lp then return lp:UnitHasIncomingResurrection(unit) end

    local name = resolveName(unit)
    if not name or not ress[name] then return nil end
    for _, val in pairs(ress[name]) do
        if val == true then return true end
    end
    return nil
end

---------- SENDING API ----------

function HealComm:SetPendingHeal(targetName, amount, spellName, targetUnit, spellRank)
    if not targetName or not amount then return end
    myPendingTarget = targetName
    myPendingAmount = amount
    myPendingTime = GetTime()

    -- When pfUI is available, set pending for SPELL_START_SELF target resolution
    if getLibpredict() and spellName and targetUnit then
        pfUI.libpredict_pending_cast = pfUI.libpredict_pending_cast or {}
        pfUI.libpredict_pending_cast.spellName = spellName
        pfUI.libpredict_pending_cast.targetGuid = targetUnit
        pfUI.libpredict_pending_cast.time = GetTime()

        -- Pre-seed pfUI prediction cache if empty for this spell+rank
        -- Without this, first-cast of a spell rank shows no heal bar
        -- because SPELL_START_SELF skips spells with no cache entry
        if amount and amount > 0 and spellRank then
            local cacheKey = spellName .. spellRank
            local realm = GetRealmName() or ""
            local pname = getPlayerName() or ""
            if pfUI_cache and pfUI_cache["prediction"]
               and pfUI_cache["prediction"][realm]
               and pfUI_cache["prediction"][realm][pname]
               and pfUI_cache["prediction"][realm][pname]["heals"] then
                local c = pfUI_cache["prediction"][realm][pname]["heals"]
                if not c[cacheKey] then
                    c[cacheKey] = { [1] = amount, [2] = true }
                end
            end
        end
    end
end

function HealComm:AnnounceHealStop()
    if isHealing and not getLibpredict() then
        ProcessHealStop(getPlayerName())
        SendHealCommMsg("Healstop")
    end
    if isResurrecting and not getLibpredict() then
        ProcessRessStop(getPlayerName())
        SendHealCommMsg("Resurrection/stop/")
        SendResCommMsg("RESNO " .. (myCurrentTarget or ""))
    end
    isHealing = false
    isResurrecting = false
    myCurrentTarget = nil
    myCurrentAmount = 0
    myCurrentSpell = nil
    -- Clear regrowth timer on failure
    if regrowth_timer then
        regrowth_timer = nil
        regrowth_start = nil
        regrowth_target = nil
        regrowth_rank = nil
    end
    -- Clear pending too (cast failed entirely)
    myPendingTarget = nil
    myPendingAmount = 0
    myPendingTime = 0
end

function HealComm:AnnounceHot(targetName, spell, duration, rank)
    if not targetName or not spell or not duration then return end
    if getLibpredict() then return end -- pfUI handles via hooks

    -- Use set-bonus-corrected durations
    if spell == "Reju" then duration = rejuvDuration
    elseif spell == "Renew" then duration = renewDuration
    end

    ProcessHot(getPlayerName(), targetName, spell, duration, nil, rank)
    local rankStr = rank and tostring(rank) or "0"
    SendHealCommMsg(spell .. "/" .. targetName .. "/" .. duration .. "/" .. rankStr .. "/")
end

function HealComm:AnnounceRess(targetName)
    if not targetName then return end
    if getLibpredict() then return end

    ProcessRess(getPlayerName(), targetName)
    isResurrecting = true
    SendHealCommMsg("Resurrection/" .. targetName .. "/start/")
    SendResCommMsg("RES " .. targetName)
end

---------- STANDALONE: SPELL HOOKS ----------
-- Hook CastSpell/CastSpellByName/UseAction to track spell_queue and instant HoTs
-- (mirrors libpredict's hooks for when pfUI is not available)
-- Hooks always installed but each checks getLibpredict() per-call

if type(hooksecurefunc) == "function" then
    hooksecurefunc("CastSpell", function(id, bookType)
        if getLibpredict() then return end
        local effect, rank = ParseSpellInfo(id, bookType)
        if not effect then return end
        spell_queue[1] = effect
        spell_queue[2] = effect .. (rank or "")
        spell_queue[3] = UnitName("target") and UnitCanAssist("player", "target")
            and UnitName("target") or UnitName("player")

        local rankNum = nil
        if rank and rank ~= "" then
            rankNum = tonumber(string.gsub(rank, "Rank ", "")) or nil
        end

        -- Instant HoTs
        if effect == "Rejuvenation" then
            local hotTarget = spell_queue[3]
            local now = GetTime()
            local key = "Reju" .. hotTarget
            if instantHotCooldown[key] and (now - instantHotCooldown[key]) < INSTANT_HOT_COOLDOWN then return end
            instantHotCooldown[key] = now
            ProcessHot(getPlayerName(), hotTarget, "Reju", rejuvDuration, nil, rankNum)
            local rs = rankNum and tostring(rankNum) or "0"
            SendHealCommMsg("Reju/" .. hotTarget .. "/" .. rejuvDuration .. "/" .. rs .. "/")
        elseif effect == "Renew" then
            local hotTarget = spell_queue[3]
            local now = GetTime()
            local key = "Renew" .. hotTarget
            if instantHotCooldown[key] and (now - instantHotCooldown[key]) < INSTANT_HOT_COOLDOWN then return end
            instantHotCooldown[key] = now
            ProcessHot(getPlayerName(), hotTarget, "Renew", renewDuration, nil, rankNum)
            local rs = rankNum and tostring(rankNum) or "0"
            SendHealCommMsg("Renew/" .. hotTarget .. "/" .. renewDuration .. "/" .. rs .. "/")
        end
    end)

    hooksecurefunc("CastSpellByName", function(effect, target)
        if getLibpredict() then return end
        local effect, rank = ParseSpellInfo(effect)
        if not effect then return end

        local default = UnitName("target") and UnitCanAssist("player", "target")
            and UnitName("target") or UnitName("player")

        -- Resolve target parameter to a name
        if target then
            if type(target) == "string" then
                local ok, resolved = pcall(UnitName, target)
                if ok and resolved then
                    target = resolved
                end
                -- If pcall failed, might be a GUID (SuperWoW) or invalid string
                -- Leave as-is
            elseif target == true or target == 1 then
                target = UnitName("player")
            end
        end

        -- Only update spell_queue if no cast is in progress
        -- (prevents instant spam from destroying the queue during a Regrowth cast)
        if not myCurrentSpell then
            spell_queue[1] = effect
            spell_queue[2] = effect .. (rank or "")
            spell_queue[3] = target or default
        end

        local rankNum = nil
        if rank and rank ~= "" then
            rankNum = tonumber(string.gsub(rank, "Rank ", "")) or nil
        end

        -- Instant HoTs
        if effect == "Rejuvenation" then
            local hotTarget = target or default
            local now = GetTime()
            local key = "Reju" .. hotTarget
            if instantHotCooldown[key] and (now - instantHotCooldown[key]) < INSTANT_HOT_COOLDOWN then return end
            instantHotCooldown[key] = now
            ProcessHot(getPlayerName(), hotTarget, "Reju", rejuvDuration, nil, rankNum)
            local rs = rankNum and tostring(rankNum) or "0"
            SendHealCommMsg("Reju/" .. hotTarget .. "/" .. rejuvDuration .. "/" .. rs .. "/")
        elseif effect == "Renew" then
            local hotTarget = target or default
            local now = GetTime()
            local key = "Renew" .. hotTarget
            if instantHotCooldown[key] and (now - instantHotCooldown[key]) < INSTANT_HOT_COOLDOWN then return end
            instantHotCooldown[key] = now
            ProcessHot(getPlayerName(), hotTarget, "Renew", renewDuration, nil, rankNum)
            local rs = rankNum and tostring(rankNum) or "0"
            SendHealCommMsg("Renew/" .. hotTarget .. "/" .. renewDuration .. "/" .. rs .. "/")
        end
    end)

    hooksecurefunc("UseAction", function(slot, target, selfcast)
        if getLibpredict() then return end
        if GetActionText(slot) or not IsCurrentAction(slot) then return end
        tooltipScanner:ClearLines()
        tooltipScanner:SetAction(slot)
        local nameObj = getglobal("QHealCommTooltipTextLeft1")
        local rankObj = getglobal("QHealCommTooltipTextRight1")
        local effect = nameObj and nameObj:GetText()
        local rank = rankObj and rankObj:GetText()
        if not effect then return end
        if rank == "" then rank = nil end
        spell_queue[1] = effect
        spell_queue[2] = effect .. (rank or "")
        spell_queue[3] = selfcast and UnitName("player")
            or UnitName("target") and UnitCanAssist("player", "target")
            and UnitName("target") or UnitName("player")

        local rankNum = nil
        if rank and rank ~= "" then
            rankNum = tonumber(string.gsub(rank, "Rank ", "")) or nil
        end

        -- Instant HoTs
        if effect == "Rejuvenation" then
            local hotTarget = spell_queue[3]
            local now = GetTime()
            local key = "Reju" .. hotTarget
            if instantHotCooldown[key] and (now - instantHotCooldown[key]) < INSTANT_HOT_COOLDOWN then return end
            instantHotCooldown[key] = now
            ProcessHot(getPlayerName(), hotTarget, "Reju", rejuvDuration, nil, rankNum)
            local rs = rankNum and tostring(rankNum) or "0"
            SendHealCommMsg("Reju/" .. hotTarget .. "/" .. rejuvDuration .. "/" .. rs .. "/")
        elseif effect == "Renew" then
            local hotTarget = spell_queue[3]
            local now = GetTime()
            local key = "Renew" .. hotTarget
            if instantHotCooldown[key] and (now - instantHotCooldown[key]) < INSTANT_HOT_COOLDOWN then return end
            instantHotCooldown[key] = now
            ProcessHot(getPlayerName(), hotTarget, "Renew", renewDuration, nil, rankNum)
            local rs = rankNum and tostring(rankNum) or "0"
            SendHealCommMsg("Renew/" .. hotTarget .. "/" .. renewDuration .. "/" .. rs .. "/")
        end
    end)
end

---------- EVENT FRAME ----------

local frame = CreateFrame("Frame", "QHealCommFrame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("UNIT_HEALTH")
frame:RegisterEvent("SPELLCAST_START")
frame:RegisterEvent("SPELLCAST_STOP")
frame:RegisterEvent("SPELLCAST_FAILED")
frame:RegisterEvent("SPELLCAST_INTERRUPTED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("LEARNED_SPELL_IN_TAB")
frame:RegisterEvent("CHARACTER_POINTS_CHANGED")
frame:RegisterEvent("UNIT_INVENTORY_CHANGED")
frame:RegisterEvent("PLAYER_LOGOUT")

-- Nampower events
if has_nampower then
    frame:RegisterEvent("SPELL_FAILED_SELF")
    frame:RegisterEvent("SPELL_DELAYED_SELF")
    frame:RegisterEvent("SPELL_HEAL_BY_SELF")
end

frame:SetScript("OnEvent", function()
    if event == "PLAYER_LOGOUT" then
        this:UnregisterAllEvents()
        this:SetScript("OnEvent", nil)
        return
    end

    if event == "CHAT_MSG_ADDON" then
        if getLibpredict() then return end -- pfUI handles receiving
        if arg1 == "HealComm" or arg1 == "CTRA" then
            ParseChatMessage(arg4, arg2, arg1)
        end

    elseif event == "UNIT_HEALTH" then
        if getLibpredict() then return end
        local name = UnitName(arg1)
        if name and ress[name] and not UnitIsDeadOrGhost(arg1) then
            ress[name] = nil
        end

    elseif event == "SPELLCAST_START" then
        -- arg1 = spellName, arg2 = castTime (ms)
        -- Track current cast for GetMyPendingHeal (needed even with pfUI)
        if myPendingTarget and myPendingAmount > 0
           and myPendingTime and (GetTime() - myPendingTime) < 2 then
            myCurrentTarget = myPendingTarget
            myCurrentAmount = myPendingAmount
            myCurrentSpell = arg1
            myPendingTarget = nil
            myPendingAmount = 0
            myPendingTime = 0
            isHealing = true

            if not getLibpredict() then
                -- Regrowth: track target/rank for delayed HoT
                if arg1 == "Regrowth" then
                    local fullSpell = spell_queue[2]
                    local _, _, rankStr = fullSpell and string.find(fullSpell, "Rank (%d+)")
                    regrowth_target = myCurrentTarget
                    regrowth_rank = rankStr and tonumber(rankStr) or nil
                end

                -- Standalone: announce heal via HealComm messages
                local casttime = arg2 or 2000
                ProcessHeal(getPlayerName(), myCurrentTarget, myCurrentAmount, casttime)
                SendHealCommMsg("Heal/" .. myCurrentTarget .. "/" .. myCurrentAmount .. "/" .. casttime .. "/")
            end
        elseif not getLibpredict() then
            -- Fallback: use spell_queue (from hooks) + cache for non-QuickHeal casts
            if spell_queue[1] == arg1 and cache[spell_queue[2]] then
                local amount = cache[spell_queue[2]][1]
                local casttime = arg2 or 2000
                local target = spell_queue[3]
                myCurrentTarget = target
                myCurrentAmount = amount
                myCurrentSpell = arg1
                isHealing = true

                -- Regrowth: track target/rank for delayed HoT
                if arg1 == "Regrowth" then
                    local fullSpell = spell_queue[2]
                    local _, _, rankStr = fullSpell and string.find(fullSpell, "Rank (%d+)")
                    regrowth_target = target
                    regrowth_rank = rankStr and tonumber(rankStr) or nil
                end

                ProcessHeal(getPlayerName(), target, amount, casttime)
                SendHealCommMsg("Heal/" .. (target or "") .. "/" .. amount .. "/" .. casttime .. "/")
            end
        end

    elseif event == "SPELLCAST_STOP" then
        -- Cast completed successfully (or stale event)
        -- Check for stale event (Nampower)
        if has_nampower and GetCastInfo then
            local ok, info = pcall(GetCastInfo)
            if ok and info then
                return -- cast still active, ignore stale SPELLCAST_STOP
            end
        end
        if isHealing then
            if not getLibpredict() then
                ProcessHealStop(getPlayerName())
                -- Regrowth HoT: set timer for delayed announcement
                -- (matches libpredict's regrowth_timer in SPELL_GO_SELF)
                if myCurrentSpell == "Regrowth" and regrowth_target then
                    regrowth_start = GetTime()
                    regrowth_timer = GetTime() + 0.1
                end
            end
            isHealing = false
            myCurrentTarget = nil
            myCurrentAmount = 0
            myCurrentSpell = nil
        end
        if isResurrecting and not getLibpredict() then
            -- Rez cast completed - don't clear ress, set timer
            isResurrecting = false
        end

    elseif event == "SPELLCAST_FAILED" then
        HealComm:AnnounceHealStop()

    elseif event == "SPELLCAST_INTERRUPTED" then
        -- Could be SpellStopCasting (chaining) or damage interrupt
        -- Send Healstop but preserve pending (new cast may follow)
        if isHealing and not getLibpredict() then
            ProcessHealStop(getPlayerName())
            SendHealCommMsg("Healstop")
        end
        if isResurrecting and not getLibpredict() then
            ProcessRessStop(getPlayerName())
            SendHealCommMsg("Resurrection/stop/")
            SendResCommMsg("RESNO " .. (myCurrentTarget or ""))
        end
        isHealing = false
        isResurrecting = false
        myCurrentTarget = nil
        myCurrentAmount = 0
        myCurrentSpell = nil
        -- Clear regrowth timer
        regrowth_timer = nil
        regrowth_start = nil
        regrowth_target = nil
        regrowth_rank = nil
        -- NOTE: myPendingTarget preserved for heal chaining

    elseif event == "SPELL_FAILED_SELF" then
        -- Nampower: more reliable failure detection
        HealComm:AnnounceHealStop()

    elseif event == "SPELL_DELAYED_SELF" then
        -- Nampower: pushback
        if isHealing and arg2 and not getLibpredict() then
            ProcessHealDelay(getPlayerName(), arg2)
            SendHealCommMsg("Healdelay/" .. arg2 .. "/")
        end

    elseif event == "SPELL_HEAL_BY_SELF" then
        -- Nampower: cache heal amounts for non-QuickHeal casts
        if getLibpredict() then return end
        -- arg3=spellId, arg4=amount, arg5=critical
        local amount = arg4
        local isCrit = arg5 == 1
        if amount and spell_queue[1] then
            UpdateCache(spell_queue[2], amount, isCrit)
        end

    elseif event == "PLAYER_ENTERING_WORLD"
        or event == "LEARNED_SPELL_IN_TAB"
        or event == "CHARACTER_POINTS_CHANGED" then
        if getLibpredict() then return end
        FlagCacheStale()
        CheckSetBonuses()

    elseif event == "UNIT_INVENTORY_CHANGED" then
        if getLibpredict() then return end
        if arg1 and arg1 ~= "player" then return end
        -- Check if gear actually changed
        local gear = ""
        for id = 1, 18 do
            gear = gear .. (GetInventoryItemLink("player", id) or "")
        end
        if gear == gear_string then return end
        gear_string = gear
        FlagCacheStale()
        CheckSetBonuses()
    end
end)

-- OnUpdate: cleanup + Regrowth timer
frame:SetScript("OnUpdate", function()
    if getLibpredict() then return end

    local now = GetTime()
    if (this.tick or 0) > now then return end
    this.tick = now + 0.1 -- 10 FPS

    -- Trigger delayed Regrowth HoT announcement
    if regrowth_timer and now > regrowth_timer then
        local target = regrowth_target or getPlayerName()
        local duration = 20
        local startTime = regrowth_start
        local rank = regrowth_rank

        ProcessHot(getPlayerName(), target, "Regr", duration, startTime, rank)
        local rankStr = rank and tostring(rank) or "0"
        SendHealCommMsg("Regr/" .. target .. "/" .. duration .. "/" .. rankStr .. "/")

        regrowth_timer = nil
        regrowth_start = nil
        regrowth_target = nil
        regrowth_rank = nil
    end

    -- Expire timed-out heal entries
    for timestamp, _ in pairs(evts) do
        if now >= timestamp then
            evts[timestamp] = nil
        end
    end

    -- Expire ress timers
    for target, senders in pairs(ress_timers) do
        for sender, expiry in pairs(senders) do
            if now >= expiry then
                senders[sender] = nil
                if ress[target] then ress[target][sender] = nil end
            end
        end
    end
end)
