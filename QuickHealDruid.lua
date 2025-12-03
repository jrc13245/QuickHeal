local function writeLine(s,r,g,b)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(s, r or 1, g or 1, b or 0.5)
    end
end

function QuickHeal_Druid_GetRatioHealthyExplanation()
    local RatioHealthy = QuickHeal_GetRatioHealthy();
    local RatioFull = QuickHealVariables["RatioFull"];

    if RatioHealthy >= RatioFull then
        return QUICKHEAL_SPELL_REGROWTH .. " will always be used in and out of combat, and "  .. QUICKHEAL_SPELL_HEALING_TOUCH .. " will never be used. ";
    else
        if RatioHealthy > 0 then
            return QUICKHEAL_SPELL_REGROWTH .. " will be used in combat if the target has less than " .. RatioHealthy*100 .. "% life, and " .. QUICKHEAL_SPELL_HEALING_TOUCH .. " will be used otherwise. ";
        else
            return QUICKHEAL_SPELL_REGROWTH .. " will never be used. " .. QUICKHEAL_SPELL_HEALING_TOUCH .. " will always be used in and out of combat. ";
        end
    end
end

function QuickHeal_Druid_FindHealSpellToUse(Target, healType, multiplier, forceMaxHPS)
    local SpellID = nil;
    local HealSize = 0;
    local Overheal = false;
    local ForceHTinCombat = false;
    local NaturesGrace = false;

    -- +Healing-PenaltyFactor = (1-((20-LevelLearnt)*0.0375)) for all spells learnt before level 20
    local PF1 = 0.2875;
    local PF8 = 0.55;
    local PFRG1 = 0.7 * 1.042; -- Rank 1 of RG (1.041 compensates for the 0.50 factor that should be 0.48 for RG1)
    local PF14 = 0.775;
    local PFRG2 = 0.925;

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
    local healMod20 = (2.0/3.5) * Bonus;
    local healMod25 = (2.5/3.5) * Bonus;
    local healMod30 = (3.0/3.5) * Bonus;
    local healMod35 = Bonus;
    local healModRG = (2.0/3.5) * Bonus * 0.5; -- The 0.5 factor is calculated as DirectHeal/(DirectHeal+HoT)
    debug("Final Healing Bonus (1.5,2.0,2.5,3.0,3.5,Regrowth)", healMod15,healMod20,healMod25,healMod30,healMod35,healModRG);

    local InCombat = UnitAffectingCombat('player') or UnitAffectingCombat(Target);

    -- Gift of Nature - Increases healing by 2% per rank
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,9); 
    local gonMod = 2*talentRank/100 + 1;
    debug(string.format("Gift of Nature modifier: %f", gonMod));

    -- Tranquil Spirit - Decreases mana usage by 2% per rank on HT only
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,10); 
    local tsMod = 1 - 2*talentRank/100;
    debug(string.format("Tranquil Spirit modifier: %f", tsMod));

    -- Moonglow - Decrease mana usage by 3% per rank
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,13); 
    local mgMod = 1 - 3*talentRank/100;
    debug(string.format("Moonglow modifier: %f", mgMod));

    -- Improved Regrowth Talent (increases Regrowth effect by 5% per rank, as crit is 50% bonus only)
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,14);
    local iregMod = 5*talentRank/100 + 1;
    debug(string.format("Improved Regrowth talentmodification: %f", iregMod))

    local TargetIsHealthy = Health >= RatioHealthy;
    local ManaLeft = UnitMana('player');

    if TargetIsHealthy then
        debug("Target is healthy ",Health);
    end
    
    -- Detect Clearcasting (from Omen of Clarity, talent(1,10))
    if QuickHeal_DetectBuff('player',"Spell_Shadow_ManaBurn",1) then -- Spell_Shadow_ManaBurn (1)
        ManaLeft = UnitManaMax('player');  -- set to max mana so max spell rank will be cast
        healneed = 10^6; -- deliberate overheal (mana is free)
        debug("BUFF: Clearcasting (Omen of Clarity)");
    end

    -- Detect Nature's Swiftness (next nature spell is instant cast)
    if QuickHeal_DetectBuff('player',"Spell_Nature_RavenForm") then
        debug("BUFF: Nature's Swiftness (out of combat healing forced)");
        ForceHTinCombat = true;
    end

    -- Detect proc of 'Hand of Edward the Odd' mace (next spell is instant cast)
    if QuickHeal_DetectBuff('player',"Spell_Holy_SearingLight") then
        debug("BUFF: Hand of Edward the Odd (out of combat healing forced)");
        InCombat = false;
    end

    -------------------------------------------

    -- Detect Wushoolay's Charm of Nature (Trinket from Zul'Gurub, Madness event)
    if QuickHeal_DetectBuff('player',"Spell_Nature_Regenerate") then
        debug("BUFF: Wushoolay (healing touch forced)");
        ForceHTinCombat = true;
    end

    if QuickHeal_DetectBuff('player',"Spell_Nature_NaturesBlessing") then
        NaturesGrace = true;
    end

    -------------------------------------------

    -- Get total healing modifier (factor) caused by healing target debuffs
    local HDB = QuickHeal_GetHealModifier(Target);
    debug("Target debuff healing modifier",HDB);
    healneed = healneed/HDB;

    -- Get a list of ranks available for all spells
    local SpellIDsHT = GetSpellIDs(QUICKHEAL_SPELL_HEALING_TOUCH);
    local SpellIDsRG = GetSpellIDs(QUICKHEAL_SPELL_REGROWTH);

    local maxRankHT = table.getn(SpellIDsHT);
    local maxRankRG = table.getn(SpellIDsRG);
    
    debug(string.format("Found HT up to rank %d, RG up to rank %d", maxRankHT, maxRankRG));

    --Get max HealRanks that are allowed to be used
    local downRankFH = QuickHealVariables.DownrankValueFH or 0  -- rank for RG
    local downRankNH = QuickHealVariables.DownrankValueNH or 0 -- rank for HT

    -- Compensation for health lost during combat
    local k=1.0;
    local K=1.0;
    if InCombat then
        k=0.9;
        K=0.8;
    end


    if TargetIsHealthy or maxRankRG<1 then
        -- target is healthy so use the closest available mana efficient healing
        debug(string.format("target healthy or no Regrowth available, will use Healing Touch"))
        if Health < RatioFull then
            SpellID = SpellIDsHT[1]; HealSize = (44+healMod15*PF1)*gonMod; -- Default to rank 1
            if healneed > ( 100+healMod20*PF8)*gonMod*k and ManaLeft >=  55*tsMod*mgMod and maxRankHT >=  2 and downRankNH >= 2 and SpellIDsHT[2] then SpellID =  SpellIDsHT[2]; HealSize =  (100+healMod20*PF8)*gonMod end
            if healneed > ( 219+healMod25*PF14)*gonMod*K and ManaLeft >= 110*tsMod*mgMod and maxRankHT >=  3 and downRankNH >= 3 and SpellIDsHT[3] then SpellID =  SpellIDsHT[3]; HealSize =  (219+healMod25*PF14)*gonMod end
            if healneed > ( 404+healMod30)*gonMod*K and ManaLeft >= 185*tsMod*mgMod and maxRankHT >=  4 and downRankNH >= 4 and downRankNH >= 4 and SpellIDsHT[4] then SpellID =  SpellIDsHT[4]; HealSize =  (404+healMod30)*gonMod end
            if healneed > ( 633+healMod35)*gonMod*K and ManaLeft >= 270*tsMod*mgMod and maxRankHT >=  5 and downRankNH >= 5 and SpellIDsHT[5] then SpellID =  SpellIDsHT[5]; HealSize =  (633+healMod35)*gonMod end
            if healneed > ( 818+healMod35)*gonMod*K and ManaLeft >= 335*tsMod*mgMod and maxRankHT >=  6 and downRankNH >= 6 and SpellIDsHT[6] then SpellID =  SpellIDsHT[6]; HealSize =  (818+healMod35)*gonMod end
            if healneed > (1028+healMod35)*gonMod*K and ManaLeft >= 405*tsMod*mgMod and maxRankHT >=  7 and downRankNH >= 7 and SpellIDsHT[7] then SpellID =  SpellIDsHT[7]; HealSize = (1028+healMod35)*gonMod end
            if healneed > (1313+healMod35)*gonMod*K and ManaLeft >= 495*tsMod*mgMod and maxRankHT >=  8 and downRankNH >= 8 and SpellIDsHT[8] then SpellID =  SpellIDsHT[8]; HealSize = (1313+healMod35)*gonMod end
            if healneed > (1656+healMod35)*gonMod*K and ManaLeft >= 600*tsMod*mgMod and maxRankHT >=  9 and downRankNH >= 9 and SpellIDsHT[9] then SpellID =  SpellIDsHT[9]; HealSize = (1656+healMod35)*gonMod end
            if healneed > (2060+healMod35)*gonMod*K and ManaLeft >= 720*tsMod*mgMod and maxRankHT >= 10 and downRankNH >= 10 and SpellIDsHT[10] then SpellID = SpellIDsHT[10]; HealSize = (2060+healMod35)*gonMod end
            if healneed > (2472+healMod35)*gonMod*K and ManaLeft >= 800*tsMod*mgMod and maxRankHT >= 11 and downRankNH >= 11 and SpellIDsHT[11] then SpellID = SpellIDsHT[11]; HealSize = (2472+healMod35)*gonMod end
        end
    elseif ForceHTinCombat then
        SpellID = SpellIDsHT[1]; HealSize = (44+healMod15*PF1)*gonMod; -- Default to rank 1
        if healneed > (100+healMod20*PF8)*gonMod*k and ManaLeft >=  55*tsMod*mgMod and maxRankHT >=  2 and downRankNH >= 2 and SpellIDsHT[2] then SpellID =  SpellIDsHT[2]; HealSize =  (100+healMod20*PF8)*gonMod end
        if healneed > (219+healMod25*PF14)*gonMod*K and ManaLeft >= 110*tsMod*mgMod and maxRankHT >=  3 and downRankNH >= 3 and SpellIDsHT[3] then SpellID =  SpellIDsHT[3]; HealSize =  (219+healMod25*PF14)*gonMod end
        if healneed > (404+healMod30)*gonMod*K and ManaLeft >= 185*tsMod*mgMod and maxRankHT >=  4 and downRankNH >= 4 and SpellIDsHT[4] then SpellID =  SpellIDsHT[4]; HealSize =  (404+healMod30)*gonMod end
        if healneed > (633+healMod35)*gonMod*K and ManaLeft >= 270*tsMod*mgMod and maxRankHT >=  5 and downRankNH >= 5 and SpellIDsHT[5] then SpellID =  SpellIDsHT[5]; HealSize =  (633+healMod35)*gonMod end
        if healneed > (818+healMod35)*gonMod*K and ManaLeft >= 335*tsMod*mgMod and maxRankHT >=  6 and downRankNH >= 6 and SpellIDsHT[6] then SpellID =  SpellIDsHT[6]; HealSize =  (818+healMod35)*gonMod end
        if healneed > (1028+healMod35)*gonMod*K and ManaLeft >= 405*tsMod*mgMod and maxRankHT >=  7 and downRankNH >= 7 and SpellIDsHT[7] then SpellID =  SpellIDsHT[7]; HealSize = (1028+healMod35)*gonMod end
        if healneed > (1313+healMod35)*gonMod*K and ManaLeft >= 495*tsMod*mgMod and maxRankHT >=  8 and downRankNH >= 8 and SpellIDsHT[8] then SpellID =  SpellIDsHT[8]; HealSize = (1313+healMod35)*gonMod end
        if healneed > (1656+healMod35)*gonMod*K and ManaLeft >= 600*tsMod*mgMod and maxRankHT >=  9 and downRankNH >= 9 and SpellIDsHT[9] then SpellID =  SpellIDsHT[9]; HealSize = (1656+healMod35)*gonMod end
        if healneed > (2060+healMod35)*gonMod*K and ManaLeft >= 720*tsMod*mgMod and maxRankHT >= 10 and downRankNH >= 10 and SpellIDsHT[10] then SpellID = SpellIDsHT[10]; HealSize = (2060+healMod35)*gonMod end
        if healneed > (2472+healMod35)*gonMod*K and ManaLeft >= 800*tsMod*mgMod and maxRankHT >= 11 and downRankNH >= 11 and SpellIDsHT[11] then SpellID = SpellIDsHT[11]; HealSize = (2472+healMod35)*gonMod end
    else
        -- target is unhealthy and player has Regrowth
        debug(string.format("In combat and target unhealthy and Regrowth available, will use Regrowth"));
        if Health < RatioFull then
            SpellID = SpellIDsRG[1]; HealSize = (91+healModRG*PFRG1)*iregMod*gonMod; -- Default to rank 1
            if healneed > (176+healModRG*PFRG2)*iregMod*gonMod*k and ManaLeft >= 164*tsMod*mgMod and maxRankRG >= 2 and downRankFH >= 2 and SpellIDsRG[2] then SpellID = SpellIDsRG[2]; HealSize =  (176+healModRG*PFRG2)*iregMod*gonMod end
            if healneed > (257+healModRG)*iregMod*gonMod*k and ManaLeft >= 224*tsMod*mgMod and maxRankRG >= 3 and downRankFH >= 3 and SpellIDsRG[3] then SpellID = SpellIDsRG[3]; HealSize =  (257+healModRG)*iregMod*gonMod end
            if healneed > (339+healModRG)*iregMod*gonMod*k and ManaLeft >= 280*tsMod*mgMod and maxRankRG >= 4 and downRankFH >= 4 and SpellIDsRG[4] then SpellID = SpellIDsRG[4]; HealSize =  (339+healModRG)*iregMod*gonMod end
            if healneed > (431+healModRG)*iregMod*gonMod*k and ManaLeft >= 336*tsMod*mgMod and maxRankRG >= 5 and downRankFH >= 5 and SpellIDsRG[5] then SpellID = SpellIDsRG[5]; HealSize =  (431+healModRG)*iregMod*gonMod end
            if healneed > (543+healModRG)*iregMod*gonMod*k and ManaLeft >= 408*tsMod*mgMod and maxRankRG >= 6 and downRankFH >= 6 and SpellIDsRG[6] then SpellID = SpellIDsRG[6]; HealSize =  (543+healModRG)*iregMod*gonMod end
            if healneed > (686+healModRG)*iregMod*gonMod*k and ManaLeft >= 492*tsMod*mgMod and maxRankRG >= 7 and downRankFH >= 7 and SpellIDsRG[7] then SpellID = SpellIDsRG[7]; HealSize =  (686+healModRG)*iregMod*gonMod end
            if healneed > (857+healModRG)*iregMod*gonMod*k and ManaLeft >= 592*tsMod*mgMod and maxRankRG >= 8 and downRankFH >= 8 and SpellIDsRG[8] then SpellID = SpellIDsRG[8]; HealSize =  (857+healModRG)*iregMod*gonMod end
            if healneed > (1061+healModRG)*iregMod*gonMod*k and ManaLeft >= 704*tsMod*mgMod and maxRankRG >= 9 and downRankFH >= 9 and SpellIDsRG[9] then SpellID = SpellIDsRG[9]; HealSize = (1061+healModRG)*iregMod*gonMod end
        end
    end
    
    return SpellID,HealSize*HDB;
end

function QuickHeal_Druid_FindHealSpellToUseNoTarget(maxhealth, healDeficit, healType, multiplier, forceMaxHPS, forceMaxRank, hdb, incombat)
    local SpellID = nil;
    local HealSize = 0;
    local Overheal = false;
    local ForceHTinCombat = false;

    -- +Healing-PenaltyFactor = (1-((20-LevelLearnt)*0.0375)) for all spells learnt before level 20
    local PF1 = 0.2875;
    local PF8 = 0.55;
    local PFRG1 = 0.7 * 1.042; -- Rank 1 of RG (1.041 compensates for the 0.50 factor that should be 0.48 for RG1)
    local PF14 = 0.775;
    local PFRG2 = 0.925;

    -- Local aliases to access main module functionality and settings
    local RatioFull = QuickHealVariables["RatioFull"];
    local RatioHealthy = QuickHeal_GetRatioHealthy();
    local UnitHasHealthInfo = QuickHeal_UnitHasHealthInfo;
    local EstimateUnitHealNeed = QuickHeal_EstimateUnitHealNeed;
    local GetSpellIDs = QuickHeal_GetSpellIDs;
    local debug = QuickHeal_debug;

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
    local healMod20 = (2.0/3.5) * Bonus;
    local healMod25 = (2.5/3.5) * Bonus;
    local healMod30 = (3.0/3.5) * Bonus;
    local healMod35 = Bonus;
    local healModRG = (2.0/3.5) * Bonus * 0.5; -- The 0.5 factor is calculated as DirectHeal/(DirectHeal+HoT)
    debug("Final Healing Bonus (1.5,2.0,2.5,3.0,3.5,Regrowth)", healMod15,healMod20,healMod25,healMod30,healMod35,healModRG);

    local InCombat = UnitAffectingCombat('player') or incombat;

    -- Gift of Nature - Increases healing by 2% per rank
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,9);
    local gonMod = 2*talentRank/100 + 1;
    debug(string.format("Gift of Nature modifier: %f", gonMod));

    -- Tranquil Spirit - Decreases mana usage by 2% per rank on HT and RG
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,10);
    local tsMod = 1 - 2*talentRank/100;
    debug(string.format("Tranquil Spirit modifier: %f", tsMod));

    -- Moonglow - Decrease mana usage by 3% per rank
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,13);
    local mgMod = 1 - 3*talentRank/100;
    debug(string.format("Moonglow modifier: %f", mgMod));

    -- Improved Regrowth Talent (increases Regrowth effect by 5% per rank, as crit is 50% bonus only)
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,14);
    local iregMod = 5*talentRank/100 + 1;
    debug(string.format("Improved Regrowth talentmodification: %f", iregMod))


    local TargetIsHealthy = Health >= RatioHealthy;
    local ManaLeft = UnitMana('player');

    if TargetIsHealthy then
        debug("Target is healthy ",Health);
    end

    -- Detect Clearcasting (from Omen of Clarity, talent(1,10))
    if QuickHeal_DetectBuff('player',"Spell_Shadow_ManaBurn",1) then -- Spell_Shadow_ManaBurn (1)
        ManaLeft = UnitManaMax('player');  -- set to max mana so max spell rank will be cast
        healneed = 10^6; -- deliberate overheal (mana is free)
        debug("BUFF: Clearcasting (Omen of Clarity)");
    end

    -- Detect Nature's Swiftness (next nature spell is instant cast)
    if QuickHeal_DetectBuff('player',"Spell_Nature_RavenForm") then
        debug("BUFF: Nature's Swiftness (out of combat healing forced)");
        ForceHTinCombat = true;
    end

    -- Detect proc of 'Hand of Edward the Odd' mace (next spell is instant cast)
    if QuickHeal_DetectBuff('player',"Spell_Holy_SearingLight") then
        debug("BUFF: Hand of Edward the Odd (out of combat healing forced)");
        InCombat = false;
    end

    -------------------------------------------

    -- Detect Wushoolay's Charm of Nature (Trinket from Zul'Gurub, Madness event)
    if QuickHeal_DetectBuff('player',"Spell_Nature_Regenerate") then
        debug("BUFF: Nature's Swiftness (out of combat healing forced)");
        ForceHTinCombat = true;
    end

    -- Detect Nature's Grace (next nature spell is hasted by 0.5 seconds)
    if QuickHeal_DetectBuff('player',"Spell_Nature_NaturesBlessing") and healneed < ((219+healMod25*PF14)*gonMod*2.8) and
            not QuickHeal_DetectBuff('player',"Spell_Nature_Regenerate") then
        ManaLeft = 110*tsMod*mgMod;
    end

    -------------------------------------------

    ---- Get total healing modifier (factor) caused by healing target debuffs
    --local HDB = QuickHeal_GetHealModifier(Target);
    --debug("Target debuff healing modifier",HDB);
    healneed = healneed/hdb;

    -- Get a list of ranks available for all spells
    local SpellIDsHT = GetSpellIDs(QUICKHEAL_SPELL_HEALING_TOUCH);
    local SpellIDsRG = GetSpellIDs(QUICKHEAL_SPELL_REGROWTH);
    --local SpellIDsRJ = GetSpellIDs(QUICKHEAL_SPELL_REJUVENATION);

    local maxRankHT = table.getn(SpellIDsHT);
    local maxRankRG = table.getn(SpellIDsRG);
    --local maxRankRJ = table.getn(SpellIDsRJ);

    debug(string.format("Found HT up to rank %d, RG up to rank %d", maxRankHT, maxRankRG));

    --Get max HealRanks that are allowed to be used
    local downRankFH = QuickHealVariables.DownrankValueFH or 0  -- rank for RG
    local downRankNH = QuickHealVariables.DownrankValueNH or 0 -- rank for HT

    -- Compensation for health lost during combat
    local k=1.0;
    local K=1.0;
    if InCombat then
        k=0.9;
        K=0.8;
    end


    if not forceMaxHPS then
        SpellID = SpellIDsHT[1]; HealSize = (44+healMod15*PF1)*gonMod; -- Default to rank 1
        if healneed > ( 100+healMod20*PF8 )*gonMod*k and ManaLeft >=  55*tsMod*mgMod and maxRankHT >=  2 and downRankNH >= 2 and SpellIDsHT[2] then SpellID =  SpellIDsHT[2]; HealSize =  (100+healMod20*PF8)*gonMod end
        if healneed > ( 219+healMod25*PF14)*gonMod*K and ManaLeft >= 110*tsMod*mgMod and maxRankHT >=  3 and downRankNH >= 3 and SpellIDsHT[3] then SpellID =  SpellIDsHT[3]; HealSize =  (219+healMod25*PF14)*gonMod end
        if healneed > ( 404+healMod30)*gonMod*K and ManaLeft >= 185*tsMod*mgMod and maxRankHT >=  4 and downRankNH >= 4 and SpellIDsHT[4] then SpellID =  SpellIDsHT[4]; HealSize =  (404+healMod30)*gonMod end
        if healneed > ( 633+healMod35)*gonMod*K and ManaLeft >= 270*tsMod*mgMod and maxRankHT >=  5 and downRankNH >= 5 and SpellIDsHT[5] then SpellID =  SpellIDsHT[5]; HealSize =  (633+healMod35)*gonMod end
        if healneed > ( 818+healMod35)*gonMod*K and ManaLeft >= 335*tsMod*mgMod and maxRankHT >=  6 and downRankNH >= 6 and SpellIDsHT[6] then SpellID =  SpellIDsHT[6]; HealSize =  (818+healMod35)*gonMod end
        if healneed > (1028+healMod35)*gonMod*K and ManaLeft >= 405*tsMod*mgMod and maxRankHT >=  7 and downRankNH >= 7 and SpellIDsHT[7] then SpellID =  SpellIDsHT[7]; HealSize = (1028+healMod35)*gonMod end
        if healneed > (1313+healMod35)*gonMod*K and ManaLeft >= 495*tsMod*mgMod and maxRankHT >=  8 and downRankNH >= 8 and SpellIDsHT[8] then SpellID =  SpellIDsHT[8]; HealSize = (1313+healMod35)*gonMod end
        if healneed > (1656+healMod35)*gonMod*K and ManaLeft >= 600*tsMod*mgMod and maxRankHT >=  9 and downRankNH >= 9 and SpellIDsHT[9] then SpellID =  SpellIDsHT[9]; HealSize = (1656+healMod35)*gonMod end
        if healneed > (2060+healMod35)*gonMod*K and ManaLeft >= 720*tsMod*mgMod and maxRankHT >= 10 and downRankNH >= 10 and SpellIDsHT[10] then SpellID = SpellIDsHT[10]; HealSize = (2060+healMod35)*gonMod end
        if healneed > (2472+healMod35)*gonMod*K and ManaLeft >= 800*tsMod*mgMod and maxRankHT >= 11 and downRankNH >= 11 and SpellIDsHT[11] then SpellID = SpellIDsHT[11]; HealSize = (2472+healMod35)*gonMod end
    else
        SpellID = SpellIDsRG[1]; HealSize = (91+healModRG*PFRG1)*iregMod*gonMod; -- Default to rank 1
        if healneed > (176+healModRG*PFRG2)*iregMod*gonMod*k and ManaLeft >= 164*tsMod*mgMod and maxRankRG >= 2 and downRankFH >= 2 then SpellID = SpellIDsRG[2]; HealSize =  (176+healModRG*PFRG2)*iregMod*gonMod end
        if healneed > (257+healModRG)*iregMod*gonMod*k and ManaLeft >= 224*tsMod*mgMod and maxRankRG >= 3 and downRankFH >= 3 and SpellIDsRG[3] then SpellID = SpellIDsRG[3]; HealSize =  (257+healModRG)*iregMod*gonMod end
        if healneed > (339+healModRG)*iregMod*gonMod*k and ManaLeft >= 280*tsMod*mgMod and maxRankRG >= 4 and downRankFH >= 4 and SpellIDsRG[4] then SpellID = SpellIDsRG[4]; HealSize =  (339+healModRG)*iregMod*gonMod end
        if healneed > (431+healModRG)*iregMod*gonMod*k and ManaLeft >= 336*tsMod*mgMod and maxRankRG >= 5 and downRankFH >= 5 and SpellIDsRG[5] then SpellID = SpellIDsRG[5]; HealSize =  (431+healModRG)*iregMod*gonMod end
        if healneed > (543+healModRG)*iregMod*gonMod*k and ManaLeft >= 408*tsMod*mgMod and maxRankRG >= 6 and downRankFH >= 6 and SpellIDsRG[6] then SpellID = SpellIDsRG[6]; HealSize =  (543+healModRG)*iregMod*gonMod end
        if healneed > (686+healModRG)*iregMod*gonMod*k and ManaLeft >= 492*tsMod*mgMod and maxRankRG >= 7 and downRankFH >= 7 and SpellIDsRG[7] then SpellID = SpellIDsRG[7]; HealSize =  (686+healModRG)*iregMod*gonMod end
        if healneed > (857+healModRG)*iregMod*gonMod*k and ManaLeft >= 592*tsMod*mgMod and maxRankRG >= 8 and downRankFH >= 8 and SpellIDsRG[8] then SpellID = SpellIDsRG[8]; HealSize =  (857+healModRG)*iregMod*gonMod end
        if healneed > (1061+healModRG)*iregMod*gonMod*k and ManaLeft >= 704*tsMod*mgMod and maxRankRG >= 9 and downRankFH >= 9 and SpellIDsRG[9] then SpellID = SpellIDsRG[9]; HealSize = (1061+healModRG)*iregMod*gonMod end
    end

    return SpellID,HealSize*hdb;
end

function QuickHeal_Druid_FindHoTSpellToUse(Target, healType, forceMaxRank)
    local SpellID = nil;
    local HealSize = 0;

    -- +Healing-PenaltyFactor = (1-((20-LevelLearnt)*0.0375)) for all spells learnt before level 20
    local PF1 = 0.2875;
    local PF8 = 0.55;
    local PFRG1 = 0.7 * 1.042; -- Rank 1 of RG (1.041 compensates for the 0.50 factor that should be 0.48 for RG1)
    local PF14 = 0.775;
    local PFRG2 = 0.925;

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
    local healMod20 = (2.0/3.5) * Bonus;
    local healMod25 = (2.5/3.5) * Bonus;
    local healMod30 = (3.0/3.5) * Bonus;
    local healMod35 = Bonus;
    local healModRG = (2.0/3.5) * Bonus * 0.5; -- The 0.5 factor is calculated as DirectHeal/(DirectHeal+HoT)
    debug("Final Healing Bonus (1.5,2.0,2.5,3.0,3.5,Regrowth)", healMod15,healMod20,healMod25,healMod30,healMod35,healModRG);

    local InCombat = UnitAffectingCombat('player') or UnitAffectingCombat(Target);

    -- Gift of Nature - Increases healing by 2% per rank
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,9);
    local gonMod = 2*talentRank/100 + 1;
    debug(string.format("Gift of Nature modifier: %f", gonMod));

    -- Moonglow - Decrease mana usage by 3% per rank
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,13);
    local mgMod = 1 - 3*talentRank/100;
    debug(string.format("Moonglow modifier: %f", mgMod));

    -- Genesis -- Increases Rejuvenation effects by 5% per rank
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,7);
    local genMod = 5*talentRank/100 + 1;
    debug(string.format("Genesis modifier: %f", genMod));

    local TargetIsHealthy = Health >= RatioHealthy;
    local ManaLeft = UnitMana('player');

    if TargetIsHealthy then
        debug("Target is healthy ",Health);
    end

    -- Detect Clearcasting (from Omen of Clarity, talent(1,10))
    if QuickHeal_DetectBuff('player',"Spell_Shadow_ManaBurn",1) then -- Spell_Shadow_ManaBurn (1)
        ManaLeft = UnitManaMax('player');  -- set to max mana so max spell rank will be cast
        healneed = 10^6; -- deliberate overheal (mana is free)
        debug("BUFF: Clearcasting (Omen of Clarity)");
    end

    -- Get total healing modifier (factor) caused by healing target debuffs
    local HDB = QuickHeal_GetHealModifier(Target);
    debug("Target debuff healing modifier",HDB);
    healneed = healneed/HDB;

    -- Get a list of ranks available for all spells
    local SpellIDsHT = GetSpellIDs(QUICKHEAL_SPELL_HEALING_TOUCH);
    local SpellIDsRG = GetSpellIDs(QUICKHEAL_SPELL_REGROWTH);
    local SpellIDsRJ = GetSpellIDs(QUICKHEAL_SPELL_REJUVENATION);

    local maxRankHT = table.getn(SpellIDsHT);
    local maxRankRG = table.getn(SpellIDsRG);
    local maxRankRJ = table.getn(SpellIDsRJ);

    debug(string.format("Found HT up to rank %d, RG up to rank %d, RJ up to rank %d", maxRankHT, maxRankRG, maxRankRJ));

    -- Compensation for health lost during combat
    local k=1.0;
    local K=1.0;
    if InCombat then
        k=0.9;
        K=0.8;
    end


    if healType == "hot" then

        if not forceMaxRank then
            SpellID = SpellIDsRJ[1]; HealSize = (36+healMod15)*genMod*gonMod; -- Default to Rejuvenation (Rank 1)
            if healneed > (60+healMod15)*genMod*gonMod*k and ManaLeft >= 40*mgMod and maxRankRJ >=2 and SpellIDsRJ[2] then SpellID = SpellIDsRJ[2]; HealSize = (60+healMod15)*genMod*gonMod end
            if healneed > (120+healMod15)*genMod*gonMod*k and ManaLeft >= 75*mgMod and maxRankRJ >=3 and SpellIDsRJ[3] then SpellID = SpellIDsRJ[3]; HealSize = (120+healMod15)*genMod*gonMod end
            if healneed > (180+healMod15)*genMod*gonMod*k and ManaLeft >= 105*mgMod and maxRankRJ >=4 and SpellIDsRJ[4] then SpellID = SpellIDsRJ[4]; HealSize = (180+healMod15)*genMod*gonMod end
            if healneed > (246+healMod15)*genMod*gonMod*k and ManaLeft >= 135*mgMod and maxRankRJ >=5 and SpellIDsRJ[5] then SpellID = SpellIDsRJ[5]; HealSize = (246+healMod15)*genMod*gonMod end
            if healneed > (306+healMod15)*genMod*gonMod*k and ManaLeft >= 160*mgMod and maxRankRJ >=6 and SpellIDsRJ[6] then SpellID = SpellIDsRJ[6]; HealSize = (306+healMod15)*genMod*gonMod end
            if healneed > (390+healMod15)*genMod*gonMod*k and ManaLeft >= 195*mgMod and maxRankRJ >=7 and SpellIDsRJ[7] then SpellID = SpellIDsRJ[7]; HealSize = (390+healMod15)*genMod*gonMod end
            if healneed > (492+healMod15)*genMod*gonMod*k and ManaLeft >= 235*mgMod and maxRankRJ >=8 and SpellIDsRJ[8] then SpellID = SpellIDsRJ[8]; HealSize = (492+healMod15)*genMod*gonMod end
            if healneed > (612+healMod15)*genMod*gonMod*k and ManaLeft >= 280*mgMod and maxRankRJ >=9 and SpellIDsRJ[9] then SpellID = SpellIDsRJ[9]; HealSize = (608+healMod15)*genMod*gonMod end
            if healneed > (756+healMod15)*genMod*gonMod*k and ManaLeft >= 335*mgMod and maxRankRJ >=10 and SpellIDsRJ[10] then SpellID = SpellIDsRJ[10]; HealSize = (756+healMod15)*genMod*gonMod end
            if healneed > (888+healMod15)*genMod*gonMod*k and ManaLeft >= 360*mgMod and maxRankRJ >=11 and SpellIDsRJ[11] then SpellID = SpellIDsRJ[11]; HealSize = (888+healMod15)*genMod*gonMod end
        else
            SpellID = SpellIDsRJ[11]; HealSize = (888+healMod15)*genMod*gonMod
            if maxRankRJ >=1 and SpellIDsRJ[1] then SpellID = SpellIDsRJ[1]; HealSize = (36+healMod15)*genMod*gonMod end
            if maxRankRJ >=2 and SpellIDsRJ[2] then SpellID = SpellIDsRJ[2]; HealSize = (60+healMod15)*genMod*gonMod end
            if maxRankRJ >=3 and SpellIDsRJ[3] then SpellID = SpellIDsRJ[3]; HealSize = (120+healMod15)*genMod*gonMod end
            if maxRankRJ >=4 and SpellIDsRJ[4] then SpellID = SpellIDsRJ[4]; HealSize = (180+healMod15)*genMod*gonMod end
            if maxRankRJ >=5 and SpellIDsRJ[5] then SpellID = SpellIDsRJ[5]; HealSize = (246+healMod15)*genMod*gonMod end
            if maxRankRJ >=6 and SpellIDsRJ[6] then SpellID = SpellIDsRJ[6]; HealSize = (306+healMod15)*genMod*gonMod end
            if maxRankRJ >=7 and SpellIDsRJ[7] then SpellID = SpellIDsRJ[7]; HealSize = (390+healMod15)*genMod*gonMod end
            if maxRankRJ >=8 and SpellIDsRJ[8] then SpellID = SpellIDsRJ[8]; HealSize = (492+healMod15)*genMod*gonMod end
            if maxRankRJ >=9 and SpellIDsRJ[9] then SpellID = SpellIDsRJ[9]; HealSize = (612+healMod15)*genMod*gonMod end
            if maxRankRJ >=10 and SpellIDsRJ[10] then SpellID = SpellIDsRJ[10]; HealSize = (756+healMod15)*genMod*gonMod end
            if maxRankRJ >=11 and SpellIDsRJ[11] then SpellID = SpellIDsRJ[11]; HealSize = (888+healMod15)*genMod*gonMod end
        end
        --end
    end

    return SpellID,HealSize*HDB;
end

function QuickHeal_Druid_FindHoTSpellToUseNoTarget(maxhealth, healDeficit, healType, multiplier, forceMaxHPS, forceMaxRank, hdb, incombat)
    local SpellID = nil;
    local HealSize = 0;

    -- +Healing-PenaltyFactor = (1-((20-LevelLearnt)*0.0375)) for all spells learnt before level 20
    local PF1 = 0.2875;
    local PF8 = 0.55;
    local PFRG1 = 0.7 * 1.042; -- Rank 1 of RG (1.041 compensates for the 0.50 factor that should be 0.48 for RG1)
    local PF14 = 0.775;
    local PFRG2 = 0.925;

    -- Local aliases to access main module functionality and settings
    local RatioFull = QuickHealVariables["RatioFull"];
    local RatioHealthy = QuickHeal_GetRatioHealthy();
    local UnitHasHealthInfo = QuickHeal_UnitHasHealthInfo;
    local EstimateUnitHealNeed = QuickHeal_EstimateUnitHealNeed;
    local GetSpellIDs = QuickHeal_GetSpellIDs;
    local debug = QuickHeal_debug;

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
    local healMod20 = (2.0/3.5) * Bonus;
    local healMod25 = (2.5/3.5) * Bonus;
    local healMod30 = (3.0/3.5) * Bonus;
    local healMod35 = Bonus;
    local healModRG = (2.0/3.5) * Bonus * 0.5; -- The 0.5 factor is calculated as DirectHeal/(DirectHeal+HoT)
    debug("Final Healing Bonus (1.5,2.0,2.5,3.0,3.5,Regrowth)", healMod15,healMod20,healMod25,healMod30,healMod35,healModRG);

    local InCombat = UnitAffectingCombat('player') or incombat;

    -- Gift of Nature - Increases healing by 2% per rank
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,9);
    local gonMod = 2*talentRank/100 + 1;
    debug(string.format("Gift of Nature modifier: %f", gonMod));

    -- Moonglow - Decrease mana usage by 3% per rank
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,13);
    local mgMod = 1 - 3*talentRank/100;
    debug(string.format("Moonglow modifier: %f", mgMod));

    -- Genesis -- Increases Rejuvenation effects by 5% per rank
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,7);
    local genMod = 5*talentRank/100 + 1;
    debug(string.format("Genesis modifier: %f", genMod));

    local TargetIsHealthy = Health >= RatioHealthy;
    local ManaLeft = UnitMana('player');

    if TargetIsHealthy then
        debug("Target is healthy ",Health);
    end

    -- Detect Clearcasting (from Omen of Clarity, talent(1,10))
    if QuickHeal_DetectBuff('player',"Spell_Shadow_ManaBurn",1) then -- Spell_Shadow_ManaBurn (1)
        ManaLeft = UnitManaMax('player');  -- set to max mana so max spell rank will be cast
        healneed = 10^6; -- deliberate overheal (mana is free)
        debug("BUFF: Clearcasting (Omen of Clarity)");
    end


    -- Get total healing modifier (factor) caused by healing target debuffs
    --local HDB = QuickHeal_GetHealModifier(Target);
    --debug("Target debuff healing modifier",HDB);
    healneed = healneed/hdb;

    -- Get a list of ranks available for all spells
    local SpellIDsHT = GetSpellIDs(QUICKHEAL_SPELL_HEALING_TOUCH);
    local SpellIDsRG = GetSpellIDs(QUICKHEAL_SPELL_REGROWTH);
    local SpellIDsRJ = GetSpellIDs(QUICKHEAL_SPELL_REJUVENATION);

    local maxRankHT = table.getn(SpellIDsHT);
    local maxRankRG = table.getn(SpellIDsRG);
    local maxRankRJ = table.getn(SpellIDsRJ);

    debug(string.format("Found HT up to rank %d, RG up to rank %d, RJ up to rank %d", maxRankHT, maxRankRG, maxRankRJ));

    -- Compensation for health lost during combat
    local k=1.0;
    local K=1.0;
    if InCombat then
        k=0.9;
        K=0.8;
    end


    SpellID = SpellIDsRJ[1]; HealSize = (36+healMod15)*genMod*gonMod; -- Default to Rejuvenation (rank 1)
    if healneed > (60+healMod15)*genMod*gonMod*k and ManaLeft >= 40*mgMod and maxRankRJ >=2 and SpellIDsRJ[2] then SpellID = SpellIDsRJ[2]; HealSize = (60+healMod15)*genMod*gonMod end
    if healneed > (120+healMod15)*genMod*gonMod*k and ManaLeft >= 75*mgMod and maxRankRJ >=3 and SpellIDsRJ[3] then SpellID = SpellIDsRJ[3]; HealSize = (120+healMod15)*genMod*gonMod end
    if healneed > (180+healMod15)*genMod*gonMod*k and ManaLeft >= 105*mgMod and maxRankRJ >=4 and SpellIDsRJ[4] then SpellID = SpellIDsRJ[4]; HealSize = (180+healMod15)*genMod*gonMod end
    if healneed > (246+healMod15)*genMod*gonMod*k and ManaLeft >= 135*mgMod and maxRankRJ >=5 and SpellIDsRJ[5] then SpellID = SpellIDsRJ[5]; HealSize = (246+healMod15)*genMod*gonMod end
    if healneed > (306+healMod15)*genMod*gonMod*k and ManaLeft >= 160*mgMod and maxRankRJ >=6 and SpellIDsRJ[6] then SpellID = SpellIDsRJ[6]; HealSize = (306+healMod15)*genMod*gonMod end
    if healneed > (390+healMod15)*genMod*gonMod*k and ManaLeft >= 195*mgMod and maxRankRJ >=7 and SpellIDsRJ[7] then SpellID = SpellIDsRJ[7]; HealSize = (390+healMod15)*genMod*gonMod end
    if healneed > (492+healMod15)*genMod*gonMod*k and ManaLeft >= 235*mgMod and maxRankRJ >=8 and SpellIDsRJ[8] then SpellID = SpellIDsRJ[8]; HealSize = (492+healMod15)*genMod*gonMod end
    if healneed > (612+healMod15)*genMod*gonMod*k and ManaLeft >= 280*mgMod and maxRankRJ >=9 and SpellIDsRJ[9] then SpellID = SpellIDsRJ[9]; HealSize = (608+healMod15)*genMod*gonMod end
    if healneed > (756+healMod15)*genMod*gonMod*k and ManaLeft >= 335*mgMod and maxRankRJ >=10 and SpellIDsRJ[10] then SpellID = SpellIDsRJ[10]; HealSize = (756+healMod15)*genMod*gonMod end
    if healneed > (888+healMod15)*genMod*gonMod*k and ManaLeft >= 360*mgMod and maxRankRJ >=11 and SpellIDsRJ[11] then SpellID = SpellIDsRJ[11]; HealSize = (888+healMod15)*genMod*gonMod end


    return SpellID,HealSize*hdb;
end

function QuickHeal_Command_Druid(msg)

    --if PlayerClass == "priest" then
    --  writeLine("DRUID", 0, 1, 0);
    --end

    local _, _, arg1, arg2, arg3 = string.find(msg, "%s?(%w+)%s?(%w+)%s?(%w+)")

    -- match 3 arguments
    if arg1 ~= nil and arg2 ~= nil and arg3 ~= nil then
        if arg1 == "player" or arg1 == "target" or arg1 == "targettarget" or arg1 == "party" or arg1 == "subgroup" or arg1 == "mt" or arg1 == "nonmt" then
            if arg2 == "heal" and arg3 == "max" then
                --writeLine(QuickHealData.name .. " qh " .. arg1 .. " HEAL(maxHPS)", 0, 1, 0);
                QuickHeal(arg1, nil, nil, true);
                return;
            end
            if arg2 == "hot" and arg3 == "fh" then
                --writeLine(QuickHealData.name .. " qh " .. arg1 .. " HOT(max rank & no hp check)", 0, 1, 0);
                QuickHOT(arg1, nil, nil, true, true);
                return;
            end
            if arg2 == "hot" and arg3 == "max" then
                --writeLine(QuickHealData.name .. " qh " .. arg1 .. " HOT(max rank)", 0, 1, 0);
                QuickHOT(arg1, nil, nil, true, false);
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
        if arg4 == "hot" and arg5 == "max" then
            --writeLine(QuickHealData.name .. " HOT (max)", 0, 1, 0);
            QuickHOT(nil, nil, nil, true, false);
            return;
        end
        if arg4 == "hot" and arg5 == "fh" then
            --writeLine(QuickHealData.name .. " FH (max rank & no hp check)", 0, 1, 0);
            QuickHOT(nil, nil, nil, true, true);
            return;
        end
        if arg4 == "player" or arg4 == "target" or arg4 == "targettarget" or arg4 == "party" or arg4 == "subgroup" or arg4 == "mt" or arg4 == "nonmt" then
            if arg5 == "hot" then
                --writeLine(QuickHealData.name .. " qh " .. arg1 .. " HOT", 0, 1, 0);
                QuickHOT(arg1, nil, nil, false, false);
                return;
            end
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

    if cmd == "hot" then
        --writeLine(QuickHealData.name .. " HOT", 0, 1, 0);
        QuickHOT();
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
    writeLine("== QUICKHEAL USAGE : DRUID ==");
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

    writeLine(" [type] specifies the use of a [hot] or [heal]");
    writeLine(" [mod] (optional) modifies [hot] or [heal] options:");
    writeLine("  [heal] modifier options:");
    writeLine("   [max] applies maximum rank [heal] to subgroup members that have <100% health");
    writeLine("  [hot] modifier options:");
    writeLine("   [max] applies maximum rank [hot] to subgroup members that have <100% health and no hot applied");
    writeLine("   [fh] applies maximum rank [hot] to subgroup members that have no hot applied regardless of health status");

    writeLine("/qh reset - Reset configuration to default parameters for all classes.");
end











