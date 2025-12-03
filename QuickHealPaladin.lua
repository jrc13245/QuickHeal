local function writeLine(s,r,g,b)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(s, r or 1, g or 1, b or 0.5)
    end
end

function QuickHeal_Paladin_GetRatioHealthyExplanation()
    local RatioHealthy = QuickHeal_GetRatioHealthy();
    local RatioFull = QuickHealVariables["RatioFull"];

    if RatioHealthy >= RatioFull then
        return QUICKHEAL_SPELL_HOLY_LIGHT .. " will never be used in combat. Exception : Holy Judgement buff ";
    else
        if RatioHealthy > 0 then
            return QUICKHEAL_SPELL_HOLY_LIGHT .. " will only be used in combat if the target has more than " .. RatioHealthy*100 .. "% life, and only if the healing done is greater than the greatest " .. QUICKHEAL_SPELL_FLASH_OF_LIGHT .. " available. Exception : Holy Judgement buff ";
        else
            return QUICKHEAL_SPELL_HOLY_LIGHT .. " will only be used in combat if the healing done is greater than the greatest " .. QUICKHEAL_SPELL_FLASH_OF_LIGHT .. " available. Exception : Holy Judgement buff ";
        end
    end
end

function QuickHeal_Paladin_FindSpellToUse(Target, healType, multiplier, forceMaxHPS)
    local SpellID = nil;
    local HealSize = 0;
    local Overheal = false;
	local ForceHL = false;

    -- +Healing-PenaltyFactor = (1-((20-LevelLearnt)*0.0375)) for all spells learnt before level 20
    local PF1 = 0.2875;
    local PF6 = 0.475;
    local PF14 = 0.775;

    -- Local aliases to access main module functionality and settings
    local RatioFull = QuickHealVariables["RatioFull"];
    local RatioHealthy = QuickHeal_GetRatioHealthy();
    local UnitHasHealthInfo = QuickHeal_UnitHasHealthInfo;
    local EstimateUnitHealNeed = QuickHeal_EstimateUnitHealNeed;
    local GetSpellIDs = QuickHeal_GetSpellIDs;
    local debug = QuickHeal_debug;

    -- Return immediatly if no player needs healing
    if not Target then
        return SpellID,HealSize;
    end

    if multiplier == nil then
        jgpprint(">>> multiplier is NIL <<<")
        --if multiplier > 1.0 then
        --    Overheal = true;
        --end
    elseif multiplier == 1.0 then
        jgpprint(">>> multiplier is " .. multiplier .. " <<<")
    elseif multiplier > 1.0 then
        jgpprint(">>> multiplier is " .. multiplier .. " <<<")
        Overheal = true;
    end

    -- Determine health and healneed of target
    local healneed;
    local Health;

    if QuickHeal_UnitHasHealthInfo(Target) and UnitHealthMax(Target) > 0 then
        -- Full info available
        healneed = UnitHealthMax(Target) - UnitHealth(Target); -- Here you can integrate HealComm by adding "- HealComm:getHeal(UnitName(Target))" (this can autocancel your heals even when you don't want)
        if Overheal then
            healneed = healneed * multiplier;
        else
            --
        end
        Health = UnitHealth(Target) / UnitHealthMax(Target);
    else
        -- Estimate target health
        healneed = QuickHeal_EstimateUnitHealNeed(Target,true); -- needs HealComm implementation maybe
        if Overheal then
            healneed = healneed * multiplier;
        else
            --
        end
        Health = UnitHealth(Target)/100;
    end

    local Bonus = 0
    if (AceLibrary and AceLibrary:HasInstance("ItemBonusLib-1.0")) then
        local itemBonus = AceLibrary("ItemBonusLib-1.0")
        Bonus = itemBonus:GetBonus("HEAL") or 0
        debug(string.format("Equipment Healing Bonus: %d", Bonus))
    end

    -- Calculate healing bonus
    local healMod15 = (1.5/3.5) * Bonus;
    local healMod25 = (2.5/3.5) * Bonus;
    debug("Final Healing Bonus (1.5,2.5)", healMod15,healMod25);

    local InCombat = UnitAffectingCombat('player') or UnitAffectingCombat(Target);

    -- Healing Light Talent (increases healing by 4% per rank)
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,6);
    local hlMod = 4*talentRank/100 + 1;
    debug(string.format("Healing Light talentmodification: %f", hlMod))

    local TargetIsHealthy = Health >= RatioHealthy;
    local ManaLeft = UnitMana('player');

    if TargetIsHealthy then
        debug("Target is healthy",Health);
    end

    -- Detect proc of 'Hand of Edward the Odd' mace (next spell is instant cast)
    if QuickHeal_DetectBuff('player',"Spell_Holy_SearingLight") then
        debug("BUFF: Hand of Edward the Odd (out of combat healing forced)");
        ForceHL = true;
    end

    -- Detect proc of 'Holy Judgement" (next Holy Light is fast cast)
    if QuickHeal_DetectBuff('player',"ability_paladin_judgementblue") then
        debug("BUFF: Holy Judgement (out of combat healing forced)");
        ForceHL = true;
    end

    -- Get total healing modifier (factor) caused by healing target debuffs
    local HDB = QuickHeal_GetHealModifier(Target);
    debug("Target debuff healing modifier",HDB);
    healneed = healneed/HDB;

    -- Get a list of ranks available of 'Flash of Light' and 'Holy Light'
    local SpellIDsHL = GetSpellIDs(QUICKHEAL_SPELL_HOLY_LIGHT);
    local SpellIDsFL = GetSpellIDs(QUICKHEAL_SPELL_FLASH_OF_LIGHT);
    local maxRankHL = table.getn(SpellIDsHL);
    local maxRankFL = table.getn(SpellIDsFL);
    local NoFL = maxRankFL < 1;
    debug(string.format("Found HL up to rank %d, and found FL up to rank %d", maxRankHL, maxRankFL))

    --Get max HealRanks that are allowed to be used
    local downRankFH = QuickHealVariables.DownrankValueFH or 0  -- rank for 1.5 sec heals
    local downRankNH = QuickHealVariables.DownrankValueNH or 0 -- rank for < 1.5 sec heals


    -- below changed to not differentiate between in or out if combat. Original code down below
    -- Find suitable SpellID based on the defined criteria
    local k = 1;
    local K = 1;
    if InCombat then
        local k = 0.9; -- In combat means that target is loosing life while casting, so compensate
        local K = 0.8; -- k for fast spells (FL) and K for slow spells (HL)            3 = 4 | 3 < 4 | 3 > 4
    end

    if not forceMaxHPS or not InCombat then
        if Health < RatioFull then
            if maxRankFL >=1                                                                                                                      and SpellIDsFL[1] then SpellID = SpellIDsFL[1]; HealSize = (67+healMod15)*hlMod else SpellID = SpellIDsHL[1]; HealSize = (43+healMod25*PF1)*hlMod end -- Default to rank 1 of FL or HL
            if healneed     > ( 83+healMod25*PF6)*hlMod*K and ManaLeft >= 60  and maxRankHL >=2 and ((TargetIsHealthy or ForceHL) and maxRankFL <= 1 or NoFL) and SpellIDsHL[2] then SpellID = SpellIDsHL[2]; HealSize =  (83+healMod25*PF6)*hlMod  end
            if healneed     > (102+healMod15)*hlMod*k and ManaLeft >= 50  and maxRankFL >=2 and downRankFH >= 2                              and SpellIDsFL[2] then SpellID = SpellIDsFL[2]; HealSize = (102+healMod15)*hlMod      end
            if healneed     > (153+healMod15)*hlMod*k and ManaLeft >= 70  and maxRankFL >=3 and downRankFH >= 3                              and SpellIDsFL[3] then SpellID = SpellIDsFL[3]; HealSize = (153+healMod15)*hlMod      end
            if healneed     > (173+healMod25*PF14)*hlMod*K and ManaLeft >= 110 and maxRankHL >=3 and ((TargetIsHealthy or ForceHL) and maxRankFL <= 3 or NoFL) and SpellIDsHL[3] then SpellID = SpellIDsHL[3]; HealSize = (173+healMod25*PF14)*hlMod end
            if healneed     > (206+healMod15)*hlMod*k and ManaLeft >= 90  and maxRankFL >=4 and downRankFH >= 4                              and SpellIDsFL[4] then SpellID = SpellIDsFL[4]; HealSize = (206+healMod15)*hlMod      end
            if healneed     > (278+healMod15)*hlMod*k and ManaLeft >= 115 and maxRankFL >=5 and downRankFH >= 5                              and SpellIDsFL[5] then SpellID = SpellIDsFL[5]; HealSize = (278+healMod15)*hlMod      end
            if healneed     > (333+healMod25)*hlMod*K and ManaLeft >= 190 and maxRankHL >=4 and ((TargetIsHealthy or ForceHL) and maxRankFL <= 5 or NoFL) and SpellIDsHL[4] then SpellID = SpellIDsHL[4]; HealSize = (333+healMod25)*hlMod      end
            if healneed     > (348+healMod15)*hlMod*k and ManaLeft >= 140 and maxRankFL >=6 and downRankFH >= 6                              and SpellIDsFL[6] then SpellID = SpellIDsFL[6]; HealSize = (348+healMod15)*hlMod      end
	        if healneed     > (428+healMod15)*hlMod*k and ManaLeft >= 180 and maxRankFL >=7 and downRankFH >= 7                              and SpellIDsFL[7] then SpellID = SpellIDsFL[7]; HealSize = (428+healMod15)*hlMod      end
            if healneed     > (522+healMod25)*hlMod*K and ManaLeft >= 275 and maxRankHL >=5 and ((TargetIsHealthy or ForceHL) and maxRankFL <= 7 or NoFL) and SpellIDsHL[5] then SpellID = SpellIDsHL[5]; HealSize = (522+healMod25)*hlMod      end
            if healneed     > (739+healMod25)*hlMod*K and ManaLeft >= 365 and maxRankHL >=6 and ((TargetIsHealthy or ForceHL) and maxRankFL <= 7 or NoFL) and SpellIDsHL[6] then SpellID = SpellIDsHL[6]; HealSize = (739+healMod25)*hlMod      end
            if healneed     > (999+healMod25)*hlMod*K and ManaLeft >= 465 and maxRankHL >=7 and ((TargetIsHealthy or ForceHL) and maxRankFL <= 7 or NoFL) and SpellIDsHL[7] then SpellID = SpellIDsHL[7]; HealSize = (999+healMod25)*hlMod      end
            if healneed     > (1317+healMod25)*hlMod*K and ManaLeft >= 580 and maxRankHL >=8 and ((TargetIsHealthy or ForceHL) and maxRankFL <= 7 or NoFL) and SpellIDsHL[8] then SpellID = SpellIDsHL[8]; HealSize = (1317+healMod25)*hlMod     end
            if healneed     > (1680+healMod25)*hlMod*K and ManaLeft >= 660 and maxRankHL >=9 and ((TargetIsHealthy or ForceHL) and maxRankFL <= 7 or NoFL) and SpellIDsHL[9] then SpellID = SpellIDsHL[9]; HealSize = (1680+healMod25)*hlMod     end
        end
    else
        if ManaLeft >= 35  and maxRankFL >=1 and downRankFH >= 1 and SpellIDsFL[1] then SpellID = SpellIDsFL[1]; HealSize = (67+healMod15)*hlMod end
        if ManaLeft >= 50  and maxRankFL >=2 and downRankFH >= 2 and SpellIDsFL[2] then SpellID = SpellIDsFL[2]; HealSize = (102+healMod15)*hlMod end
        if ManaLeft >= 70  and maxRankFL >=3 and downRankFH >= 3 and SpellIDsFL[3] then SpellID = SpellIDsFL[3]; HealSize = (153+healMod15)*hlMod end
        if ManaLeft >= 90  and maxRankFL >=4 and downRankFH >= 4 and SpellIDsFL[4] then SpellID = SpellIDsFL[4]; HealSize = (206+healMod15)*hlMod end
        if ManaLeft >= 115 and maxRankFL >=5 and downRankFH >= 5 and SpellIDsFL[5] then SpellID = SpellIDsFL[5]; HealSize = (278+healMod15)*hlMod end
        if ManaLeft >= 140 and maxRankFL >=6 and downRankFH >= 6 and SpellIDsFL[6] then SpellID = SpellIDsFL[6]; HealSize = (348+healMod15)*hlMod end
	    if ManaLeft >= 180 and maxRankFL >=7 and downRankFH >= 7 and SpellIDsFL[7] then SpellID = SpellIDsFL[7]; HealSize = (428+healMod15)*hlMod end
        if ManaLeft >= 275 and maxRankHL >=5 and (ForceHL and maxRankFL <= 7 or NoFL) and SpellIDsHL[5] then SpellID = SpellIDsHL[5]; HealSize = (522+healMod25)*hlMod      end
        if ManaLeft >= 365 and maxRankHL >=6 and (ForceHL and maxRankFL <= 7 or NoFL) and SpellIDsHL[6] then SpellID = SpellIDsHL[6]; HealSize = (739+healMod25)*hlMod      end
        if ManaLeft >= 465 and maxRankHL >=7 and (ForceHL and maxRankFL <= 7 or NoFL) and SpellIDsHL[7] then SpellID = SpellIDsHL[7]; HealSize = (999+healMod25)*hlMod      end
        if ManaLeft >= 580 and maxRankHL >=8 and (ForceHL and maxRankFL <= 7 or NoFL) and SpellIDsHL[8] then SpellID = SpellIDsHL[8]; HealSize = (1317+healMod25)*hlMod     end
        if ManaLeft >= 660 and maxRankHL >=9 and (ForceHL and maxRankFL <= 7 or NoFL) and SpellIDsHL[9] then SpellID = SpellIDsHL[9]; HealSize = (1680+healMod25)*hlMod     end
    end
    return SpellID,HealSize*HDB;
end

function QuickHeal_Paladin_FindHealSpellToUseNoTarget(maxhealth, healDeficit, healType, multiplier, forceMaxHPS, forceMaxRank, hdb, incombat)
    local SpellID = nil;
    local HealSize = 0;
    local Overheal = false;
	local ForceHL = false;

    if multiplier == nil then
        jgpprint(">>> multiplier is NIL <<<")
        --if multiplier > 1.0 then
        --    Overheal = true;
        --end
    elseif multiplier == 1.0 then
        jgpprint(">>> multiplier is " .. multiplier .. " <<<")
    elseif multiplier > 1.0 then
        jgpprint(">>> multiplier is " .. multiplier .. " <<<")
        Overheal = true;
    end

    -- +Healing-PenaltyFactor = (1-((20-LevelLearnt)*0.0375)) for all spells learnt before level 20
    local PF1 = 0.2875;
    local PF6 = 0.475;
    local PF14 = 0.775;

    -- Local aliases to access main module functionality and settings
    local RatioFull = QuickHealVariables["RatioFull"];
    local RatioHealthy = QuickHeal_GetRatioHealthy();
    local UnitHasHealthInfo = QuickHeal_UnitHasHealthInfo;
    local EstimateUnitHealNeed = QuickHeal_EstimateUnitHealNeed;
    local GetSpellIDs = QuickHeal_GetSpellIDs;
    local debug = QuickHeal_debug;

    -- Determine health and heal need of target
    local healneed = healDeficit * multiplier;
    local Health = healDeficit / maxhealth;

    local Bonus = 0
    if (AceLibrary and AceLibrary:HasInstance("ItemBonusLib-1.0")) then
        local itemBonus = AceLibrary("ItemBonusLib-1.0")
        Bonus = itemBonus:GetBonus("HEAL") or 0
        debug(string.format("Equipment Healing Bonus: %d", Bonus))
    end

    -- Calculate healing bonus
    local healMod15 = (1.5/3.5) * Bonus;
    local healMod25 = (2.5/3.5) * Bonus;
    debug("Final Healing Bonus (1.5,2.5)", healMod15,healMod25);

    local InCombat = UnitAffectingCombat('player') or incombat;

    -- Healing Light Talent (increases healing by 4% per rank)
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,6);
    local hlMod = 4*talentRank/100 + 1;
    debug(string.format("Healing Light talentmodification: %f", hlMod))

    local TargetIsHealthy = Health >= RatioHealthy;
    local ManaLeft = UnitMana('player');

    if TargetIsHealthy then
        debug("Target is healthy",Health);
    end

    -- Detect proc of 'Hand of Edward the Odd' mace (next spell is instant cast)
    if QuickHeal_DetectBuff('player',"Spell_Holy_SearingLight") then
        debug("BUFF: Hand of Edward the Odd (out of combat healing forced)");
        ForceHL = true;
    end

    -- Detect proc of 'Holy Judgement" (next Holy Light is fast cast)
    if QuickHeal_DetectBuff('player',"ability_paladin_judgementblue") then
        debug("BUFF: Holy Judgement (out of combat healing forced)");
        ForceHL = true;
    end

    -- Get total healing modifier (factor) caused by healing target debuffs
    --local HDB = QuickHeal_GetHealModifier(Target);
    --debug("Target debuff healing modifier",HDB);
    healneed = healneed/hdb;


    -- Get a list of ranks available of 'Flash of Light' and 'Holy Light'
    local SpellIDsHL = GetSpellIDs(QUICKHEAL_SPELL_HOLY_LIGHT);
    local SpellIDsFL = GetSpellIDs(QUICKHEAL_SPELL_FLASH_OF_LIGHT);
    local maxRankHL = table.getn(SpellIDsHL);
    local maxRankFL = table.getn(SpellIDsFL);
    local NoFL = maxRankFL < 1;
    debug(string.format("Found HL up to rank %d, and found FL up to rank %d", maxRankHL, maxRankFL))

    --Get max HealRanks that are allowed to be used
    local downRankFH = QuickHealVariables.DownrankValueFH or 0  -- fast spells (FL)
    local downRankNH = QuickHealVariables.DownrankValueNH or 0 -- slow spells (HL)


    -- below changed to not differentiate between in or out if combat. Original code down below
    -- Find suitable SpellID based on the defined criteria
    local k = 1;
    local K = 1;
    if InCombat then
        local k = 0.9; -- In combat means that target is loosing life while casting, so compensate
        local K = 0.8; -- k for fast spells (FL) and K for slow spells (HL)           
    end

    if not forceMaxHPS or not InCombat then
        if maxRankFL >=1                                                                                                                      and SpellIDsFL[1] then SpellID = SpellIDsFL[1]; HealSize = (67+healMod15)*hlMod else SpellID = SpellIDsHL[1]; HealSize = (43+healMod25*PF1)*hlMod end -- Default to rank 1 of FL or HL
        if healneed     > ( 83+healMod25*PF6)*hlMod*K and ManaLeft >= 60  and maxRankHL >=2 and ((TargetIsHealthy or ForceHL) and maxRankFL <= 1 or NoFL) and SpellIDsHL[2] then SpellID = SpellIDsHL[2]; HealSize =  (83+healMod25*PF6)*hlMod  end
        if healneed     > (102+healMod15)*hlMod     *k and ManaLeft >= 50  and maxRankFL >=2 and downRankFH >= 2                              and SpellIDsFL[2] then SpellID = SpellIDsFL[2]; HealSize = (102+healMod15)*hlMod      end
        if healneed     > (153+healMod15)*hlMod     *k and ManaLeft >= 70  and maxRankFL >=3 and downRankFH >= 3                              and SpellIDsFL[3] then SpellID = SpellIDsFL[3]; HealSize = (153+healMod15)*hlMod      end
        if healneed     > (173+healMod25*PF14)*hlMod*K and ManaLeft >= 110 and maxRankHL >=3 and ((TargetIsHealthy or ForceHL) and maxRankFL <= 3 or NoFL) and SpellIDsHL[3] then SpellID = SpellIDsHL[3]; HealSize = (173+healMod25*PF14)*hlMod end
        if healneed     > (206+healMod15)*hlMod     *k and ManaLeft >= 90  and maxRankFL >=4 and downRankFH >= 4                              and SpellIDsFL[4] then SpellID = SpellIDsFL[4]; HealSize = (206+healMod15)*hlMod      end
        if healneed     > (278+healMod15)*hlMod     *k and ManaLeft >= 115 and maxRankFL >=5 and downRankFH >= 5                              and SpellIDsFL[5] then SpellID = SpellIDsFL[5]; HealSize = (278+healMod15)*hlMod      end
        if healneed     > (333+healMod25)*hlMod     *K and ManaLeft >= 190 and maxRankHL >=4 and (TargetIsHealthy and maxRankFL <= 5 or NoFL) and SpellIDsHL[4] then SpellID = SpellIDsHL[4]; HealSize = (333+healMod25)*hlMod      end
        if healneed     > (348+healMod15)*hlMod     *k and ManaLeft >= 140 and maxRankFL >=6 and downRankFH >= 6                              and SpellIDsFL[6] then SpellID = SpellIDsFL[6]; HealSize = (348+healMod15)*hlMod      end
	    if healneed     > (428+healMod15)*hlMod     *k and ManaLeft >= 180 and maxRankFL >=7 and downRankFH >= 7                              and SpellIDsFL[7] then SpellID = SpellIDsFL[7]; HealSize = (428+healMod15)*hlMod      end
        if healneed     > (522+healMod25)*hlMod     *K and ManaLeft >= 275 and maxRankHL >=5 and ((TargetIsHealthy or ForceHL) and maxRankFL <= 7 or NoFL) and SpellIDsHL[5] then SpellID = SpellIDsHL[5]; HealSize = (522+healMod25)*hlMod      end
        if healneed     > (739+healMod25)*hlMod     *K and ManaLeft >= 365 and maxRankHL >=6 and ((TargetIsHealthy or ForceHL) and maxRankFL <= 7 or NoFL) and SpellIDsHL[6] then SpellID = SpellIDsHL[6]; HealSize = (739+healMod25)*hlMod      end
        if healneed     > (999+healMod25)*hlMod     *K and ManaLeft >= 465 and maxRankHL >=7 and ((TargetIsHealthy or ForceHL) and maxRankFL <= 7 or NoFL) and SpellIDsHL[7] then SpellID = SpellIDsHL[7]; HealSize = (999+healMod25)*hlMod      end
        if healneed     > (1317+healMod25)*hlMod    *K and ManaLeft >= 580 and maxRankHL >=8 and ((TargetIsHealthy or ForceHL) and maxRankFL <= 7 or NoFL) and SpellIDsHL[8] then SpellID = SpellIDsHL[8]; HealSize = (1317+healMod25)*hlMod     end
        if healneed     > (1680+healMod25)*hlMod    *K and ManaLeft >= 660 and maxRankHL >=9 and ((TargetIsHealthy or ForceHL) and maxRankFL <= 7 or NoFL) and SpellIDsHL[9] then SpellID = SpellIDsHL[9]; HealSize = (1680+healMod25)*hlMod     end
    else
        if ManaLeft >= 35  and maxRankFL >=1 and downRankFH >= 1 and SpellIDsFL[1] then SpellID = SpellIDsFL[1]; HealSize = (67+healMod15)*hlMod end
        if ManaLeft >= 50  and maxRankFL >=2 and downRankFH >= 2 and SpellIDsFL[2] then SpellID = SpellIDsFL[2]; HealSize = (102+healMod15)*hlMod end
        if ManaLeft >= 70  and maxRankFL >=3 and downRankFH >= 3 and SpellIDsFL[3] then SpellID = SpellIDsFL[3]; HealSize = (153+healMod15)*hlMod end
        if ManaLeft >= 90  and maxRankFL >=4 and downRankFH >= 4 and SpellIDsFL[4] then SpellID = SpellIDsFL[4]; HealSize = (206+healMod15)*hlMod end
        if ManaLeft >= 115 and maxRankFL >=5 and downRankFH >= 5 and SpellIDsFL[5] then SpellID = SpellIDsFL[5]; HealSize = (278+healMod15)*hlMod end
        if ManaLeft >= 140 and maxRankFL >=6 and downRankFH >= 6 and SpellIDsFL[6] then SpellID = SpellIDsFL[6]; HealSize = (348+healMod15)*hlMod end
	    if ManaLeft >= 180 and maxRankFL >=7 and downRankFH >= 7 and SpellIDsFL[7] then SpellID = SpellIDsFL[7]; HealSize = (428+healMod15)*hlMod end
		if ManaLeft >= 275 and maxRankHL >=5 and (ForceHL and maxRankFL <= 7 or NoFL) and SpellIDsHL[5] then SpellID = SpellIDsHL[5]; HealSize = (522+healMod25)*hlMod      end
        if ManaLeft >= 365 and maxRankHL >=6 and (ForceHL and maxRankFL <= 7 or NoFL) and SpellIDsHL[6] then SpellID = SpellIDsHL[6]; HealSize = (739+healMod25)*hlMod      end
        if ManaLeft >= 465 and maxRankHL >=7 and (ForceHL and maxRankFL <= 7 or NoFL) and SpellIDsHL[7] then SpellID = SpellIDsHL[7]; HealSize = (999+healMod25)*hlMod      end
        if ManaLeft >= 580 and maxRankHL >=8 and (ForceHL and maxRankFL <= 7 or NoFL) and SpellIDsHL[8] then SpellID = SpellIDsHL[8]; HealSize = (1317+healMod25)*hlMod     end
        if ManaLeft >= 660 and maxRankHL >=9 and (ForceHL and maxRankFL <= 7 or NoFL) and SpellIDsHL[9] then SpellID = SpellIDsHL[9]; HealSize = (1680+healMod25)*hlMod     end
    end

    return SpellID,HealSize*hdb;
end

function QuickHeal_Paladin_FindHoTSpellToUse(Target, healType, forceMaxRank)
    local SpellID = nil;
    local HealSize = 0;

    -- Local aliases to access main module functionality and settings
    local RatioFull = QuickHealVariables["RatioFull"];
    local RatioHealthy = QuickHeal_GetRatioHealthy();
    local UnitHasHealthInfo = QuickHeal_UnitHasHealthInfo;
    local EstimateUnitHealNeed = QuickHeal_EstimateUnitHealNeed;
    local GetSpellIDs = QuickHeal_GetSpellIDs;
    local debug = QuickHeal_debug;

    -- Return immediately if no player needs healing
    if not Target then
        return SpellID,HealSize;
    end

    -- Determine health and heal need of target
    local healneed;
    local Health;
    if UnitHasHealthInfo(Target) then
        -- Full info available
        healneed = UnitHealthMax(Target) - UnitHealth(Target); -- Here you can integrate HealComm by adding "- HealComm:getHeal(UnitName(Target))" (this can autocancel your heals even when you don't want)
        Health = UnitHealth(Target) / UnitHealthMax(Target);
    else
        -- Estimate target health
        healneed = EstimateUnitHealNeed(Target,true);
        Health = UnitHealth(Target)/100;
    end

    local Bonus = 0
    if (AceLibrary and AceLibrary:HasInstance("ItemBonusLib-1.0")) then
        local itemBonus = AceLibrary("ItemBonusLib-1.0")
        Bonus = itemBonus:GetBonus("HEAL") or 0
        debug(string.format("Equipment Healing Bonus: %d", Bonus))
    end

    -- Calculate healing bonus
    local healMod15 = (1.5/3.5) * Bonus;
    debug("Final Healing Bonus (1.5)", healMod15);

    -- Healing Light Talent (increases healing by 4% per rank)
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,6);
    local hlMod = 4*talentRank/100 + 1;
    debug(string.format("Healing Light talentmodification: %f", hlMod))

    -- Divine Favor Talent (increases Holy shock effect by 5% per rank, as crit is 50% bonus only)
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,13);
    local dfMod = 5*talentRank/100 + 1;
    debug(string.format("Divine Favor talentmodification: %f", dfMod))

    local TargetIsHealthy = Health >= RatioHealthy;
    local ManaLeft = UnitMana('player');

    if TargetIsHealthy then
        debug("Target is healthy",Health);
    end

    -- Get total healing modifier (factor) caused by healing target debuffs
    local HDB = QuickHeal_GetHealModifier(Target);
    debug("Target debuff healing modifier", HDB);
    healneed = healneed / HDB;

    -- Get a list of ranks available for Holy Shock only
    local SpellIDsHS = GetSpellIDs(QUICKHEAL_SPELL_HOLY_SHOCK);
    local maxRankHS = table.getn(SpellIDsHS);
    debug(string.format("Found HS up to rank %d", maxRankHS));

    QuickHeal_debug(string.format(
        "healneed: %f  target: %s  healType: %s  forceMaxRank: %s",
        healneed, Target, healType, tostring(forceMaxRank)
    ));


    if not forceMaxRank then
        -- Mode normal : choisir rang selon besoin de soin
        SpellID = SpellIDsHS[1]; HealSize = (315+healMod15)*hlMod*dfMod; -- Rank 1
        if healneed >(360+healMod15)*hlMod*dfMod and ManaLeft >= 335 and maxRankHS >=2 then SpellID = SpellIDsHS[2]; HealSize = (360+healMod15)*hlMod*dfMod end
        if healneed >(500+healMod15)*hlMod*dfMod and ManaLeft >= 410 and maxRankHS >=3 then SpellID = SpellIDsHS[3]; HealSize = (500+healMod15)*hlMod*dfMod end
        if healneed >(655+healMod15)*hlMod*dfMod and ManaLeft >= 485 and maxRankHS >=4 then SpellID = SpellIDsHS[4]; HealSize = (655+healMod15)*hlMod*dfMod end
    else
        -- Mode max rank : toujours le rang le plus élevé
        if maxRankHS >= 1 then
            SpellID = SpellIDsHS[maxRankHS];
            HealSize = (655+healMod15)*hlMod*dfMod; -- valeur indicative
        end
    end


return SpellID, HealSize * HDB;

end

function QuickHeal_Paladin_FindHoTSpellToUseNoTarget(maxhealth, healDeficit, healType, multiplier, forceMaxHPS, forceMaxRank, hdb, incombat)
    local SpellID = nil;
    local HealSize = 0;

    -- Local aliases to access main module functionality and settings
    local RatioFull = QuickHealVariables["RatioFull"];
    local RatioHealthy = QuickHeal_GetRatioHealthy();
    local UnitHasHealthInfo = QuickHeal_UnitHasHealthInfo;
    local EstimateUnitHealNeed = QuickHeal_EstimateUnitHealNeed;
    local GetSpellIDs = QuickHeal_GetSpellIDs;
    local debug = QuickHeal_debug;

    -- Return immediately if no player needs healing
    if not Target then
        return SpellID,HealSize;
    end

    -- Determine health and heal need of target
    local healneed;
    local Health;
    if UnitHasHealthInfo(Target) then
        -- Full info available
        healneed = UnitHealthMax(Target) - UnitHealth(Target); -- Here you can integrate HealComm by adding "- HealComm:getHeal(UnitName(Target))" (this can autocancel your heals even when you don't want)
        Health = UnitHealth(Target) / UnitHealthMax(Target);
    else
        -- Estimate target health
        healneed = EstimateUnitHealNeed(Target,true);
        Health = UnitHealth(Target)/100;
    end

    local Bonus = 0
    if (AceLibrary and AceLibrary:HasInstance("ItemBonusLib-1.0")) then
        local itemBonus = AceLibrary("ItemBonusLib-1.0")
        Bonus = itemBonus:GetBonus("HEAL") or 0
        debug(string.format("Equipment Healing Bonus: %d", Bonus))
    end

    -- Calculate healing bonus
    local healMod15 = (1.5/3.5) * Bonus;
    debug("Final Healing Bonus (1.5)", healMod15);

    -- Healing Light Talent (increases healing by 4% per rank)
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,6);
    local hlMod = 4*talentRank/100 + 1;
    debug(string.format("Healing Light talentmodification: %f", hlMod))

    -- Divine Favor Talent (increases Holy shock effect by 5% per rank, as crit is 50% bonus only)
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,13);
    local dfMod = 5*talentRank/100 + 1;
    debug(string.format("Divine Favor talentmodification: %f", dfMod))

    local TargetIsHealthy = Health >= RatioHealthy;
    local ManaLeft = UnitMana('player');

    if TargetIsHealthy then
        debug("Target is healthy",Health);
    end

    -- Get total healing modifier (factor) caused by healing target debuffs
    local HDB = QuickHeal_GetHealModifier(Target);
    debug("Target debuff healing modifier",HDB);
    healneed = healneed/HDB;

    -- Get a list of ranks available of 'Holy Shock'
    local SpellIDsHS = GetSpellIDs(QUICKHEAL_SPELL_HOLY_SHOCK);
    local maxRankHS = table.getn(SpellIDsHS);
    debug(string.format("Found HS up to rank %d", maxRankHS));

    -- Si on force le rang maximum (ex: /qh hot max)
    if forceMaxRank then
        if maxRankHS >= 1 then
            SpellID = SpellIDsHS[maxRankHS];
            HealSize = (655+healMod15)*hlMod*dfMod; -- estimation du rang 4
        end
        return SpellID, HealSize * hdb;
    end

    -- Mode normal : choisir rang selon besoin de soin
    SpellID = SpellIDsHS[1]; HealSize = (315+healMod15)*hlMod*dfMod; -- Rank 1
    if healneed >(360+healMod15)*hlMod*dfMod and ManaLeft >= 335 and maxRankHS >=2 and SpellIDsHS[2] then SpellID = SpellIDsHS[2]; HealSize = (360+healMod15)*hlMod*dfMod end
    if healneed >(500+healMod15)*hlMod*dfMod and ManaLeft >= 410 and maxRankHS >=3 and SpellIDsHS[3] then SpellID = SpellIDsHS[3]; HealSize = (500+healMod15)*hlMod*dfMod end
    if healneed >(655+healMod15)*hlMod*dfMod and ManaLeft >= 485 and maxRankHS >=4 and SpellIDsHS[4] then SpellID = SpellIDsHS[4]; HealSize = (655+healMod15)*hlMod*dfMod end

    return SpellID, HealSize * hdb;
end



function QuickHeal_Command_Paladin(msg)

    local _, _, arg1, arg2, arg3 = string.find(msg, "%s?(%w+)%s?(%w+)%s?(%w+)")
    
    -- match 3 arguments
    if arg1 ~= nil and arg2 ~= nil and arg3 ~= nil then
        if arg1 == "player" or arg1 == "target" or arg1 == "targettarget" or arg1 == "party" or arg1 == "subgroup" or arg1 == "mt" or arg1 == "nonmt" then
            if arg2 == "heal" and arg3 == "max" then
                QuickHeal(arg1, nil, nil, true);
                return;
            end
            -- 🔄 remplacement HOT -> HS
            if arg2 == "hs" and arg3 == "fh" then
                QuickHOT(arg1, nil, nil, true, true);
                return;
            end
            if arg2 == "hs" and arg3 == "max" then
                QuickHOT(arg1, nil, nil, true, false);
                return;
            end
        end
    end

    -- match 2 arguments
    local _, _, arg4, arg5 = string.find(msg, "%s?(%w+)%s?(%w+)")

    if arg4 ~= nil and arg5 ~= nil then
        if arg4 == "debug" then
            if arg5 == "on" then
                QHV.DebugMode = true;
                return;
            elseif arg5 == "off" then
                QHV.DebugMode = false;
                return;
            end
        end
        if arg4 == "heal" and arg5 == "max" then
            QuickHeal(nil, nil, nil, true);
            return;
        end
        -- 🔄 remplacement HOT -> HS
        if arg4 == "hs" and arg5 == "max" then
            QuickHOT(nil, nil, nil, true, false);
            return;
        end
        if arg4 == "hs" and arg5 == "fh" then
            QuickHOT(nil, nil, nil, true, true);
            return;
        end
        if arg4 == "player" or arg4 == "target" or arg4 == "targettarget" or arg4 == "party" or arg4 == "subgroup" or arg4 == "mt" or arg4 == "nonmt" then
            if arg5 == "hs" then
                QuickHOT(arg4, nil, nil, false, false);
                return;
            end
            if arg5 == "heal" then
                QuickHeal(arg4, nil, nil, false);
                return;
            end
        end
    end

    -- match 1 argument
    local cmd = string.lower(msg)

    if cmd == "cfg" then
        QuickHeal_ToggleConfigurationPanel();
        return;
    end

    if cmd == "toggle" then
        QuickHeal_Toggle_Healthy_Threshold();
        return;
    end

    if cmd == "downrank" or cmd == "dr" then
        ToggleDownrankWindow();
        return;
    end

    if cmd == "tanklist" or cmd == "tl" then
        QH_ShowHideMTListUI();
        return;
    end

    if cmd == "reset" then
        QuickHeal_SetDefaultParameters();
        writeLine(QuickHealData.name .. " reset to default configuration", 0, 0, 1);
        QuickHeal_ToggleConfigurationPanel();
        QuickHeal_ToggleConfigurationPanel();
        return;
    end

    if cmd == "heal" then
        QuickHeal();
        return;
    end

    -- 🔄 remplacement HOT -> HS
    if cmd == "hs" then
        QuickHOT();
        return;
    end

    -- /qh hot ne fait plus rien
    if cmd == "hot" then
        writeLine("The command /qh hot is disabled for paladins. Use /qh hs instead.", 1, 0, 0);
        return;
    end

    if cmd == "" then
        QuickHeal(nil);
        return;
    elseif cmd == "player" or cmd == "target" or cmd == "targettarget" or cmd == "party" or cmd == "subgroup" or cmd == "mt" or cmd == "nonmt" then
        QuickHeal(cmd);
        return;
    end

    -- Help
    writeLine("== QUICKHEAL USAGE : PALADIN ==");
    writeLine("/qh cfg - Opens up the configuration panel.");
    writeLine("/qh toggle - Switches between High HPS and Normal HPS.");
    writeLine("/qh downrank | dr - Opens the downrank limit slider.");
    writeLine("/qh tanklist | tl - Toggles display of the main tank list.");
    writeLine("/qh [mask] [type] [mod] - Heals the ally who needs it most.");
    writeLine(" [mask] constrains healing pool to:");
    writeLine("   [player] yourself");
    writeLine("   [target] your target");
    writeLine("   [targettarget] your target's target");
    writeLine("   [party] your party");
    writeLine("   [mt] main tanks");
    writeLine("   [nonmt] everyone but the main tanks");
    writeLine("   [subgroup] your raid subgroup");
    writeLine(" [type] specifies the use of:");
    writeLine("   [heal] - direct heal");
    writeLine("   [hs]   - Holy Shock");
    writeLine(" [mod] optional:");
    writeLine("   [max] - uses max rank");
    writeLine("   [fh]  - uses max rank ignoring HP threshold");
    writeLine("/qh reset - Reset configuration to default parameters.");
end


 ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- extend by Drokin
-- MELEE PALADIN HEALING functions.  Currently in beta.
-- The following functions give paladins that choose to heal in melee additional tools to automate Holy Strike and Holy Shock.
-- /run qhHStrike(93,3);  -- Smart Holy Stike function, 1st number is the min %healing threshold to trigger, the 2nd number is the # of targets needed under threshold (DEFAULT set at 93% threshold on 3 targets)
-- /run qhHShock(85); -- Smart Holy Shock function, number is the min % healing threshold to trigger (DEFAULT is set to 85%)

-- Define CastHolyStrike as a global function
function qhHStrike(HSminHP,HSminTargets)
    -- Get the count of players meeting the conditions
    local playersInRange = GetPlayersBelowHealthThresholdInRange(HSminHP);

	-- Cast Holy Strike if min # of targets conditions are met
    if playersInRange >= HSminTargets then
        CastSpellByName("Holy Strike");
        -- Uncomment next line for debug messages
        -- DEFAULT_CHAT_FRAME:AddMessage("Holy Strike cast! Players in range: " .. playersInRange); else DEFAULT_CHAT_FRAME:AddMessage("Conditions not met. Players in range: " .. playersInRange);
    end
end

-- Define HealWithHolyShock as a global function
function qhHShock(SHOCKminHP)
    -- Find the lowest health unit and its health percentage
    local target, healthPct = GetLowestHealthUnit();

    -- Cast Holy Shock only if target exists and their health is below the threshold
    if target and healthPct < SHOCKminHP then
        CastSpellByName("Holy Shock", target);
        -- Uncomment the next line if you want a chat message when Holy Shock is cast for debugging
        -- DEFAULT_CHAT_FRAME:AddMessage("Holy Shock cast on: " .. UnitName(target) .. " (Health: " .. string.format("%.1f", healthPct) .. "%)");     else if target then DEFAULT_CHAT_FRAME:AddMessage("Target " .. UnitName(target) .. " has health above " .. SHOCKminHP .. "%. No Holy Shock cast."); else DEFAULT_CHAT_FRAME:AddMessage("No valid target found for Holy Shock."); end
    end
end

-- Define IsHealable as a function
function IsHealable(unit)
    -- Returns true if the unit is valid, friendly, alive, and connected
    return UnitExists(unit) and UnitIsFriend("player", unit) and not UnitIsDeadOrGhost(unit) and UnitIsConnected(unit);
end

-- Define IsWithin10Yards as a function for Holy Strike.  8yds check is currently used
function IsWithin10Yards(unit)
    -- Checks if a unit is within 10 yards using CheckInteractDistance
    return CheckInteractDistance(unit, 3); -- 3 = 10 yards interraction distance
end

-- Define GetPlayersBelowHealthThresholdInRange as a function for Holy Strike
function GetPlayersBelowHealthThresholdInRange(minHPf)
    -- Returns the count of healable players within 10 yards with health at or below the specified threshold
    local count = 0;
    -- Check all raid members if in raid
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local unit = "raid" .. i;
            if IsHealable(unit) and IsWithin10Yards(unit) then
                local healthPercent = (UnitHealth(unit) / UnitHealthMax(unit)) * 100;
				if healthPercent <= minHPf then
                    count = count + 1;
                end
			end
        end
    else
        -- Check player and party members if in a party or solo
        local units = {"player"};
        if GetNumPartyMembers() > 0 then
            for i = 1, GetNumPartyMembers() do
                table.insert(units, "party" .. i);
            end
        end

        for _, unit in ipairs(units) do
            if IsHealable(unit) and IsWithin10Yards(unit) then
                local healthPercent = (UnitHealth(unit) / UnitHealthMax(unit)) * 100;
                if healthPercent <= minHPf then
                    count = count + 1;
                end
            end
        end
    end
    return count;
end

-- Define GetLowestHealthUnit as a global function for Holy Shock
function GetLowestHealthUnit()
    -- Finds the unit with the lowest health percentage
    local lowestUnit = nil;
    local lowestHealthPct = 100;

    -- Check all raid members if in raid
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local unit = "raid" .. i;
            if IsHealable(unit) and CheckInteractDistance(unit, 4) then -- 4 = 20 yards
                local healthPct = (UnitHealth(unit) / UnitHealthMax(unit)) * 100; -- Fixed missing parenthesis
                if healthPct < lowestHealthPct then
                    lowestUnit = unit;
                    lowestHealthPct = healthPct;
                end
            end
        end
    else
        -- Check player, party members, and pets if in a party or solo
        local units = {"player"};
        if GetNumPartyMembers() > 0 then
            for i = 1, GetNumPartyMembers() do
                table.insert(units, "party" .. i);
            end
        end

        for _, unit in ipairs(units) do
            if IsHealable(unit) and CheckInteractDistance(unit, 4) then
                local healthPct = ((UnitHealth(unit)+HealComm:getHeal(UnitName(unit))) / UnitHealthMax(unit)) * 100;
                if healthPct < lowestHealthPct then
                    lowestUnit = unit;
                    lowestHealthPct = healthPct;
                end
            end
        end
    end

    return lowestUnit, lowestHealthPct; -- Return both unit and health percentage
end











