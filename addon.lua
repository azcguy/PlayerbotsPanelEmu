
local _self = PlayerbotsPanelEmu
local _frame = PlayerbotsPanelEmu.frame
local _cfg = PlayerbotsPanelEmu.config
local _emu = PlayerbotsPanelEmu.emulator
local _debug = AceLibrary:GetInstance("AceDebug-2.0")
local _dbchar = {}
local _dbaccount = nil


-- chat commands to control addon itself
_self.commands = {
    type = 'group',
    args = {
        toggle = {
            name = "toggle",
            desc = "Toggle PlayerbotsPanel",
            type = 'execute',
            func = function() _self:OnClick() end
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

function _self:OnInitialize()
    print("Initialized")
    _debug:SetDebugging(true)
    _debug:SetDebugLevel(_cfg.debugLevel)
    _frame:HookScript("OnUpdate", PlayerbotsPanelEmu.Update)
    _dbchar = PlayerbotsPanelEmu.db.char
    _dbaccount = PlayerbotsPanelEmu.db.account
    _self:CreateWindow()
    _self:RegisterChatCommand("/ppemu", _self.commands)
    _self:RegisterEvent("CHAT_MSG_ADDON")
    _self:RegisterEvent("PLAYER_LOGIN")
    _self:RegisterEvent("PLAYER_LOGOUT")
    _self:RegisterEvent("PLAYER_ENTERING_WORLD")
    _self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    _self:RegisterEvent("PLAYER_LEVEL_UP")
    _self:RegisterEvent("BAG_UPDATE")
    _self:RegisterEvent("BANKFRAME_OPENED")
    _self:RegisterEvent("BANKFRAME_CLOSED")
    _self:RegisterEvent("TRADE_ACCEPT_UPDATE")
    _self:RegisterEvent("EQUIP_BIND_CONFIRM")
    _emu:Init()

    local botText = CreateFrame("Frame", nil, UIParent)
    botText:SetSize(1300, 300)
    botText:SetPoint("TOPLEFT", 0, 0)
    botText.text = botText:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    botText.text:SetAllPoints()
    botText.text:SetText("B O T")
    botText.text:SetTextHeight(300)
    botText.text:SetTextColor(1, 0, 1 )
end

function _self:EQUIP_BIND_CONFIRM(index)
    EquipPendingItem(index)
end

function _self:BAG_UPDATE(bagID)
    _emu.SetBagChanged(bagID)
end
function _self:PLAYER_LOGIN()
    _emu:PLAYER_LOGIN()
end
function _self:PLAYER_LOGOUT()
    _emu:PLAYER_LOGOUT()
end

function _self:BANKFRAME_OPENED()
    _emu:BANKFRAME_OPENED()
end

function _self:BANKFRAME_CLOSED()
    _emu:BANKFRAME_CLOSED()
end

function _self:TRADE_ACCEPT_UPDATE(player, target)
    _emu:TRADE_ACCEPT_UPDATE(player, target)
end

function _self:PLAYER_ENTERING_WORLD()
    _frame:Show()
end

function _self:PLAYER_EQUIPMENT_CHANGED(slot, hasItem)
    local link = nil
    local count = 0
    if hasItem then
        link = GetInventoryItemLink("player", slot)
        count = GetInventoryItemCount("player", slot)
    end
    _emu:GenerateItemEquippedReport(slot, count, link)
end

function _self:PLAYER_LEVEL_UP(levelFromEvent)
    _emu:PLAYER_LEVEL_UP(levelFromEvent)
end

function _self:OnEnable()
    self:SetDebugging(true)
    _frame:Show()
end

function _self:OnShow()
end

function _self:OnHide()
end

function _self:OnDisable()
    self:SetDebugging(false) 
    _emu:PLAYER_LOGOUT()
end

function _self:Update(elapsed)
    _emu:Update(elapsed)
end

function _self:ClosePanel()
	HideUIPanel(_frame)
end

function _self:print(t)
    DEFAULT_CHAT_FRAME:AddMessage("PlayerbotsPanelEmu: " .. t)
end

function _self:CHAT_MSG_ADDON(prefix, message, channel, sender)
    _emu:CHAT_MSG_ADDON(prefix, message, channel, sender)
end

function _self:OnClick()
    if _frame:IsVisible() then
        _frame:Hide()
    else 
        _frame:Show()
    end
end

local function MakeButton(text, x, y, sx, sy, onClick)
    local btn = CreateFrame("Button", nil, _frame, "UIPanelButtonTemplate")
    btn:SetPoint("TOPLEFT", x, y)
    btn:SetSize(sx,sy)
    btn:SetText(text)
    btn:SetScript("OnClick", function(self, button, down)
        onClick()
    end)
    btn:RegisterForClicks("AnyUp")
end

local bags = {}

local function CacheInventory()
    
end

local function  DumpBagLinks()
    for bag = 0, 4 do
        local name = GetBagName(bag)
        if name then
            local _, link, _, _, _, _, _, _, _, _, _ = GetItemInfo(name)
            print(link)
        end
    end
end


function _self:CreateWindow()
    UIPanelWindows[_frame:GetName()] = { area = "center", pushable = 0, whileDead = 1 }
    tinsert(UISpecialFrames, _frame:GetName())
    _frame:SetFrameStrata("DIALOG")
    _frame:SetWidth(400)
    _frame:SetHeight(100)
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
    MakeButton("Sim Logout", 0, currentY, 100, rowHeight, _emu.SimLogout)
    MakeButton("Sim Login", 100, currentY, 100, rowHeight, _emu.SimLogin)
    MakeButton("Dump Bag Links", 200, currentY, 100, rowHeight, DumpBagLinks)
    MakeButton("Scan bags", 300, currentY, 100, rowHeight, _emu.ScanBags)
    currentY = currentY - 25

    local function TestProtectedFunc()
        print("Using item from bag0 slot1, if the exe is unprotected the item will be used")
        UseContainerItem(0, 1, "player")
    end

    MakeButton("TestProtected", 0, currentY, 100, rowHeight, TestProtectedFunc)

    local function DumpReputations()
        local numFactions = GetNumFactions();
        local factionName, _, _, _, _, barValue, _, _, isHeader, _, hasRep = GetFactionInfoByID(509)
        print(factionName, barValue)
        for i=1, numFactions do
            local name, description, standingID, barMin, barMax, barValue, atWarWith, canToggleAtWar, isHeader, isCollapsed, hasRep, isWatched, isChild = GetFactionInfo(i);
            if not isHeader then
                print(name, barValue, PlayerbotsPanelEmu.broker.data.factionId.list[name][1])
            end
        end
    end

    MakeButton("Dump Rep", 100, currentY, 100, rowHeight, DumpReputations)

end
