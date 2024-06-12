PlayerbotsPanelEmu    = AceLibrary("AceAddon-2.0"):new("AceConsole-2.0", "AceDB-2.0", "AceHook-2.1", "AceDebug-2.0", "AceEvent-2.0")
PlayerbotsPanelEmu.rootPath = "Interface\\AddOns\\PlayerbotsPanel\\"
PlayerbotsPanelEmu.frame    = CreateFrame("Frame", "PlayerbotsPanelEmuFrame", UIParent)
PlayerbotsPanelEmu:RegisterDB("PlayerbotsPanelEmuDb", "PlayerbotsPanelEmuDbPerChar")
PlayerbotsPanelEmu.broker = PlayerbotsBroker
