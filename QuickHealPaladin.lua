-- QuickHeal Paladin Module (Refactored)
-- Consolidated spell selection with shared helper functions

local function writeLine(s,r,g,b)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(s, r or 1, g or 1, b or 0.5)
    end
end

-- Penalty Factors for low-level spells
local PF = {
    [1] = 0.2875,
    [6] = 0.475,
    [14] = 0.775,
}

function QuickHeal_Paladin_GetRatioHealthyExplanation()
    local RatioHealthy = QuickHeal_GetRatioHealthy()
    local RatioFull = QuickHealVariables["RatioFull"]

    if RatioHealthy >= RatioFull then
        return QUICKHEAL_SPELL_HOLY_LIGHT .. " will never be used in combat. Exception : Holy Judgement buff "
    else
        if RatioHealthy > 0 then
            return QUICKHEAL_SPELL_HOLY_LIGHT .. " will only be used in combat if the target has more than " .. RatioHealthy*100 .. "% life, and only if the healing done is greater than the greatest " .. QUICKHEAL_SPELL_FLASH_OF_LIGHT .. " available. Exception : Holy Judgement buff "
        else
            return QUICKHEAL_SPELL_HOLY_LIGHT .. " will only be used in combat if the healing done is greater than the greatest " .. QUICKHEAL_SPELL_FLASH_OF_LIGHT .. " available. Exception : Holy Judgement buff "
        end
    end
end

-- Calculate all Paladin-specific modifiers
local function GetPaladinModifiers()
    local mods = {}

    -- Equipment healing bonus (cached)
    mods.bonus = QuickHeal_GetEquipmentBonus()

    -- Calculate healing modifiers by cast time
    mods.healMod15 = (1.5/3.5) * mods.bonus
    mods.healMod25 = (2.5/3.5) * mods.bonus

    -- Healing Light Talent - increases healing by 4% per rank
    local hlRank = QuickHeal_GetTalentRank(1, 6)
    mods.hlMod = 1 + 4 * hlRank / 100

    -- Divine Favor Talent - increases Holy Shock effect by 5% per rank (crit is 50% bonus)
    local dfRank = QuickHeal_GetTalentRank(1, 13)
    mods.dfMod = 1 + 5 * dfRank / 100

    return mods
end

-- Check for Paladin-specific buffs that affect healing
-- Returns: forceHL flag
local function CheckPaladinBuffs()
    local forceHL = false

    -- Detect Hand of Edward the Odd (next spell is instant cast)
    if QuickHeal_DetectBuff('player', "Spell_Holy_SearingLight") then
        QuickHeal_debug("BUFF: Hand of Edward the Odd (out of combat healing forced)")
        forceHL = true
    end

    -- Detect Holy Judgement (next Holy Light is fast cast)
    if QuickHeal_DetectBuff('player', "ability_paladin_judgementblue") then
        QuickHeal_debug("BUFF: Holy Judgement (out of combat healing forced)")
        forceHL = true
    end

    return forceHL
end

-- Unified heal spell selection (works with or without target)
-- target: unit ID or nil (for NoTarget mode)
-- maxhealth, healDeficit, hdb, incombat: used when target is nil
function QuickHeal_Paladin_FindSpellToUse(target, healType, multiplier, forceMaxHPS, maxhealth, healDeficit, hdb, incombat)
    local SpellID = nil
    local HealSize = 0
    multiplier = multiplier or 1

    local RatioFull = QuickHealVariables["RatioFull"]
    local RatioHealthy = QuickHeal_GetRatioHealthy()
    local debug = QuickHeal_debug

    -- Get health info
    local healneed, Health, HDB
    if target then
        if QuickHeal_UnitHasHealthInfo(target) and UnitHealthMax(target) > 0 then
            healneed = UnitHealthMax(target) - UnitHealth(target)
            if multiplier > 1.0 then
                healneed = healneed * multiplier
            end
            Health = UnitHealth(target) / UnitHealthMax(target)
        else
            healneed = QuickHeal_EstimateUnitHealNeed(target, true)
            if multiplier > 1.0 then
                healneed = healneed * multiplier
            end
            Health = UnitHealth(target) / 100
        end
        HDB = QuickHeal_GetHealModifier(target)
        incombat = UnitAffectingCombat('player') or UnitAffectingCombat(target)
    else
        if not maxhealth or maxhealth <= 0 then return nil, 0 end
        healneed = healDeficit * multiplier
        Health = healDeficit / maxhealth
        HDB = hdb or 1
        incombat = UnitAffectingCombat('player') or incombat
    end

    -- Return if no target
    if target == nil and maxhealth == nil then
        return nil, 0
    end

    debug("Target debuff healing modifier", HDB)
    healneed = healneed / HDB

    -- Check for overheal
    if multiplier and multiplier > 1.0 then
        jgpprint(">>> multiplier is " .. multiplier .. " <<<")
    end

    -- Get modifiers
    local mods = GetPaladinModifiers()
    local ManaLeft = UnitMana('player')

    -- Check buffs
    local ForceHL = CheckPaladinBuffs()

    -- Get spell IDs
    local SpellIDsHL = QuickHeal_GetSpellIDs(QUICKHEAL_SPELL_HOLY_LIGHT)
    local SpellIDsFL = QuickHeal_GetSpellIDs(QUICKHEAL_SPELL_FLASH_OF_LIGHT)

    local maxRankHL = table.getn(SpellIDsHL)
    local maxRankFL = table.getn(SpellIDsFL)
    local NoFL = maxRankFL < 1

    debug(string.format("Found HL up to rank %d, and found FL up to rank %d", maxRankHL, maxRankFL))

    -- Downrank settings
    local downRankFH = QuickHealVariables.DownrankValueFH or 0
    local downRankNH = QuickHealVariables.DownrankValueNH or 0

    -- Combat multipliers
    local k, K = QuickHeal_GetCombatMultipliers(incombat)

    local TargetIsHealthy = Health >= RatioHealthy
    local hlMod = mods.hlMod
    local healMod15, healMod25 = mods.healMod15, mods.healMod25

    if TargetIsHealthy then
        debug("Target is healthy", Health)
    end

    if not forceMaxHPS or not incombat then
        if Health < RatioFull or not target then
            -- Default to FL rank 1 or HL rank 1
            if maxRankFL >= 1 and SpellIDsFL[1] then
                SpellID = SpellIDsFL[1]; HealSize = (67 + healMod15) * hlMod
            else
                SpellID = SpellIDsHL[1]; HealSize = (43 + healMod25 * PF[1]) * hlMod
            end
            if healneed > (83 + healMod25 * PF[6]) * hlMod * K  and ManaLeft >= 60  and maxRankHL >= 2 and ((TargetIsHealthy or ForceHL) and maxRankFL <= 1 or NoFL) and SpellIDsHL[2] then SpellID = SpellIDsHL[2]; HealSize = (83 + healMod25 * PF[6]) * hlMod end
            if healneed > (102 + healMod15) * hlMod * k         and ManaLeft >= 50  and maxRankFL >= 2 and downRankFH >= 2 and SpellIDsFL[2] then SpellID = SpellIDsFL[2]; HealSize = (102 + healMod15) * hlMod end
            if healneed > (153 + healMod15) * hlMod * k         and ManaLeft >= 70  and maxRankFL >= 3 and downRankFH >= 3 and SpellIDsFL[3] then SpellID = SpellIDsFL[3]; HealSize = (153 + healMod15) * hlMod end
            if healneed > (173 + healMod25 * PF[14]) * hlMod * K and ManaLeft >= 110 and maxRankHL >= 3 and ((TargetIsHealthy or ForceHL) and maxRankFL <= 3 or NoFL) and SpellIDsHL[3] then SpellID = SpellIDsHL[3]; HealSize = (173 + healMod25 * PF[14]) * hlMod end
            if healneed > (206 + healMod15) * hlMod * k         and ManaLeft >= 90  and maxRankFL >= 4 and downRankFH >= 4 and SpellIDsFL[4] then SpellID = SpellIDsFL[4]; HealSize = (206 + healMod15) * hlMod end
            if healneed > (278 + healMod15) * hlMod * k         and ManaLeft >= 115 and maxRankFL >= 5 and downRankFH >= 5 and SpellIDsFL[5] then SpellID = SpellIDsFL[5]; HealSize = (278 + healMod15) * hlMod end
            if healneed > (333 + healMod25) * hlMod * K         and ManaLeft >= 190 and maxRankHL >= 4 and ((TargetIsHealthy or ForceHL) and maxRankFL <= 5 or NoFL) and SpellIDsHL[4] then SpellID = SpellIDsHL[4]; HealSize = (333 + healMod25) * hlMod end
            if healneed > (348 + healMod15) * hlMod * k         and ManaLeft >= 140 and maxRankFL >= 6 and downRankFH >= 6 and SpellIDsFL[6] then SpellID = SpellIDsFL[6]; HealSize = (348 + healMod15) * hlMod end
            if healneed > (428 + healMod15) * hlMod * k         and ManaLeft >= 180 and maxRankFL >= 7 and downRankFH >= 7 and SpellIDsFL[7] then SpellID = SpellIDsFL[7]; HealSize = (428 + healMod15) * hlMod end
            if healneed > (522 + healMod25) * hlMod * K         and ManaLeft >= 275 and maxRankHL >= 5 and ((TargetIsHealthy or ForceHL) and maxRankFL <= 7 or NoFL) and SpellIDsHL[5] then SpellID = SpellIDsHL[5]; HealSize = (522 + healMod25) * hlMod end
            if healneed > (739 + healMod25) * hlMod * K         and ManaLeft >= 365 and maxRankHL >= 6 and ((TargetIsHealthy or ForceHL) and maxRankFL <= 7 or NoFL) and SpellIDsHL[6] then SpellID = SpellIDsHL[6]; HealSize = (739 + healMod25) * hlMod end
            if healneed > (999 + healMod25) * hlMod * K         and ManaLeft >= 465 and maxRankHL >= 7 and ((TargetIsHealthy or ForceHL) and maxRankFL <= 7 or NoFL) and SpellIDsHL[7] then SpellID = SpellIDsHL[7]; HealSize = (999 + healMod25) * hlMod end
            if healneed > (1317 + healMod25) * hlMod * K        and ManaLeft >= 580 and maxRankHL >= 8 and ((TargetIsHealthy or ForceHL) and maxRankFL <= 7 or NoFL) and SpellIDsHL[8] then SpellID = SpellIDsHL[8]; HealSize = (1317 + healMod25) * hlMod end
            if healneed > (1680 + healMod25) * hlMod * K        and ManaLeft >= 660 and maxRankHL >= 9 and ((TargetIsHealthy or ForceHL) and maxRankFL <= 7 or NoFL) and SpellIDsHL[9] then SpellID = SpellIDsHL[9]; HealSize = (1680 + healMod25) * hlMod end
        end
    else
        -- Force max HPS
        if ManaLeft >= 35  and maxRankFL >= 1 and downRankFH >= 1 and SpellIDsFL[1] then SpellID = SpellIDsFL[1]; HealSize = (67 + healMod15) * hlMod end
        if ManaLeft >= 50  and maxRankFL >= 2 and downRankFH >= 2 and SpellIDsFL[2] then SpellID = SpellIDsFL[2]; HealSize = (102 + healMod15) * hlMod end
        if ManaLeft >= 70  and maxRankFL >= 3 and downRankFH >= 3 and SpellIDsFL[3] then SpellID = SpellIDsFL[3]; HealSize = (153 + healMod15) * hlMod end
        if ManaLeft >= 90  and maxRankFL >= 4 and downRankFH >= 4 and SpellIDsFL[4] then SpellID = SpellIDsFL[4]; HealSize = (206 + healMod15) * hlMod end
        if ManaLeft >= 115 and maxRankFL >= 5 and downRankFH >= 5 and SpellIDsFL[5] then SpellID = SpellIDsFL[5]; HealSize = (278 + healMod15) * hlMod end
        if ManaLeft >= 140 and maxRankFL >= 6 and downRankFH >= 6 and SpellIDsFL[6] then SpellID = SpellIDsFL[6]; HealSize = (348 + healMod15) * hlMod end
        if ManaLeft >= 180 and maxRankFL >= 7 and downRankFH >= 7 and SpellIDsFL[7] then SpellID = SpellIDsFL[7]; HealSize = (428 + healMod15) * hlMod end
        if ManaLeft >= 275 and maxRankHL >= 5 and (ForceHL and maxRankFL <= 7 or NoFL) and SpellIDsHL[5] then SpellID = SpellIDsHL[5]; HealSize = (522 + healMod25) * hlMod end
        if ManaLeft >= 365 and maxRankHL >= 6 and (ForceHL and maxRankFL <= 7 or NoFL) and SpellIDsHL[6] then SpellID = SpellIDsHL[6]; HealSize = (739 + healMod25) * hlMod end
        if ManaLeft >= 465 and maxRankHL >= 7 and (ForceHL and maxRankFL <= 7 or NoFL) and SpellIDsHL[7] then SpellID = SpellIDsHL[7]; HealSize = (999 + healMod25) * hlMod end
        if ManaLeft >= 580 and maxRankHL >= 8 and (ForceHL and maxRankFL <= 7 or NoFL) and SpellIDsHL[8] then SpellID = SpellIDsHL[8]; HealSize = (1317 + healMod25) * hlMod end
        if ManaLeft >= 660 and maxRankHL >= 9 and (ForceHL and maxRankFL <= 7 or NoFL) and SpellIDsHL[9] then SpellID = SpellIDsHL[9]; HealSize = (1680 + healMod25) * hlMod end
    end

    return SpellID, HealSize * HDB
end

-- NoTarget wrapper for backwards compatibility
function QuickHeal_Paladin_FindHealSpellToUseNoTarget(maxhealth, healDeficit, healType, multiplier, forceMaxHPS, forceMaxRank, hdb, incombat)
    return QuickHeal_Paladin_FindSpellToUse(nil, healType, multiplier, forceMaxHPS, maxhealth, healDeficit, hdb, incombat)
end

-- Unified HoT/Holy Shock spell selection
function QuickHeal_Paladin_FindHoTSpellToUse(target, healType, forceMaxRank, maxhealth, healDeficit, hdb, incombat)
    local SpellID = nil
    local HealSize = 0

    local RatioHealthy = QuickHeal_GetRatioHealthy()
    local debug = QuickHeal_debug

    -- Get health info
    local healneed, Health, HDB
    if target then
        if QuickHeal_UnitHasHealthInfo(target) then
            healneed = UnitHealthMax(target) - UnitHealth(target)
            Health = UnitHealth(target) / UnitHealthMax(target)
        else
            healneed = QuickHeal_EstimateUnitHealNeed(target, true)
            Health = UnitHealth(target) / 100
        end
        HDB = QuickHeal_GetHealModifier(target)
    else
        if not healDeficit or healDeficit <= 0 then
            return nil, 0
        end
        healneed = healDeficit * 1
        Health = 1 - (healDeficit / maxhealth)
        HDB = hdb or 1
    end

    debug("Target debuff healing modifier", HDB)
    healneed = healneed / HDB

    -- Return if no target
    if target == nil and maxhealth == nil then
        return nil, 0
    end

    -- Get modifiers
    local mods = GetPaladinModifiers()
    local ManaLeft = UnitMana('player')

    -- Get Holy Shock spell IDs
    local SpellIDsHS = QuickHeal_GetSpellIDs(QUICKHEAL_SPELL_HOLY_SHOCK)
    local maxRankHS = table.getn(SpellIDsHS)

    debug(string.format("Found HS up to rank %d", maxRankHS))

    local hlMod = mods.hlMod
    local dfMod = mods.dfMod
    local healMod15 = mods.healMod15

    local TargetIsHealthy = Health >= RatioHealthy
    if TargetIsHealthy then
        debug("Target is healthy", Health)
    end

    QuickHeal_debug(string.format(
        "healneed: %f  target: %s  healType: %s  forceMaxRank: %s",
        healneed, tostring(target), tostring(healType), tostring(forceMaxRank)
    ))

    if forceMaxRank then
        -- Force max rank
        if maxRankHS >= 1 then
            SpellID = SpellIDsHS[maxRankHS]
            HealSize = (655 + healMod15) * hlMod * dfMod
        end
    else
        -- Select rank based on healneed
        SpellID = SpellIDsHS[1]; HealSize = (315 + healMod15) * hlMod * dfMod
        if healneed > (360 + healMod15) * hlMod * dfMod and ManaLeft >= 335 and maxRankHS >= 2 and SpellIDsHS[2] then SpellID = SpellIDsHS[2]; HealSize = (360 + healMod15) * hlMod * dfMod end
        if healneed > (500 + healMod15) * hlMod * dfMod and ManaLeft >= 410 and maxRankHS >= 3 and SpellIDsHS[3] then SpellID = SpellIDsHS[3]; HealSize = (500 + healMod15) * hlMod * dfMod end
        if healneed > (655 + healMod15) * hlMod * dfMod and ManaLeft >= 485 and maxRankHS >= 4 and SpellIDsHS[4] then SpellID = SpellIDsHS[4]; HealSize = (655 + healMod15) * hlMod * dfMod end
    end

    return SpellID, HealSize * HDB
end

-- NoTarget wrapper for backwards compatibility
function QuickHeal_Paladin_FindHoTSpellToUseNoTarget(maxhealth, healDeficit, healType, multiplier, forceMaxHPS, forceMaxRank, hdb, incombat)
    return QuickHeal_Paladin_FindHoTSpellToUse(nil, healType, forceMaxRank, maxhealth, healDeficit, hdb, incombat)
end

-- Command handler
function QuickHeal_Command_Paladin(msg)
    local _, _, arg1, arg2, arg3 = string.find(msg, "%s?(%w+)%s?(%w+)%s?(%w+)")

    -- Match 3 arguments
    if arg1 and arg2 and arg3 then
        if arg1 == "player" or arg1 == "target" or arg1 == "targettarget" or arg1 == "party" or arg1 == "subgroup" or arg1 == "mt" or arg1 == "nonmt" then
            if arg2 == "heal" and arg3 == "max" then
                QuickHeal(arg1, nil, nil, true)
                return
            end
            if arg2 == "hs" and arg3 == "fh" then
                QuickHOT(arg1, nil, nil, true, true)
                return
            end
            if arg2 == "hs" and arg3 == "max" then
                QuickHOT(arg1, nil, nil, true, false)
                return
            end
        end
    end

    -- Match 2 arguments
    local _, _, arg4, arg5 = string.find(msg, "%s?(%w+)%s?(%w+)")

    if arg4 and arg5 then
        if arg4 == "debug" then
            if arg5 == "on" then
                QHV.DebugMode = true
                return
            elseif arg5 == "off" then
                QHV.DebugMode = false
                return
            end
        end
        if arg4 == "heal" and arg5 == "max" then
            QuickHeal(nil, nil, nil, true)
            return
        end
        if arg4 == "hs" and arg5 == "max" then
            QuickHOT(nil, nil, nil, true, false)
            return
        end
        if arg4 == "hs" and arg5 == "fh" then
            QuickHOT(nil, nil, nil, true, true)
            return
        end
        if arg4 == "player" or arg4 == "target" or arg4 == "targettarget" or arg4 == "party" or arg4 == "subgroup" or arg4 == "mt" or arg4 == "nonmt" then
            if arg5 == "hs" then
                QuickHOT(arg4, nil, nil, false, false)
                return
            end
            if arg5 == "heal" then
                QuickHeal(arg4, nil, nil, false)
                return
            end
        end
    end

    -- Match 1 argument
    local cmd = string.lower(msg)

    if cmd == "cfg" then
        QuickHeal_ToggleConfigurationPanel()
        return
    end
    if cmd == "toggle" then
        QuickHeal_Toggle_Healthy_Threshold()
        return
    end
    if cmd == "downrank" or cmd == "dr" then
        ToggleDownrankWindow()
        return
    end
    if cmd == "tanklist" or cmd == "tl" then
        QH_ShowHideMTListUI()
        return
    end
    if cmd == "reset" then
        QuickHeal_SetDefaultParameters()
        writeLine(QuickHealData.name .. " reset to default configuration", 0, 0, 1)
        QuickHeal_ToggleConfigurationPanel()
        QuickHeal_ToggleConfigurationPanel()
        return
    end
    if cmd == "dll" then
        QuickHeal_ReportDLLStatus()
        return
    end
    if cmd == "heal" then
        QuickHeal()
        return
    end
    if cmd == "hs" then
        QuickHOT()
        return
    end
    if cmd == "hot" then
        writeLine("The command /qh hot is disabled for paladins. Use /qh hs instead.", 1, 0, 0)
        return
    end
    if cmd == "" then
        QuickHeal(nil)
        return
    elseif cmd == "player" or cmd == "target" or cmd == "targettarget" or cmd == "party" or cmd == "subgroup" or cmd == "mt" or cmd == "nonmt" then
        QuickHeal(cmd)
        return
    end

    -- Print usage
    writeLine("== QUICKHEAL USAGE : PALADIN ==")
    writeLine("/qh cfg - Opens up the configuration panel.")
    writeLine("/qh toggle - Switches between High HPS and Normal HPS.")
    writeLine("/qh downrank | dr - Opens the downrank limit slider.")
    writeLine("/qh tanklist | tl - Toggles display of the main tank list.")
    writeLine("/qh [mask] [type] [mod] - Heals the ally who needs it most.")
    writeLine(" [mask]: player, target, targettarget, party, mt, nonmt, subgroup")
    writeLine(" [type]: heal (direct heal), hs (Holy Shock)")
    writeLine(" [mod]: max (max rank), fh (firehose - max rank, no hp check)")
    writeLine("/qh reset - Reset configuration to default parameters.")
end

------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Melee Paladin Healing Functions (by Drokin)
-- Smart automation for Holy Strike and Holy Shock in melee range
-- /run qhHStrike(93,3) - Holy Strike at 93% HP threshold with 3 targets needed
-- /run qhHShock(85) - Holy Shock at 85% HP threshold

function qhHStrike(HSminHP, HSminTargets)
    local playersInRange = GetPlayersBelowHealthThresholdInRange(HSminHP)
    if playersInRange >= HSminTargets then
        CastSpellByName("Holy Strike")
    end
end

function qhHShock(SHOCKminHP)
    local target, healthPct = GetLowestHealthUnit()
    if target and healthPct < SHOCKminHP then
        CastSpellByName("Holy Shock", target)
    end
end

function IsHealable(unit)
    return UnitExists(unit) and UnitIsFriend("player", unit) and not UnitIsDeadOrGhost(unit) and UnitIsConnected(unit)
end

function IsWithin10Yards(unit)
    return CheckInteractDistance(unit, 3)
end

function GetPlayersBelowHealthThresholdInRange(minHPf)
    local count = 0
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local unit = "raid" .. i
            if IsHealable(unit) and IsWithin10Yards(unit) then
                local healthPercent = (UnitHealth(unit) / UnitHealthMax(unit)) * 100
                if healthPercent <= minHPf then
                    count = count + 1
                end
            end
        end
    else
        local units = {"player"}
        if GetNumPartyMembers() > 0 then
            for i = 1, GetNumPartyMembers() do
                table.insert(units, "party" .. i)
            end
        end
        for _, unit in ipairs(units) do
            if IsHealable(unit) and IsWithin10Yards(unit) then
                local healthPercent = (UnitHealth(unit) / UnitHealthMax(unit)) * 100
                if healthPercent <= minHPf then
                    count = count + 1
                end
            end
        end
    end
    return count
end

function GetLowestHealthUnit()
    local lowestUnit = nil
    local lowestHealthPct = 100

    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local unit = "raid" .. i
            if IsHealable(unit) and CheckInteractDistance(unit, 4) then
                local healthPct = (UnitHealth(unit) / UnitHealthMax(unit)) * 100
                if healthPct < lowestHealthPct then
                    lowestUnit = unit
                    lowestHealthPct = healthPct
                end
            end
        end
    else
        local units = {"player"}
        if GetNumPartyMembers() > 0 then
            for i = 1, GetNumPartyMembers() do
                table.insert(units, "party" .. i)
            end
        end
        for _, unit in ipairs(units) do
            if IsHealable(unit) and CheckInteractDistance(unit, 4) then
                local healthPct = ((UnitHealth(unit) + HealComm:getHeal(UnitName(unit))) / UnitHealthMax(unit)) * 100
                if healthPct < lowestHealthPct then
                    lowestUnit = unit
                    lowestHealthPct = healthPct
                end
            end
        end
    end

    return lowestUnit, lowestHealthPct
end
