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

-- Wait function taken from http://wowwiki.wikia.com/wiki/USERAPI_wait
local waitTable = {};
local waitFrame = nil;

function SmartQuestTracker_wait(delay, func, ...)
  if(type(delay)~="number" or type(func)~="function") then
    return false;
  end
  if(waitFrame == nil) then
    waitFrame = CreateFrame("Frame","WaitFrame", UIParent);
    waitFrame:SetScript("onUpdate",function (self,elapse)
      local count = #waitTable;
      local i = 1;
      while(i<=count) do
        local waitRecord = tremove(waitTable,i);
        local d = tremove(waitRecord,1);
        local f = tremove(waitRecord,1);
        local p = tremove(waitRecord,1);
        if(d>elapse) then
          tinsert(waitTable,i,{d-elapse,f,p});
          i = i + 1;
        else
          count = count - 1;
          f(unpack(p));
        end
      end
    end);
  end
  tinsert(waitTable,{delay,func,{...}});
  return true;
end
-- end wait function

local autoTracked = {}
local autoRemove
local autoSort
local removeComplete
local showDailies

local function getQuestInfo(index)
	local title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID, startEvent, displayQuestID, isOnMap, hasLocalPOI, isTask, isStory = GetQuestLogTitle(index)

	if isHeader then
		return nil
	end

	local questMapId, questFloorId = GetQuestWorldMapAreaID(questID)
	local distance, reachable = GetDistanceSqToQuest(index)
	local areaid = GetCurrentMapAreaID();
	local isTracked = IsQuestWatched(index)

	local isRepeatable = frequency == LE_QUEST_FREQUENCY_DAILY or frequency == LE_QUEST_FREQUENCY_WEEKLY
	local isDaily = frequency == LE_QUEST_FREQUENCY_DAILY
	local isWeekly =  frequency == LE_QUEST_FREQUENCY_WEEKLY
	local isLocal = questMapId == areaid or (questMapId == 0 and isOnMap) or hasLocalPOI
	local isCompleted = not isComplete == nil
	local isAutoTracked = autoTracked[questID] == true


	quest = {};

    quest["id"] = questID
    quest["title"] = title
    quest["isLocal"] = isLocal
    quest["distance"] = distance
    quest["isRepeatable"] = isRepeatable
    quest["isDaily"] = isDaily
    quest["isWeekly"] = isWeekly
    quest["isCompleted"] = isCompleted
    quest["isTracked"] = isTracked
    quest["isAutoTracked"] = isAutoTracked

	return quest
end

local function trackQuest(index, quest, markAutoTracked)
	if (not quest["isTracked"]) or markAutoTracked then
		autoTracked[quest["id"]] = true
		AddQuestWatch(index)
	end

	if autoSort then
		SortQuestWatches()
	end
end

local function untrackQuest(index, quest)
	if quest["isAutoTracked"] and autoRemove then
		autoTracked[quest["id"]] = nil
		RemoveQuestWatch(index)
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
	local areaid = GetCurrentMapAreaID();
	local inInstance, instanceType = IsInInstance()
	local numEntries, _ = GetNumQuestLogEntries()
	for questIndex = 1, numEntries do
		local quest = getQuestInfo(questIndex)

		if not (quest == nil) then
			if (quest["isComplete"] and removeComplete) then
				untrackQuest(questIndex, quest)
			elseif quest["isLocal"] then
				trackQuest(questIndex, quest)
			elseif showDailies and quest["isDaily"] and not inInstance then
				trackQuest(questIndex, quest)
			elseif showDailies and quest["isWeekly"] then
				trackQuest(questIndex, quest)
			else
				untrackQuest(questIndex, quest)
			end
		end
	end
	if autoSort then
		SortQuestWatches()
	end
end

local function debugPrintQuestsHelper(onlyWatched)
	local areaid = GetCurrentMapAreaID();
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
		local quest = getQuestInfo(questIndex)
		if not (quest == nil) then
			if (not onlyWatched) or (onlyWatched and quest["isTracked"]) then
				print("#" .. quest["id"] .. " - |cffFF6A00" .. quest["title"] .. "|r")
				print("Completed: ".. tostring(quest["isCompleted"]))
				print("IsLocal: " .. tostring(quest["isLocal"]))
				print("Distance: " .. quest["distance"])
				print("AutoTracked: " .. tostring(quest["isAutoTracked"]))
				print("Is repeatable: " .. tostring(quest["isRepeatable"]))
				print("Is Daily: " .. tostring(quest["isDaily"]))
				print("Is Weekly: " .. tostring(quest["isWeekly"]))
			end
		end
	end
end

--Function we can call when a setting changes.
function MyPlugin:Update()
	autoRemove = E.db.ElvUI_SmartQuestTracker.AutoRemove
	autoSort =  E.db.ElvUI_SmartQuestTracker.AutoSort
	removeComplete = E.db.ElvUI_SmartQuestTracker.RemoveComplete
	showDailies = E.db.ElvUI_SmartQuestTracker.ShowDailies

	SmartQuestTracker_wait(0.1, untrackAllQuests)
	SmartQuestTracker_wait(0.5, run_update)
end

function MyPlugin:QUEST_WATCH_UPDATE(event, questIndex)
	local quest = getQuestInfo(questIndex)
	if (removeComplete and quest["isCompleted"]) then
		untrackQuest(questIndex, quest)
	else
		trackQuest(questIndex, quest, true)
	end
end

function MyPlugin:QUEST_ACCEPTED(event, questIndex)
	local quest = getQuestInfo(questIndex)
    trackQuest(questIndex, quest, true)
end

function MyPlugin:ZONE_CHANGED()
	SmartQuestTracker_wait(0.1, run_update)
end

function MyPlugin:ZONE_CHANGED_NEW_AREA()
	SmartQuestTracker_wait(0.1, run_update)
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
					showDailies = {
						order = 3,
						type = "toggle",
						name = "Keep daily and weekly quest tracked",
						get = function(info)
							return E.db.ElvUI_SmartQuestTracker.ShowDailies
						end,
						set = function(info, value)
							E.db.ElvUI_SmartQuestTracker.ShowDailies = value
							MyPlugin:Update()
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
	MyPlugin:RegisterEvent("QUEST_ACCEPTED")

	MyPlugin:Update()
end

E:RegisterModule(MyPlugin:GetName()) --Register the module with ElvUI. ElvUI will now call MyPlugin:Initialize() when ElvUI is ready to load our plugin.
