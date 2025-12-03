-- QuickHeal Druid Module (Refactored)
-- Consolidated spell selection with shared helper functions

local function writeLine(s,r,g,b)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(s, r or 1, g or 1, b or 0.5)
    end
end

-- Penalty Factors for low-level spells
local PF = {
    [1] = 0.2875,
    [8] = 0.55,
    [14] = 0.775,
    RG1 = 0.7 * 1.042,  -- Rank 1 of RG (compensates for 0.50 factor that should be 0.48)
    RG2 = 0.925,
}

function QuickHeal_Druid_GetRatioHealthyExplanation()
    local RatioHealthy = QuickHeal_GetRatioHealthy()
    local RatioFull = QuickHealVariables["RatioFull"]

    if RatioHealthy >= RatioFull then
        return QUICKHEAL_SPELL_REGROWTH .. " will always be used in and out of combat, and "  .. QUICKHEAL_SPELL_HEALING_TOUCH .. " will never be used. "
    else
        if RatioHealthy > 0 then
            return QUICKHEAL_SPELL_REGROWTH .. " will be used in combat if the target has less than " .. RatioHealthy*100 .. "% life, and " .. QUICKHEAL_SPELL_HEALING_TOUCH .. " will be used otherwise. "
        else
            return QUICKHEAL_SPELL_REGROWTH .. " will never be used. " .. QUICKHEAL_SPELL_HEALING_TOUCH .. " will always be used in and out of combat. "
        end
    end
end

-- Calculate all Druid-specific modifiers
local function GetDruidModifiers()
    local mods = {}

    -- Equipment healing bonus (cached)
    mods.bonus = QuickHeal_GetEquipmentBonus()

    -- Calculate healing modifiers by cast time
    mods.healMod15 = (1.5/3.5) * mods.bonus
    mods.healMod20 = (2.0/3.5) * mods.bonus
    mods.healMod25 = (2.5/3.5) * mods.bonus
    mods.healMod30 = (3.0/3.5) * mods.bonus
    mods.healMod35 = mods.bonus
    mods.healModRG = (2.0/3.5) * mods.bonus * 0.5  -- DirectHeal/(DirectHeal+HoT) factor

    -- Gift of Nature - Increases healing by 2% per rank
    local gonRank = QuickHeal_GetTalentRank(3, 9)
    mods.gonMod = 1 + 2 * gonRank / 100

    -- Tranquil Spirit - Decreases mana usage by 2% per rank on HT
    local tsRank = QuickHeal_GetTalentRank(3, 10)
    mods.tsMod = 1 - 2 * tsRank / 100

    -- Moonglow - Decrease mana usage by 3% per rank
    local mgRank = QuickHeal_GetTalentRank(1, 13)
    mods.mgMod = 1 - 3 * mgRank / 100

    -- Improved Regrowth - increases Regrowth effect by 5% per rank (crit is 50% bonus)
    local iregRank = QuickHeal_GetTalentRank(3, 14)
    mods.iregMod = 1 + 5 * iregRank / 100

    -- Genesis - Increases Rejuvenation effects by 5% per rank
    local genRank = QuickHeal_GetTalentRank(3, 7)
    mods.genMod = 1 + 5 * genRank / 100

    return mods
end

-- Check for Druid-specific buffs that affect healing
-- Returns: inCombat (adjusted), manaLeft (adjusted), healneed (adjusted), forceHTinCombat
local function CheckDruidBuffs(inCombat, manaLeft, healneed, mods)
    local forceHTinCombat = false

    -- Detect Clearcasting (from Omen of Clarity)
    if QuickHeal_DetectBuff('player', "Spell_Shadow_ManaBurn", 1) then
        QuickHeal_debug("BUFF: Clearcasting (Omen of Clarity)")
        manaLeft = UnitManaMax('player')
        healneed = 10^6
    end

    -- Detect Nature's Swiftness (next nature spell is instant cast)
    if QuickHeal_DetectBuff('player', "Spell_Nature_RavenForm") then
        QuickHeal_debug("BUFF: Nature's Swiftness (out of combat healing forced)")
        forceHTinCombat = true
    end

    -- Detect Hand of Edward the Odd (next spell is instant cast)
    if QuickHeal_DetectBuff('player', "Spell_Holy_SearingLight") then
        QuickHeal_debug("BUFF: Hand of Edward the Odd (out of combat healing forced)")
        inCombat = false
    end

    -- Detect Wushoolay's Charm of Nature (Trinket from Zul'Gurub)
    if QuickHeal_DetectBuff('player', "Spell_Nature_Regenerate") then
        QuickHeal_debug("BUFF: Wushoolay (healing touch forced)")
        forceHTinCombat = true
    end

    return inCombat, manaLeft, healneed, forceHTinCombat
end

-- Unified heal spell selection (works with or without target)
-- target: unit ID or nil (for NoTarget mode)
-- maxhealth, healDeficit, hdb, incombat: used when target is nil
function QuickHeal_Druid_FindHealSpellToUse(target, healType, multiplier, forceMaxHPS, maxhealth, healDeficit, hdb, incombat)
    local SpellID = nil
    local HealSize = 0
    multiplier = multiplier or 1

    local RatioFull = QuickHealVariables["RatioFull"]
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
        incombat = UnitAffectingCombat('player') or UnitAffectingCombat(target)
    else
        if not maxhealth or maxhealth <= 0 then return nil, 0 end
        healneed = healDeficit * multiplier
        Health = healDeficit / maxhealth
        HDB = hdb or 1
        incombat = UnitAffectingCombat('player') or incombat
    end

    debug("Target debuff healing modifier", HDB)
    healneed = healneed / HDB

    -- Return if no target needs healing
    if target and not target then
        return nil, 0
    end

    -- Check for overheal
    if multiplier and multiplier > 1.0 then
        jgpprint(">>> multiplier is " .. multiplier .. " <<<")
    end

    -- Get modifiers
    local mods = GetDruidModifiers()
    local ManaLeft = UnitMana('player')

    -- Check buffs
    local forceHTinCombat
    incombat, ManaLeft, healneed, forceHTinCombat = CheckDruidBuffs(incombat, ManaLeft, healneed, mods)

    -- Detect Nature's Grace for NoTarget mode (affects mana limit)
    if not target and QuickHeal_DetectBuff('player', "Spell_Nature_NaturesBlessing") and
       healneed < ((219 + mods.healMod25 * PF[14]) * mods.gonMod * 2.8) and
       not QuickHeal_DetectBuff('player', "Spell_Nature_Regenerate") then
        ManaLeft = 110 * mods.tsMod * mods.mgMod
    end

    -- Get spell IDs
    local SpellIDsHT = QuickHeal_GetSpellIDs(QUICKHEAL_SPELL_HEALING_TOUCH)
    local SpellIDsRG = QuickHeal_GetSpellIDs(QUICKHEAL_SPELL_REGROWTH)

    local maxRankHT = table.getn(SpellIDsHT)
    local maxRankRG = table.getn(SpellIDsRG)

    debug(string.format("Found HT up to rank %d, RG up to rank %d", maxRankHT, maxRankRG))

    -- Downrank settings
    local downRankFH = QuickHealVariables.DownrankValueFH or 0
    local downRankNH = QuickHealVariables.DownrankValueNH or 0

    -- Combat multipliers
    local k, K = QuickHeal_GetCombatMultipliers(incombat)

    local TargetIsHealthy = Health >= RatioHealthy
    local gonMod = mods.gonMod
    local tsMod = mods.tsMod
    local mgMod = mods.mgMod
    local iregMod = mods.iregMod
    local healMod15, healMod20, healMod25, healMod30, healMod35 = mods.healMod15, mods.healMod20, mods.healMod25, mods.healMod30, mods.healMod35
    local healModRG = mods.healModRG

    if TargetIsHealthy then
        debug("Target is healthy", Health)
    end

    -- Use Healing Touch when target is healthy, Regrowth unavailable, or forceHTinCombat
    if TargetIsHealthy or maxRankRG < 1 or forceHTinCombat or (not target and not forceMaxHPS) then
        debug("Using Healing Touch")
        if Health < RatioFull then
            SpellID = SpellIDsHT[1]; HealSize = (44 + healMod15 * PF[1]) * gonMod
            if healneed > (100 + healMod20 * PF[8]) * gonMod * k  and ManaLeft >= 55 * tsMod * mgMod  and maxRankHT >= 2  and downRankNH >= 2  and SpellIDsHT[2]  then SpellID = SpellIDsHT[2];  HealSize = (100 + healMod20 * PF[8]) * gonMod end
            if healneed > (219 + healMod25 * PF[14]) * gonMod * K and ManaLeft >= 110 * tsMod * mgMod and maxRankHT >= 3  and downRankNH >= 3  and SpellIDsHT[3]  then SpellID = SpellIDsHT[3];  HealSize = (219 + healMod25 * PF[14]) * gonMod end
            if healneed > (404 + healMod30) * gonMod * K          and ManaLeft >= 185 * tsMod * mgMod and maxRankHT >= 4  and downRankNH >= 4  and SpellIDsHT[4]  then SpellID = SpellIDsHT[4];  HealSize = (404 + healMod30) * gonMod end
            if healneed > (633 + healMod35) * gonMod * K          and ManaLeft >= 270 * tsMod * mgMod and maxRankHT >= 5  and downRankNH >= 5  and SpellIDsHT[5]  then SpellID = SpellIDsHT[5];  HealSize = (633 + healMod35) * gonMod end
            if healneed > (818 + healMod35) * gonMod * K          and ManaLeft >= 335 * tsMod * mgMod and maxRankHT >= 6  and downRankNH >= 6  and SpellIDsHT[6]  then SpellID = SpellIDsHT[6];  HealSize = (818 + healMod35) * gonMod end
            if healneed > (1028 + healMod35) * gonMod * K         and ManaLeft >= 405 * tsMod * mgMod and maxRankHT >= 7  and downRankNH >= 7  and SpellIDsHT[7]  then SpellID = SpellIDsHT[7];  HealSize = (1028 + healMod35) * gonMod end
            if healneed > (1313 + healMod35) * gonMod * K         and ManaLeft >= 495 * tsMod * mgMod and maxRankHT >= 8  and downRankNH >= 8  and SpellIDsHT[8]  then SpellID = SpellIDsHT[8];  HealSize = (1313 + healMod35) * gonMod end
            if healneed > (1656 + healMod35) * gonMod * K         and ManaLeft >= 600 * tsMod * mgMod and maxRankHT >= 9  and downRankNH >= 9  and SpellIDsHT[9]  then SpellID = SpellIDsHT[9];  HealSize = (1656 + healMod35) * gonMod end
            if healneed > (2060 + healMod35) * gonMod * K         and ManaLeft >= 720 * tsMod * mgMod and maxRankHT >= 10 and downRankNH >= 10 and SpellIDsHT[10] then SpellID = SpellIDsHT[10]; HealSize = (2060 + healMod35) * gonMod end
            if healneed > (2472 + healMod35) * gonMod * K         and ManaLeft >= 800 * tsMod * mgMod and maxRankHT >= 11 and downRankNH >= 11 and SpellIDsHT[11] then SpellID = SpellIDsHT[11]; HealSize = (2472 + healMod35) * gonMod end
        end
    else
        -- In combat, unhealthy target, has Regrowth - use Regrowth
        debug("In combat and target unhealthy and Regrowth available, will use Regrowth")
        if Health < RatioFull then
            SpellID = SpellIDsRG[1]; HealSize = (91 + healModRG * PF.RG1) * iregMod * gonMod
            if healneed > (176 + healModRG * PF.RG2) * iregMod * gonMod * k and ManaLeft >= 164 * tsMod * mgMod and maxRankRG >= 2 and downRankFH >= 2 and SpellIDsRG[2] then SpellID = SpellIDsRG[2]; HealSize = (176 + healModRG * PF.RG2) * iregMod * gonMod end
            if healneed > (257 + healModRG) * iregMod * gonMod * k         and ManaLeft >= 224 * tsMod * mgMod and maxRankRG >= 3 and downRankFH >= 3 and SpellIDsRG[3] then SpellID = SpellIDsRG[3]; HealSize = (257 + healModRG) * iregMod * gonMod end
            if healneed > (339 + healModRG) * iregMod * gonMod * k         and ManaLeft >= 280 * tsMod * mgMod and maxRankRG >= 4 and downRankFH >= 4 and SpellIDsRG[4] then SpellID = SpellIDsRG[4]; HealSize = (339 + healModRG) * iregMod * gonMod end
            if healneed > (431 + healModRG) * iregMod * gonMod * k         and ManaLeft >= 336 * tsMod * mgMod and maxRankRG >= 5 and downRankFH >= 5 and SpellIDsRG[5] then SpellID = SpellIDsRG[5]; HealSize = (431 + healModRG) * iregMod * gonMod end
            if healneed > (543 + healModRG) * iregMod * gonMod * k         and ManaLeft >= 408 * tsMod * mgMod and maxRankRG >= 6 and downRankFH >= 6 and SpellIDsRG[6] then SpellID = SpellIDsRG[6]; HealSize = (543 + healModRG) * iregMod * gonMod end
            if healneed > (686 + healModRG) * iregMod * gonMod * k         and ManaLeft >= 492 * tsMod * mgMod and maxRankRG >= 7 and downRankFH >= 7 and SpellIDsRG[7] then SpellID = SpellIDsRG[7]; HealSize = (686 + healModRG) * iregMod * gonMod end
            if healneed > (857 + healModRG) * iregMod * gonMod * k         and ManaLeft >= 592 * tsMod * mgMod and maxRankRG >= 8 and downRankFH >= 8 and SpellIDsRG[8] then SpellID = SpellIDsRG[8]; HealSize = (857 + healModRG) * iregMod * gonMod end
            if healneed > (1061 + healModRG) * iregMod * gonMod * k        and ManaLeft >= 704 * tsMod * mgMod and maxRankRG >= 9 and downRankFH >= 9 and SpellIDsRG[9] then SpellID = SpellIDsRG[9]; HealSize = (1061 + healModRG) * iregMod * gonMod end
        end
    end

    return SpellID, HealSize * HDB
end

-- NoTarget wrapper for backwards compatibility
function QuickHeal_Druid_FindHealSpellToUseNoTarget(maxhealth, healDeficit, healType, multiplier, forceMaxHPS, forceMaxRank, hdb, incombat)
    return QuickHeal_Druid_FindHealSpellToUse(nil, healType, multiplier, forceMaxHPS, maxhealth, healDeficit, hdb, incombat)
end

-- Unified HoT spell selection (Rejuvenation)
function QuickHeal_Druid_FindHoTSpellToUse(target, healType, forceMaxRank, maxhealth, healDeficit, hdb, incombat)
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
        incombat = UnitAffectingCombat('player') or UnitAffectingCombat(target)
    else
        if not maxhealth or maxhealth <= 0 then return nil, 0 end
        healneed = (healDeficit or 0) * (1)  -- multiplier not used for HoT
        Health = (healDeficit or 0) / maxhealth
        HDB = hdb or 1
        incombat = UnitAffectingCombat('player') or incombat
    end

    debug("Target debuff healing modifier", HDB)
    healneed = healneed / HDB

    -- Return if no target
    if target == nil and maxhealth == nil then
        return nil, 0
    end

    -- Get modifiers
    local mods = GetDruidModifiers()
    local ManaLeft = UnitMana('player')

    -- Detect Clearcasting (from Omen of Clarity)
    if QuickHeal_DetectBuff('player', "Spell_Shadow_ManaBurn", 1) then
        debug("BUFF: Clearcasting (Omen of Clarity)")
        ManaLeft = UnitManaMax('player')
        healneed = 10^6
    end

    -- Get spell IDs
    local SpellIDsRJ = QuickHeal_GetSpellIDs(QUICKHEAL_SPELL_REJUVENATION)
    local maxRankRJ = table.getn(SpellIDsRJ)

    debug(string.format("Found RJ up to rank %d", maxRankRJ))

    -- Combat multipliers
    local k, K = QuickHeal_GetCombatMultipliers(incombat)

    local gonMod = mods.gonMod
    local mgMod = mods.mgMod
    local genMod = mods.genMod
    local healMod15 = mods.healMod15

    local TargetIsHealthy = Health >= RatioHealthy
    if TargetIsHealthy then
        debug("Target is healthy", Health)
    end

    if healType == "hot" then
        if not forceMaxRank then
            -- Select rank based on healneed
            SpellID = SpellIDsRJ[1]; HealSize = (36 + healMod15) * genMod * gonMod
            if healneed > (60 + healMod15) * genMod * gonMod * k  and ManaLeft >= 40 * mgMod  and maxRankRJ >= 2  and SpellIDsRJ[2]  then SpellID = SpellIDsRJ[2];  HealSize = (60 + healMod15) * genMod * gonMod end
            if healneed > (120 + healMod15) * genMod * gonMod * k and ManaLeft >= 75 * mgMod  and maxRankRJ >= 3  and SpellIDsRJ[3]  then SpellID = SpellIDsRJ[3];  HealSize = (120 + healMod15) * genMod * gonMod end
            if healneed > (180 + healMod15) * genMod * gonMod * k and ManaLeft >= 105 * mgMod and maxRankRJ >= 4  and SpellIDsRJ[4]  then SpellID = SpellIDsRJ[4];  HealSize = (180 + healMod15) * genMod * gonMod end
            if healneed > (246 + healMod15) * genMod * gonMod * k and ManaLeft >= 135 * mgMod and maxRankRJ >= 5  and SpellIDsRJ[5]  then SpellID = SpellIDsRJ[5];  HealSize = (246 + healMod15) * genMod * gonMod end
            if healneed > (306 + healMod15) * genMod * gonMod * k and ManaLeft >= 160 * mgMod and maxRankRJ >= 6  and SpellIDsRJ[6]  then SpellID = SpellIDsRJ[6];  HealSize = (306 + healMod15) * genMod * gonMod end
            if healneed > (390 + healMod15) * genMod * gonMod * k and ManaLeft >= 195 * mgMod and maxRankRJ >= 7  and SpellIDsRJ[7]  then SpellID = SpellIDsRJ[7];  HealSize = (390 + healMod15) * genMod * gonMod end
            if healneed > (492 + healMod15) * genMod * gonMod * k and ManaLeft >= 235 * mgMod and maxRankRJ >= 8  and SpellIDsRJ[8]  then SpellID = SpellIDsRJ[8];  HealSize = (492 + healMod15) * genMod * gonMod end
            if healneed > (612 + healMod15) * genMod * gonMod * k and ManaLeft >= 280 * mgMod and maxRankRJ >= 9  and SpellIDsRJ[9]  then SpellID = SpellIDsRJ[9];  HealSize = (612 + healMod15) * genMod * gonMod end
            if healneed > (756 + healMod15) * genMod * gonMod * k and ManaLeft >= 335 * mgMod and maxRankRJ >= 10 and SpellIDsRJ[10] then SpellID = SpellIDsRJ[10]; HealSize = (756 + healMod15) * genMod * gonMod end
            if healneed > (888 + healMod15) * genMod * gonMod * k and ManaLeft >= 360 * mgMod and maxRankRJ >= 11 and SpellIDsRJ[11] then SpellID = SpellIDsRJ[11]; HealSize = (888 + healMod15) * genMod * gonMod end
        else
            -- Force max rank
            if maxRankRJ >= 1  and SpellIDsRJ[1]  then SpellID = SpellIDsRJ[1];  HealSize = (36 + healMod15) * genMod * gonMod end
            if maxRankRJ >= 2  and SpellIDsRJ[2]  then SpellID = SpellIDsRJ[2];  HealSize = (60 + healMod15) * genMod * gonMod end
            if maxRankRJ >= 3  and SpellIDsRJ[3]  then SpellID = SpellIDsRJ[3];  HealSize = (120 + healMod15) * genMod * gonMod end
            if maxRankRJ >= 4  and SpellIDsRJ[4]  then SpellID = SpellIDsRJ[4];  HealSize = (180 + healMod15) * genMod * gonMod end
            if maxRankRJ >= 5  and SpellIDsRJ[5]  then SpellID = SpellIDsRJ[5];  HealSize = (246 + healMod15) * genMod * gonMod end
            if maxRankRJ >= 6  and SpellIDsRJ[6]  then SpellID = SpellIDsRJ[6];  HealSize = (306 + healMod15) * genMod * gonMod end
            if maxRankRJ >= 7  and SpellIDsRJ[7]  then SpellID = SpellIDsRJ[7];  HealSize = (390 + healMod15) * genMod * gonMod end
            if maxRankRJ >= 8  and SpellIDsRJ[8]  then SpellID = SpellIDsRJ[8];  HealSize = (492 + healMod15) * genMod * gonMod end
            if maxRankRJ >= 9  and SpellIDsRJ[9]  then SpellID = SpellIDsRJ[9];  HealSize = (612 + healMod15) * genMod * gonMod end
            if maxRankRJ >= 10 and SpellIDsRJ[10] then SpellID = SpellIDsRJ[10]; HealSize = (756 + healMod15) * genMod * gonMod end
            if maxRankRJ >= 11 and SpellIDsRJ[11] then SpellID = SpellIDsRJ[11]; HealSize = (888 + healMod15) * genMod * gonMod end
        end
    end

    return SpellID, HealSize * HDB
end

-- NoTarget wrapper for backwards compatibility
function QuickHeal_Druid_FindHoTSpellToUseNoTarget(maxhealth, healDeficit, healType, multiplier, forceMaxHPS, forceMaxRank, hdb, incombat)
    return QuickHeal_Druid_FindHoTSpellToUse(nil, healType, forceMaxRank, maxhealth, healDeficit, hdb, incombat)
end

-- Command handler
function QuickHeal_Command_Druid(msg)
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
    writeLine("== QUICKHEAL USAGE : DRUID ==")
    writeLine("/qh cfg - Opens up the configuration panel.")
    writeLine("/qh toggle - Switches between High HPS and Normal HPS.")
    writeLine("/qh downrank | dr - Opens the slider to limit QuickHeal to constrain healing to lower ranks.")
    writeLine("/qh tanklist | tl - Toggles display of the main tank list UI.")
    writeLine("/qh [mask] [type] [mod] - Heals the party/raid member that most needs it.")
    writeLine(" [mask]: player, target, targettarget, party, mt, nonmt, subgroup")
    writeLine(" [type]: heal (Healing Touch), hot (Rejuvenation)")
    writeLine(" [mod]: max (max rank), fh (firehose - max rank, no hp check)")
    writeLine("/qh reset - Reset configuration to default parameters.")
end
