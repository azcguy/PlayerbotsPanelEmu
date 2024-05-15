PlayerbotsComsEmulator = {}
local _emu = PlayerbotsComsEmulator
local _cfg = PlayerbotsPanelEmuConfig
local _debug = AceLibrary:GetInstance("AceDebug-2.0")
local _dbchar = nil
local _simLogout = false

local _prefixCode = "pb8aj2" -- just something unique from other addons
local _handshakeCode = "hs"
local _logoutCode = "lo"

local _ping = "p"
local _botStatus = {}
_botStatus.handshake = false -- reset on logout

-- ============================================================================================

local MSG_SEPARATOR = ":"
local NULL_LINK = "~"
local MSG_SEPARATOR_BYTE = string.byte(":")

local MSG_HEADER = {}
MSG_HEADER.SYSTEM = string.byte("s")
MSG_HEADER.REPORT = string.byte("r")

PlayerbotsBrokerReportType = {}
local REPORT_TYPE = PlayerbotsBrokerReportType
REPORT_TYPE.ITEM_EQUIPPED = string.byte("g") -- gear item equipped or unequipped
REPORT_TYPE.CURRENCY = string.byte("c") -- currency changed
REPORT_TYPE.INVENTORY = string.byte("i") -- inventory changed (bag changed, item added / removed / destroyed)
REPORT_TYPE.TALENTS = string.byte("t") -- talent learned / spec changed / talents reset
REPORT_TYPE.SPELLS = string.byte("s") -- spell learned
REPORT_TYPE.QUEST = string.byte("q") -- single quest accepted, abandoned, changed, completed

local SYS_MSG_TYPE = {}
SYS_MSG_TYPE.HANDSHAKE = string.byte("h")
SYS_MSG_TYPE.PING = string.byte("p")
SYS_MSG_TYPE.LOGOUT = string.byte("l")

-- ============================================================================================

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

local MSG_HANDLERS = {}
MSG_HANDLERS[MSG_HEADER.SYSTEM] = SYS_MSG_HANDLERS
MSG_HANDLERS[MSG_HEADER.REPORT] = REP_MSG_HANDLERS

function PlayerbotsComsEmulator:CHAT_MSG_ADDON(prefix, message, channel, sender)
    print("MASTER >> " .. message)
    if sender == _dbchar.master then
        if prefix == _prefixCode then
            -- confirm that the message has valid format
            local header, separator1, subtype, separator2 = strbyte(message, 1, 4)
            local separator3 = strbyte(message, 8)
            -- 1 [HEADER] 2 [SEPARATOR] 3 [SUBTYPE] 4 [SEPARATOR] 5 [ID1] 6 [ID2] 7 [ID3] 8 [ID4] 9 [ID5] 10 [SEPARATOR] [PAYLOAD]
            -- s:p:65000:payload
            if separator1 == MSG_SEPARATOR_BYTE and separator2 == MSG_SEPARATOR_BYTE and separator3 == MSG_SEPARATOR_BYTE then
                local handlers = MSG_HANDLERS[header]
                if handlers then
                    local handler = handlers[subtype]
                    if handler then
                        local id = tonumber(strsub(5, 7))
                        local payload = strsub(message, 9)
                        handler(id, payload)
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