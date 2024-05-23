PlayerbotsComsEmulator = {}
local _emu = PlayerbotsComsEmulator
local _cfg = PlayerbotsPanelEmuConfig
local _debug = AceLibrary:GetInstance("AceDebug-2.0")
local _dbchar = {}
local _simLogout = false
local _updateHandler = PlayerbotsPanelUpdateHandler

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
local _pbuffer = {} -- payload buffer

-- ============================================================================================
-- SHARED BETWEEN EMU/BROKER

local MSG_SEPARATOR = ":"
local MSG_SEPARATOR_BYTE = _strbyte(":")
local FLOAT_DOT_BYTE = _strbyte(".")
local MSG_HEADER = {}
local NULL_LINK = "~"
local UTF8_NUM_FIRST = _strbyte("1") -- 49
local UTF8_NUM_LAST = _strbyte("9") -- 57

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
QUERY_TYPE.GEAR       =         _strbyte("g") -- only what is equipped
QUERY_TYPE.INVENTORY  =         _strbyte("i") -- whats in the bags and bags themselves
QUERY_TYPE.TALENTS    =         _strbyte("t") -- talents and talent points 
QUERY_TYPE.SPELLS     =         _strbyte("s") -- spellbook
QUERY_TYPE.QUESTS     =         _strbyte("q") -- all quests
QUERY_TYPE.STRATEGIES =         _strbyte("S")

PlayerbotsBrokerQueryOpcode = {}
local QUERY_OPCODE = PlayerbotsBrokerQueryOpcode
QUERY_OPCODE.PROGRESS =         _strbyte("p") -- query is in progress
QUERY_OPCODE.FINAL    =         _strbyte("f") -- final message of the query, contains the final payload, and closes query
-- bytes 49 - 57 are errors


PlayerbotsBrokerCommandType = {}
local CMD_TYPE = PlayerbotsBrokerCommandType
CMD_TYPE.SUMMON = 0 
CMD_TYPE.STAY = 1
CMD_TYPE.FOLLOW = 2

-- ============================================================================================

local _changedBags = {}
local _shouldScanBags = false
local _bagstates = {}

for i=-2, 11 do
    local size = 0
    if i == -2 then size = 32 end -- -2 keychain
    if i == -1 then size = 28 end -- -1 bank space
    if i == 0 then size = 16 end  --  0 backpack
    _bagstates[i] = {
        link = nil,
        size = size,
        contents = {}
    }
end

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

local function GenerateExperienceReport()
    local level = UnitLevel(PLAYER)
    local floatXp = inverseLerp(0.0, UnitXPMax(PLAYER), UnitXP(PLAYER))
    local payload = _tconcat({level, floatXp}, MSG_SEPARATOR)
    GenerateMessage(MSG_HEADER.REPORT, REPORT_TYPE.EXPERIENCE, 0, payload)
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
end

local _time = 0
local _nextHandshakeTime = 0
local _nextBagScanTime = 0
local _bagScanTickrate = 0.1
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
            for i = 0, 4 do
                PlayerbotsComsEmulator.ScanBagChanges(i, false)
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
    for bag = 1, 4 do
        local name = GetBagName(bag)
        if name then 
            local slots = GetContainerNumSlots(bag)
            local _, link, _, _, _, _, _, _, _, _, _ = GetItemInfo(name)
            local payload = _tconcat({"b", tostring(bag), tostring(slots), link }, MSG_SEPARATOR)
            GenerateMessage(MSG_HEADER.QUERY, QUERY_OPCODE.PROGRESS, id, payload)
        end
    end

    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag)
        for slot = 1, slots do
            local texture, count, locked, quality, readable, lootable, link = GetContainerItemInfo(bag, slot)
            if link then
                local payload = _tconcat({"i", tostring(bag), tostring(slot), tostring(count), link }, MSG_SEPARATOR)
                GenerateMessage(MSG_HEADER.QUERY, QUERY_OPCODE.PROGRESS, id, payload)
            end
        end
    end

    GenerateMessage(MSG_HEADER.QUERY, QUERY_OPCODE.FINAL, id, nil)
end

local MSG_HANDLERS = {}
MSG_HANDLERS[MSG_HEADER.SYSTEM] = SYS_MSG_HANDLERS
MSG_HANDLERS[MSG_HEADER.REPORT] = {}

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

function PlayerbotsComsEmulator:PLAYER_LEVEL_UP()
    GenerateExperienceReport()
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
                            count = 0
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
                local payload = _tconcat({"i", tostring(bagSlot), tostring(slot), tostring(count), link }, MSG_SEPARATOR)
                GenerateMessage(MSG_HEADER.REPORT, REPORT_TYPE.INVENTORY, nil, payload)
            end
        end
    end
end

function  PlayerbotsComsEmulator.ScanBags(silent, startBag, endBag) -- silent will not create reports, used when initializing
    local scanStart = _eval(startBag, startBag, 0)
    local scanEnd = _eval(endBag, endBag, 11)
    for i=scanStart, scanEnd do
        PlayerbotsComsEmulator.ScanBagChanges(i, silent)

    end
end


--function PlayerbotsComsEmulator:GenerateWhoReport(level, location)