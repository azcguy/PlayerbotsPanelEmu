PlayerbotsComsEmulator = {}
local _emu = PlayerbotsComsEmulator
local _cfg = PlayerbotsPanelEmuConfig
local _debug = AceLibrary:GetInstance("AceDebug-2.0")
local _dbchar = nil
local _master = nil

local _prefixCode = "pp8aj2" -- just something unique from other addons
local _handshakeCode = "hs"
local _botStatus = {}
_botStatus.handshake = false -- reset on logout



function PlayerbotsComsEmulator:Init()
    print("Starting emulator")
    _dbchar = PlayerbotsPanelEmu.db.char
end

local _time = 0
local _nextHandshakeTime = 0
function PlayerbotsComsEmulator:Update(elapsed)
    _time = _time + elapsed
    if not _botStatus.handshake then   -- send handshake every second 
        if _nextHandshakeTime < _time then
            print("Sending handshake")
            _nextHandshakeTime = _time + 1
            Send(_handshakeCode)            
        end
    else
        -- start sending periodic reports and responding to queries
    end
end

function PlayerbotsComsEmulator:CHAT_MSG_ADDON(prefix, message, channel, sender)
    if prefix == _prefixCode then
        if not _botStatus.handshake then
            if message == _handshakeCode then
                _botStatus.handshake = true
            end
        else
            

        end
    end
end

local function print(t)
    DEFAULT_CHAT_FRAME:AddMessage("PlayerbotsPanelEmu: " .. t)
end

-- Sends addon msg to master
function Send(msg)
    SendAddonMessage(_prefixCode, msg, "WHISPER", _dbchar.master)
end