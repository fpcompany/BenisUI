local _, ns = ...
local BenisUI = ns.BenisUI

-- Restyles the objective (quest) tracker: clean fonts, no header art,
-- flat progress bars and square quest item buttons.
local QuestTracker = BenisUI:RegisterModule('QuestTracker')

local FONT = BenisUI.media.font
local TEXTURE = BenisUI.media.texture
local Skin = BenisUI.Skin

local TRACKER_NAMES = {
	'ScenarioObjectiveTracker',
	'UIWidgetObjectiveTracker',
	'CampaignQuestObjectiveTracker',
	'QuestObjectiveTracker',
	'AdventureObjectiveTracker',
	'AchievementObjectiveTracker',
	'MonthlyActivitiesObjectiveTracker',
	'ProfessionsRecipeTracker',
	'BonusObjectiveTracker',
	'WorldQuestObjectiveTracker',
	'InitiativeTasksObjectiveTracker',
}

-- the tracker draws everything through these shared font objects
local function ReplaceFonts()
	local objects = {
		_G.ObjectiveFont,
		_G.ObjectiveTrackerLineFont,
		_G.ObjectiveTrackerHeaderFont,
	}
	for i = 12, 22 do
		objects[#objects + 1] = _G['ObjectiveTrackerFont' .. i]
	end

	for _, fontObject in next, objects do
		if fontObject then
			local _, size = fontObject:GetFont()
			fontObject:SetFont(FONT, size or 12, 'OUTLINE')
			fontObject:SetShadowOffset(0, 0)
		end
	end
end

local function SkinHeader(header)
	if not header then return end

	if header.Background then
		header.Background:SetAtlas(nil)
	end
	if header.Text then
		header.Text:SetTextColor(1, 1, 1)
	end
end

local function ReskinItemButton(button)
	if not button or button.BenisUISkinned then return end
	button.BenisUISkinned = true

	local normal = button:GetNormalTexture()
	if normal then normal:SetAlpha(0) end
	local pushed = button:GetPushedTexture()
	if pushed then pushed:SetAlpha(0) end
	local highlight = button:GetHighlightTexture()
	if highlight then highlight:SetColorTexture(1, 1, 1, 0.25) end

	local icon = button.icon or button.Icon
	if icon then
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end

	Skin:Border(button)

	local count = button.Count
	if count then
		count:SetFont(FONT, 12, 'OUTLINE')
	end
end

local function OnAddBlock(_, block)
	if not block then return end
	ReskinItemButton(block.ItemButton)
	ReskinItemButton(block.itemButton)
end

local function ReskinBar(bar)
	if not bar or bar.BenisUISkinned then return end
	bar.BenisUISkinned = true

	-- drop the ornate frame textures, keep the fill
	local fill = bar:GetStatusBarTexture()
	for _, region in next, { bar:GetRegions() } do
		if region ~= fill and region.IsObjectType and region:IsObjectType('Texture') then
			region:SetTexture(nil)
			region:SetAlpha(0)
		end
	end

	bar:SetStatusBarTexture(TEXTURE)
	bar:SetStatusBarColor(0.25, 0.6, 1)

	local backdrop = Skin:Backdrop(bar, nil, 1)
	backdrop:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
	backdrop:SetBackdropColor(0, 0, 0, 0.8)

	if bar.Label then
		bar.Label:SetFont(FONT, 11, 'OUTLINE')
		bar.Label:ClearAllPoints()
		bar.Label:SetPoint('CENTER', bar)
	end
end

local function OnGetProgressBar(tracker, key)
	local progressBar = tracker.usedProgressBars and tracker.usedProgressBars[key]
	ReskinBar(progressBar and progressBar.Bar)
end

local function OnGetTimerBar(tracker, key)
	local timerBar = tracker.usedTimerBars and tracker.usedTimerBars[key]
	ReskinBar(timerBar and timerBar.Bar)
end

local function Skin()
	ReplaceFonts()

	local trackerFrame = _G.ObjectiveTrackerFrame
	if trackerFrame then
		SkinHeader(trackerFrame.Header)
	end

	for _, name in next, TRACKER_NAMES do
		local tracker = _G[name]
		if tracker then
			SkinHeader(tracker.Header)
			if tracker.AddBlock then
				hooksecurefunc(tracker, 'AddBlock', OnAddBlock)
			end
			if tracker.GetProgressBar then
				hooksecurefunc(tracker, 'GetProgressBar', OnGetProgressBar)
			end
			if tracker.GetTimerBar then
				hooksecurefunc(tracker, 'GetTimerBar', OnGetTimerBar)
			end
		end
	end
end

function QuestTracker:OnInit()
	if C_AddOns.IsAddOnLoaded('Blizzard_ObjectiveTracker') then
		Skin()
	else
		local waiter = CreateFrame('Frame')
		waiter:RegisterEvent('ADDON_LOADED')
		waiter:SetScript('OnEvent', function(self, _, addon)
			if addon == 'Blizzard_ObjectiveTracker' then
				self:UnregisterAllEvents()
				Skin()
			end
		end)
	end
end
