PlayerbotsComsEmulator = {}
local _emu = PlayerbotsComsEmulator
local _cfg = PlayerbotsPanelEmuConfig
local _debug = AceLibrary:GetInstance("AceDebug-2.0")
local _dbchar = {}
local _simLogout = false

local _prefixCode = "pb8aj2" -- just something unique from other addons
local _botStatus = {}
local PLAYER = "player"
_botStatus.handshake = false -- reset on logout

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


-- ============================================================================================
-- SHARED BETWEEN EMU/BROKER

local MSG_SEPARATOR = ":"
local MSG_SEPARATOR_BYTE      = _strbyte(":")
local FLOAT_DOT_BYTE          =  _strbyte(".")
local BYTE_ZERO               = _strbyte("0")
local BYTE_MINUS              = _strbyte("-")
local BYTE_NULL_LINK          = _strbyte("~")
local MSG_HEADER = {}
local NULL_LINK = "~"
local UTF8_NUM_FIRST          = _strbyte("1") -- 49
local UTF8_NUM_LAST           = _strbyte("9") -- 57

MSG_HEADER.SYSTEM =             _strbyte("s")
MSG_HEADER.REPORT =             _strbyte("r")
MSG_HEADER.QUERY =              _strbyte("q")
MSG_HEADER.COMMAND =            _strbyte("c")

PlayerbotsBrokerReportType = {}
local REPORT_TYPE = PlayerbotsBrokerReportType
REPORT_TYPE.ITEM_EQUIPPED =     _strbyte("g") -- gear item equipped or unequipped
REPORT_TYPE.CURRENCY =          _strbyte("c") -- currency changed
REPORT_TYPE.INVENTORY =         _strbyte("i") -- inventory changed (bag changed, item added / removed / destroyed)
REPORT_TYPE.TALENTS =           _strbyte("t") -- talent learned / spec changed / talents reset
REPORT_TYPE.SPELLS =            _strbyte("s") -- spell learned
REPORT_TYPE.QUEST =             _strbyte("q") -- single quest accepted, abandoned, changed, completed
REPORT_TYPE.EXPERIENCE =        _strbyte("e") -- level, experience
REPORT_TYPE.STATS =             _strbyte("S") -- all stats and combat ratings

local SYS_MSG_TYPE = {}
SYS_MSG_TYPE.HANDSHAKE =        _strbyte("h")
SYS_MSG_TYPE.PING =             _strbyte("p")
SYS_MSG_TYPE.LOGOUT =           _strbyte("l")

PlayerbotsBrokerQueryType = {}
local QUERY_TYPE = PlayerbotsBrokerQueryType
QUERY_TYPE.WHO        =         _strbyte("w") -- level, class, spec, location, experience and more
QUERY_TYPE.CURRENCY   =         _strbyte("c") -- money, honor, tokens
CURRENCY_MONEY        =                  "g" -- subtype: money
CURRENCY_OTHER        =                  "c" -- subtype: other currency (with id)
QUERY_TYPE.GEAR       =         _strbyte("g") -- only what is equipped
QUERY_TYPE.INVENTORY  =         _strbyte("i") -- whats in the bags and bags themselves
QUERY_TYPE.TALENTS    =         _strbyte("t") -- talents and talent points 
QUERY_TYPE.SPELLS     =         _strbyte("s") -- spellbook
QUERY_TYPE.QUESTS     =         _strbyte("q") -- all quests
QUERY_TYPE.STRATEGIES =         _strbyte("S")
QUERY_TYPE.STATS      =         _strbyte("T") -- all
--[[ Stats are grouped and sent together 
    subtypes:
        b - base + resists
        m - melee
        r - ranged
        s - spell
        d - defenses
]] 
QUERY_TYPE.STATS_BASE     =         _strbyte("b") -- all stats
QUERY_TYPE.STATS_MELEE    =         _strbyte("m") -- all stats
QUERY_TYPE.STATS_RANGED   =         _strbyte("r") -- all stats
QUERY_TYPE.STATS_SPELL    =         _strbyte("s") -- all stats
QUERY_TYPE.STATS_DEFENSES =         _strbyte("d") -- all stats

PlayerbotsBrokerQueryOpcode = {}
local QUERY_OPCODE = PlayerbotsBrokerQueryOpcode
QUERY_OPCODE.PROGRESS =         _strbyte("p") -- query is in progress
QUERY_OPCODE.FINAL    =         _strbyte("f") -- final message of the query, contains the final payload, and closes query
-- bytes 49 - 57 are errors

PlayerbotsBrokerCommandType = {}
local COMMAND = PlayerbotsBrokerCommandType
COMMAND.STATE        =          _strbyte("s")
--[[ 
    subtypes:
        s - stay
        f - follow
        g - grind
        F - flee
        r - runaway (kite mob)
        l - leave party
]] 
COMMAND.ITEM          =         _strbyte("i")
COMMAND.ITEM_EQUIP    =         _strbyte("e")
COMMAND.ITEM_UNEQUIP  =         _strbyte("u")
COMMAND.ITEM_USE      =         _strbyte("U")
COMMAND.ITEM_USE_ON   =         _strbyte("t")
COMMAND.ITEM_DESTROY  =         _strbyte("d")
COMMAND.ITEM_SELL     =         _strbyte("s")
COMMAND.ITEM_SELL_JUNK=         _strbyte("j")
COMMAND.ITEM_BUY      =         _strbyte("b")
--[[ 
    subtypes:
        e - equip
        u - unequip
        U - use
        t - use on target
        d - destroy
        s - sell
        j - sell junk
        b - buy
]] 
COMMAND.GIVE_GOLD     =         _strbyte("g")
COMMAND.BANK          =         _strbyte("b")
--[[ 
    subtypes:
        d - bank deposit
        w - bank withdraw
        D - guild bank deposit 
        W - guild bank withdraw
]]
COMMAND.QUEST          =         _strbyte("b")
--[[ 
    subtypes:
        a - accept quest
        A - accept all
        d - drop quest
        r - choose reward item
        t - talk to quest npc
        u - use game object (use los query to obtain the game object link)
]]
COMMAND.MISC           =         _strbyte("m")
--[[ 
    subtypes:
        t - learn from trainer
        c - cast spell
        h - set home at innkeeper
        r - release spirit when dead
        R - revive when near spirit healer
        s - summon
]]

-- ============================================================================================
-- PARSER 

-- This is a forward parser, call next..() functions to get value of type required by the msg
-- If the payload is null, the parser is considered broken and functions will return default non null values
local _parser = {
    separator = MSG_SEPARATOR_BYTE,
    dotbyte = FLOAT_DOT_BYTE,
    buffer = {}
}

local BYTE_LINK_SEP = _strbyte("|")
local BYTE_LINK_TERMINATOR = _strbyte("r")

_parser.start = function (self, payload)
    if not payload then 
        self.broken = true
        return
    end
    self.payload = payload
    self.len = _strlen(payload)
    self.broken = false
    self.bufferCount = 0
    self.cursor = 1
end
_parser.nextString = function(self)
    if self.broken then
        return "NULL"
    end
    local strbyte = _strbyte
    local strchar = _strchar
    local buffer = self.buffer
    local p = self.payload
    for i = self.cursor, self.len+1 do
        local c = strbyte(p, i)
        if c == nil or c == self.separator then
            local bufferCount = self.bufferCount
            if bufferCount > 0 then
                self.cursor = i + 1
                if buffer[1] == NULL_LINK then
                    self.bufferCount = 0
                    return nil 
                end
                
                local result = _tconcat(buffer, nil, 1, bufferCount)
                self.bufferCount = 0
                return result
            else
                return nil
            end
        else
            self.cursor = i
            local bufferCount = self.bufferCount + 1
            self.bufferCount = bufferCount
            buffer[bufferCount] = strchar(c)
        end
    end
end

_parser.stringToEnd = function(self)
    if self.broken then
        return "NULL"
    end
    self.bufferCount = 0
    local p = self.payload
    local c = strbyte(p, self.cursor)
    if c == BYTE_NULL_LINK then
        return nil 
    else
        return _strsub(p, self.cursor)
    end
end

_parser.nextLink = function(self)
    if self.broken then
        return nil
    end
    local strbyte = _strbyte
    local strchar = _strchar
    local buffer = self.buffer
    local p = self.payload
    local start = self.cursor
    local v = false -- validate  the | char
    -- if after the validator proceeds an 'r' then we terminate the link
    for i = self.cursor, self.len+1 do
        local c = strbyte(p, i)
        self.cursor = i
        if v == true then
            if c == BYTE_LINK_TERMINATOR then
                local result = _strsub(p, start, i)
                self.cursor = i + 2 -- as we dont end on separator we jump 1 ahead
                return result
            else
                v = false
            end
        end

        if c == BYTE_LINK_SEP then
            v = true
        end

        if c == NULL_LINK then
            self.cursor = i + 1
            return nil
        end

        if c == nil then
            -- we reached the end of payload but didnt close the link, the link is either not a link or invalid
            -- return null?
            return nil
        end
    end
end

_parser.nextInt = function(self)
    if self.broken then
        return 0
    end
    local buffer = self.buffer
    local p = self.payload
    local strbyte = _strbyte
    local pow = _pow
    local floor = _floor
    for i = self.cursor, self.len + 1 do
        local c = strbyte(p, i)
        if c == nil or c == self.separator then
            local bufferCount = self.bufferCount
            if bufferCount > 0 then
                self.cursor = i + 1
                local result = 0
                local sign = 1
                local start = 1
                if buffer[1] == BYTE_MINUS then
                    sign = -1
                    start = 2
                end
                for t= start, bufferCount do
                    result = result + ((buffer[t]-48)*pow(10, bufferCount - t))
                end
                result = result * sign
                self.bufferCount = 0
                return floor(result)
            end
        else
            self.cursor = i
            local bufferCount = self.bufferCount + 1
            self.bufferCount = bufferCount
            buffer[bufferCount] = c
        end
    end
end
_parser.nextFloat = function(self)
    if self.broken then
        return 0.0
    end
    local tobyte = string.byte
    local buffer = self.buffer
    local p = self.payload
    local pow = _pow
    for i = self.cursor, self.len + 1 do
        local c = tobyte(p, i)
        if c == nil or c == self.separator then
            local bufferCount = self.bufferCount
            if bufferCount > 0 then
                self.cursor = i + 1
                local result = 0
                local dotPos = -1
                local sign = 1
                local start = 1
                if buffer[1] == BYTE_MINUS then
                    sign = -1
                    start = 2
                end
                -- find dot
                for t=1, bufferCount do
                    if buffer[t] == self.dotbyte then
                        dotPos = t
                        break
                    end
                end
                -- if no dot, use simplified int algo
                if dotPos == -1 then
                    for t=start, bufferCount do
                        result = result + ((buffer[t]-48)*pow(10, bufferCount - t))
                    end
                    result = result * sign
                    self.bufferCount = 0
                    return result -- still returns a float because of pow
                else
                    for t=start, dotPos-1 do -- int
                        result = result + ((buffer[t]-48)*pow(10, dotPos - t - 1))
                    end
                    for t=dotPos+1, bufferCount do -- decimal
                        result = result + ((buffer[t]-48)* pow(10, (t-dotPos) * -1))
                    end
                    result = result * sign
                    self.bufferCount = 0
                    return result
                end
            end
        else
            self.cursor = i
            local bufferCount = self.bufferCount + 1
            self.bufferCount = bufferCount
            buffer[bufferCount] = c
        end
    end
end
_parser.nextBool = function (self)
    if self.broken then
        return false
    end
    local strbyte = _strbyte
    local strchar = _strchar
    local buffer = self.buffer
    local p = self.payload
    for i = self.cursor, self.len+1 do
        local c = strbyte(p, i)
        if c == nil or c == self.separator then
            if self.bufferCount > 0 then
                self.cursor = i + 1
                self.bufferCount = 0
                if buffer[1] == BYTE_ZERO then
                    return false
                else
                    return true
                end
            else
                return nil
            end
        else
            self.cursor = i
            local bufferCount = self.bufferCount + 1
            self.bufferCount = bufferCount
            buffer[bufferCount] = c
        end
    end
end

_parser.nextChar = function (self)
    if self.broken then
        return false
    end
    local strbyte = _strbyte
    local strchar = _strchar
    local p = self.payload
    local result = nil
    for i = self.cursor, self.len+1 do
        local c = strbyte(p, i)
        if c == nil or c == self.separator then
            self.cursor = i + 1
            self.bufferCount = 0
            return result
        else
            self.cursor = i
            if not result then
                result = strchar(c)
            end
        end
    end
end

_parser.nextCharAsByte = function (self)
    return _strbyte(self:nextChar())
end

_parser.validateLink = function(link)
    if link == nil then return false end
    local l = _strlen(link)
    local v1 = _strbyte(link, l) == BYTE_LINK_TERMINATOR
    local v2 = _strbyte(link, l-1) == BYTE_LINK_SEP
    return v1 and v2
end

-----------------------------------------------------------------------------
----- PARSER END / SHARED REGION END
-----------------------------------------------------------------------------

local _pbuffer = {} -- payload buffer
local _pbufferCount = 0
local _pbufferRound = false
local _pbufferDebugMode = false

local function bufferAdd_STRING(str, debugName)
    _pbufferCount = _pbufferCount + 1
    if str == nil then
        str = NULL_LINK
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
    local result = _tconcat(_pbuffer, MSG_SEPARATOR)
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
    local msg = table.concat({
        string.char(header),
        MSG_SEPARATOR,
        string.char(subtype),
        MSG_SEPARATOR,
        string.format("%03d", id),
        MSG_SEPARATOR,
        payload})
    SendAddonMessage(_prefixCode, msg, "WHISPER", _dbchar.master)
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
    GenerateMessage(MSG_HEADER.REPORT, REPORT_TYPE.EXPERIENCE, 0, bufferToString())
end

function PlayerbotsComsEmulator:GenerateItemEquippedReport(slot, count, link)
    local finalLink = _eval(link, link, NULL_LINK)
    local payload = _tconcat({slot, count, finalLink}, MSG_SEPARATOR)
    GenerateMessage(MSG_HEADER.REPORT, REPORT_TYPE.ITEM_EQUIPPED, 0, payload)
end

function PlayerbotsComsEmulator:Init()
    print("Starting emulator")
    _dbchar = PlayerbotsPanelEmu.db.char
    PlayerbotsComsEmulator.ScanBags(false)
    PlayerbotsComsEmulator.ScanCurrencies(false)
    CastSpellByID(13159)

end


function PlayerbotsComsEmulator:Update(elapsed)
    _time = _time + elapsed

    if _simLogout then return end

    if not _botStatus.handshake then   -- send handshake every second 
        if _nextHandshakeTime < _time then
            print("Sending handshake")
            _nextHandshakeTime = _time + 1
            GenerateMessage(MSG_HEADER.SYSTEM, SYS_MSG_TYPE.HANDSHAKE)
        end
    else
        if _nextBagScanTime < _time then
            _nextBagScanTime = _time + _bagScanTickrate
            if not CheckInteractDistance(_dbchar.master, 2) then
                CastSpellByID(13159)
                FollowUnit(_dbchar.master)
            end
            PlayerbotsComsEmulator.ScanCurrencies(false)
            PlayerbotsComsEmulator.ScanBagChanges(-2, false)
            for i = 0, 4 do
                PlayerbotsComsEmulator.ScanBagChanges(i, false)
            end
            if _atBank  then
                PlayerbotsComsEmulator.ScanBagChanges(-1, false)
                PlayerbotsComsEmulator.ScanBags(false, 5, 11)
            end
        end
    end
end

local SYS_MSG_HANDLERS = {}
SYS_MSG_HANDLERS[SYS_MSG_TYPE.HANDSHAKE] = function(id, payload)
    _botStatus.handshake = true
end

SYS_MSG_HANDLERS[SYS_MSG_TYPE.PING] = function(id, payload)
    GenerateMessage(MSG_HEADER.SYSTEM, SYS_MSG_TYPE.PING)
end

SYS_MSG_HANDLERS[SYS_MSG_TYPE.LOGOUT] = function(id, payload)
    _botStatus.handshake = false
end

local QUERY_MSG_HANDLERS = {}
QUERY_MSG_HANDLERS[QUERY_TYPE.WHO] = function (id, payload)
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
    }, MSG_SEPARATOR)
    GenerateMessage(MSG_HEADER.QUERY, QUERY_OPCODE.FINAL, id, payload)
end

-- WIP! WIP! WIP! WIP! WIP! WIP! WIP! WIP! WIP! WIP! WIP! WIP! WIP! WIP! WIP! WIP! WIP! WIP! WIP! WIP! WIP! WIP! 
QUERY_MSG_HANDLERS[QUERY_TYPE.STATS] = function (id, payload)
    --[[
        ratingIndex - Index of a rating; the following global constants are provided for convenience (number)
            CR_BLOCK - Block skill
            CR_CRIT_MELEE - Melee critical strike chance
            CR_CRIT_RANGED - Ranged critical strike chance
            CR_CRIT_SPELL - Spell critical strike chance
            CR_CRIT_TAKEN_MELEE - Melee Resilience
            CR_CRIT_TAKEN_RANGED - Ranged Resilience
            CR_CRIT_TAKEN_SPELL - Spell Resilience
            CR_DEFENSE_SKILL - Defense skill
            CR_DODGE - Dodge skill
            CR_HASTE_MELEE - Melee haste
            CR_HASTE_RANGED - Ranged haste
            CR_HASTE_SPELL - Spell haste
            CR_HIT_MELEE - Melee chance to hit
            CR_HIT_RANGED - Ranged chance to hit
            CR_HIT_SPELL - Spell chance to hit
            CR_HIT_TAKEN_MELEE - Unused
            CR_HIT_TAKEN_RANGED - Unused
            CR_HIT_TAKEN_SPELL - Unused
            CR_PARRY - Parry skill
            CR_WEAPON_SKILL - Weapon skill
            CR_WEAPON_SKILL_MAINHAND - Main-hand weapon skill
            CR_WEAPON_SKILL_OFFHAND - Offhand weapon skill
            CR_WEAPON_SKILL_RANGED - Ranged weapon skill
    ]]

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

    local _, effectiveArmor, _, armorPositive, armorNegative = UnitArmor(PLAYER)
    bufferAdd_INT(effectiveArmor)
    bufferAdd_INT(armorPositive)
    bufferAdd_INT(armorNegative)
    local _, effectivePetArmor, _, armorPetPositive, armorPetNegative = UnitArmor("pet")
    bufferAdd_INT(effectivePetArmor)
    bufferAdd_INT(armorPetPositive)
    bufferAdd_INT(armorPetNegative)

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

    local expertise = GetExpertise()
    local expertisePerc, offhandExpertisePercent = GetExpertisePercent()
    
    bufferAdd_INT(expertise, "expertise")
    bufferAdd_FLOAT(expertisePerc, "expertisePerc")
    bufferAdd_FLOAT(offhandExpertisePercent, "offhandExpertisePercent")


    GenerateMessage(MSG_HEADER.QUERY, QUERY_OPCODE.PROGRESS, id, _tconcat(_pbuffer, MSG_SEPARATOR))

    bufferClear()

    local minMeleeDamage, maxMeleeDamage, minMeleeOffHandDamage, maxMeleeOffHandDamage, meleePhysicalBonusPositive, meleePhysicalBonusNegative, meleeDamageBuffPercent = UnitDamage(PLAYER)
    local meleeSpeed, meleeOffhandSpeed = UnitAttackSpeed(PLAYER)
    local meleeAtkPowerBase, meleeAtkPowerPositive, meleeAtkPowerNegative = UnitAttackPower(PLAYER)
    local meleeHaste, meleeHasteBonus = GetCRValues(CR_HASTE_MELEE)
    local meleeCrit, meleeCritBonus = GetCRValues(CR_CRIT_MELEE)
    local meleeHit, meleeHitBonus = GetCRValues(CR_HIT_MELEE)
    local meleeResil, meleeResilBonus = GetCRValues(CR_CRIT_TAKEN_MELEE)
    
    -- All floats should be rounded to 2 decimals, so 0.513213 becomes 0.51

    bufferAdd_STRING("m")
    bufferAdd_FLOAT(minMeleeDamage, "minMeleeDamage")
    bufferAdd_FLOAT(maxMeleeDamage, "maxMeleeDamage") 
    bufferAdd_FLOAT(minMeleeOffHandDamage, "minMeleeOffHandDamage") 
    bufferAdd_FLOAT(maxMeleeOffHandDamage, "maxMeleeOffHandDamage") 
    bufferAdd_INT(meleePhysicalBonusPositive, "meleePhysicalBonusPositive") 
    bufferAdd_INT(meleePhysicalBonusNegative, "meleePhysicalBonusNegative")
    bufferAdd_FLOAT(meleeDamageBuffPercent, "meleeDamageBuffPercent") 

    bufferAdd_FLOAT(meleeSpeed, "meleeSpeed")
    bufferAdd_FLOAT(meleeOffhandSpeed, "meleeOffhandSpeed")

    bufferAdd_INT(meleeAtkPowerBase, "meleeAtkPowerBase")
    bufferAdd_INT(meleeAtkPowerPositive, "meleeAtkPowerPositive")
    bufferAdd_INT(meleeAtkPowerNegative, "meleeAtkPowerNegative")

    bufferAdd_INT(meleeHaste, "meleeHaste")
    bufferAdd_FLOAT(meleeHasteBonus, "meleeHasteBonus")

    bufferAdd_INT(meleeCrit, "meleeCrit")
    bufferAdd_FLOAT(meleeCritBonus, "meleeCritBonus") 

    bufferAdd_INT(meleeHit, "meleeHit")
    bufferAdd_FLOAT(meleeHitBonus, "meleeHitBonus") 

    bufferAdd_INT(meleeResil, "meleeResil")
    bufferAdd_FLOAT(meleeResilBonus, "meleeResilBonus") 

    GenerateMessage(MSG_HEADER.QUERY, QUERY_OPCODE.FINAL, id, _tconcat(_pbuffer, MSG_SEPARATOR))
end

QUERY_MSG_HANDLERS[QUERY_TYPE.GEAR] = function (id, _)
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
            local payload = _tconcat({i, count, link}, MSG_SEPARATOR)
            GenerateMessage(MSG_HEADER.QUERY, QUERY_OPCODE.PROGRESS, id, payload)
        end
    end
    GenerateMessage(MSG_HEADER.QUERY, QUERY_OPCODE.FINAL, id, nil)
end

QUERY_MSG_HANDLERS[QUERY_TYPE.INVENTORY] = function (id, _)

    local function genBag(bag)
        local name = GetBagName(bag)
        if name then 
            local slots = GetContainerNumSlots(bag)
            local _, link, _, _, _, _, _, _, _, _, _ = GetItemInfo(name)
            local payload = _tconcat({"b", tostring(bag), tostring(slots), link }, MSG_SEPARATOR)
            GenerateMessage(MSG_HEADER.QUERY, QUERY_OPCODE.PROGRESS, id, payload)
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
                local payload = _tconcat({"i", tostring(bag), tostring(slot), tostring(count), link }, MSG_SEPARATOR)
                GenerateMessage(MSG_HEADER.QUERY, QUERY_OPCODE.PROGRESS, id, payload)
            end
        end
    end

    genItems(-2)
    for bag = 0, 4 do
        genItems(bag)
    end

    GenerateMessage(MSG_HEADER.QUERY, QUERY_OPCODE.FINAL, id, nil)
end

QUERY_MSG_HANDLERS[QUERY_TYPE.CURRENCY] = function (id, payload)
    local cache = _currencyCache
    local payload = _tconcat({CURRENCY_MONEY, tostring(cache.gold), tostring(cache.silver), tostring(cache.copper) }, MSG_SEPARATOR) -- report gold changed
    GenerateMessage(MSG_HEADER.QUERY, QUERY_OPCODE.PROGRESS, id, payload)

    for itemId, count in pairs(_currencyCache.other) do
        if itemId ~= 0 then
            local payload = _tconcat({CURRENCY_OTHER, tostring(itemId), tostring(count) }, MSG_SEPARATOR) -- report other currency changed
            GenerateMessage(MSG_HEADER.QUERY, QUERY_OPCODE.PROGRESS, id, payload)
        end
    end

    GenerateMessage(MSG_HEADER.QUERY, QUERY_OPCODE.FINAL, id, nil)
end

local COMMAND_HANDLERS_ITEM = {}
COMMAND_HANDLERS_ITEM[COMMAND.ITEM_USE] = function ()
    print("cmd.item_use")
    local link = _parser:nextLink()
    local bag, slot, item = PlayerbotsComsEmulator.FindItemByLink(link)
    if item then
        UseContainerItem(bag, slot, "player")
    end
end

COMMAND_HANDLERS_ITEM[COMMAND.ITEM_USE_ON] = function ()
    print("cmd.item_use_on")
    local link1 = _parser:nextLink()
    local link2 = _parser:nextLink()
    local bag1, slot1, item1 = PlayerbotsComsEmulator.FindItemByLink(link1)
    local bag2, slot2, item2 = PlayerbotsComsEmulator.FindItemByLink(link2)
    if item1 and item2 then
        PickupItem(item1.link)
        -- Unfinished
    end
end

COMMAND_HANDLERS_ITEM[COMMAND.ITEM_EQUIP] = function ()
    print("cmd.item_equip")
    local link = _parser:nextLink()
    local bag, slot, item = PlayerbotsComsEmulator.FindItemByLink(link)
    if item then
        UseContainerItem(bag, slot, "player")
    end
end

COMMAND_HANDLERS_ITEM[COMMAND.ITEM_UNEQUIP] = function ()
    print("cmd.item_unequip")
    local link = _parser:nextLink()
    local eslot = PlayerbotsComsEmulator.FindEquipSlotByLink(link)
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
    PlayerbotsComsEmulator:ScanBags()
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
COMMAND_HANDLERS[COMMAND.ITEM] = function (id, payload)
    _parser:start(payload)
    local subCmd = _parser:nextCharAsByte()
    local impl = COMMAND_HANDLERS_ITEM[subCmd]
    if impl then
        impl()
    end
end



local MSG_HANDLERS = {}
MSG_HANDLERS[MSG_HEADER.SYSTEM] = SYS_MSG_HANDLERS
MSG_HANDLERS[MSG_HEADER.REPORT] = {}
MSG_HANDLERS[MSG_HEADER.COMMAND] = COMMAND_HANDLERS

--EquipItemByName

function PlayerbotsComsEmulator:CHAT_MSG_ADDON(prefix, message, channel, sender)
    print("|cffb4ff29 << MASTER |r " .. message)
    if sender == _dbchar.master then
        if prefix == _prefixCode then
            -- confirm that the message has valid format
            local header, sep1, subtype, sep2, idb1, idb2, idb3, sep3 = _strbyte(message, 1, 8)
            local _separatorByte = MSG_SEPARATOR_BYTE
            -- BYTES
            -- 1 [HEADER] 2 [SEPARATOR] 3 [SUBTYPE/QUERY_OPCODE] 4 [SEPARATOR] 5-6-7 [ID] 8 [SEPARATOR] 9 [PAYLOAD / NEXT QUERY]
            -- s:p:999:payload
            if sep1 == _separatorByte and sep2 == _separatorByte and sep3 == _separatorByte then
                if header == MSG_HEADER.QUERY then
                    -- here we treat queries differently because master can pack multiple queries into a single message
                    -- total length of a query is 8 bytes, so in a single message we can pack 30 queries (taking into account trailing sep) (254 max length/8)
                    for offset = 0, 29 do
                        if offset > 0 then
                            header, _, subtype, _, idb1, idb2, idb3, _ = _strbyte(message, 8 * offset, 8 * (offset + 1))
                        end
                        if header and header == MSG_HEADER.QUERY then
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

function PlayerbotsComsEmulator:SimLogout()
    GenerateMessage(MSG_HEADER.SYSTEM, SYS_MSG_TYPE.LOGOUT)
    _simLogout = true
    _botStatus.handshake = false
end

function PlayerbotsComsEmulator:SimLogin()
    _simLogout = false
end

function PlayerbotsComsEmulator:PLAYER_LOGIN()
end

function PlayerbotsComsEmulator:PLAYER_LOGOUT()
end

function PlayerbotsComsEmulator:PLAYER_LEVEL_UP(levelFromEvent)
    GenerateExperienceReport(levelFromEvent)
end

function PlayerbotsComsEmulator:BANKFRAME_OPENED()
    _atBank = true
end

function PlayerbotsComsEmulator:BANKFRAME_CLOSED()
    _atBank = false
end

function PlayerbotsComsEmulator:TRADE_ACCEPT_UPDATE(player, target)
    if target == 1 then
        AcceptTrade()
    end
end

function PlayerbotsComsEmulator.SetBagChanged(bagSlot)
    if bagSlot >= 0 then
        _changedBags[bagSlot] = true
    end
end

function PlayerbotsComsEmulator.ScanBagChanges(bagSlot, silent)
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
                local payload = _tconcat({"b", tostring(bagSlot), tostring(size), link }, MSG_SEPARATOR)
                GenerateMessage(MSG_HEADER.REPORT, REPORT_TYPE.INVENTORY, nil, payload)
            end
        else
            if not silent and bagState.link then -- bag was removed from this slot
                bagState.link = nil
                bagState.size = 0
                local payload = _tconcat({"b", tostring(bagSlot), tostring(0), NULL_LINK }, MSG_SEPARATOR)
                GenerateMessage(MSG_HEADER.REPORT, REPORT_TYPE.INVENTORY, nil, payload)
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
                        local payload = _tconcat({"i", tostring(bagSlot), tostring(slot), tostring(count), link }, MSG_SEPARATOR)
                        GenerateMessage(MSG_HEADER.REPORT, REPORT_TYPE.INVENTORY, nil, payload)
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
                local payload = _tconcat({"i", tostring(bagSlot), tostring(slot), tostring(count), _eval(link, link, NULL_LINK) }, MSG_SEPARATOR)
                GenerateMessage(MSG_HEADER.REPORT, REPORT_TYPE.INVENTORY, nil, payload)
            end
        end
    end
end

function  PlayerbotsComsEmulator.ScanBags(silent, startBag, endBag) -- silent will not create reports, used when initializing
    local scanStart = _eval(startBag, startBag, -2)
    local scanEnd = _eval(endBag, endBag, 11)
    for i=scanStart, scanEnd do
        PlayerbotsComsEmulator.ScanBagChanges(i, silent)
    end
end


function  PlayerbotsComsEmulator.ScanCurrencies(silent)
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
        local payload = _tconcat({CURRENCY_MONEY, tostring(gold), tostring(silver), tostring(copper) }, MSG_SEPARATOR) -- report gold changed
        GenerateMessage(MSG_HEADER.REPORT, REPORT_TYPE.CURRENCY, nil, payload)
    end

    for index = 1, GetCurrencyListSize() do
        local name, isHeader, isExpanded, isUnused, isWatched, count, extraCurrencyType, icon, itemID = GetCurrencyListInfo(index)
        if itemID ~= 0 then
            if _currencyCache.other[itemID] ~= count then
                _currencyCache.other[itemID] = count
                if not silent then
                    local payload = _tconcat({CURRENCY_OTHER, tostring(itemID), tostring(count) }, MSG_SEPARATOR) -- report other currency changed
                    GenerateMessage(MSG_HEADER.REPORT, REPORT_TYPE.CURRENCY, nil, payload)
                end
            end
        end
    end
end

function PlayerbotsComsEmulator.FindItemByLink(link)
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

function PlayerbotsComsEmulator.FindEquipSlotByLink(link)
    if link and _parser.validateLink(link) then
        for eslot = 0, 20 do 
            local equipped = GetInventoryItemLink("player", eslot)
            if equipped == link then
                return eslot
            end
        end
    end
end