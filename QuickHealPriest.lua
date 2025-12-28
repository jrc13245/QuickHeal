-- QuickHeal Priest Module (Refactored)
-- Consolidated spell selection with shared helper functions

-- Penalty Factors for low-level spells
local PF = QuickHeal_PenaltyFactor or {
    [1] = 0.2875, [4] = 0.4, [10] = 0.625, [18] = 0.925, [20] = 1.0
}

function QuickHeal_Priest_GetRatioHealthyExplanation()
    if QuickHealVariables.RatioHealthyPriest >= QuickHealVariables.RatioFull then
        return QUICKHEAL_SPELL_FLASH_HEAL .. " will always be used in combat, and " .. QUICKHEAL_SPELL_LESSER_HEAL .. ", " .. QUICKHEAL_SPELL_HEAL .. " or " .. QUICKHEAL_SPELL_GREATER_HEAL .. " will be used when out of combat. ";
    else
        if QuickHealVariables.RatioHealthyPriest > 0 then
            return QUICKHEAL_SPELL_FLASH_HEAL .. " will be used in combat if the target has less than " .. QuickHealVariables.RatioHealthyPriest*100 .. "% life, and " .. QUICKHEAL_SPELL_LESSER_HEAL .. ", " .. QUICKHEAL_SPELL_HEAL .. " or " .. QUICKHEAL_SPELL_GREATER_HEAL .. " will be used otherwise. ";
        else
            return QUICKHEAL_SPELL_FLASH_HEAL .. " will never be used. " .. QUICKHEAL_SPELL_LESSER_HEAL .. ", " .. QUICKHEAL_SPELL_HEAL .. " or " .. QUICKHEAL_SPELL_GREATER_HEAL .. " will always be used in and out of combat. ";
        end
    end
end

-- Calculate all Priest-specific modifiers
-- Returns: table with bonus, healMods, shMod, ihMod, sgMod
local function GetPriestModifiers()
    local mods = {}

    -- Equipment healing bonus (cached)
    mods.bonus = QuickHeal_GetEquipmentBonus()

    -- Spiritual Guidance - 5% of Spirit per rank
    local sgRank = QuickHeal_GetTalentRank(2, 12)
    local _, spirit = UnitStat('player', 5)
    mods.sgMod = (spirit or 0) * 5 * sgRank / 100

    -- Total healing bonus
    local totalBonus = mods.bonus + mods.sgMod

    -- Healing modifiers by cast time (with 0.85 downrank penalty for direct heals)
    mods.healMod15 = (1.5/3.5) * totalBonus * 0.85
    mods.healMod20 = (2.0/3.5) * totalBonus * 0.85
    mods.healMod25 = (2.5/3.5) * totalBonus * 0.85
    mods.healMod30 = (3.0/3.5) * totalBonus * 0.85

    -- HoT modifiers (no downrank penalty)
    mods.hotMod15 = (1.5/3.5) * totalBonus
    mods.hotMod30 = (3.0/3.5) * totalBonus

    -- Spiritual Healing - 6% per rank
    local shRank = QuickHeal_GetTalentRank(2, 15)
    mods.shMod = 1 + 6 * shRank / 100

    -- Improved Healing - reduces mana by 5% per rank
    local ihRank = QuickHeal_GetTalentRank(2, 11)
    mods.ihMod = 1 - 5 * ihRank / 100

    return mods
end

-- Check for Priest-specific buffs that affect healing
-- Returns: inCombat (adjusted), manaLeft (adjusted), healneed (adjusted), forceGH
local function CheckPriestBuffs(target, inCombat, manaLeft, healneed)
    local forceGH = false

    -- Hand of Edward the Odd - instant cast
    if QuickHeal_DetectBuff('player', "Spell_Holy_SearingLight") then
        QuickHeal_debug("BUFF: Hand of Edward the Odd (out of combat healing forced)")
        inCombat = false
    end

    -- Hazza'rah's Charm - force Greater Heal
    if QuickHeal_DetectBuff('player', "Spell_Holy_HealingAura") then
        QuickHeal_debug("BUFF: Hazza'rah buff (Greater Heal forced)")
        forceGH = true
    end

    -- Inner Focus or Spirit of Redemption - free mana
    if QuickHeal_DetectBuff('player', "Spell_Frost_WindWalkOn", 1) or
       QuickHeal_DetectBuff('player', "Spell_Holy_GreaterHeal") then
        QuickHeal_debug("Inner Focus or Spirit of Redemption active")
        manaLeft = UnitManaMax('player')
        healneed = 1000000
    end

    return inCombat, manaLeft, healneed, forceGH
end

-- Unified heal spell selection (works with or without target)
-- target: unit ID or nil (for NoTarget mode)
-- maxhealth, healDeficit, hdb, incombat: used when target is nil
function QuickHeal_Priest_FindHealSpellToUse(target, healType, multiplier, forceMaxHPS, maxhealth, healDeficit, hdb, incombat)
    local SpellID = nil
    local HealSize = 0
    multiplier = multiplier or 1

    -- Get health info
    local healneed, Health, HDB
    if target then
        healneed, Health, HDB = QuickHeal_GetTargetHealth(target, nil, nil, multiplier, nil)
        incombat = UnitAffectingCombat('player') or UnitAffectingCombat(target)
    else
        healneed, Health, HDB = QuickHeal_GetTargetHealth(nil, maxhealth, healDeficit, multiplier, hdb)
        incombat = UnitAffectingCombat('player') or incombat
    end

    if healneed <= 0 then return nil, 0 end

    -- Get modifiers
    local mods = GetPriestModifiers()
    local ManaLeft = UnitMana('player')

    -- Check buffs
    local forceGH
    incombat, ManaLeft, healneed, forceGH = CheckPriestBuffs(target, incombat, ManaLeft, healneed)

    -- Get spell IDs (cached)
    local SpellIDsLH = QuickHeal_GetSpellIDs(QUICKHEAL_SPELL_LESSER_HEAL)
    local SpellIDsH  = QuickHeal_GetSpellIDs(QUICKHEAL_SPELL_HEAL)
    local SpellIDsGH = QuickHeal_GetSpellIDs(QUICKHEAL_SPELL_GREATER_HEAL)
    local SpellIDsFH = QuickHeal_GetSpellIDs(QUICKHEAL_SPELL_FLASH_HEAL)

    local maxRankLH = table.getn(SpellIDsLH)
    local maxRankH  = table.getn(SpellIDsH)
    local maxRankGH = table.getn(SpellIDsGH)
    local maxRankFH = table.getn(SpellIDsFH)

    -- Downrank settings
    local downRankFH = QuickHealVariables.DownrankValueFH or 99
    local downRankNH = QuickHealVariables.DownrankValueNH or 99

    -- Combat multipliers
    local k, K = QuickHeal_GetCombatMultipliers(incombat)

    local TargetIsHealthy = Health >= QuickHealVariables.RatioHealthyPriest
    local shMod = mods.shMod
    local ihMod = mods.ihMod
    local healMod15, healMod20, healMod25, healMod30 = mods.healMod15, mods.healMod20, mods.healMod25, mods.healMod30

    -- Hazza'rah buff path - force Greater Heal
    if forceGH and ManaLeft >= 351*ihMod and maxRankGH >= 1 and downRankNH >= 8 and SpellIDsGH[1] then
        if Health < QuickHealVariables.RatioFull then
            SpellID = SpellIDsGH[1]; HealSize = (838+healMod30)*shMod
            if healneed > (1066+healMod30)*K*shMod and ManaLeft >= 432*ihMod and maxRankGH >= 2 and downRankNH >= 9  and SpellIDsGH[2] then SpellID = SpellIDsGH[2]; HealSize = (1066+healMod30)*shMod end
            if healneed > (1328+healMod30)*K*shMod and ManaLeft >= 517*ihMod and maxRankGH >= 3 and downRankNH >= 10 and SpellIDsGH[3] then SpellID = SpellIDsGH[3]; HealSize = (1328+healMod30)*shMod end
            if healneed > (1632+healMod30)*K*shMod and ManaLeft >= 622*ihMod and maxRankGH >= 4 and downRankNH >= 11 and SpellIDsGH[4] then SpellID = SpellIDsGH[4]; HealSize = (1632+healMod30)*shMod end
            if healneed > (1768+healMod30)*K*shMod and ManaLeft >= 674*ihMod and maxRankGH >= 5 and downRankNH >= 12 and SpellIDsGH[5] then SpellID = SpellIDsGH[5]; HealSize = (1768+healMod30)*shMod end
        end
    -- Normal healing (mana efficient)
    elseif not incombat or TargetIsHealthy or maxRankFH < 1 then
        if Health < QuickHealVariables.RatioFull then
            SpellID = SpellIDsLH[1]; HealSize = (53+healMod15*PF[1])*shMod
            if healneed > ( 84+healMod20*PF[4])*k*shMod  and ManaLeft >= 45*ihMod  and maxRankLH >= 2 and downRankNH >= 2  and SpellIDsLH[2] then SpellID = SpellIDsLH[2]; HealSize = ( 84+healMod20*PF[4])*shMod end
            if healneed > (154+healMod25*PF[10])*K*shMod and ManaLeft >= 75*ihMod  and maxRankLH >= 3 and downRankNH >= 3  and SpellIDsLH[3] then SpellID = SpellIDsLH[3]; HealSize = (154+healMod25*PF[10])*shMod end
            if healneed > (330+healMod30*PF[18])*K*shMod and ManaLeft >= 155*ihMod and maxRankH >= 1  and downRankNH >= 4  and SpellIDsH[1]  then SpellID = SpellIDsH[1];  HealSize = (330+healMod30*PF[18])*shMod end
            if healneed > (476+healMod30)*K*shMod        and ManaLeft >= 205*ihMod and maxRankH >= 2  and downRankNH >= 5  and SpellIDsH[2]  then SpellID = SpellIDsH[2];  HealSize = (476+healMod30)*shMod end
            if healneed > (624+healMod30)*K*shMod        and ManaLeft >= 255*ihMod and maxRankH >= 3  and downRankNH >= 6  and SpellIDsH[3]  then SpellID = SpellIDsH[3];  HealSize = (624+healMod30)*shMod end
            if healneed > (667+healMod30)*K*shMod        and ManaLeft >= 305*ihMod and maxRankH >= 4  and downRankNH >= 7  and SpellIDsH[4]  then SpellID = SpellIDsH[4];  HealSize = (667+healMod30)*shMod end
            if healneed > (838+healMod30)*K*shMod        and ManaLeft >= 370*ihMod and maxRankGH >= 1 and downRankNH >= 8  and SpellIDsGH[1] then SpellID = SpellIDsGH[1]; HealSize = (838+healMod30)*shMod end
            if healneed > (1066+healMod30)*K*shMod       and ManaLeft >= 455*ihMod and maxRankGH >= 2 and downRankNH >= 9  and SpellIDsGH[2] then SpellID = SpellIDsGH[2]; HealSize = (1066+healMod30)*shMod end
            if healneed > (1328+healMod30)*K*shMod       and ManaLeft >= 545*ihMod and maxRankGH >= 3 and downRankNH >= 10 and SpellIDsGH[3] then SpellID = SpellIDsGH[3]; HealSize = (1328+healMod30)*shMod end
            if healneed > (1632+healMod30)*K*shMod       and ManaLeft >= 655*ihMod and maxRankGH >= 4 and downRankNH >= 11 and SpellIDsGH[4] then SpellID = SpellIDsGH[4]; HealSize = (1632+healMod30)*shMod end
            if healneed > (1768+healMod30)*K*shMod       and ManaLeft >= 710*ihMod and maxRankGH >= 5 and downRankNH >= 12 and SpellIDsGH[5] then SpellID = SpellIDsGH[5]; HealSize = (1768+healMod30)*shMod end
        end
    -- In combat, unhealthy target - use Flash Heal
    elseif not forceMaxHPS then
        if Health < QuickHealVariables.RatioFull then
            SpellID = SpellIDsFH[1]; HealSize = (225+healMod15)*shMod
            if healneed > (297+healMod15)*k*shMod and ManaLeft >= 155 and maxRankFH >= 2 and downRankFH >= 2 and SpellIDsFH[2] then SpellID = SpellIDsFH[2]; HealSize = (297+healMod15)*shMod end
            if healneed > (319+healMod15)*k*shMod and ManaLeft >= 185 and maxRankFH >= 3 and downRankFH >= 3 and SpellIDsFH[3] then SpellID = SpellIDsFH[3]; HealSize = (319+healMod15)*shMod end
            if healneed > (387+healMod15)*k*shMod and ManaLeft >= 215 and maxRankFH >= 4 and downRankFH >= 4 and SpellIDsFH[4] then SpellID = SpellIDsFH[4]; HealSize = (387+healMod15)*shMod end
            if healneed > (498+healMod15)*k*shMod and ManaLeft >= 265 and maxRankFH >= 5 and downRankFH >= 5 and SpellIDsFH[5] then SpellID = SpellIDsFH[5]; HealSize = (498+healMod15)*shMod end
            if healneed > (618+healMod15)*k*shMod and ManaLeft >= 315 and maxRankFH >= 6 and downRankFH >= 6 and SpellIDsFH[6] then SpellID = SpellIDsFH[6]; HealSize = (618+healMod15)*shMod end
            if healneed > (769+healMod15)*k*shMod and ManaLeft >= 380 and maxRankFH >= 7 and downRankFH >= 7 and SpellIDsFH[7] then SpellID = SpellIDsFH[7]; HealSize = (769+healMod15)*shMod end
        end
    -- Force max HPS - use highest Flash Heal
    else
        if ManaLeft >= 125 and maxRankFH >= 1 and downRankFH >= 1 and SpellIDsFH[1] then SpellID = SpellIDsFH[1]; HealSize = (225+healMod15)*shMod end
        if ManaLeft >= 155 and maxRankFH >= 2 and downRankFH >= 2 and SpellIDsFH[2] then SpellID = SpellIDsFH[2]; HealSize = (297+healMod15)*shMod end
        if ManaLeft >= 185 and maxRankFH >= 3 and downRankFH >= 3 and SpellIDsFH[3] then SpellID = SpellIDsFH[3]; HealSize = (319+healMod15)*shMod end
        if ManaLeft >= 215 and maxRankFH >= 4 and downRankFH >= 4 and SpellIDsFH[4] then SpellID = SpellIDsFH[4]; HealSize = (387+healMod15)*shMod end
        if ManaLeft >= 265 and maxRankFH >= 5 and downRankFH >= 5 and SpellIDsFH[5] then SpellID = SpellIDsFH[5]; HealSize = (498+healMod15)*shMod end
        if ManaLeft >= 315 and maxRankFH >= 6 and downRankFH >= 6 and SpellIDsFH[6] then SpellID = SpellIDsFH[6]; HealSize = (618+healMod15)*shMod end
        if ManaLeft >= 380 and maxRankFH >= 7 and downRankFH >= 7 and SpellIDsFH[7] then SpellID = SpellIDsFH[7]; HealSize = (769+healMod15)*shMod end
    end

    return SpellID, HealSize * HDB
end

-- NoTarget wrapper for backwards compatibility
function QuickHeal_Priest_FindHealSpellToUseNoTarget(maxhealth, healDeficit, healType, multiplier, forceMaxHPS, forceMaxRank, hdb, incombat)
    return QuickHeal_Priest_FindHealSpellToUse(nil, healType, multiplier, forceMaxHPS, maxhealth, healDeficit, hdb, incombat)
end

-- Unified HoT spell selection (Renew)
function QuickHeal_Priest_FindHoTSpellToUse(target, healType, forceMaxRank, maxhealth, healDeficit, hdb, incombat)
    local SpellID = nil
    local HealSize = 0

    -- Get health info
    local healneed, Health, HDB
    if target then
        healneed, Health, HDB = QuickHeal_GetTargetHealth(target, nil, nil, 1, nil)
        incombat = UnitAffectingCombat('player') or UnitAffectingCombat(target)
    else
        healneed, Health, HDB = QuickHeal_GetTargetHealth(nil, maxhealth, healDeficit, 1, hdb)
        incombat = UnitAffectingCombat('player') or incombat
    end

    -- Get modifiers
    local mods = GetPriestModifiers()
    local ManaLeft = UnitMana('player')

    -- Check buffs
    incombat, ManaLeft, healneed = CheckPriestBuffs(target, incombat, ManaLeft, healneed)

    -- Get Renew spell IDs
    local SpellIDsR = QuickHeal_GetSpellIDs(QUICKHEAL_SPELL_RENEW)
    local maxRankR = table.getn(SpellIDsR)

    local k, K = QuickHeal_GetCombatMultipliers(incombat)
    local shMod = mods.shMod
    local healMod30 = mods.hotMod30

    if healType == "hot" then
        if not forceMaxRank then
            -- Select rank based on healneed
            SpellID = SpellIDsR[1]; HealSize = (45+healMod30)*shMod
            if healneed > (100+healMod30)*k*shMod and ManaLeft >= 65  and maxRankR >= 2  and SpellIDsR[2]  then SpellID = SpellIDsR[2];  HealSize = (100+healMod30)*shMod end
            if healneed > (175+healMod30)*k*shMod and ManaLeft >= 105 and maxRankR >= 3  and SpellIDsR[3]  then SpellID = SpellIDsR[3];  HealSize = (175+healMod30)*shMod end
            if healneed > (245+healMod30)*k*shMod and ManaLeft >= 140 and maxRankR >= 4  and SpellIDsR[4]  then SpellID = SpellIDsR[4];  HealSize = (245+healMod30)*shMod end
            if healneed > (270+healMod30)*k*shMod and ManaLeft >= 170 and maxRankR >= 5  and SpellIDsR[5]  then SpellID = SpellIDsR[5];  HealSize = (270+healMod30)*shMod end
            if healneed > (340+healMod30)*k*shMod and ManaLeft >= 205 and maxRankR >= 6  and SpellIDsR[6]  then SpellID = SpellIDsR[6];  HealSize = (340+healMod30)*shMod end
            if healneed > (435+healMod30)*k*shMod and ManaLeft >= 250 and maxRankR >= 7  and SpellIDsR[7]  then SpellID = SpellIDsR[7];  HealSize = (435+healMod30)*shMod end
            if healneed > (555+healMod30)*k*shMod and ManaLeft >= 305 and maxRankR >= 8  and SpellIDsR[8]  then SpellID = SpellIDsR[8];  HealSize = (555+healMod30)*shMod end
            if healneed > (690+healMod30)*k*shMod and ManaLeft >= 365 and maxRankR >= 9  and SpellIDsR[9]  then SpellID = SpellIDsR[9];  HealSize = (690+healMod30)*shMod end
            if healneed > (825+healMod30)*k*shMod and ManaLeft >= 410 and maxRankR >= 10 and SpellIDsR[10] then SpellID = SpellIDsR[10]; HealSize = (825+healMod30)*shMod end
        else
            -- Force max rank
            if maxRankR >= 1  and SpellIDsR[1]  then SpellID = SpellIDsR[1];  HealSize = (45+healMod30)*shMod end
            if maxRankR >= 2  and SpellIDsR[2]  then SpellID = SpellIDsR[2];  HealSize = (100+healMod30)*shMod end
            if maxRankR >= 3  and SpellIDsR[3]  then SpellID = SpellIDsR[3];  HealSize = (175+healMod30)*shMod end
            if maxRankR >= 4  and SpellIDsR[4]  then SpellID = SpellIDsR[4];  HealSize = (245+healMod30)*shMod end
            if maxRankR >= 5  and SpellIDsR[5]  then SpellID = SpellIDsR[5];  HealSize = (270+healMod30)*shMod end
            if maxRankR >= 6  and SpellIDsR[6]  then SpellID = SpellIDsR[6];  HealSize = (340+healMod30)*shMod end
            if maxRankR >= 7  and SpellIDsR[7]  then SpellID = SpellIDsR[7];  HealSize = (435+healMod30)*shMod end
            if maxRankR >= 8  and SpellIDsR[8]  then SpellID = SpellIDsR[8];  HealSize = (555+healMod30)*shMod end
            if maxRankR >= 9  and SpellIDsR[9]  then SpellID = SpellIDsR[9];  HealSize = (690+healMod30)*shMod end
            if maxRankR >= 10 and SpellIDsR[10] then SpellID = SpellIDsR[10]; HealSize = (825+healMod30)*shMod end
        end
    elseif healType == "channel" then
        -- Channel heal type uses direct heals
        return QuickHeal_Priest_FindHealSpellToUse(target, healType, 1, false, maxhealth, healDeficit, hdb, incombat)
    end

    return SpellID, HealSize * HDB
end

-- NoTarget wrapper for backwards compatibility
function QuickHeal_Priest_FindHoTSpellToUseNoTarget(maxhealth, healDeficit, healType, multiplier, forceMaxHPS, forceMaxRank, hdb, incombat)
    return QuickHeal_Priest_FindHoTSpellToUse(nil, healType, forceMaxRank, maxhealth, healDeficit, hdb, incombat)
end

-- Utility function to get spell info by healneed
function QuickHealSpellID(healneed)
    local SpellID, HealSize = QuickHeal_Priest_FindHealSpellToUse(nil, "channel", 1, false, 10000, healneed, 1, false)

    if not SpellID then
        return nil, nil
    end

    local SpellName, SpellRank = GetSpellName(SpellID, BOOKTYPE_SPELL)
    if SpellRank == "" then SpellRank = nil end

    local rankNum = SpellRank and string.gsub(SpellRank, "%a+", "") or "1"
    return SpellName, rankNum
end

-- Command handler
function QuickHeal_Command_Priest(msg)
    local _, _, arg1, arg2, arg3 = string.find(msg, "%s?(%w+)%s?(%w+)%s?(%w+)")

    -- Match 3 arguments
    if arg1 and arg2 and arg3 then
        if arg1 == "player" or arg1 == "target" or arg1 == "targettarget" or arg1 == "party" or arg1 == "subgroup" or arg1 == "mt" or arg1 == "nonmt" then
            if arg2 == "heal" and arg3 == "max" then
                QuickHeal(arg1, nil, nil, true)
                return
            end
            if arg2 == "hot" and arg3 == "fh" then
                QuickHOT(arg1, nil, nil, true, true)
                return
            end
            if arg2 == "hot" and arg3 == "max" then
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
        if arg4 == "hot" and arg5 == "max" then
            QuickHOT(nil, nil, nil, true, false)
            return
        end
        if arg4 == "hot" and arg5 == "fh" then
            QuickHOT(nil, nil, nil, true, true)
            return
        end
        if arg4 == "player" or arg4 == "target" or arg4 == "targettarget" or arg4 == "party" or arg4 == "subgroup" or arg4 == "mt" or arg4 == "nonmt" then
            if arg5 == "hot" then
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
    if cmd == "hot" then
        QuickHOT()
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
    writeLine("== QUICKHEAL USAGE : PRIEST ==")
    writeLine("/qh cfg - Opens up the configuration panel.")
    writeLine("/qh toggle - Switches between High HPS and Normal HPS.")
    writeLine("/qh downrank | dr - Opens the slider to limit QuickHeal to constrain healing to lower ranks.")
    writeLine("/qh tanklist | tl - Toggles display of the main tank list UI.")
    writeLine("/qh [mask] [type] [mod] - Heals the party/raid member that most needs it.")
    writeLine(" [mask]: player, target, targettarget, party, mt, nonmt, subgroup")
    writeLine(" [type]: heal (channeled), hot (Renew)")
    writeLine(" [mod]: max (max rank), fh (firehose - max rank, no hp check)")
    writeLine("/qh reset - Reset configuration to default parameters.")
end
