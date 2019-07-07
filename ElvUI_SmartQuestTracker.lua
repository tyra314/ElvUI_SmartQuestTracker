--[[
	Copyright 2019 tyra <https://twitter.com/tyra_314>. All rights reserved.

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

local function DebugLog(...)
--@debug@
printResult = "|cffFF6A00Smart Quest Tracker|r: "
for i,v in ipairs({...}) do
	printResult = printResult .. tostring(v) .. " "
end
DEFAULT_CHAT_FRAME:AddMessage(printResult)
--@end-debug@
end

local E, L, V, P, G = unpack(ElvUI); --Import: Engine, Locales, PrivateDB, ProfileDB, GlobalDB
local MyPlugin = E:NewModule('ElvUI_SmartQuestTracker', 'AceHook-3.0', 'AceEvent-3.0', 'AceTimer-3.0'); --Create a plugin within ElvUI and adopt AceHook-3.0, AceEvent-3.0 and AceTimer-3.0. We can make use of these later.
local EP = LibStub("LibElvUIPlugin-1.0") --We can use this to automatically insert our GUI tables when ElvUI_Config is loaded.
local addonName, addonTable = ... --See http://www.wowinterface.com/forums/showthread.php?t=51502&p=304704&postcount=2

--Default options
P["ElvUI_SmartQuestTracker"] = {
	["HandlingComplete"] = "keep_local",
	["RemoveLegendary"] = true,
	["RemoveWaypoints"] = false,
	["AutoRemove"] = true,
	["AutoSort"] = true,
	["ShowDailies"] = false,
	["ZenMode"] = false,
	["zenModeDistance"] = 100000
}

local autoTracked = {}
local autoRemove
local autoSort
local removeComplete
local keepComplete
local removeLegendary
local showDailies
local removeWaypoints
local zenMode
local zenModeRunning
local zenModeDistance

-- control variables to pass arguments from on event handler to another
local skippedUpdate = false
local updateQuestIndex = nil
local newQuestIndex = nil
local doUpdate = false

local function getQuestInfo(index)
	--     title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID, startEvent, displayQuestID, isOnMap, hasLocalPOI, isTask, isBounty, isStory, isHidden, isScaling = GetQuestLogTitle(questLogIndex)
	local  title,     _,              _, isHeader,           _, isCompleted, frequency, questID, startEvent, displayQuestID, isOnMap, hasLocalPOI, isTask, isBounty, isStory, isHidden, isScaling = GetQuestLogTitle(index)

	local isLegendaryQuest = C_QuestLog.IsLegendaryQuest(questID)
	local QuestZoneID = C_TaskQuest.GetQuestZoneID(questID)
	local nextWaypoint = C_QuestLog.GetNextWaypoint(questID)

	--@debug@
	print("%%%%%%%%%" .. tostring(title) .. "%%%%%%%")
	--@end-debug@

	if isHeader then
		return nil
	end

	local questMapId = C_TaskQuest.GetQuestZoneID(questID)
	if questMapId == nil then
		questMapId = GetQuestUiMapID(questID)
	end
	if nextWaypoint ~= nil and nextWaypoint ~= questMapId and removeWaypoints then
		questMapId = 0
	end
	local distance, reachable = GetDistanceSqToQuest(index)
	local areaid = C_Map.GetBestMapForUnit("player")

    local isDaily = frequency == LE_QUEST_FREQUENCY_DAILY
	local isWeekly =  frequency == LE_QUEST_FREQUENCY_WEEKLY

	local isCompleted = isCompleted ~= nil

	local tagId = GetQuestTagInfo(questID)
	local isInstance = false
	if tagId then
	    isInstance = tagId == QUEST_TAG_DUNGEON or tagId == QUEST_TAG_HEROIC or tagId == QUEST_TAG_RAID or tagId == QUEST_TAG_RAID10 or tagId == QUEST_TAG_RAID25
	end

	--@debug@
	print("isHeader: ".. tostring(isHeader) .. " isCompleted: ".. tostring(isCompleted) .. " nextWaypoint: ".. tostring(nextWaypoint) .. " questMapId: ".. tostring(questMapId) .." QuestZoneID: ".. tostring(QuestZoneID) .. " areaid: ".. tostring(areaid) .. " hasLocalPOI: ".. tostring(hasLocalPOI) .. " questID: ".. tostring(questID) .. " isOnMap: ".. tostring(isOnMap) .. " isTask: ".. tostring(isTask) .. " isBounty: ".. tostring(isBounty) .. " isStory: ".. tostring(isStory) .. " isHidden: ".. tostring(isHidden) .. " isScaling: ".. tostring(isScaling) .. " isLegendaryQuest: " .. tostring(isLegendaryQuest) .. " reachable: " .. tostring(reachable) .. " distance: " .. tostring(distance))
	--@end-debug@

	return questID, questMapId, isOnMap or hasLocalPOI, isCompleted, isDaily, isWeekly, isInstance, isTask, isLegendaryQuest, distance
end

local function trackQuest(index, questID, markAutoTracked)
	if autoTracked[questID] ~= true and markAutoTracked then
		autoTracked[questID] = true
		AddQuestWatch(index)
	end

    if autoSort then
		SortQuestWatches()
	end
end

local function untrackQuest(index, questID)
	if autoTracked[questID] == true then
		RemoveQuestWatch(index)
		autoTracked[questID] = nil
	end

    if autoSort then
		SortQuestWatches()
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

local function run_update()
	--@debug@
	DebugLog("Running full update")
	--@end-debug@
	MyPlugin:RunUpdate()
end

local function debugPrintQuestsHelper(onlyWatched)
	local areaid = C_Map.GetBestMapForUnit("player");
	print("#########################")
	print("Current MapID: " .. areaid)

	local inInstance, instanceType = IsInInstance()

	print("In instance: " .. tostring(inInstance))
	print("Instance type: " .. instanceType)

	local numEntries, numQuests = GetNumQuestLogEntries()
	print(numQuests .. " Quests in " .. numEntries .. " Entries.")
	local numWatches = GetNumQuestWatches()
	print(numWatches .. " Quests tracked.")
	print("#########################")

	for questIndex = 1, numEntries do
		local questID, questMapId, isOnMap, isCompleted, isDaily, isWeekly, isInstance, isWorldQuest, isLegendaryQuest = getQuestInfo(questIndex)
		if not (questID == nil) then
			if (not onlyWatched) or (onlyWatched and autoTracked[questID] == true) then
				print("#" .. questID .. " - |cffFF6A00" .. select(1, GetQuestLogTitle(questIndex)) .. "|r")
                print("MapID: " .. tostring(questMapId) .. " IsOnMap: " .. tostring(isOnMap) .. " isInstance: " .. tostring(isInstance))
				print("AutoTracked: " .. tostring(autoTracked[questID] == true) .. " isLocal: " .. tostring(((questMapId == 0 and isOnMap) or (questMapId == areaid)) and not (isInstance and not inInstance and not isCompleted)))
				print("Completed: ".. tostring(isCompleted) .. " Daily: " .. tostring(isDaily) .. " Weekly: " .. tostring(isWeekly) .. " WorldQuest: " .. tostring(isWorldQuest) .. " LegendaryQuest: " .. tostring(isLegendaryQuest))
			end
		end
	end

	print("C_QuestLog.GetQuestsOnMap(areaid): ")

	local quests = C_QuestLog.GetQuestsOnMap(areaid)
	for qid = 1, #quests do
		local quest = quests[qid]
		print("questID: " .. quest.questID)
	end
end

function hasFocusQuest(mapID)
	if not zenMode or mapID == nil then
		return false
	end
	local quests = C_QuestLog.GetQuestsOnMap(mapID)
	for qid = 1, #quests do
		local quest = quests[qid]
		local index = GetQuestLogIndexByID(quest.questID);
		local distanceSq, _ = GetDistanceSqToQuest(index)

		if distanceSq <= zenModeDistance then
			return true
		end
	end

	return false
end

--Function we can call when a setting changes.
function MyPlugin:Update()
	autoRemove = E.db.ElvUI_SmartQuestTracker.AutoRemove
	autoSort =  E.db.ElvUI_SmartQuestTracker.AutoSort
	removeLegendary = E.db.ElvUI_SmartQuestTracker.RemoveLegendary
	removeWaypoints = E.db.ElvUI_SmartQuestTracker.RemoveWaypoints
	showDailies = E.db.ElvUI_SmartQuestTracker.ShowDailies
	handlingComplete = E.db.ElvUI_SmartQuestTracker.HandlingComplete
	zenMode = E.db.ElvUI_SmartQuestTracker.ZenMode
	zenModeDistance = E.db.ElvUI_SmartQuestTracker.zenModeDistance

	if handlingComplete == "keep" then
		keepComplete = true
		removeComplete = false
	elseif handlingComplete == "keep_local" then
		keepComplete = false
		removeComplete = false
	elseif handlingComplete == "remove" then
		keepComplete = false
		removeComplete = true
	end

	untrackAllQuests()
	run_update()
	if not zenModeRunning then
		self:ScheduleTimer("ZenMode", 1)
	end
end

function MyPlugin:RunUpdate()
	if self.update_running ~= true then
		self.update_running = true

		-- Update play information cache, so we don't run it for every quest
		self.areaID = C_Map.GetBestMapForUnit("player")
		self.inInstance = select(1, IsInInstance())
		self.hasFocus = hasFocusQuest(self.areaID)

		--@debug@
		DebugLog("MyPlugin:RunUpdate")
		--@end-debug@
		self:ScheduleTimer("PartialUpdate", 0.01, 1)
	else
		self.update_required = true
	end
end

function MyPlugin:ZenMode()
	if zenMode then
		zenModeRunning = true
		if not WorldMapFrame:IsVisible() then
			--@debug@
			DebugLog("Running zen mode update")
			--@end-debug@

			run_update()
		end
		self:ScheduleTimer("ZenMode", 1)
	else
		zenModeRunning = false
	end
end

function MyPlugin:PartialUpdate(index)
	local numEntries, _ = GetNumQuestLogEntries()

	if index >= numEntries then
		--@debug@
		DebugLog("Finished partial updates")
		--@end-debug@

		if self.update_required == true then
			self.update_required = nil
			self.areaID = C_Map.GetBestMapForUnit("player")
			self.inInstance = select(1, IsInInstance())
			self.hasFocus = hasFocusQuest(self.areaID)

			--@debug@
			DebugLog("Reschedule partial update")
			--@end-debug@
			self:ScheduleTimer("PartialUpdate", 0.01, 1)
		else
			if autoSort then
				SortQuestWatches()
			end
			self.update_running = nil
		end

		return
	end

	local questID, questMapId, isOnMap, isCompleted, isDaily, isWeekly, isInstance, isWorldQuest, isLegendaryQuest, distance = getQuestInfo(index)
	if not (questID == nil) then
		if isCompleted and removeComplete then
			untrackQuest(index, questID)
		elseif isCompleted and keepComplete then
			trackQuest(index, questID, not isWorldQuest)
		elseif self.hasFocus and distance > zenModeDistance then
			untrackQuest(index, questID)
		elseif isLegendaryQuest and removeLegendary and not isOnMap then
			untrackQuest(index, questID)
		elseif (isOnMap or (questMapId == self.areaID)) and not (isInstance and not self.inInstance and not isCompleted) then
			trackQuest(index, questID, not isWorldQuest)
		elseif showDailies and isDaily and not inInstance then
			trackQuest(index, questID, not isWorldQuest)
		elseif showDailies and isWeekly then
			trackQuest(index, questID, not isWorldQuest)
		else
			untrackQuest(index, questID)
		end
	end

	self:ScheduleTimer("PartialUpdate", 0.01, index + 1)
end

-- event handlers

function MyPlugin:QUEST_WATCH_UPDATE(event, questIndex)
	DebugLog("Update for quest:", questIndex)

	local questID, _, _, isCompleted, _, _, _, isWorldQuest, _ = getQuestInfo(questIndex)
	if questID ~= nil then
		updateQuestIndex = nil
		if removeComplete and isCompleted then
			untrackQuest(questIndex, questID)
		elseif not isWorldQuest then
			trackQuest(questIndex, questID, not isWorldQuest)
		end
	end
end

function MyPlugin:QUEST_LOG_UPDATE(event)
	DebugLog("Running update for quests")
	-- run_update()
end

function MyPlugin:QUEST_ACCEPTED(event, questIndex)
	DebugLog("Accepted new quest:", questIndex)

	local questID, _, _, isCompleted, _, _, _, isWorldQuest, _ = getQuestInfo(questIndex)
	if questID ~= nil then
		updateQuestIndex = nil
		if removeComplete and isCompleted then
			untrackQuest(questIndex, questID)
		elseif not isWorldQuest then
			trackQuest(questIndex, questID, not isWorldQuest)
		end
	end
end

function MyPlugin:QUEST_REMOVED(event, questIndex)
	DebugLog("REMOVED:", questIndex)
	autoTracked[questIndex] = nil
	-- run_update()
end

function MyPlugin:ZONE_CHANGED()
	DebugLog("ZONE_CHANGED")
	run_update()
end

function MyPlugin:ZONE_CHANGED_NEW_AREA()
	DebugLog("ZONE_CHANGED_NEW_AREA")
	run_update()
end


--This function inserts our GUI table into the ElvUI Config. You can read about AceConfig here: http://www.wowace.com/addons/ace3/pages/ace-config-3-0-options-tables/
function MyPlugin:InsertOptions()
	E.Options.args.ElvUI_SmartQuestTracker = {
		order = 100,
		type = "group",
		name = "|cffFF6A00Smart Quest Tracker|r",
		args = {
			zenMode = {
				order = 1,
				type = "group",
				name = L['Zen mode (experimental)'],
				guiInline = true,
				args = {
					zenModeDesc = {
						order = 1,
						type = "description",
						name = "Zen mode will only track those Quest, which are within the given distance, if at least one quest is within the given distance. (This will be MUCH more demanding on the CPU, as a constant scanning is required.)"
					},
					zenModeEnabled = {
						order = 10,
						type = "toggle",
						name = "Enabled",
						get = function(info)
							return E.db.ElvUI_SmartQuestTracker.ZenMode
						end,
						set = function(info, value)
							E.db.ElvUI_SmartQuestTracker.ZenMode = value
							MyPlugin:Update() --We changed a setting, call our Update function
						end,
					},
					zenModeDistance = {
						order = 11,
						type = "range",
						name = "Distance to quest",
						min = 1,
						max = 10000000,
						softMin = 10000,
						softMax = 1000000,
						step = 1,
						bigStep = 10000,
						get = function(info)
							return E.db.ElvUI_SmartQuestTracker.zenModeDistance
						end,
						set = function(info, value)
							E.db.ElvUI_SmartQuestTracker.zenModeDistance = value
							MyPlugin:Update() --We changed a setting, call our Update function
						end,
					}
				}
			},
			clear = {
				order = 1,
				type = "group",
				name = L['Untrack quests when changing area'],
				guiInline = true,
				args = {
					removelegendary = {
						order = 3,
						type = "toggle",
						name = "Keep story quests",
						get = function(info)
							return not E.db.ElvUI_SmartQuestTracker.RemoveLegendary
						end,
						set = function(info, value)
							E.db.ElvUI_SmartQuestTracker.RemoveLegendary = not value
							MyPlugin:Update() --We changed a setting, call our Update function
						end,
					},
					removewaypoints = {
						order = 2,
						type = "toggle",
						name = "Quest waypoints",
						get = function(info)
							return E.db.ElvUI_SmartQuestTracker.RemoveWaypoints
						end,
						set = function(info, value)
							E.db.ElvUI_SmartQuestTracker.RemoveWaypoints = value
							MyPlugin:Update() --We changed a setting, call our Update function
						end,
					},
					autoremove = {
						order = 1,
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
					showDailies = {
						order = 5,
						type = "toggle",
						name = L["Keep daily and weekly"],
						get = function(info)
							return E.db.ElvUI_SmartQuestTracker.ShowDailies
						end,
						set = function(info, value)
							E.db.ElvUI_SmartQuestTracker.ShowDailies = value
							MyPlugin:Update()
						end,
					},
					removecomplete = {
						order = 10,
						type = "select",
						style = "radio",
						name =  L['Handling of completed quests'],
						values = {
							keep = "Keep all",
							keep_local = "Keep only local",
							remove = "Remove all",
						},
						get = function(info)
							return E.db.ElvUI_SmartQuestTracker.HandlingComplete
						end,
						set = function(info, value)
							E.db.ElvUI_SmartQuestTracker.HandlingComplete = value
							MyPlugin:Update() --We changed a setting, call our Update function
						end,
					},
				},
			},
			sort = {
				order = 2,
				type = "group",
				name = L['Sorting of quests in tracker'],
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
						order = 2,
						name = 'Print all quests to chat',
						func = function() debugPrintQuestsHelper(false) end,
					},
					printWatched = {
						type = 'execute',
						order = 3,
						name = 'Print tracked quests to chat',
						func = function() debugPrintQuestsHelper(true) end,
					},
					untrack = {
						type = 'execute',
						order = 1,
						name = 'Untrack all quests',
						func = function() untrackAllQuests() end,
					},
					update = {
						type = 'execute',
						order = 4,
						name = 'Force update of tracked quests',
						func = function() run_update() end,
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
	MyPlugin:RegisterEvent("ZONE_CHANGED")
	MyPlugin:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	MyPlugin:RegisterEvent("QUEST_WATCH_UPDATE")
	MyPlugin:RegisterEvent("QUEST_LOG_UPDATE")
	MyPlugin:RegisterEvent("QUEST_ACCEPTED")
	MyPlugin:RegisterEvent("QUEST_REMOVED")

	MyPlugin:Update()
end

E:RegisterModule(MyPlugin:GetName()) --Register the module with ElvUI. ElvUI will now call MyPlugin:Initialize() when ElvUI is ready to load our plugin.
