ROOT_PATH     = "Interface\\AddOns\\PlayerbotsPanel\\"
PlayerbotsPanelEmu    = AceLibrary("AceAddon-2.0"):new("AceConsole-2.0", "AceDB-2.0", "AceHook-2.1", "AceDebug-2.0", "AceEvent-2.0")
PlayerbotsPanelEmuFrame    = CreateFrame("Frame", "PlayerbotsPanelEmuFrame", UIParent)
PlayerbotsPanelEmu:RegisterDB("PlayerbotsPanelEmuDb", "PlayerbotsPanelEmuDbPerChar")

local _frame = PlayerbotsPanelEmuFrame
local _cfg = PlayerbotsPanelEmuConfig
local _debug = AceLibrary:GetInstance("AceDebug-2.0")
local _dbchar = {}
local _dbaccount = nil
local _emu = PlayerbotsComsEmulator


-- chat commands to control addon itself
PlayerbotsPanelEmu.commands = {
    type = 'group',
    args = {
        toggle = {
            name = "toggle",
            desc = "Toggle PlayerbotsPanel",
            type = 'execute',
            func = function() PlayerbotsPanelEmu:OnClick() end
        },
        clearAll = {
            name = "clearall",
            desc = "Clears all bot data",
            type = 'execute',
            func = function() 
                print("Clearing all bot data")
                if _dbchar then
                    _dbchar.bots = {}
                end
            end
        }
    }
}

function PlayerbotsPanelEmu:OnInitialize()
    print("Initialized")
    _debug:SetDebugging(true)
    _debug:SetDebugLevel(_cfg.debugLevel)
    _frame:HookScript("OnUpdate", PlayerbotsPanelEmu.Update)
    _dbchar = PlayerbotsPanelEmu.db.char
    _dbaccount = PlayerbotsPanelEmu.db.account
    self:CreateWindow()
    self:RegisterChatCommand("/ppemu", self.commands)
    self:RegisterEvent("CHAT_MSG_ADDON")
    self:RegisterEvent("PLAYER_LOGIN")
    self:RegisterEvent("PLAYER_LOGOUT")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    _emu:Init()
end

function PlayerbotsPanelEmu:PLAYER_LOGIN()
    _emu:PLAYER_LOGIN()
end
function PlayerbotsPanelEmu:PLAYER_LOGOUT()
    _emu:PLAYER_LOGOUT()
end

function PlayerbotsPanelEmu:PLAYER_ENTERING_WORLD()
    _frame:Show()
end

function PlayerbotsPanelEmu:PLAYER_EQUIPMENT_CHANGED(slot, hasItem)
    local link = nil
    local count = 0
    if hasItem then
        link = GetInventoryItemLink("player", slot)
        count = GetInventoryItemCount("player", slot)
    end
    _emu:GenerateItemEquippedReport(slot, count, link)
end

function PlayerbotsPanelEmu:OnEnable()
    self:SetDebugging(true)
    _frame:Show()
end

function PlayerbotsPanelEmu:OnShow()
end

function PlayerbotsPanelEmu:OnHide()
end

function PlayerbotsPanelEmu:OnDisable()
    self:SetDebugging(false) 
    _emu:PLAYER_LOGOUT()
end

function PlayerbotsPanelEmu:Update(elapsed)
    _emu:Update(elapsed)
end

function PlayerbotsPanelEmu:ClosePanel()
	HideUIPanel(PlayerbotsPanelEmuFrame)
end

function PlayerbotsPanelEmu:print(t)
    DEFAULT_CHAT_FRAME:AddMessage("PlayerbotsPanelEmu: " .. t)
end

function PlayerbotsPanelEmu:CHAT_MSG_ADDON(prefix, message, channel, sender)
    _emu:CHAT_MSG_ADDON(prefix, message, channel, sender)
end

function PlayerbotsPanelEmu:OnClick()
    if _frame:IsVisible() then
        _frame:Hide()
    else 
        _frame:Show()
    end
end

function PlayerbotsPanelEmu:CreateWindow()
    UIPanelWindows[_frame:GetName()] = { area = "center", pushable = 0, whileDead = 1 }
    tinsert(UISpecialFrames, _frame:GetName())
    _frame:SetFrameStrata("DIALOG")
    _frame:SetWidth(800)
    _frame:SetHeight(420)
    _frame:SetPoint("CENTER")
    _frame:SetMovable(true)
    _frame:RegisterForDrag("LeftButton")
    _frame:SetScript("OnDragStart", _frame.StartMoving)
    _frame:SetScript("OnDragStop", _frame.StopMovingOrSizing)
    _frame:SetScript("OnShow", PlayerbotsPanelEmu.OnShow)
    _frame:SetScript("OnHide", PlayerbotsPanelEmu.OnHide)
    _frame:EnableMouse(true)
    _frame.tex = _frame:CreateTexture(nil, "ARTWORK")
    _frame.tex:SetTexture("Interface\\FriendsFrame\\PlusManz-CharacterBG.blp")
    _frame.tex:SetTexCoord(0.15, 0.85, 0.18, 0.82)
    _frame.tex:SetSize(_frame:GetWidth(), _frame:GetHeight())
    _frame.tex:SetPoint("TOPLEFT", 0, 0)

    local rowHeight = 20
    local currentY = 0
    local strMaster =  _frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    strMaster:SetPoint("TOPLEFT", 120 + 150, currentY)
    strMaster:SetSize(150, rowHeight)
    strMaster:SetText(_dbchar.master)

    local ebSetMaster = CreateFrame("EditBox", nil, _frame, "InputBoxTemplate")
    ebSetMaster:SetPoint("TOPLEFT", 120,currentY)
    ebSetMaster:SetSize(150,rowHeight)
    ebSetMaster:SetText("")
    ebSetMaster:SetAutoFocus(false)

    local btnSetMaster = CreateFrame("Button", nil, _frame, "UIPanelButtonTemplate")
    btnSetMaster:SetPoint("TOPLEFT", 0, currentY)
    btnSetMaster:SetSize(120,rowHeight)
    btnSetMaster:SetText("Set master")
    btnSetMaster:SetScript("OnClick", function(self, button, down)
        ebSetMaster:ClearFocus()
        _dbchar.master = ebSetMaster:GetText()
        strMaster:SetText(_dbchar.master)
    end)
    btnSetMaster:RegisterForClicks("AnyUp")

    currentY = currentY - 25
    local btnSimLogout = CreateFrame("Button", nil, _frame, "UIPanelButtonTemplate")
    btnSimLogout:SetPoint("TOPLEFT", 0, currentY)
    btnSimLogout:SetSize(100,rowHeight)
    btnSimLogout:SetText("Sim Logout")
    btnSimLogout:SetScript("OnClick", function(self, button, down)
        _emu:SimLogout()
    end)
    btnSimLogout:RegisterForClicks("AnyUp")

    local btnSimLogout = CreateFrame("Button", nil, _frame, "UIPanelButtonTemplate")
    btnSimLogout:SetPoint("TOPLEFT", 100, currentY)
    btnSimLogout:SetSize(100, rowHeight)
    btnSimLogout:SetText("Sim Login")
    btnSimLogout:SetScript("OnClick", function(self, button, down)
        _emu:SimLogin()
    end)
    btnSimLogout:RegisterForClicks("AnyUp")
end



