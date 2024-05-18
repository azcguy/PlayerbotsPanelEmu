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

-- ============================================================================================
-- SHARED BETWEEN EMU/BROKER

local MSG_SEPARATOR = ":"
local MSG_SEPARATOR_BYTE = _strbyte(":")
local FLOAT_DOT_BYTE = _strbyte(".")
local MSG_HEADER = {}
local NULL_LINK = "~"
local UTF8_NUM_FIRST = _strbyte("1") -- 49
local UTF8_NUM_LAST = _strbyte("9") -- 57

MSG_HEADER.SYSTEM = _strbyte("s")
MSG_HEADER.REPORT = _strbyte("r")
MSG_HEADER.QUERY = _strbyte("q")

PlayerbotsBrokerReportType = {}
local REPORT_TYPE = PlayerbotsBrokerReportType
REPORT_TYPE.ITEM_EQUIPPED = _strbyte("g") -- gear item equipped or unequipped
REPORT_TYPE.CURRENCY = _strbyte("c") -- currency changed
REPORT_TYPE.INVENTORY = _strbyte("i") -- inventory changed (bag changed, item added / removed / destroyed)
REPORT_TYPE.TALENTS = _strbyte("t") -- talent learned / spec changed / talents reset
REPORT_TYPE.SPELLS = _strbyte("s") -- spell learned
REPORT_TYPE.QUEST = _strbyte("q") -- single quest accepted, abandoned, changed, completed

local SYS_MSG_TYPE = {}
SYS_MSG_TYPE.HANDSHAKE = _strbyte("h")
SYS_MSG_TYPE.PING = _strbyte("p")
SYS_MSG_TYPE.LOGOUT = _strbyte("l")


PlayerbotsBrokerQueryType = {}
local QUERY_TYPE = PlayerbotsBrokerQueryType
QUERY_TYPE.WHO = _strbyte("w") -- level, class, spec, location, experience and more
QUERY_TYPE.CURRENCY = _strbyte("c") -- money, honor, tokens
QUERY_TYPE.GEAR = _strbyte("g") -- only what is equipped
QUERY_TYPE.INVENTORY = _strbyte("i") -- whats in the bags and bags themselves
QUERY_TYPE.TALENTS = _strbyte("t") -- talents and talent points 
QUERY_TYPE.SPELLS = _strbyte("s") -- spellbook
QUERY_TYPE.QUESTS = _strbyte("q") -- all quests
QUERY_TYPE.STRATEGIES = _strbyte("S")

PlayerbotsBrokerQueryOpcode = {}
local QUERY_OPCODE = PlayerbotsBrokerQueryOpcode
QUERY_OPCODE.PROGRESS = _strbyte("p") -- query is in progress
QUERY_OPCODE.FINAL = _strbyte("f") -- final message of the query, contains the final payload, and closes query
-- bytes 49 - 57 are errors


PlayerbotsBrokerCommandType = {}
local CMD_TYPE = PlayerbotsBrokerCommandType
CMD_TYPE.SUMMON = 0 
CMD_TYPE.STAY = 1
CMD_TYPE.FOLLOW = 2

-- ============================================================================================

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

function PlayerbotsComsEmulator:Init()
    print("Starting emulator")
    _dbchar = PlayerbotsPanelEmu.db.char
end

local _time = 0
local _nextHandshakeTime = 0
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
        -- start sending periodic reports and responding to queries
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
    local spec2_unlocked = GetNumTalentGroups(false, false) > 1 and 1 or 0
    local active_spec = GetActiveTalentGroup(false, false)
    local _, _, points1,_, _ = GetTalentTabInfo(1, nil, nil, 1) -- Return values id, description, and isUnlocked were added in patch 4.0.1 despite what API says
    local _, _, points2,_, _ = GetTalentTabInfo(2, false, false, 1)
    local _, _, points3,_, _ = GetTalentTabInfo(3, false, false, 1)
    local level = UnitLevel(PLAYER)
    local zone = GetZoneText()
    local floatXp = inverseLerp(0, UnitXPMax(PLAYER), UnitXP(PLAYER))
    local points4 = 0 -- second spec
    local points5 = 0
    local points6 = 0
    if spec2_unlocked > 0 then
        _, _, points4, _, _ = GetTalentTabInfo(1, false, false, 2)
        _, _, points5, _, _ = GetTalentTabInfo(2, false, false, 2)
        _, _, points6, _, _ = GetTalentTabInfo(3, false, false, 2)
    end
    local payload = table.concat({
        class,
        MSG_SEPARATOR,
        level,
        MSG_SEPARATOR,
        spec2_unlocked,
        MSG_SEPARATOR,
        active_spec, -- dualspec
        MSG_SEPARATOR,
        points1,
        MSG_SEPARATOR,
        points2,
        MSG_SEPARATOR,
        points3,
        MSG_SEPARATOR,
        points4,
        MSG_SEPARATOR,
        points5,
        MSG_SEPARATOR,
        points6,
        MSG_SEPARATOR,
        floatXp,
        MSG_SEPARATOR,
        zone
    })
    GenerateMessage(MSG_HEADER.QUERY, QUERY_OPCODE.FINAL, id, payload)
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

local function print(t)
    DEFAULT_CHAT_FRAME:AddMessage("EMU: " .. t)
end

function PlayerbotsComsEmulator:GenerateItemEquippedReport(slot, count, link)
    local finalLink = link and link or NULL_LINK
    local payload = table.concat({tostring(slot), MSG_SEPARATOR, tostring(count), MSG_SEPARATOR, finalLink})
    GenerateMessage(MSG_HEADER.REPORT, REPORT_TYPE.ITEM_EQUIPPED, 0, payload)
end


--function PlayerbotsComsEmulator:GenerateWhoReport(level, location)