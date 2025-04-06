local function writeLine(s,r,g,b)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(s, r or 1, g or 1, b or 0.5)
    end
end

function QuickHeal_Paladin_GetRatioHealthyExplanation()
    local RatioHealthy = QuickHeal_GetRatioHealthy();
    local RatioFull = QuickHealVariables["RatioFull"];

    if RatioHealthy >= RatioFull then
        return QUICKHEAL_SPELL_HOLY_LIGHT .. " will never be used in combat. ";
    else
        if RatioHealthy > 0 then
            return QUICKHEAL_SPELL_HOLY_LIGHT .. " will only be used in combat if the target has more than " .. RatioHealthy*100 .. "% life, and only if the healing done is greater than the greatest " .. QUICKHEAL_SPELL_FLASH_OF_LIGHT .. " available. ";
        else
            return QUICKHEAL_SPELL_HOLY_LIGHT .. " will only be used in combat if the healing done is greater than the greatest " .. QUICKHEAL_SPELL_FLASH_OF_LIGHT .. " available. ";
        end
    end
end

function QuickHeal_Paladin_FindSpellToUse(Target, healType, multiplier, forceMaxHPS)
    local SpellID = nil;
    local HealSize = 0;
    local Overheal = false;

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

    if QuickHeal_UnitHasHealthInfo(Target) then
        -- Full info available
        healneed = UnitHealthMax(Target) - UnitHealth(Target) - HealComm:getHeal(UnitName(Target)); -- Implementatin for HealComm
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

    -- if BonusScanner is running, get +Healing bonus
    local Bonus = 0;
    if (BonusScanner) then
        Bonus = tonumber(BonusScanner:GetBonus("HEAL"));
        debug(string.format("Equipment Healing Bonus: %d", Bonus));
    end

    -- Calculate healing bonus
    local healMod15 = (1.5/3.5) * Bonus; -- For Flash of Light (1.5s cast)
    local healMod25 = (2.5/3.5) * Bonus; -- For Holy Light (2.5s cast)
    debug("Final Healing Bonus (1.5,2.5)", healMod15,healMod25);

    local InCombat = UnitAffectingCombat('player') or UnitAffectingCombat(Target);

    -- Healing Light Talent (increases healing by 4% per rank)
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,5);
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
        InCombat = false;
    end

    -- Get total healing modifier (factor) caused by healing target debuffs
    local HDB = QuickHeal_GetHealModifier(Target);
    debug("Target debuff healing modifier",HDB);
    healneed = healneed/HDB;

    -- Get a list of ranks available of 'Holy Light' and 'Flash of Light'
    local SpellIDsHL = GetSpellIDs(QUICKHEAL_SPELL_HOLY_LIGHT);
    local SpellIDsFL = GetSpellIDs(QUICKHEAL_SPELL_FLASH_OF_LIGHT);
    local maxRankHL = table.getn(SpellIDsHL);
    local maxRankFL = table.getn(SpellIDsFL);
    local NoFL = maxRankFL < 1;
    debug(string.format("Found HL up to rank %d, and found FL up to rank %d", maxRankHL, maxRankFL))

    --Get max HealRanks that are allowed to be used
    local downRankFH = QuickHealVariables.DownrankValueFH  -- rank for 1.5 sec heals (Flash of Light)
    local downRankNH = QuickHealVariables.DownrankValueNH -- rank for 2.5 sec heals (Holy Light) - *Note: Original code seems to mix these up in comments*


    -- below changed to not differentiate between in or out if combat. Original code down below
    -- Find suitable SpellID based on the defined criteria
    local k = 1; -- Factor for 1.5s cast spells
    local K = 1; -- Factor for 2.5s cast spells
    if InCombat then
        k = 0.9; -- In combat means that target is loosing life while casting, so compensate
        K = 0.8; -- k for fast spells (FL) and K for slow spells (HL)
    end

    -- Base Heal values from 1.12.1 (average where applicable) - UPDATED VALUES
    local FoLR1_Heal = 72;   local FoLR1_Mana = 35;   -- Avg(67-77)
    local FoLR2_Heal = 110;  local FoLR2_Mana = 50;   -- Avg(102-117) rounded up
    local FoLR3_Heal = 162;  local FoLR3_Mana = 70;   -- Avg(153-171)
    local FoLR4_Heal = 219;  local FoLR4_Mana = 90;   -- Avg(206-231) rounded up
    local FoLR5_Heal = 294;  local FoLR5_Mana = 115;  -- Avg(278-310)
    local FoLR6_Heal = 369;  local FoLR6_Mana = 140;  -- Avg(348-389) rounded up
    local FoLR7_Heal = 461;  local FoLR7_Mana = 180;  -- Avg(428-493) rounded up, Mana updated

    local HLR1_Heal = 47;    local HLR1_Mana = 35;    -- Avg(42-51) rounded up, Mana updated
    local HLR2_Heal = 89;    local HLR2_Mana = 60;    -- Avg(81-96) rounded up
    local HLR3_Heal = 182;   local HLR3_Mana = 110;   -- Avg(167-196) rounded up
    local HLR4_Heal = 345;   local HLR4_Mana = 190;   -- Avg(322-368)
    local HLR5_Heal = 538;   local HLR5_Mana = 275;   -- Avg(506-569) rounded up
    local HLR6_Heal = 758;   local HLR6_Mana = 365;   -- Avg(717-799)
    local HLR7_Heal = 1022;  local HLR7_Mana = 465;   -- Avg(968-1076)
    local HLR8_Heal = 1343;  local HLR8_Mana = 580;   -- Avg(1272-1414)
    local HLR9_Heal = 1680;  local HLR9_Mana = 660;   -- Avg(1590-1770)

    if not forceMaxHPS then
        -- Efficiency Mode: Choose the smallest rank that covers the healneed (with combat compensation)
        if Health < RatioFull then -- Only heal if target is below the "Full" threshold defined in settings
            -- Default to rank 1 of FL (if available) or HL
            if maxRankFL >= 1 then SpellID = SpellIDsFL[1]; HealSize = FoLR1_Heal*hlMod+healMod15 else SpellID = SpellIDsHL[1]; HealSize = HLR1_Heal*hlMod+healMod25*PF1 end

            -- Holy Light Rank 2 (Only if target healthy and lower FoL not enough, or no FoL)
            if healneed > ( HLR2_Heal*hlMod+healMod25*PF6 )*K and ManaLeft >= HLR2_Mana and maxRankHL >=2 and (TargetIsHealthy and maxRankFL <= 1 or NoFL) then SpellID = SpellIDsHL[2]; HealSize = HLR2_Heal*hlMod+healMod25*PF6 end
            -- Flash of Light Rank 2
            if healneed > (FoLR2_Heal*hlMod+healMod15)*k and ManaLeft >= FoLR2_Mana and maxRankFL >=2 and downRankFH >= 2 then SpellID = SpellIDsFL[2]; HealSize = FoLR2_Heal*hlMod+healMod15 end
            -- Flash of Light Rank 3
            if healneed > (FoLR3_Heal*hlMod+healMod15)*k and ManaLeft >= FoLR3_Mana and maxRankFL >=3 and downRankFH >= 3 then SpellID = SpellIDsFL[3]; HealSize = FoLR3_Heal*hlMod+healMod15 end
            -- Holy Light Rank 3 (Only if target healthy and lower FoL not enough, or no FoL)
            if healneed > ( HLR3_Heal*hlMod+healMod25*PF14)*K and ManaLeft >= HLR3_Mana and maxRankHL >=3 and (TargetIsHealthy and maxRankFL <= 3 or NoFL) then SpellID = SpellIDsHL[3]; HealSize = HLR3_Heal*hlMod+healMod25*PF14 end
            -- Flash of Light Rank 4
            if healneed > (FoLR4_Heal*hlMod+healMod15)*k and ManaLeft >= FoLR4_Mana and maxRankFL >=4 and downRankFH >= 4 then SpellID = SpellIDsFL[4]; HealSize = FoLR4_Heal*hlMod+healMod15 end
            -- Flash of Light Rank 5
            if healneed > (FoLR5_Heal*hlMod+healMod15)*k and ManaLeft >= FoLR5_Mana and maxRankFL >=5 and downRankFH >= 5 then SpellID = SpellIDsFL[5]; HealSize = FoLR5_Heal*hlMod+healMod15 end
            -- Holy Light Rank 4 (Only if target healthy and lower FoL not enough, or no FoL)
            if healneed > ( HLR4_Heal*hlMod+healMod25)*K and ManaLeft >= HLR4_Mana and maxRankHL >=4 and (TargetIsHealthy and maxRankFL <= 5 or NoFL) then SpellID = SpellIDsHL[4]; HealSize = HLR4_Heal*hlMod+healMod25 end
            -- Flash of Light Rank 6
            if healneed > (FoLR6_Heal*hlMod+healMod15)*k and ManaLeft >= FoLR6_Mana and maxRankFL >=6 and downRankFH >= 6 then SpellID = SpellIDsFL[6]; HealSize = FoLR6_Heal*hlMod+healMod15 end
            -- >>> ADDED: Flash of Light Rank 7 <<<
            if healneed > (FoLR7_Heal*hlMod+healMod15)*k and ManaLeft >= FoLR7_Mana and maxRankFL >=7 and downRankFH >= 7 then SpellID = SpellIDsFL[7]; HealSize = FoLR7_Heal*hlMod+healMod15 end
            -- Holy Light Rank 5 (Only if target healthy and FoL R1-R7 not enough, or no FoL) -- <<<< UPDATED maxRankFL check
            if healneed > ( HLR5_Heal*hlMod+healMod25)*K and ManaLeft >= HLR5_Mana and maxRankHL >=5 and (TargetIsHealthy and maxRankFL <= 7 or NoFL) then SpellID = SpellIDsHL[5]; HealSize = HLR5_Heal*hlMod+healMod25 end
            -- Holy Light Rank 6 (Only if target healthy and FoL R1-R7 not enough, or no FoL) -- <<<< UPDATED maxRankFL check
            if healneed > ( HLR6_Heal*hlMod+healMod25)*K and ManaLeft >= HLR6_Mana and maxRankHL >=6 and (TargetIsHealthy and maxRankFL <= 7 or NoFL) then SpellID = SpellIDsHL[6]; HealSize = HLR6_Heal*hlMod+healMod25 end
            -- Holy Light Rank 7 (Only if target healthy and FoL R1-R7 not enough, or no FoL) -- <<<< UPDATED maxRankFL check
            if healneed > ( HLR7_Heal*hlMod+healMod25)*K and ManaLeft >= HLR7_Mana and maxRankHL >=7 and (TargetIsHealthy and maxRankFL <= 7 or NoFL) then SpellID = SpellIDsHL[7]; HealSize = HLR7_Heal*hlMod+healMod25 end
            -- Holy Light Rank 8 (Only if target healthy and FoL R1-R7 not enough, or no FoL) -- <<<< UPDATED maxRankFL check
            if healneed > ( HLR8_Heal*hlMod+healMod25)*K and ManaLeft >= HLR8_Mana and maxRankHL >=8 and (TargetIsHealthy and maxRankFL <= 7 or NoFL) then SpellID = SpellIDsHL[8]; HealSize = HLR8_Heal*hlMod+healMod25 end
            -- Holy Light Rank 9 (Only if target healthy and FoL R1-R7 not enough, or no FoL) -- <<<< UPDATED maxRankFL check
            if healneed > ( HLR9_Heal*hlMod+healMod25)*K and ManaLeft >= HLR9_Mana and maxRankHL >=9 and (TargetIsHealthy and maxRankFL <= 7 or NoFL) then SpellID = SpellIDsHL[9]; HealSize = HLR9_Heal*hlMod+healMod25 end
        end -- end if Health < RatioFull
    else
        -- Max HPS Mode: Use the highest available Flash of Light rank allowed by mana and downranking settings
        -- (This mode seems to heavily prefer FoL for speed, ignoring HL unless FoL isn't available/allowed)
        if ManaLeft >= FoLR1_Mana and maxRankFL >=1 and downRankFH >= 1 then SpellID = SpellIDsFL[1]; HealSize = FoLR1_Heal*hlMod+healMod15 end
        if ManaLeft >= FoLR2_Mana and maxRankFL >=2 and downRankFH >= 2 then SpellID = SpellIDsFL[2]; HealSize = FoLR2_Heal*hlMod+healMod15 end
        if ManaLeft >= FoLR3_Mana and maxRankFL >=3 and downRankFH >= 3 then SpellID = SpellIDsFL[3]; HealSize = FoLR3_Heal*hlMod+healMod15 end
        if ManaLeft >= FoLR4_Mana and maxRankFL >=4 and downRankFH >= 4 then SpellID = SpellIDsFL[4]; HealSize = FoLR4_Heal*hlMod+healMod15 end
        if ManaLeft >= FoLR5_Mana and maxRankFL >=5 and downRankFH >= 5 then SpellID = SpellIDsFL[5]; HealSize = FoLR5_Heal*hlMod+healMod15 end
        if ManaLeft >= FoLR6_Mana and maxRankFL >=6 and downRankFH >= 6 then SpellID = SpellIDsFL[6]; HealSize = FoLR6_Heal*hlMod+healMod15 end
        -- >>> ADDED: Flash of Light Rank 7 <<<
        if ManaLeft >= FoLR7_Mana and maxRankFL >=7 and downRankFH >= 7 then SpellID = SpellIDsFL[7]; HealSize = FoLR7_Heal*hlMod+healMod15 end
        -- If no FoL is usable, maybe default to highest HL? Original code doesn't seem to handle this edge case well in MaxHPS mode.
    end -- end if not forceMaxHPS / else

    -- Apply target's healing debuff modifier AFTER selecting the spell and calculating its potential heal
    return SpellID,HealSize*HDB;
end

function QuickHeal_Paladin_FindHealSpellToUseNoTarget(maxhealth, healDeficit, healType, multiplier, forceMaxHPS, forceMaxRank, hdb, incombat)
    local SpellID = nil;
    local HealSize = 0;
    local Overheal = false;

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
    local Health = (maxhealth - healDeficit) / maxhealth; -- Calculate current health ratio

    -- if BonusScanner is running, get +Healing bonus
    local Bonus = 0;
    if (BonusScanner) then
        Bonus = tonumber(BonusScanner:GetBonus("HEAL"));
        debug(string.format("Equipment Healing Bonus: %d", Bonus));
    end

    -- Calculate healing bonus
    local healMod15 = (1.5/3.5) * Bonus; -- For Flash of Light (1.5s cast)
    local healMod25 = (2.5/3.5) * Bonus; -- For Holy Light (2.5s cast)
    debug("Final Healing Bonus (1.5,2.5)", healMod15,healMod25);

    local InCombat = UnitAffectingCombat('player') or incombat;

    -- Healing Light Talent (increases healing by 4% per rank)
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,5);
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
        InCombat = false;
    end

    -- Get total healing modifier (factor) caused by healing target debuffs
    -- local HDB = QuickHeal_GetHealModifier(Target); -- Using passed 'hdb' argument instead
    -- debug("Target debuff healing modifier",hdb);
    healneed = healneed/hdb;

    -- Get a list of ranks available of 'Holy Light' and 'Flash of Light'
    local SpellIDsHL = GetSpellIDs(QUICKHEAL_SPELL_HOLY_LIGHT);
    local SpellIDsFL = GetSpellIDs(QUICKHEAL_SPELL_FLASH_OF_LIGHT);
    local maxRankHL = table.getn(SpellIDsHL);
    local maxRankFL = table.getn(SpellIDsFL);
    local NoFL = maxRankFL < 1;
    debug(string.format("Found HL up to rank %d, and found FL up to rank %d", maxRankHL, maxRankFL))

    --Get max HealRanks that are allowed to be used
    local downRankFH = QuickHealVariables.DownrankValueFH  -- rank for 1.5 sec heals (Flash of Light)
    local downRankNH = QuickHealVariables.DownrankValueNH -- rank for 2.5 sec heals (Holy Light) - *Note: Original code seems to mix these up in comments*


    -- below changed to not differentiate between in or out if combat. Original code down below
    -- Find suitable SpellID based on the defined criteria
    local k = 1; -- Factor for 1.5s cast spells
    local K = 1; -- Factor for 2.5s cast spells
    if InCombat then
        k = 0.9; -- In combat means that target is loosing life while casting, so compensate
        K = 0.8; -- k for fast spells (FL) and K for slow spells (HL)
    end

    -- Base Heal values from 1.12.1 (average where applicable) - UPDATED VALUES
    local FoLR1_Heal = 72;   local FoLR1_Mana = 35;   -- Avg(67-77)
    local FoLR2_Heal = 110;  local FoLR2_Mana = 50;   -- Avg(102-117) rounded up
    local FoLR3_Heal = 162;  local FoLR3_Mana = 70;   -- Avg(153-171)
    local FoLR4_Heal = 219;  local FoLR4_Mana = 90;   -- Avg(206-231) rounded up
    local FoLR5_Heal = 294;  local FoLR5_Mana = 115;  -- Avg(278-310)
    local FoLR6_Heal = 369;  local FoLR6_Mana = 140;  -- Avg(348-389) rounded up
    local FoLR7_Heal = 461;  local FoLR7_Mana = 180;  -- Avg(428-493) rounded up, Mana updated

    local HLR1_Heal = 47;    local HLR1_Mana = 35;    -- Avg(42-51) rounded up, Mana updated
    local HLR2_Heal = 89;    local HLR2_Mana = 60;    -- Avg(81-96) rounded up
    local HLR3_Heal = 182;   local HLR3_Mana = 110;   -- Avg(167-196) rounded up
    local HLR4_Heal = 345;   local HLR4_Mana = 190;   -- Avg(322-368)
    local HLR5_Heal = 538;   local HLR5_Mana = 275;   -- Avg(506-569) rounded up
    local HLR6_Heal = 758;   local HLR6_Mana = 365;   -- Avg(717-799)
    local HLR7_Heal = 1022;  local HLR7_Mana = 465;   -- Avg(968-1076)
    local HLR8_Heal = 1343;  local HLR8_Mana = 580;   -- Avg(1272-1414)
    local HLR9_Heal = 1680;  local HLR9_Mana = 660;   -- Avg(1590-1770)

    if not forceMaxHPS then
        -- Efficiency Mode: Choose the smallest rank that covers the healneed (with combat compensation)
        -- Default to rank 1 of FL (if available) or HL
        if maxRankFL >= 1 then SpellID = SpellIDsFL[1]; HealSize = FoLR1_Heal*hlMod+healMod15 else SpellID = SpellIDsHL[1]; HealSize = HLR1_Heal*hlMod+healMod25*PF1 end

        -- Holy Light Rank 2 (Only if target healthy and lower FoL not enough, or no FoL)
        if healneed > ( HLR2_Heal*hlMod+healMod25*PF6 )*K and ManaLeft >= HLR2_Mana and maxRankHL >=2 and (TargetIsHealthy and maxRankFL <= 1 or NoFL) then SpellID = SpellIDsHL[2]; HealSize = HLR2_Heal*hlMod+healMod25*PF6 end
        -- Flash of Light Rank 2
        if healneed > (FoLR2_Heal*hlMod+healMod15)*k and ManaLeft >= FoLR2_Mana and maxRankFL >=2 and downRankFH >= 2 then SpellID = SpellIDsFL[2]; HealSize = FoLR2_Heal*hlMod+healMod15 end
        -- Flash of Light Rank 3
        if healneed > (FoLR3_Heal*hlMod+healMod15)*k and ManaLeft >= FoLR3_Mana and maxRankFL >=3 and downRankFH >= 3 then SpellID = SpellIDsFL[3]; HealSize = FoLR3_Heal*hlMod+healMod15 end
        -- Holy Light Rank 3 (Only if target healthy and lower FoL not enough, or no FoL)
        if healneed > ( HLR3_Heal*hlMod+healMod25*PF14)*K and ManaLeft >= HLR3_Mana and maxRankHL >=3 and (TargetIsHealthy and maxRankFL <= 3 or NoFL) then SpellID = SpellIDsHL[3]; HealSize = HLR3_Heal*hlMod+healMod25*PF14 end
        -- Flash of Light Rank 4
        if healneed > (FoLR4_Heal*hlMod+healMod15)*k and ManaLeft >= FoLR4_Mana and maxRankFL >=4 and downRankFH >= 4 then SpellID = SpellIDsFL[4]; HealSize = FoLR4_Heal*hlMod+healMod15 end
        -- Flash of Light Rank 5
        if healneed > (FoLR5_Heal*hlMod+healMod15)*k and ManaLeft >= FoLR5_Mana and maxRankFL >=5 and downRankFH >= 5 then SpellID = SpellIDsFL[5]; HealSize = FoLR5_Heal*hlMod+healMod15 end
        -- Holy Light Rank 4 (Only if target healthy and lower FoL not enough, or no FoL)
        if healneed > ( HLR4_Heal*hlMod+healMod25)*K and ManaLeft >= HLR4_Mana and maxRankHL >=4 and (TargetIsHealthy and maxRankFL <= 5 or NoFL) then SpellID = SpellIDsHL[4]; HealSize = HLR4_Heal*hlMod+healMod25 end
        -- Flash of Light Rank 6
        if healneed > (FoLR6_Heal*hlMod+healMod15)*k and ManaLeft >= FoLR6_Mana and maxRankFL >=6 and downRankFH >= 6 then SpellID = SpellIDsFL[6]; HealSize = FoLR6_Heal*hlMod+healMod15 end
        -- >>> ADDED: Flash of Light Rank 7 <<<
        if healneed > (FoLR7_Heal*hlMod+healMod15)*k and ManaLeft >= FoLR7_Mana and maxRankFL >=7 and downRankFH >= 7 then SpellID = SpellIDsFL[7]; HealSize = FoLR7_Heal*hlMod+healMod15 end
        -- Holy Light Rank 5 (Only if target healthy and FoL R1-R7 not enough, or no FoL) -- <<<< UPDATED maxRankFL check
        if healneed > ( HLR5_Heal*hlMod+healMod25)*K and ManaLeft >= HLR5_Mana and maxRankHL >=5 and (TargetIsHealthy and maxRankFL <= 7 or NoFL) then SpellID = SpellIDsHL[5]; HealSize = HLR5_Heal*hlMod+healMod25 end
        -- Holy Light Rank 6 (Only if target healthy and FoL R1-R7 not enough, or no FoL) -- <<<< UPDATED maxRankFL check
        if healneed > ( HLR6_Heal*hlMod+healMod25)*K and ManaLeft >= HLR6_Mana and maxRankHL >=6 and (TargetIsHealthy and maxRankFL <= 7 or NoFL) then SpellID = SpellIDsHL[6]; HealSize = HLR6_Heal*hlMod+healMod25 end
        -- Holy Light Rank 7 (Only if target healthy and FoL R1-R7 not enough, or no FoL) -- <<<< UPDATED maxRankFL check
        if healneed > ( HLR7_Heal*hlMod+healMod25)*K and ManaLeft >= HLR7_Mana and maxRankHL >=7 and (TargetIsHealthy and maxRankFL <= 7 or NoFL) then SpellID = SpellIDsHL[7]; HealSize = HLR7_Heal*hlMod+healMod25 end
        -- Holy Light Rank 8 (Only if target healthy and FoL R1-R7 not enough, or no FoL) -- <<<< UPDATED maxRankFL check
        if healneed > ( HLR8_Heal*hlMod+healMod25)*K and ManaLeft >= HLR8_Mana and maxRankHL >=8 and (TargetIsHealthy and maxRankFL <= 7 or NoFL) then SpellID = SpellIDsHL[8]; HealSize = HLR8_Heal*hlMod+healMod25 end
        -- Holy Light Rank 9 (Only if target healthy and FoL R1-R7 not enough, or no FoL) -- <<<< UPDATED maxRankFL check
        if healneed > ( HLR9_Heal*hlMod+healMod25)*K and ManaLeft >= HLR9_Mana and maxRankHL >=9 and (TargetIsHealthy and maxRankFL <= 7 or NoFL) then SpellID = SpellIDsHL[9]; HealSize = HLR9_Heal*hlMod+healMod25 end
    else
        -- Max HPS Mode: Use the highest available Flash of Light rank allowed by mana and downranking settings
        -- (This mode seems to heavily prefer FoL for speed, ignoring HL unless FoL isn't available/allowed)
        if ManaLeft >= FoLR1_Mana and maxRankFL >=1 and downRankFH >= 1 then SpellID = SpellIDsFL[1]; HealSize = FoLR1_Heal*hlMod+healMod15 end
        if ManaLeft >= FoLR2_Mana and maxRankFL >=2 and downRankFH >= 2 then SpellID = SpellIDsFL[2]; HealSize = FoLR2_Heal*hlMod+healMod15 end
        if ManaLeft >= FoLR3_Mana and maxRankFL >=3 and downRankFH >= 3 then SpellID = SpellIDsFL[3]; HealSize = FoLR3_Heal*hlMod+healMod15 end
        if ManaLeft >= FoLR4_Mana and maxRankFL >=4 and downRankFH >= 4 then SpellID = SpellIDsFL[4]; HealSize = FoLR4_Heal*hlMod+healMod15 end
        if ManaLeft >= FoLR5_Mana and maxRankFL >=5 and downRankFH >= 5 then SpellID = SpellIDsFL[5]; HealSize = FoLR5_Heal*hlMod+healMod15 end
        if ManaLeft >= FoLR6_Mana and maxRankFL >=6 and downRankFH >= 6 then SpellID = SpellIDsFL[6]; HealSize = FoLR6_Heal*hlMod+healMod15 end
        -- >>> ADDED: Flash of Light Rank 7 <<<
        if ManaLeft >= FoLR7_Mana and maxRankFL >=7 and downRankFH >= 7 then SpellID = SpellIDsFL[7]; HealSize = FoLR7_Heal*hlMod+healMod15 end
        -- If no FoL is usable, maybe default to highest HL? Original code doesn't seem to handle this edge case well in MaxHPS mode.
    end -- end if not forceMaxHPS / else

    -- Apply target's healing debuff modifier AFTER selecting the spell and calculating its potential heal
    return SpellID,HealSize*hdb;
end

function QuickHeal_Command_Paladin(msg)

    --if PlayerClass == "priest" then
    --  writeLine("PALADIN", 0, 1, 0);
    --end

    local _, _, arg1, arg2, arg3 = string.find(msg, "%s?(%w+)%s?(%w+)%s?(%w+)")

    -- match 3 arguments
    if arg1 ~= nil and arg2 ~= nil and arg3 ~= nil then
        if arg1 == "player" or arg1 == "target" or arg1 == "targettarget" or arg1 == "party" or arg1 == "subgroup" or arg1 == "mt" or arg1 == "nonmt" then
            if arg2 == "heal" and arg3 == "max" then
                --writeLine(QuickHealData.name .. " qh " .. arg1 .. " HEAL(maxHPS)", 0, 1, 0);
                --QuickHeal(arg1, nil, nil, true);
                QuickHeal(arg1, nil, nil, true);
                return;
            end
        end
    end

    -- match 2 arguments
    local _, _, arg4, arg5= string.find(msg, "%s?(%w+)%s?(%w+)")

    if arg4 ~= nil and arg5 ~= nil then
        if arg4 == "debug" then
            if arg5 == "on" then
                QHV.DebugMode = true;
                --writeLine(QuickHealData.name .. " debug mode enabled", 0, 0, 1);
                return;
            elseif arg5 == "off" then
                QHV.DebugMode = false;
                --writeLine(QuickHealData.name .. " debug mode disabled", 0, 0, 1);
                return;
            end
        end
        if arg4 == "heal" and arg5 == "max" then
            --writeLine(QuickHealData.name .. " HEAL (max)", 0, 1, 0);
            QuickHeal(nil, nil, nil, true);
            return;
        end
        if arg4 == "player" or arg4 == "target" or arg4 == "targettarget" or arg4 == "party" or arg4 == "subgroup" or arg4 == "mt" or arg4 == "nonmt" then
            if arg5 == "heal" then
                --writeLine(QuickHealData.name .. " qh " .. arg1 .. " HEAL", 0, 1, 0);
                QuickHeal(arg1, nil, nil, false);
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
        ToggleDownrankWindow()
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
        --writeLine(QuickHealData.name .. " HEAL", 0, 1, 0);
        QuickHeal();
        return;
    end

    if cmd == "" then
        --writeLine(QuickHealData.name .. " qh", 0, 1, 0);
        QuickHeal(nil);
        return;
    elseif cmd == "player" or cmd == "target" or cmd == "targettarget" or cmd == "party" or cmd == "subgroup" or cmd == "mt" or cmd == "nonmt" then
        --writeLine(QuickHealData.name .. " qh " .. cmd, 0, 1, 0);
        QuickHeal(cmd);
        return;
    end

    -- Print usage information if arguments do not match
    --writeLine(QuickHealData.name .. " Usage:");
    writeLine("== QUICKHEAL USAGE : PALADIN ==");
    writeLine("/qh cfg - Opens up the configuration panel.");
    writeLine("/qh toggle - Switches between High HPS and Normal HPS.  Heals (Healthy Threshold 0% or 100%).");
    writeLine("/qh downrank | dr - Opens the slider to limit QuickHeal to constrain healing to lower ranks.");
    writeLine("/qh tanklist | tl - Toggles display of the main tank list UI.");
    writeLine("/qh [mask] [type] [mod] - Heals the party/raid member that most needs it with the best suited healing spell.");
    writeLine(" [mask] constrains healing pool to:");
    writeLine("  [player] yourself");
    writeLine("  [target] your target");
    writeLine("  [targettarget] your target's target");
    writeLine("  [party] your party");
    writeLine("  [mt] main tanks (defined in the configuration panel)");
    writeLine("  [nonmt] everyone but the main tanks");
    writeLine("  [subgroup] raid subgroups (defined in the configuration panel)");

    writeLine(" [mod] (optional) modifies [heal] options:");
    writeLine("  [max] applies maximum rank HPS [heal] to subgroup members that have <100% health");

    writeLine("/qh reset - Reset configuration to default parameters for all classes.");
end