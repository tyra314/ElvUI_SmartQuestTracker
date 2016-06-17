--[[
	Copyright 2016 tyra <https://twitter.com/tyra_314>. All rights reserved.

	This work is licensed under the Creative Commons Attribution-NonCommercial-
	ShareAlike 4.0 International License. To view a copy of this license, visit
	http://creativecommons.org/licenses/by-nc-sa/4.0/ or send a letter to
	Creative Commons, PO Box 1866, Mountain View, CA 94042, USA.
]]

--[[
	This is a framework showing how to create a plugin for ElvUI.
	It creates some default options and inserts a GUI table to the ElvUI Config.
	If you have questions then ask in the Tukui lua section: http://www.tukui.org/forums/forum.php?id=27
]]

local E, L, V, P, G = unpack(ElvUI); --Import: Engine, Locales, PrivateDB, ProfileDB, GlobalDB
local MyPlugin = E:NewModule('ElvUI_SmartQuestTracker', 'AceHook-3.0', 'AceEvent-3.0', 'AceTimer-3.0'); --Create a plugin within ElvUI and adopt AceHook-3.0, AceEvent-3.0 and AceTimer-3.0. We can make use of these later.
local EP = LibStub("LibElvUIPlugin-1.0") --We can use this to automatically insert our GUI tables when ElvUI_Config is loaded.
local addonName, addonTable = ... --See http://www.wowinterface.com/forums/showthread.php?t=51502&p=304704&postcount=2

--Default options
P["ElvUI_SmartQuestTracker"] = {
	["RemoveComplete"] = false,
	["AutoRemove"] = true,
	["AutoSort"] = true,
}

local frame = CreateFrame("Frame")
local autoRemove
local autoSort
local removeComplete
local autoTracked = {}

local function getQuestId(index)
 	local _, _, _, _, _, _, _, questID, _, _, _, _, _, _ = GetQuestLogTitle(index)

	return questID
end

local function trackQuest(index, markAutoTracked)
	local questID = getQuestId(index)
	local isWatched = IsQuestWatched(index)

	if (not isWatched) or markAutoTracked then
		autoTracked[questID] = true
		AddQuestWatch(index)
	end
end

local function untrackQuest(index)
	local questID = getQuestId(index)

	if autoTracked[questID] and autoRemove then
		autoTracked[questID] = nil
		RemoveQuestWatch(index)
	end
end

local function untrackAllQuests()
	local numEntries, _ = GetNumQuestLogEntries()

	for index = 1, numEntries do
		local _, _, _, isHeader, _, _, _, _, _, _, _, _, _, _ = GetQuestLogTitle(index)
		if ( not isHeader) then
			RemoveQuestWatch(index)
		end
	end

	autoTracked = {}
end

local function debugPrintQuestsHelper(onlyWatched)
	local areaid = GetCurrentMapAreaID();
	print("Current MapID: " .. areaid)
	local numEntries, numQuests = GetNumQuestLogEntries()
	print(numQuests .. " Quests in " .. numEntries .. " Entries.")
	local numWatches = GetNumQuestWatches()
	print(numWatches .. " Quests tracked.")
	print("#########################")

	for questIndex = 1, numEntries do
		local title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID, startEvent, displayQuestID, isOnMap, hasLocalPOI, isTask, isStory = GetQuestLogTitle(questIndex)
		if ( not isHeader) then
			local questMapId, questFloorId = GetQuestWorldMapAreaID(questID)
			local distance, reachable = GetDistanceSqToQuest(questIndex)
			if (not onlyWatched) or (onlyWatched and IsQuestWatched(questIndex)) then
				print("#" .. questID .. " - |cffFF6A00" .. title .. "|r")
				print("MapID: " .. questMapId .. " - IsOnMap: " .. tostring(isOnMap) .. " - hasLocalPOI: " .. tostring(hasLocalPOI))
				print("Distance: " .. distance)
				if autoTracked[questID] then
					print("AutoTracked: yes")
				else
					print("AutoTracked: no")
				end
			end
		end
	end
end

local function run_update()
	local areaid = GetCurrentMapAreaID();
	local numEntries, _ = GetNumQuestLogEntries()
	for questIndex = 1, numEntries do
		local _, _, _, isHeader, _, isComplete, _, questID, _, _, isOnMap, hasLocalPOI, _, _ = GetQuestLogTitle(questIndex)
		if ( not isHeader) then
			local questMapId, _ = GetQuestWorldMapAreaID(questID)
			if (isComplete and removeComplete) then
				untrackQuest(questIndex)
			elseif questMapId == areaid or (questMapId == 0 and isOnMap) or hasLocalPOI then
				trackQuest(questIndex)
			else
				untrackQuest(questIndex)
			end
		end
	end
	if autoSort then
		SortQuestWatches()
	end
end

local function EventHandler(self, event, questIndex)
	if event == "QUEST_WATCH_UPDATE" then
		local _, _, _, _, _, isComplete, _, _, _, _, _, _, _, _ = GetQuestLogTitle(questIndex)
		if (removeComplete and isComplete) then
			untrackQuest(questIndex)
		else
			trackQuest(questIndex, true)
		end
	elseif event == "QUEST_ACCEPTED" then
		trackQuest(questIndex, true)
	else
		run_update()
	end
end

--Function we can call when a setting changes.
function MyPlugin:Update()
	autoRemove = E.db.ElvUI_SmartQuestTracker.AutoRemove
	autoSort =  E.db.ElvUI_SmartQuestTracker.AutoSort
	removeComplete = E.db.ElvUI_SmartQuestTracker.RemoveComplete

	run_update()
end

--This function inserts our GUI table into the ElvUI Config. You can read about AceConfig here: http://www.wowace.com/addons/ace3/pages/ace-config-3-0-options-tables/
function MyPlugin:InsertOptions()
	E.Options.args.ElvUI_SmartQuestTracker = {
		order = 100,
		type = "group",
		name = "|cffFF6A00Smart Quest Tracker|r",
		args = {
			clear = {
				order = 1,
				type = "group",
				name = L['Untrack quests when changing area'],
				guiInline = true,
				args = {
					removecomplete = {
						order = 1,
						type = "toggle",
						name = "Completed quests",
						get = function(info)
							return E.db.ElvUI_SmartQuestTracker.RemoveComplete
						end,
						set = function(info, value)
							E.db.ElvUI_SmartQuestTracker.RemoveComplete = value
							MyPlugin:Update() --We changed a setting, call our Update function
						end,
					},
					autoremove = {
						order = 2,
						type = "toggle",
						name = "Quests from other areas",
						get = function(info)
							return E.db.ElvUI_SmartQuestTracker.AutoRemove
						end,
						set = function(info, value)
							E.db.ElvUI_SmartQuestTracker.AutoRemove = value
							MyPlugin:Update() --We changed a setting, call our Update function
						end,
					},
				},
			},
			sort = {
				order = 2,
				type = "group",
				name = L['Sort of quests in tracker'],
				guiInline = true,
				args = {
					autosort = {
						order = 1,
						type = "toggle",
						name = "Automatically sort quests",
						get = function(info)
							return E.db.ElvUI_SmartQuestTracker.AutoSort
						end,
						set = function(info, value)
							E.db.ElvUI_SmartQuestTracker.AutoSort = value
							MyPlugin:Update() --We changed a setting, call our Update function
						end,
					},
				},
			},
			debug = {
				order = 3,
				type = "group",
				name = "Debug",
				guiInline = true,
				args = {
					print = {
						type = 'execute',
						order = 1,
						name = 'Print all quests to chat',
						func = function() debugPrintQuestsHelper(false) end,
					},
					printWatched = {
						type = 'execute',
						order = 1,
						name = 'Print tracked quests to chat',
						func = function() debugPrintQuestsHelper(true) end,
					},
					untrack = {
						type = 'execute',
						order = 1,
						name = 'Untrack all quests',
						func = function() untrackAllQuests() end,
					},
				},
			},
		},
	}
end

function MyPlugin:Initialize()
	--Register plugin so options are properly inserted when config is loaded
	EP:RegisterPlugin(addonName, MyPlugin.InsertOptions)


	--Register event triggers
	frame:RegisterEvent("ZONE_CHANGED")
	frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	frame:RegisterEvent("QUEST_WATCH_UPDATE")
	frame:RegisterEvent("QUEST_ACCEPTED")

	frame:SetScript("OnEvent", EventHandler)

	untrackAllQuests()

	MyPlugin:Update()
end

E:RegisterModule(MyPlugin:GetName()) --Register the module with ElvUI. ElvUI will now call MyPlugin:Initialize() when ElvUI is ready to load our plugin.
