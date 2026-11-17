local _, ns = ...
local BenisUI = ns.BenisUI

-- When a quest objective fills up (e.g. 8/8 Wolf Meat) while you're in a
-- group, announces it in party chat:
--   PEEPEE POOPOO <quest name> <item name> 8/8
-- Trigger logic follows Questie's QuestieAnnounce: an objective must first be
-- seen incomplete, then announces once when numFulfilled reaches numRequired.
-- Questie ignores objective.finished because Forever reports it wrong.
local QuestAnnounce = BenisUI:RegisterModule('QuestAnnounce')

local PREFIX = 'PEEPEE POOPOO'

local seenIncomplete = {} -- ['questID:index'] = true
local announced = {}      -- ['questID:index'] = true (once per session, like Questie)

-- objective text is "8/8 Wolf Meat" on retail, "Wolf Meat: 8/8" on older
-- clients; strip the count either way to get the item name
local function ItemName(text)
	local name = text:gsub('%d+%s*/%s*%d+', ''):gsub('^%s*:?%s*', ''):gsub('%s*:?%s*$', '')
	return name ~= '' and name or text
end

local function Channel()
	if IsInRaid() then
		return 'RAID'
	elseif IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and not IsInGroup(LE_PARTY_CATEGORY_HOME) then
		return 'INSTANCE_CHAT'
	elseif IsInGroup() then
		return 'PARTY'
	end
end

local function Send(msg, channel)
	if _G.SendChatMessage then
		_G.SendChatMessage(msg, channel)
	else
		C_ChatInfo.SendChatMessage(msg, channel)
	end
end

local function Announce(title, text, have, need)
	local msg = ('%s %s %s %d/%d'):format(PREFIX, title, ItemName(text), have, need)
	local channel = Channel()
	if QuestAnnounce.debug then
		print(('|cff1784d1Benis|rUI quest announce [%s]: %s'):format(channel or 'not in group', msg))
	end
	if channel then Send(msg, channel) end
end

local function Scan()
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		local questID = info and not info.isHeader and info.questID
		if questID and questID ~= 0 and HaveQuestData(questID) then
			local objectives = C_QuestLog.GetQuestObjectives(questID)
			for index, objective in ipairs(objectives or {}) do
				local have = tonumber(objective.numFulfilled) or 0
				local need = tonumber(objective.numRequired) or 0
				-- Forever bug (from Questie): 1/1 reported while unfinished
				if have == 1 and need == 1 and not objective.finished then have = 0 end

				local key = questID .. ':' .. index
				if need > 0 and objective.text and objective.text ~= '' then
					if have < need then
						seenIncomplete[key] = true
					elseif seenIncomplete[key] and not announced[key] then
						seenIncomplete[key] = nil
						announced[key] = true
						local title = info.title or C_QuestLog.GetTitleForQuestID(questID) or ''
						Announce(title, objective.text, have, need)
					end
				end
			end
		end
	end
end

-- quest events fire in bursts; coalesce into one scan
local pending = false
local function QueueScan()
	if pending then return end
	pending = true
	C_Timer.After(0.2, function()
		pending = false
		Scan()
	end)
end

function QuestAnnounce:OnInit()
	local events = CreateFrame('Frame')
	for _, event in ipairs({ 'QUEST_LOG_UPDATE', 'QUEST_WATCH_UPDATE' }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:RegisterUnitEvent('UNIT_QUEST_LOG_CHANGED', 'player')
	events:SetScript('OnEvent', QueueScan)
	QueueScan()
end
