PlayerbotsPanelEmu.emulator = {}
local _self = PlayerbotsPanelEmu.emulator
local _cfg = PlayerbotsPanelEmu.config
local _debug = AceLibrary:GetInstance("AceDebug-2.0")
local _broker = PlayerbotsPanelEmu.broker
local _const = PlayerbotsPanelEmu.broker.consts
local _parser = PlayerbotsPanelEmu.broker.util.parser.Create()
local _dbchar = {}
local _simLogout = false
local PLAYER = "player"
local _selfStatus = {}
_selfStatus.handshake = false -- reset on logout

-- ============================================================================================
-- ============== Locals optimization, use in hotpaths
-- ============================================================================================

local _strbyte = string.byte
local _strchar = string.char
local _strsplit = strsplit
local _strsub = string.sub
local _strlen = string.len
local _tonumber = tonumber
local _strformat = string.format
local _pairs = pairs
local _tinsert = table.insert
local _tremove = table.remove
local _tconcat = table.concat
local _getn = getn
local _sendAddonMsg = SendAddonMessage
local _pow = math.pow
local _floor = math.floor


local _currencyCache = {}
_currencyCache.copper = 0
_currencyCache.silver = 0
_currencyCache.gold = 0
_currencyCache.honor = 0
_currencyCache.arenaPoints = 0
_currencyCache.other = {}

local _pbuffer = {} -- payload buffer
local _pbufferCount = 0
local _pbufferRound = false
local _pbufferDebugMode = false

local function bufferAdd_STRING(str, debugName)
    _pbufferCount = _pbufferCount + 1
    if str == nil then
        str = _const.NULL_LINK
    end
    if _pbufferDebugMode and debugName then
        print("BUFFER: " .. debugName .. " - " .. str)
    end
    _pbuffer[_pbufferCount] = str
end

local function bufferAdd_INT(value, debugName)
    if value == nil then
        value = 0
    elseif type(value) == "number" then
        value = math.floor(value)
    end
    bufferAdd_STRING(tostring(value), debugName)
end

local function bufferAdd_FLOAT(value, debugName)
    if value == nil then
        value = 0
    elseif type(value) == "number" then
        value = math.floor(value * 100 ) / 100
    end
    bufferAdd_STRING(tostring(value), debugName)
end

local function bufferSetDebug(val)
    _pbufferDebugMode = val
end

local function bufferClear()
    wipe(_pbuffer)
    _pbufferCount = 0
    _pbufferDebugMode = false
end

local function bufferToString()
    local result = _tconcat(_pbuffer, _const.MSG_SEPARATOR)
    bufferClear()
    return result
end

-- ============================================================================================
-- BAGS
local _changedBags = {}
local _shouldScanBags = false
local _bagstates = {}
local _time = 0
local _nextHandshakeTime = 0
local _nextBagScanTime = 0
local _bagScanTickrate = 0.1
local _atBank = false
local _initalBankScanComplete = false

for i=-2, 11 do
    local size = 0
    if i == -2 then size = 32 end -- -2 keychain
    if i == -1 then size = 28 end -- -1 bank space
    if i == 0 then size = 16 end  --  0 backpack
    _bagstates[i] = {
        link = nil,
        size = size,
        contents = {},
        getFree = function (self)
            local freeCount = self.size
            local firstFreeSlot = nil
            for i=1, size do
                local item = self.contents[i]
                if item and item.link then
                    freeCount = freeCount - 1
                else
                    firstFreeSlot = i
                end
            end
            return freeCount, firstFreeSlot
        end
    }
end

-- ============================================================================================

local function _eval(eval, ifTrue, ifFalse)
    if eval then
        return ifTrue
    else
        return ifFalse
    end
end

local function _eval01(eval)
    if eval then
        return 1
    else
        return 0
    end
end

local function inverseLerp(a, b, t)
    a = a * 1.0
    b = b * 1.0
    t = t * 1.0
    return (t-a)/(b-a)
end

local function GenerateMessage(header, subtype, id, payload)
    if not id then id = 0 end
    if not _dbchar.master then return end
    local msg = table.concat({
        string.char(header),
        _const.MSG_SEPARATOR,
        string.char(subtype),
        _const.MSG_SEPARATOR,
        string.format("%03d", id),
        _const.MSG_SEPARATOR,
        payload})
    SendAddonMessage(_const.prefixCode, msg, "WHISPER", _dbchar.master)
    print("|cff7afffb >> MASTER |r " ..  msg)
end

local function GenerateExperienceReport(levelFromEvent)
    local level = UnitLevel(PLAYER)
    if levelFromEvent then
        level = levelFromEvent
    end
    local floatXp = inverseLerp(0.0, UnitXPMax(PLAYER), UnitXP(PLAYER))
    bufferClear()
    bufferAdd_INT(level)
    bufferAdd_FLOAT(floatXp)
    GenerateMessage(_const.MSG_HEADER.REPORT, _const.REPORT_TYPE.EXPERIENCE, 0, bufferToString())
end

function _self:GenerateItemEquippedReport(slot, count, link)
    local finalLink = _eval(link, link, _const.NULL_LINK)
    local payload = _tconcat({slot, count, finalLink}, _const.MSG_SEPARATOR)
    GenerateMessage(_const.MSG_HEADER.REPORT, _const.REPORT_TYPE.ITEM_EQUIPPED, 0, payload)
end

function _self:Init()
    print("Starting emulator")
    _dbchar = PlayerbotsPanelEmu.db.char
    _self.ScanBags(false)
    _self.ScanCurrencies(false)
    CastSpellByID(13159)
end

function _self:Update(elapsed)
    _time = _time + elapsed

    if _simLogout then return end

    if not _selfStatus.handshake then   -- send handshake every second 
        if _nextHandshakeTime < _time then
            print("Sending handshake")
            _nextHandshakeTime = _time + 1
            GenerateMessage(_const.MSG_HEADER.SYSTEM, _const.SYS_MSG_TYPE.HANDSHAKE)
        end
    else
        if _nextBagScanTime < _time then
            _nextBagScanTime = _time + _bagScanTickrate
            if  not CheckInteractDistance(_dbchar.master, 2) then
                CastSpellByID(13159)
                FollowUnit(_dbchar.master)
            end
            _self.ScanCurrencies(false)
            _self.ScanBagChanges(-2, false)
            for i = 0, 4 do
                _self.ScanBagChanges(i, false)
            end
            if _atBank  then
                _self.ScanBagChanges(-1, false)
                _self.ScanBags(false, 5, 11)
            end
        end
    end
end

local SYS_MSG_HANDLERS = {}
SYS_MSG_HANDLERS[_const.SYS_MSG_TYPE.HANDSHAKE] = function(id, payload)
    _selfStatus.handshake = true
end

SYS_MSG_HANDLERS[_const.SYS_MSG_TYPE.PING] = function(id, payload)
    GenerateMessage(_const.MSG_HEADER.SYSTEM, _const.SYS_MSG_TYPE.PING)
end

SYS_MSG_HANDLERS[_const.SYS_MSG_TYPE.LOGOUT] = function(id, payload)
    _selfStatus.handshake = false
end

local QUERY_MSG_HANDLERS = {}
QUERY_MSG_HANDLERS[_const.QUERY.WHO] = function (id, payload)
    -- CLASS(token):LEVEL(1-80):SECOND_SPEC_UNLOCKED(0-1):ACTIVE_SPEC(1-2):POINTS1:POINTS2:POINTS3:POINTS4:POINTS5:POINTS6:FLOAT_EXP:LOCATION
    -- PALADIN:65:1:1:5:10:31:40:5:10:0.89:Blasted Lands 
    local _, class = UnitClass(PLAYER)
    local spec2_unlocked = _eval01(GetNumTalentGroups(false, false) > 1)
    local active_spec = GetActiveTalentGroup(false, false)
    local _, _, points1,_, _ = GetTalentTabInfo(1, nil, nil, 1) -- Return values id, description, and isUnlocked were added in patch 4.0.1 despite what API says
    local _, _, points2,_, _ = GetTalentTabInfo(2, false, false, 1)
    local _, _, points3,_, _ = GetTalentTabInfo(3, false, false, 1)
    local level = UnitLevel(PLAYER)
    local zone = GetZoneText()
    local floatXp = inverseLerp(0.0, UnitXPMax(PLAYER), UnitXP(PLAYER))
    if floatXp ~= floatXp then
        floatXp = 0
    end
    local points4 = 0 -- second spec
    local points5 = 0
    local points6 = 0
    if spec2_unlocked > 0 then
        _, _, points4, _, _ = GetTalentTabInfo(1, false, false, 2)
        _, _, points5, _, _ = GetTalentTabInfo(2, false, false, 2)
        _, _, points6, _, _ = GetTalentTabInfo(3, false, false, 2)
    end
    local payload = _tconcat({
        class,
        level,
        spec2_unlocked,
        active_spec, -- dualspec
        points1,
        points2,
        points3,
        points4,
        points5,
        points6,
        floatXp,
        zone
    }, _const.MSG_SEPARATOR)
    GenerateMessage(_const.MSG_HEADER.QUERY, _const.QUERY_OPCODE.FINAL, id, payload)
end

QUERY_MSG_HANDLERS[_const.QUERY.REPUTATION] = function (id, payload)
	local numFactions = GetNumFactions();
    for i=1, numFactions do
	    local name, description, standingID, barMin, barMax, barValue, atWarWith, canToggleAtWar, isHeader, isCollapsed, hasRep, isWatched, isChild = GetFactionInfo(i);
        print(name, barValue, _broker.data.factionId.list[name])
    end

    GenerateMessage(_const.MSG_HEADER.QUERY, _const.QUERY_OPCODE.FINAL, id, payload)
end

QUERY_MSG_HANDLERS[_const.QUERY.STATS] = function (id, payload)
    local function GetCRValues(combatRating)
        local value =  GetCombatRating(combatRating)
        local bonus =  GetCombatRatingBonus(combatRating)
        return value, bonus
    end
    bufferClear()
    bufferAdd_STRING("b")

    --[[
        1 - Agility
        2 - Intellect
        3 - Spirit
        4 - Stamina
        5 - Strength
    ]]

    for i=1, 5 do
        local value, effectiveStat, positive, negative = UnitStat(PLAYER, i)
        bufferAdd_INT(effectiveStat)
        bufferAdd_INT(positive)
        bufferAdd_INT(negative)

        if i == 1 then -- STRENGTH related stats
            local attackPower = GetAttackPowerForStat(1, effectiveStat)
            bufferAdd_INT(attackPower)
        elseif i == 2 then -- AGILITY related stats
            local attackPower = GetAttackPowerForStat(2, effectiveStat)
            bufferAdd_INT(attackPower)
            local agiCritChance = GetCritChanceFromAgility(PLAYER)
            bufferAdd_FLOAT(agiCritChance)
        elseif i == 3 then -- STAMINA
            local maxHpModifier = GetUnitMaxHealthModifier("pet")
            bufferAdd_INT(maxHpModifier)
        elseif i == 4 then -- intellect
            local critFromIntellect =  GetSpellCritChanceFromIntellect(PLAYER)
            bufferAdd_FLOAT(critFromIntellect)
        elseif i == 5 then -- spirit
            local healthRegenFromSpirit =  GetUnitHealthRegenRateFromSpirit(PLAYER)
            local manaRegenFromSpirit = GetUnitManaRegenRateFromSpirit(PLAYER)
            bufferAdd_INT(healthRegenFromSpirit)
            bufferAdd_FLOAT(manaRegenFromSpirit)
        end
    end



    --[[
        1 - Arcane
        2 - Fire
        3 - Nature
        4 - Frost
        5 - Shadow
    ]]

    for i=1, 5 do
        local base, resistance, positive, negative = UnitResistance(PLAYER, i)
        bufferAdd_INT(resistance)
        bufferAdd_INT(positive)
        bufferAdd_INT(negative)
    end

    GenerateMessage(_const.MSG_HEADER.QUERY, _const.QUERY_OPCODE.PROGRESS, id, _tconcat(_pbuffer, _const.MSG_SEPARATOR))

    bufferClear()
    
    -- All floats should be rounded to 2 decimals, so 0.513213 becomes 0.51
    
    
    -- MELEE

    bufferAdd_STRING("m")
    local minMeleeDamage, maxMeleeDamage, minMeleeOffHandDamage, maxMeleeOffHandDamage, meleePhysicalBonusPositive, meleePhysicalBonusNegative, meleeDamageBuffPercent = UnitDamage(PLAYER)
    bufferAdd_FLOAT(minMeleeDamage, "minMeleeDamage")
    bufferAdd_FLOAT(maxMeleeDamage, "maxMeleeDamage") 
    bufferAdd_FLOAT(minMeleeOffHandDamage, "minMeleeOffHandDamage") 
    bufferAdd_FLOAT(maxMeleeOffHandDamage, "maxMeleeOffHandDamage") 
    bufferAdd_INT(meleePhysicalBonusPositive, "meleePhysicalBonusPositive") 
    bufferAdd_INT(meleePhysicalBonusNegative, "meleePhysicalBonusNegative")
    bufferAdd_FLOAT(meleeDamageBuffPercent, "meleeDamageBuffPercent") 

    local meleeSpeed, meleeOffhandSpeed = UnitAttackSpeed(PLAYER)
    bufferAdd_FLOAT(meleeSpeed, "meleeSpeed")
    bufferAdd_FLOAT(meleeOffhandSpeed, "meleeOffhandSpeed")

    local meleeAtkPowerBase, meleeAtkPowerPositive, meleeAtkPowerNegative = UnitAttackPower(PLAYER)
    bufferAdd_INT(meleeAtkPowerBase, "meleeAtkPowerBase")
    bufferAdd_INT(meleeAtkPowerPositive, "meleeAtkPowerPositive")
    bufferAdd_INT(meleeAtkPowerNegative, "meleeAtkPowerNegative")

    local meleeHaste, meleeHasteBonus = GetCRValues(CR_HASTE_MELEE)
    bufferAdd_INT(meleeHaste, "meleeHaste")
    bufferAdd_FLOAT(meleeHasteBonus, "meleeHasteBonus")

    local meleeCritRating, meleeCritRatingBonus = GetCRValues(CR_CRIT_MELEE)
    local meleeCritChance = GetCritChance()
    bufferAdd_INT(meleeCritRating, "meleeCritRating")
    bufferAdd_FLOAT(meleeCritRatingBonus, "meleeCritRatingBonus")
    bufferAdd_FLOAT(meleeCritChance, "meleeCritChance")

    local meleeHit, meleeHitBonus = GetCRValues(CR_HIT_MELEE)
    bufferAdd_INT(meleeHit, "meleeHit")
    bufferAdd_FLOAT(meleeHitBonus, "meleeHitBonus")

    local armorPenPercent = GetArmorPenetration()
    local armorPen, armorPenBonus = GetCRValues(CR_ARMOR_PENETRATION)
    bufferAdd_INT(armorPen, "armorPen")
    bufferAdd_FLOAT(armorPenPercent, "armorPenPercent") 
    bufferAdd_FLOAT(armorPenBonus, "armorPenBonus") 

    local expertise, offhandExpertise = GetExpertise()
    local expertisePerc, offhandExpertisePercent = GetExpertisePercent()
    local expertiseRating, expertiseRatingBonus = GetCombatRatingBonus(CR_EXPERTISE)
    bufferAdd_INT(expertise, "expertise")
    bufferAdd_INT(offhandExpertise, "offhandExpertise")
    bufferAdd_FLOAT(expertisePerc, "expertisePerc")
    bufferAdd_FLOAT(offhandExpertisePercent, "offhandExpertisePercent")
    bufferAdd_INT(expertiseRating, "expertiseRating")
    bufferAdd_FLOAT(expertiseRatingBonus, "expertiseRatingBonus")

    GenerateMessage(_const.MSG_HEADER.QUERY, _const.QUERY_OPCODE.PROGRESS, id, _tconcat(_pbuffer, _const.MSG_SEPARATOR))
    bufferClear()


    -- RANGED

    bufferAdd_STRING("r")
    local rangedAttackSpeed, rangedMinDamage, rangedMaxDamage, rangedPhysicalBonusPositive, rangedPhysicalBonusNegative, rangedDamageBuffPercent = UnitRangedDamage(PLAYER);
    bufferAdd_FLOAT(rangedAttackSpeed, "rangedAttackSpeed")
    bufferAdd_FLOAT(rangedMinDamage, "rangedMinDamage") 
    bufferAdd_FLOAT(rangedMaxDamage, "rangedMaxDamage") 
    bufferAdd_INT(rangedPhysicalBonusPositive, "rangedPhysicalBonusPositive") 
    bufferAdd_INT(rangedPhysicalBonusNegative, "rangedPhysicalBonusNegative") 
    bufferAdd_FLOAT(rangedDamageBuffPercent, "rangedDamageBuffPercent")

	local rangedAttackPower, rangedAttackPowerPositive, rangedAttackPowerNegative = UnitRangedAttackPower(PLAYER);
    bufferAdd_INT(rangedAttackPower, "rangedAttackPower")
    bufferAdd_INT(rangedAttackPowerPositive, "rangedAttackPowerPositive")
    bufferAdd_INT(rangedAttackPowerNegative, "rangedAttackPowerNegative")

    local rangedHaste, rangedHasteBonus = GetCRValues(CR_HASTE_RANGED)
    bufferAdd_INT(rangedHaste, "rangedHaste")
    bufferAdd_FLOAT(rangedHasteBonus, "rangedHasteBonus")

    local rangedCritRating, rangedCritRatingBonus = GetCRValues(CR_CRIT_RANGED)
    local rangedCritChance = GetRangedCritChance()
    bufferAdd_INT(rangedCritRating, "rangedCritRating")
    bufferAdd_FLOAT(rangedCritRatingBonus, "rangedCritRatingBonus")
    bufferAdd_FLOAT(rangedCritChance, "rangedCritChance")

    local rangedHit, rangedHitBonus = GetCRValues(CR_HIT_RANGED)
    bufferAdd_INT(rangedHit, "rangedHit")
    bufferAdd_FLOAT(rangedHitBonus, "rangedHitBonus")

    GenerateMessage(_const.MSG_HEADER.QUERY, _const.QUERY_OPCODE.PROGRESS, id, _tconcat(_pbuffer, _const.MSG_SEPARATOR))
    bufferClear()

    -- SPELL
    bufferAdd_STRING("s")

    for i=2, MAX_SPELL_SCHOOLS do -- skip physical, start at 2
        bufferAdd_INT(GetSpellBonusDamage(i), "spellBonusDamage_" .. i)
    end

    bufferAdd_INT(GetSpellBonusHealing(), "spellBonusHealing")

    local spellHit, spellHitBonus = GetCRValues(CR_HIT_SPELL)
    bufferAdd_INT(spellHit, "spellHit")
    bufferAdd_FLOAT(spellHitBonus, "spellHitBonus")
    
    bufferAdd_FLOAT(GetSpellPenetration(), "spellPenetration")
    
    for i=2, MAX_SPELL_SCHOOLS do -- skip physical, start at 2
        bufferAdd_FLOAT(GetSpellCritChance(i), "spellCritChance_" .. i)
    end
    
    local spellCritRating, spellCritRatingBonus = GetCRValues(CR_CRIT_SPELL)
    bufferAdd_INT(spellCritRating, "spellCritRating")
    bufferAdd_FLOAT(spellCritRatingBonus, "spellCritRatingBonus")

    local spellHaste, spellHasteBonus = GetCRValues(CR_HASTE_SPELL)
    bufferAdd_INT(spellHaste, "spellHaste")
    bufferAdd_FLOAT(spellHasteBonus, "spellHasteBonus")

    local baseManaRegen, castingManaRegen = GetManaRegen()
    bufferAdd_FLOAT(baseManaRegen, "baseManaRegen")
    bufferAdd_FLOAT(castingManaRegen, "castingManaRegen")

    GenerateMessage(_const.MSG_HEADER.QUERY, _const.QUERY_OPCODE.PROGRESS, id, _tconcat(_pbuffer, _const.MSG_SEPARATOR))
    bufferClear()

    -- DEFENSES
    bufferAdd_STRING("d")

    local _, effectiveArmor, _, armorPositive, armorNegative = UnitArmor(PLAYER)
    bufferAdd_INT(effectiveArmor)
    bufferAdd_INT(armorPositive)
    bufferAdd_INT(armorNegative)

    local _, effectivePetArmor, _, armorPetPositive, armorPetNegative = UnitArmor("pet")
    bufferAdd_INT(effectivePetArmor)
    bufferAdd_INT(armorPetPositive)
    bufferAdd_INT(armorPetNegative)

    local baseDefense, modifierDefense = UnitDefense(PLAYER);
    bufferAdd_INT(baseDefense, "baseDefense")
    bufferAdd_FLOAT(modifierDefense, "modifierDefense")
    local defenseRating, defenseRatingBonus = GetCRValues(CR_DEFENSE_SKILL)
    bufferAdd_INT(defenseRating, "defenseRating")
    bufferAdd_FLOAT(defenseRatingBonus, "defenseRatingBonus")

	local dodgeChance = GetDodgeChance()
    local dodgeRating, dodgeRatingBonus = GetCRValues(CR_DODGE)
    bufferAdd_FLOAT(dodgeChance, "dodgeChance")
    bufferAdd_INT(dodgeRating, "dodgeRating")
    bufferAdd_FLOAT(dodgeRatingBonus, "dodgeRatingBonus")

	local blockChance = GetBlockChance()
    local shieldBlock = GetShieldBlock()
    local blockRating, blockRatingBonus = GetCRValues(CR_BLOCK)
    bufferAdd_FLOAT(blockChance, "blockChance")
    bufferAdd_INT(shieldBlock, "shieldBlock")
    bufferAdd_INT(blockRating, "blockRating")
    bufferAdd_FLOAT(blockRatingBonus, "blockRatingBonus")

    local parryChance = GetParryChance()
    local parryRating, parryRatingBonus = GetCRValues(CR_PARRY)
    bufferAdd_FLOAT(parryChance, "parryChance")
    bufferAdd_INT(parryRating, "parryRating")
    bufferAdd_FLOAT(parryRatingBonus, "parryRatingBonus")

    local meleeResil, meleeResilBonus = GetCRValues(CR_CRIT_TAKEN_MELEE)
    bufferAdd_INT(meleeResil, "meleeResil")
    bufferAdd_FLOAT(meleeResilBonus, "meleeResilBonus")

    local rangedResil, rangedResilBonus = GetCRValues(CR_CRIT_TAKEN_RANGED)
    bufferAdd_INT(rangedResil, "rangedResil")
    bufferAdd_FLOAT(rangedResilBonus, "rangedResilBonus")

    local spellResil, spellResilBonus = GetCRValues(CR_CRIT_TAKEN_SPELL)
    bufferAdd_INT(spellResil, "spellResil")
    bufferAdd_FLOAT(spellResilBonus, "spellResilBonus")
    
    GenerateMessage(_const.MSG_HEADER.QUERY, _const.QUERY_OPCODE.FINAL, id, _tconcat(_pbuffer, _const.MSG_SEPARATOR))
end

QUERY_MSG_HANDLERS[_const.QUERY.GEAR] = function (id, _)
    -- Inventory slots
    -- INVSLOT_AMMO    = 0;
    -- INVSLOT_HEAD    = 1; INVSLOT_FIRST_EQUIPPED = INVSLOT_HEAD;
    -- INVSLOT_NECK    = 2;
    -- INVSLOT_SHOULDER  = 3;
    -- INVSLOT_BODY    = 4;
    -- INVSLOT_CHEST   = 5;
    -- INVSLOT_WAIST   = 6;
    -- INVSLOT_LEGS    = 7;
    -- INVSLOT_FEET    = 8;
    -- INVSLOT_WRIST   = 9;
    -- INVSLOT_HAND    = 10;
    -- INVSLOT_FINGER1   = 11;
    -- INVSLOT_FINGER2   = 12;
    -- INVSLOT_TRINKET1  = 13;
    -- INVSLOT_TRINKET2  = 14;
    -- INVSLOT_BACK    = 15;
    -- INVSLOT_MAINHAND  = 16;
    -- INVSLOT_OFFHAND   = 17;
    -- INVSLOT_RANGED    = 18;
    -- INVSLOT_TABARD    = 19;
    -- INVSLOT_LAST_EQUIPPED = INVSLOT_TABARD;
    for i=0, 19 do
        local link = GetInventoryItemLink(PLAYER, i)
        if link then
            local count = GetInventoryItemCount(PLAYER, i)
            local payload = _tconcat({i, count, link}, _const.MSG_SEPARATOR)
            GenerateMessage(_const.MSG_HEADER.QUERY, _const.QUERY_OPCODE.PROGRESS, id, payload)
        end
    end
    GenerateMessage(_const.MSG_HEADER.QUERY, _const.QUERY_OPCODE.FINAL, id, nil)
end

QUERY_MSG_HANDLERS[_const.QUERY.INVENTORY] = function (id, _)

    local function genBag(bag)
        local name = GetBagName(bag)
        if name then 
            local slots = GetContainerNumSlots(bag)
            local _, link, _, _, _, _, _, _, _, _, _ = GetItemInfo(name)
            local payload = _tconcat({"b", tostring(bag), tostring(slots), link }, _const.MSG_SEPARATOR)
            GenerateMessage(_const.MSG_HEADER.QUERY, _const.QUERY_OPCODE.PROGRESS, id, payload)
        end
    end

    genBag(-2) -- keychain
    for bag = 1, 4 do
        genBag(bag)
    end

    local function genItems(bag)
        local slots = GetContainerNumSlots(bag)
        for slot = 1, slots do
            local texture, count, locked, quality, readable, lootable, link = GetContainerItemInfo(bag, slot)
            if link then
                local payload = _tconcat({"i", tostring(bag), tostring(slot), tostring(count), link }, _const.MSG_SEPARATOR)
                GenerateMessage(_const.MSG_HEADER.QUERY, _const.QUERY_OPCODE.PROGRESS, id, payload)
            end
        end
    end

    genItems(-2)
    for bag = 0, 4 do
        genItems(bag)
    end

    GenerateMessage(_const.MSG_HEADER.QUERY, _const.QUERY_OPCODE.FINAL, id, nil)
end

QUERY_MSG_HANDLERS[_const.QUERY.CURRENCY] = function (id, payload)
    local cache = _currencyCache
    local payload = _tconcat({_const.QUERY.CURRENCY_MONEY, tostring(cache.gold), tostring(cache.silver), tostring(cache.copper) }, _const.MSG_SEPARATOR) -- report gold changed
    GenerateMessage(_const.MSG_HEADER.QUERY, _const.QUERY_OPCODE.PROGRESS, id, payload)

    for itemId, count in pairs(_currencyCache.other) do
        if itemId ~= 0 then
            local payload = _tconcat({_const.QUERY.CURRENCY_OTHER, tostring(itemId), tostring(count) }, _const.MSG_SEPARATOR) -- report other currency changed
            GenerateMessage(_const.MSG_HEADER.QUERY, _const.QUERY_OPCODE.PROGRESS, id, payload)
        end
    end

    GenerateMessage(_const.MSG_HEADER.QUERY, _const.QUERY_OPCODE.FINAL, id, nil)
end

local COMMAND_HANDLERS_ITEM = {}
COMMAND_HANDLERS_ITEM[_const.COMMAND.ITEM_USE] = function ()
    print("cmd.item_use")
    local link = _parser:nextLink()
    local bag, slot, item = _self.FindItemByLink(link)
    if item then
        UseContainerItem(bag, slot, "player")
    end
end

COMMAND_HANDLERS_ITEM[_const.COMMAND.ITEM_USE_ON] = function ()
    print("cmd.item_use_on")
    local link1 = _parser:nextLink()
    local link2 = _parser:nextLink()
    local bag1, slot1, item1 = _self.FindItemByLink(link1)
    local bag2, slot2, item2 = _self.FindItemByLink(link2)
    if item1 and item2 then
        PickupItem(item1.link)
        -- Unfinished
    end
end

COMMAND_HANDLERS_ITEM[_const.COMMAND.ITEM_EQUIP] = function ()
    print("cmd.item_equip")
    local link = _parser:nextLink()
    local bag, slot, item = _self.FindItemByLink(link)
    if item then
        UseContainerItem(bag, slot, "player")
    end
end

COMMAND_HANDLERS_ITEM[_const.COMMAND.ITEM_UNEQUIP] = function ()
    print("cmd.item_unequip")
    local link = _parser:nextLink()
    local eslot = _self.FindEquipSlotByLink(link)
    if eslot then
        ClearCursor()
        PickupInventoryItem(eslot)

        if _bagstates[0]:getFree() > 0 then
            PutItemInBackpack()
        else
            for i=1, 4 do
                local freeTotal, firstFreeSlot = _bagstates[i]:getFree()
                if freeTotal > 0 then
                    print("bag" .. i , tostring(freeTotal))
                    PutItemInBag(i+19)
                    break
                end
            end
        end
    end 
    _self:ScanBags()
end

--COMMAND_HANDLERS_ITEM[COMMAND.ITEM_TRADE] = function ()
--    print("cmd.item_trade")
--    local link = _parser:nextLink()
--    local bag, slot, item = PlayerbotsComsEmulator.FindItemByLink(link)
--    if item then
--        InitiateTrade(_dbchar.master)
--        ClickTradeButton(index) -- click slot/pick item/place item
--        UseContainerItem(bag, slot, "player")
--    end
--end

local COMMAND_HANDLERS = {}
COMMAND_HANDLERS[_const.COMMAND.ITEM] = function (id, payload)
    _parser:start(payload)
    local subCmd = _parser:nextCharAsByte()
    local impl = COMMAND_HANDLERS_ITEM[subCmd]
    if impl then
        impl()
    end
end



local MSG_HANDLERS = {}
MSG_HANDLERS[_const.MSG_HEADER.SYSTEM] = SYS_MSG_HANDLERS
MSG_HANDLERS[_const.MSG_HEADER.REPORT] = {}
MSG_HANDLERS[_const.MSG_HEADER.COMMAND] = COMMAND_HANDLERS

--EquipItemByName

function _self:CHAT_MSG_ADDON(prefix, message, channel, sender)
    print("|cffb4ff29 << MASTER |r " .. message)
    if sender == _dbchar.master then
        if prefix == _const.prefixCode then
            -- confirm that the message has valid format
            local header, sep1, subtype, sep2, idb1, idb2, idb3, sep3 = _strbyte(message, 1, 8)
            local _separatorByte = _const.MSG_SEPARATOR_BYTE
            -- BYTES
            -- 1 [HEADER] 2 [SEPARATOR] 3 [SUBTYPE/QUERY_OPCODE] 4 [SEPARATOR] 5-6-7 [ID] 8 [SEPARATOR] 9 [PAYLOAD / NEXT QUERY]
            -- s:p:999:payload
            if sep1 == _separatorByte and sep2 == _separatorByte and sep3 == _separatorByte then
                if header == _const.MSG_HEADER.QUERY then
                    -- here we treat queries differently because master can pack multiple queries into a single message
                    -- total length of a query is 8 bytes, so in a single message we can pack 30 queries (taking into account trailing sep) (254 max length/8)
                    for offset = 0, 29 do
                        if offset > 0 then
                            header, _, subtype, _, idb1, idb2, idb3, _ = _strbyte(message, 8 * offset, 8 * (offset + 1))
                        end
                        if header and header == _const.MSG_HEADER.QUERY then
                            local qhandler = QUERY_MSG_HANDLERS[subtype]
                            if qhandler then
                                local id = ((idb1-48) * 100) + ((idb2-48) * 10) + (idb3-48)
                                qhandler(id, nil)
                            end
                        else
                            break
                        end
                    end
                else
                    local handlers = MSG_HANDLERS[header]
                    if handlers then
                        local handler = handlers[subtype]
                        if handler then
                            local id = ((idb1-48) * 100) + ((idb2-48) * 10) + (idb3-48)
                            local payload = _strsub(message, 9)
                            handler(id, payload)
                        end
                    end
                end
            end
        end
    end
end

function _self:SimLogout()
    GenerateMessage(_const.MSG_HEADER.SYSTEM, _const.SYS_MSG_TYPE.LOGOUT)
    _simLogout = true
    _selfStatus.handshake = false
end

function _self:SimLogin()
    _simLogout = false
end

function _self:PLAYER_LOGIN()
end

function _self:PLAYER_LOGOUT()
end

function _self:PLAYER_LEVEL_UP(levelFromEvent)
    GenerateExperienceReport(levelFromEvent)
end

function _self:BANKFRAME_OPENED()
    _atBank = true
end

function _self:BANKFRAME_CLOSED()
    _atBank = false
end

function _self:TRADE_ACCEPT_UPDATE(player, target)
    if target == 1 then
        AcceptTrade()
    end
end

function _self.SetBagChanged(bagSlot)
    if bagSlot >= 0 then
        _changedBags[bagSlot] = true
    end
end

function _self.ScanBagChanges(bagSlot, silent)
    local bagState = _bagstates[bagSlot]
    local specialBag = bagSlot <= 0
    local bagChanged = false

    if not specialBag then
        local name = GetBagName(bagSlot)
        if name then
            local size = GetContainerNumSlots(bagSlot)
            if size == nil then
                size = 0
            end
            local _, link, _, _, _, _, _, _, _, _, _ = GetItemInfo(name)
            if bagState.size ~= size then
                bagChanged = true
                bagState.size = size
            end
            if bagState.link ~= link then
                bagChanged = true
                bagState.link = link
            end
            if not silent and bagChanged then
                local payload = _tconcat({"b", tostring(bagSlot), tostring(size), link }, _const.MSG_SEPARATOR)
                GenerateMessage(_const.MSG_HEADER.REPORT, _const.REPORT.INVENTORY, nil, payload)
            end
        else
            if not silent and bagState.link then -- bag was removed from this slot
                bagState.link = nil
                bagState.size = 0
                local payload = _tconcat({"b", tostring(bagSlot), tostring(0), _const.NULL_LINK }, _const.MSG_SEPARATOR)
                GenerateMessage(_const.MSG_HEADER.REPORT, _const.REPORT.INVENTORY, nil, payload)
            end
        end
    end

    local size = bagState.size
    if bagChanged then -- if bag has changed, dump all items
        if bagState.link then
            for slot = 1, size do
                local texture, count, locked, quality, readable, lootable, link = GetContainerItemInfo(bagSlot, slot)
                if link then
                    local itemState = bagState.contents[slot]
                    if not itemState then
                        itemState = {
                            link = nil,
                            count = 0,
                        }
                        bagState.contents[slot] = itemState
                    end
                    itemState.link = link
                    itemState.count = count

                    if not silent then
                        local payload = _tconcat({"i", tostring(bagSlot), tostring(slot), tostring(count), link }, _const.MSG_SEPARATOR)
                        GenerateMessage(_const.MSG_HEADER.REPORT, _const.REPORT.INVENTORY, nil, payload)
                    end
                end
            end
        else

        end
    else -- if bag didnt change, only report items that changed
        for slot = 1, size do
            local texture, count, locked, quality, readable, lootable, link = GetContainerItemInfo(bagSlot, slot)
            if count == nil then
                count = 0
            end
            local itemState = bagState.contents[slot]
            if not itemState then
                itemState = {
                    link = nil,
                    count = 0
                }
                bagState.contents[slot] = itemState
            end
            local shouldReport = false
            if link then
                if not itemState.link then -- item added
                    shouldReport = true
                end
                if itemState.link ~= link then -- item changed
                    shouldReport = true
                end
                if itemState.count ~= count then -- item count changed
                    shouldReport = true
                end
            else
                if itemState.link then -- item removed
                    shouldReport = true
                end
            end

            itemState.link = link
            itemState.count = count
            if not silent and shouldReport then
                local payload = _tconcat({"i", tostring(bagSlot), tostring(slot), tostring(count), _eval(link, link, _const.NULL_LINK) }, _const.MSG_SEPARATOR)
                GenerateMessage(_const.MSG_HEADER.REPORT, _const.REPORT.INVENTORY, nil, payload)
            end
        end
    end
end

function  _self.ScanBags(silent, startBag, endBag) -- silent will not create reports, used when initializing
    local scanStart = _eval(startBag, startBag, -2)
    local scanEnd = _eval(endBag, endBag, 11)
    for i=scanStart, scanEnd do
        _self.ScanBagChanges(i, silent)
    end
end


function  _self.ScanCurrencies(silent)
    local money = GetMoney()
    local gold = floor(abs(money / 10000))
    local silver = floor(abs(mod(money / 100, 100)))
    local copper = floor(abs(mod(money, 100)))

    local shouldReportMoney = false

    if gold ~= _currencyCache.gold then
        shouldReportMoney = true
        _currencyCache.gold = gold
    end

    if silver ~= _currencyCache.silver then
        shouldReportMoney = true
        _currencyCache.silver = silver
    end

    if copper ~= _currencyCache.copper then
        shouldReportMoney = true
        _currencyCache.copper = copper
    end

    if not silent and shouldReportMoney then
        local payload = _tconcat({_const.QUERY.CURRENCY_MONEY, tostring(gold), tostring(silver), tostring(copper) }, _const.MSG_SEPARATOR) -- report gold changed
        GenerateMessage(_const.MSG_HEADER.REPORT, _const.REPORT.CURRENCY, nil, payload)
    end

    for index = 1, GetCurrencyListSize() do
        local name, isHeader, isExpanded, isUnused, isWatched, count, extraCurrencyType, icon, itemID = GetCurrencyListInfo(index)
        if itemID ~= 0 then
            if _currencyCache.other[itemID] ~= count then
                _currencyCache.other[itemID] = count
                if not silent then
                    local payload = _tconcat({_const.QUERY.CURRENCY_OTHER, tostring(itemID), tostring(count) }, _const.MSG_SEPARATOR) -- report other currency changed
                    GenerateMessage(_const.MSG_HEADER.REPORT, _const.REPORT.CURRENCY, nil, payload)
                end
            end
        end
    end
end

function _self.FindItemByLink(link)
    if link and _parser.validateLink(link) then
        for bag=-2, 11 do
            local bagState = _bagstates[bag]
            for slot = 1, bagState.size do
                local item = bagState.contents[slot]
                if item and item.link == link then
                    return bag, slot, item
                end
            end
        end
    end
end

function _self.FindEquipSlotByLink(link)
    if link and _parser.validateLink(link) then
        for eslot = 0, 20 do 
            local equipped = GetInventoryItemLink("player", eslot)
            if equipped == link then
                return eslot
            end
        end
    end
end