-- QuickHeal Shaman Module (Refactored)
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
    [12] = 0.7,
    [18] = 0.925,
}

function QuickHeal_Shaman_GetRatioHealthyExplanation()
    local RatioHealthy = QuickHeal_GetRatioHealthy()
    local RatioFull = QuickHealVariables["RatioFull"]

    if RatioHealthy >= RatioFull then
        return QUICKHEAL_SPELL_HEALING_WAVE .. " will never be used in combat. "
    else
        if RatioHealthy > 0 then
            return QUICKHEAL_SPELL_HEALING_WAVE .. " will only be used in combat if the target has more than " .. RatioHealthy*100 .. "% life, and only if the healing done is greater than the greatest " .. QUICKHEAL_SPELL_LESSER_HEALING_WAVE .. " available. "
        else
            return QUICKHEAL_SPELL_HEALING_WAVE .. " will only be used in combat if the healing done is greater than the greatest " .. QUICKHEAL_SPELL_LESSER_HEALING_WAVE .. " available. "
        end
    end
end

-- Calculate all Shaman-specific modifiers
local function GetShamanModifiers()
    local mods = {}

    -- Equipment healing bonus (cached)
    mods.bonus = QuickHeal_GetEquipmentBonus()

    -- Calculate healing modifiers by cast time
    mods.healModLHW = (1.5/3.5) * mods.bonus
    mods.healModCH = 0.6142 * mods.bonus  -- Turtle WoW 1.18 coefficient
    mods.healMod15 = (1.5/3.5) * mods.bonus
    mods.healMod20 = (2.0/3.5) * mods.bonus
    mods.healMod25 = (2.5/3.5) * mods.bonus
    mods.healMod30 = (3.0/3.5) * mods.bonus

    -- Tidal Focus - Decreases mana usage by 1% per rank
    local tfRank = QuickHeal_GetTalentRank(3, 2)
    mods.tfMod = 1 - tfRank / 100

    return mods
end

-- Check for Shaman-specific buffs that affect healing
-- Returns: inCombat (adjusted)
local function CheckShamanBuffs(inCombat)
    -- Detect Nature's Swiftness (next nature spell is instant cast)
    if QuickHeal_DetectBuff('player', "Spell_Nature_RavenForm") then
        QuickHeal_debug("BUFF: Nature's Swiftness (out of combat healing forced)")
        inCombat = false
    end

    -- Detect Hand of Edward the Odd (next spell is instant cast)
    if QuickHeal_DetectBuff('player', "Spell_Holy_SearingLight") then
        QuickHeal_debug("BUFF: Hand of Edward the Odd (out of combat healing forced)")
        inCombat = false
    end

    return inCombat
end

-- Get Healing Way modifier from target buff
local function GetHealingWayMod(target)
    local hwMod = QuickHeal_DetectBuff(target, "Spell_Nature_HealingWay")
    if hwMod then
        hwMod = 1 + 0.06 * hwMod
    else
        hwMod = 1
    end
    QuickHeal_debug("Healing Way healing modifier", hwMod)
    return hwMod
end

-- Chain Heal spell selection
function QuickHeal_Shaman_FindChainHealSpellToUse(target, healType, multiplier, forceMaxRank)
    local SpellID = nil
    local HealSize = 0
    multiplier = multiplier or 1

    local RatioFull = QuickHealVariables["RatioFull"]
    local RatioHealthy = QuickHeal_GetRatioHealthy()
    local debug = QuickHeal_debug

    -- Return if no target
    if not target then
        return nil, 0
    end

    -- Get health info
    local healneed, Health, HDB
    if QuickHeal_UnitHasHealthInfo(target) then
        healneed = UnitHealthMax(target) - UnitHealth(target)
        Health = UnitHealth(target) / UnitHealthMax(target)
    else
        healneed = QuickHeal_EstimateUnitHealNeed(target, true)
        Health = UnitHealth(target) / 100
    end

    HDB = QuickHeal_GetHealModifier(target)
    debug("Target debuff healing modifier", HDB)
    healneed = healneed / HDB

    -- Get modifiers
    local mods = GetShamanModifiers()
    local ManaLeft = UnitMana('player')

    -- Get Healing Way modifier
    local hwMod = GetHealingWayMod(target)

    -- Get Chain Heal spell IDs
    local SpellIDsCH = QuickHeal_GetSpellIDs(QUICKHEAL_SPELL_CHAIN_HEAL)
    local maxRankCH = table.getn(SpellIDsCH)

    debug(string.format("Found CH up to rank %d", maxRankCH))

    local tfMod = mods.tfMod
    local healModCH = mods.healModCH
    local healMod25 = mods.healMod25
    local K = 0.8  -- Combat compensation for slow spells

    if not forceMaxRank then
        SpellID = SpellIDsCH[1]; HealSize = 356 + healMod25
        if healneed > (898 + healModCH) * hwMod * K  and ManaLeft >= 315 * tfMod and maxRankCH >= 2 and SpellIDsCH[2] then SpellID = SpellIDsCH[2]; HealSize = (449 + healModCH) * hwMod end
        if healneed > (1213 + healModCH) * hwMod * K and ManaLeft >= 405 * tfMod and maxRankCH >= 3 and SpellIDsCH[3] then SpellID = SpellIDsCH[3]; HealSize = (607 + healModCH) * hwMod end
    else
        SpellID = SpellIDsCH[3]; HealSize = 607 * hwMod + healMod25
    end

    debug(string.format("SpellID: %s  HealSize: %s", tostring(SpellID), tostring(HealSize)))
    return SpellID, HealSize * HDB
end

-- Unified heal spell selection (works with or without target)
function QuickHeal_Shaman_FindHealSpellToUse(target, healType, multiplier, forceMaxHPS, maxhealth, healDeficit, hdb, incombat)
    local SpellID = nil
    local HealSize = 0
    multiplier = multiplier or 1

    local RatioFull = QuickHealVariables["RatioFull"]
    local RatioHealthy = QuickHeal_GetRatioHealthy()
    local debug = QuickHeal_debug

    -- Get health info
    local healneed, Health, HDB, hwMod
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
        hwMod = GetHealingWayMod(target)
    else
        if not maxhealth or maxhealth <= 0 then return nil, 0 end
        healneed = healDeficit * multiplier
        Health = healDeficit / maxhealth
        HDB = hdb or 1
        incombat = UnitAffectingCombat('player') or incombat
        hwMod = 1  -- Can't detect Healing Way without target
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
    local mods = GetShamanModifiers()
    local ManaLeft = UnitMana('player')

    -- Check buffs
    incombat = CheckShamanBuffs(incombat)

    -- Get spell IDs
    local SpellIDsHW = QuickHeal_GetSpellIDs(QUICKHEAL_SPELL_HEALING_WAVE)
    local SpellIDsLHW = QuickHeal_GetSpellIDs(QUICKHEAL_SPELL_LESSER_HEALING_WAVE)

    local maxRankHW = table.getn(SpellIDsHW)
    local maxRankLHW = table.getn(SpellIDsLHW)
    local NoLHW = maxRankLHW < 1

    debug(string.format("Found HW up to rank %d, and found LHW up to rank %d", maxRankHW, maxRankLHW))

    -- Downrank settings
    local downRankFH = QuickHealVariables.DownrankValueFH or 0
    local downRankNH = QuickHealVariables.DownrankValueNH or 0

    local tfMod = mods.tfMod
    local healModLHW = mods.healModLHW
    local healMod15, healMod20, healMod25, healMod30 = mods.healMod15, mods.healMod20, mods.healMod25, mods.healMod30

    local TargetIsHealthy = Health >= RatioHealthy
    if TargetIsHealthy then
        debug("Target is healthy", Health)
    end

    -- Combat multipliers
    local k = 0.9  -- Fast spells (LHW)
    local K = 0.8  -- Slow spells (HW)

    if incombat or forceMaxHPS then
        -- In combat: prefer LHW unless target is healthy
        debug("In combat, will prefer LHW")
        if Health < RatioFull or not target then
            -- Default to LHW or HW
            if maxRankLHW >= 1 and SpellIDsLHW[1] then
                SpellID = SpellIDsLHW[1]; HealSize = (174 + healModLHW) * hwMod
            else
                SpellID = SpellIDsHW[1]; HealSize = (39 + healMod15 * PF[1]) * hwMod
            end
            if healneed > (71 + healMod20 * PF[6]) * hwMod * k   and ManaLeft >= 45 * tfMod  and maxRankHW >= 2  and downRankNH >= 2 and SpellIDsHW[2]  then SpellID = SpellIDsHW[2];  HealSize = (71 + healMod20 * PF[6]) * hwMod end
            if healneed > (142 + healMod25 * PF[12]) * hwMod * K and ManaLeft >= 80 * tfMod  and maxRankHW >= 3  and downRankNH >= 3 and SpellIDsHW[3]  then SpellID = SpellIDsHW[3];  HealSize = (142 + healMod25 * PF[12]) * hwMod end
            if healneed > (174 + healModLHW) * hwMod * k         and ManaLeft >= 105 * tfMod and maxRankLHW >= 1 and downRankFH >= 1 and SpellIDsLHW[1] then SpellID = SpellIDsLHW[1]; HealSize = (174 + healModLHW) * hwMod end
            if healneed > (264 + healModLHW) * hwMod * k         and ManaLeft >= 145 * tfMod and maxRankLHW >= 2 and downRankFH >= 2 and SpellIDsLHW[2] then SpellID = SpellIDsLHW[2]; HealSize = (264 + healModLHW) * hwMod end
            if healneed > (292 + healMod30 * PF[18]) * hwMod * K and ManaLeft >= 155 * tfMod and maxRankHW >= 4  and downRankNH >= 4 and (TargetIsHealthy and maxRankLHW <= 2 and downRankFH <= 2 or NoLHW) and SpellIDsHW[4] then SpellID = SpellIDsHW[4]; HealSize = (292 + healMod30 * PF[18]) * hwMod end
            if healneed > (359 + healModLHW) * hwMod * k         and ManaLeft >= 185 * tfMod and maxRankLHW >= 3 and downRankFH >= 3 and SpellIDsLHW[3] then SpellID = SpellIDsLHW[3]; HealSize = (359 + healModLHW) * hwMod end
            if healneed > (408 + healMod30) * hwMod * K          and ManaLeft >= 200 * tfMod and maxRankHW >= 5  and downRankNH >= 5 and (TargetIsHealthy and maxRankLHW <= 3 and downRankFH <= 3 or NoLHW) and SpellIDsHW[5] then SpellID = SpellIDsHW[5]; HealSize = (408 + healMod30) * hwMod end
            if healneed > (486 + healModLHW) * hwMod * k         and ManaLeft >= 235 * tfMod and maxRankLHW >= 4 and downRankFH >= 4 and SpellIDsLHW[4] then SpellID = SpellIDsLHW[4]; HealSize = (486 + healModLHW) * hwMod end
            if healneed > (579 + healMod30) * hwMod * K          and ManaLeft >= 265 * tfMod and maxRankHW >= 6  and downRankNH >= 6 and (TargetIsHealthy and maxRankLHW <= 4 and downRankFH <= 4 or NoLHW) and SpellIDsHW[6] then SpellID = SpellIDsHW[6]; HealSize = (579 + healMod30) * hwMod end
            if healneed > (668 + healModLHW) * hwMod * k         and ManaLeft >= 305 * tfMod and maxRankLHW >= 5 and downRankFH >= 5 and SpellIDsLHW[5] then SpellID = SpellIDsLHW[5]; HealSize = (668 + healModLHW) * hwMod end
            if healneed > (797 + healMod30) * hwMod * K          and ManaLeft >= 340 * tfMod and maxRankHW >= 7  and downRankNH >= 7 and (TargetIsHealthy and maxRankLHW <= 5 and downRankFH <= 5 or NoLHW) and SpellIDsHW[7] then SpellID = SpellIDsHW[7]; HealSize = (797 + healMod30) * hwMod end
            if healneed > (880 + healModLHW) * hwMod * k         and ManaLeft >= 380 * tfMod and maxRankLHW >= 6 and downRankFH >= 6 and SpellIDsLHW[6] then SpellID = SpellIDsLHW[6]; HealSize = (880 + healModLHW) * hwMod end
            if healneed > (1092 + healMod30) * hwMod * K         and ManaLeft >= 440 * tfMod and maxRankHW >= 8  and downRankNH >= 8 and (TargetIsHealthy and maxRankLHW <= 6 and downRankFH <= 6 or NoLHW) and SpellIDsHW[8] then SpellID = SpellIDsHW[8]; HealSize = (1092 + healMod30) * hwMod end
            if healneed > (1464 + healMod30) * hwMod * K         and ManaLeft >= 560 * tfMod and maxRankHW >= 9  and downRankNH >= 9 and (TargetIsHealthy and maxRankLHW <= 6 and downRankFH <= 6 or NoLHW) and SpellIDsHW[9] then SpellID = SpellIDsHW[9]; HealSize = (1464 + healMod30) * hwMod end
            if healneed > (1735 + healMod30) * hwMod * K         and ManaLeft >= 620 * tfMod and maxRankHW >= 10 and downRankNH >= 10 and (TargetIsHealthy and maxRankLHW <= 6 and downRankFH <= 6 or NoLHW) and SpellIDsHW[10] then SpellID = SpellIDsHW[10]; HealSize = (1735 + healMod30) * hwMod end
        end
    else
        -- Not in combat: use closest available healing
        debug("Not in combat, will use closest available HW or LHW")
        if Health < RatioFull or not target then
            SpellID = SpellIDsHW[1]; HealSize = (39 + healMod15 * PF[1]) * hwMod
            if healneed > (71 + healMod20 * PF[6]) * hwMod   and ManaLeft >= 45 * tfMod  and maxRankHW >= 2  and downRankNH >= 2 and SpellIDsHW[2]  then SpellID = SpellIDsHW[2];  HealSize = (71 + healMod20 * PF[6]) * hwMod end
            if healneed > (142 + healMod25 * PF[12]) * hwMod and ManaLeft >= 80 * tfMod  and maxRankHW >= 3  and downRankNH >= 3 and SpellIDsHW[3]  then SpellID = SpellIDsHW[3];  HealSize = (142 + healMod25 * PF[12]) * hwMod end
            if healneed > (174 + healModLHW) * hwMod         and ManaLeft >= 105 * tfMod and maxRankLHW >= 1 and downRankFH >= 1 and SpellIDsLHW[1] then SpellID = SpellIDsLHW[1]; HealSize = (174 + healModLHW) * hwMod end
            if healneed > (264 + healModLHW) * hwMod         and ManaLeft >= 145 * tfMod and maxRankLHW >= 2 and downRankFH >= 2 and SpellIDsLHW[2] then SpellID = SpellIDsLHW[2]; HealSize = (264 + healModLHW) * hwMod end
            if healneed > (292 + healMod30 * PF[18]) * hwMod and ManaLeft >= 155 * tfMod and maxRankHW >= 4  and downRankNH >= 4 and SpellIDsHW[4]  then SpellID = SpellIDsHW[4];  HealSize = (292 + healMod30 * PF[18]) * hwMod end
            if healneed > (359 + healModLHW) * hwMod         and ManaLeft >= 185 * tfMod and maxRankLHW >= 3 and downRankFH >= 3 and SpellIDsLHW[3] then SpellID = SpellIDsLHW[3]; HealSize = (359 + healModLHW) * hwMod end
            if healneed > (408 + healMod30) * hwMod          and ManaLeft >= 200 * tfMod and maxRankHW >= 5  and downRankNH >= 5 and SpellIDsHW[5]  then SpellID = SpellIDsHW[5];  HealSize = (408 + healMod30) * hwMod end
            if healneed > (486 + healModLHW) * hwMod         and ManaLeft >= 235 * tfMod and maxRankLHW >= 4 and downRankFH >= 4 and SpellIDsLHW[4] then SpellID = SpellIDsLHW[4]; HealSize = (486 + healModLHW) * hwMod end
            if healneed > (579 + healMod30) * hwMod          and ManaLeft >= 265 * tfMod and maxRankHW >= 6  and downRankNH >= 6 and SpellIDsHW[6]  then SpellID = SpellIDsHW[6];  HealSize = (579 + healMod30) * hwMod end
            if healneed > (668 + healModLHW) * hwMod         and ManaLeft >= 305 * tfMod and maxRankLHW >= 5 and downRankFH >= 5 and SpellIDsLHW[5] then SpellID = SpellIDsLHW[5]; HealSize = (668 + healModLHW) * hwMod end
            if healneed > (797 + healMod30) * hwMod          and ManaLeft >= 340 * tfMod and maxRankHW >= 7  and downRankNH >= 7 and SpellIDsHW[7]  then SpellID = SpellIDsHW[7];  HealSize = (797 + healMod30) * hwMod end
            if healneed > (880 + healModLHW) * hwMod         and ManaLeft >= 380 * tfMod and maxRankLHW >= 6 and downRankFH >= 6 and SpellIDsLHW[6] then SpellID = SpellIDsLHW[6]; HealSize = (880 + healModLHW) * hwMod end
            if healneed > (1092 + healMod30) * hwMod         and ManaLeft >= 440 * tfMod and maxRankHW >= 8  and downRankNH >= 8 and SpellIDsHW[8]  then SpellID = SpellIDsHW[8];  HealSize = (1092 + healMod30) * hwMod end
            if healneed > (1464 + healMod30) * hwMod         and ManaLeft >= 560 * tfMod and maxRankHW >= 9  and downRankNH >= 9 and SpellIDsHW[9]  then SpellID = SpellIDsHW[9];  HealSize = (1464 + healMod30) * hwMod end
            if healneed > (1735 + healMod30) * hwMod         and ManaLeft >= 620 * tfMod and maxRankHW >= 10 and downRankNH >= 10 and SpellIDsHW[10] then SpellID = SpellIDsHW[10]; HealSize = (1735 + healMod30) * hwMod end
        end
    end

    return SpellID, HealSize * HDB
end

-- NoTarget wrapper for backwards compatibility
function QuickHeal_Shaman_FindHealSpellToUseNoTarget(maxhealth, healDeficit, healType, multiplier, forceMaxHPS, forceMaxRank, hdb, incombat)
    return QuickHeal_Shaman_FindHealSpellToUse(nil, healType, multiplier, forceMaxHPS, maxhealth, healDeficit, hdb, incombat)
end

-- Command handler
function QuickHeal_Command_Shaman(msg)
    local _, _, arg1, arg2, arg3 = string.find(msg, "%s?(%w+)%s?(%w+)%s?(%w+)")

    -- Match 3 arguments
    if arg1 and arg2 and arg3 then
        if arg1 == "player" or arg1 == "target" or arg1 == "targettarget" or arg1 == "party" or arg1 == "subgroup" or arg1 == "mt" or arg1 == "nonmt" then
            if arg2 == "heal" and arg3 == "max" then
                QuickHeal(arg1, nil, nil, true)
                return
            end
            if arg2 == "chainheal" and arg3 == "max" then
                QuickChainHeal(arg1, nil, nil, true, true)
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
        if arg4 == "chainheal" and arg5 == "max" then
            QuickChainHeal(nil, nil, nil, true, false)
            return
        end
        if arg4 == "heal" and arg5 == "max" then
            QuickHeal(nil, nil, nil, true)
            return
        end
        if arg4 == "player" or arg4 == "target" or arg4 == "targettarget" or arg4 == "party" or arg4 == "subgroup" or arg4 == "mt" or arg4 == "nonmt" then
            if arg5 == "chainheal" then
                QuickChainHeal(arg4, nil, nil, false)
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
    if cmd == "chainheal" then
        QuickChainHeal()
        return
    end
    if cmd == "heal" then
        QuickHeal()
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
    writeLine("== QUICKHEAL USAGE : SHAMAN ==")
    writeLine("/qh cfg - Opens up the configuration panel.")
    writeLine("/qh toggle - Switches between High HPS and Normal HPS.")
    writeLine("/qh downrank | dr - Opens the slider to limit QuickHeal to constrain healing to lower ranks.")
    writeLine("/qh tanklist | tl - Toggles display of the main tank list UI.")
    writeLine("/qh [mask] [type] [mod] - Heals the party/raid member that most needs it.")
    writeLine(" [mask]: player, target, targettarget, party, mt, nonmt, subgroup")
    writeLine(" [type]: heal (Healing Wave/LHW), chainheal (Chain Heal)")
    writeLine(" [mod]: max (max rank)")
    writeLine("/qh reset - Reset configuration to default parameters.")
end
