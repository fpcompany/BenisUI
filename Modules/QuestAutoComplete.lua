local _, ns = ...
local BenisUI = ns.BenisUI

-- Turns in finished quests automatically:
--   * picks finished quests from gossip / quest greeting lists
--   * clicks Continue on the progress page when the quest is completable
--   * clicks Complete on the reward page when there is no reward to choose
--     (0 or 1 choices); with 2+ choices the window stays open for you
-- Never accepts new quests. Hold Shift while talking to an NPC to skip it.
-- Toggle with /bui autoquest.
local QuestAutoComplete = BenisUI:RegisterModule('QuestAutoComplete')

local function Enabled()
	return BenisUI.db.questAutoComplete and not IsShiftKeyDown()
end

-- gossip window: select the first finished quest
local function OnGossipShow()
	if C_GossipInfo and C_GossipInfo.GetActiveQuests then
		for _, quest in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
			if quest.isComplete and quest.questID then
				C_GossipInfo.SelectActiveQuest(quest.questID)
				return
			end
		end
	elseif GetGossipActiveQuests then
		-- old API: flat list of (title, level, isTrivial, isComplete, ...) per quest
		local info = { GetGossipActiveQuests() }
		local stride = 6
		for i = 1, #info / stride do
			if info[(i - 1) * stride + 4] then
				SelectGossipActiveQuest(i)
				return
			end
		end
	end
end

-- quest greeting (NPC with only quests, no gossip): same thing
local function OnQuestGreeting()
	for i = 1, GetNumActiveQuests() do
		local _, isComplete = GetActiveTitle(i)
		if isComplete then
			SelectActiveQuest(i)
			return
		end
	end
end

local function OnQuestProgress()
	-- quests that take gold are left for you to confirm
	if IsQuestCompletable() and (GetQuestMoneyToGet() or 0) == 0 then
		CompleteQuest()
	end
end

local function OnQuestComplete()
	local choices = GetNumQuestChoices() or 0
	if choices <= 1 then
		GetQuestReward(choices)
	end
end

local handlers = {
	GOSSIP_SHOW = OnGossipShow,
	QUEST_GREETING = OnQuestGreeting,
	QUEST_PROGRESS = OnQuestProgress,
	QUEST_COMPLETE = OnQuestComplete,
}

function QuestAutoComplete:OnInit()
	local events = CreateFrame('Frame')
	for event in pairs(handlers) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript('OnEvent', function(_, event)
		if Enabled() then handlers[event]() end
	end)
end
