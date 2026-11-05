local _, ns = ...
local BenisUI = ns.BenisUI

-- Per-window skins for the Blizzard frames, on top of BenisUI.Skin. Each one
-- starts with the generic Skin:Frame pass and then only names what that pass
-- can't reach on its own.
--
-- Frame names move between patches. Everything here is nil-guarded and looked
-- up through Skin:Get, so a rename shows up in '/bui skins' rather than as a
-- window that quietly stayed ugly.
BenisUI:RegisterModule('BlizzardFrames')

local Skin = BenisUI.Skin

local function SkinSeries(count, kind, prefix, suffix)
	suffix = suffix or ''

	local found = false
	for index = 1, count do
		local frame = _G[prefix .. index .. suffix]
		if frame then
			found = true
			Skin[kind](Skin, frame)
		end
	end

	-- a series that resolved nothing means the prefix moved; log the first
	-- name as the representative miss rather than all `count` of them
	if not found then Skin:Get(prefix .. '1' .. suffix) end
end

--------------------------------------------------------------------------------
-- Merchant
--------------------------------------------------------------------------------

local function SkinMerchant()
	local frame = Skin:Get('MerchantFrame')
	if not frame then return end

	Skin:Frame(frame)

	for _, name in next, {
		'MerchantMoneyBg', 'MerchantMoneyInset',
		'MerchantExtraCurrencyBg', 'MerchantExtraCurrencyInset',
		'MerchantBuyBackItemNameFrame',
	} do
		Skin:Strip(_G[name])
	end

	if Skin:Get('MerchantItem1') then
		for index = 1, MERCHANT_ITEMS_PER_PAGE or 10 do
			Skin:Strip(_G['MerchantItem' .. index])
			Skin:Strip(_G['MerchantItem' .. index .. 'NameFrame'])
			Skin:ItemButton(_G['MerchantItem' .. index .. 'ItemButton'])
		end
	end

	Skin:ItemButton(Skin:Get('MerchantBuyBackItemItemButton'))
	Skin:ItemButton(Skin:Get('MerchantRepairItemButton'))
	Skin:ItemButton(Skin:Get('MerchantRepairAllButton'))
	Skin:ItemButton(Skin:Get('MerchantGuildBankRepairButton'))

	SkinSeries(2, 'Tab', 'MerchantFrameTab')
end

--------------------------------------------------------------------------------
-- Mail
--------------------------------------------------------------------------------

local function SkinMail()
	local frame = Skin:Get('MailFrame')
	if not frame then return end

	Skin:Frame(frame)
	SkinSeries(2, 'Tab', 'MailFrameTab')

	-- inbox
	if Skin:Get('MailItem1') then
		for index = 1, INBOXITEMS_TO_DISPLAY or 7 do
			Skin:Strip(_G['MailItem' .. index])
			Skin:ItemButton(_G['MailItem' .. index .. 'Button'])
		end
	end

	-- send
	Skin:Strip(Skin:Get('SendMailFrame'))
	Skin:EditBox(Skin:Get('SendMailNameEditBox'))
	Skin:EditBox(Skin:Get('SendMailSubjectEditBox'))
	Skin:EditBox(Skin:Get('SendMailMoneyGold'))
	Skin:EditBox(Skin:Get('SendMailMoneySilver'))
	Skin:EditBox(Skin:Get('SendMailMoneyCopper'))
	Skin:Button(Skin:Get('SendMailMailButton'))
	Skin:Button(Skin:Get('SendMailCancelButton'))
	SkinSeries(ATTACHMENTS_MAX_SEND or 12, 'ItemButton', 'SendMailAttachment')

	-- open
	local open = Skin:Get('OpenMailFrame')
	if open then
		Skin:Frame(open)
		Skin:Button(Skin:Get('OpenMailReplyButton'))
		Skin:Button(Skin:Get('OpenMailDeleteButton'))
		Skin:Button(Skin:Get('OpenMailCancelButton'))
		Skin:Button(Skin:Get('OpenMailReportSpamButton'))
		Skin:ItemButton(Skin:Get('OpenMailMoneyButton'))
		SkinSeries(ATTACHMENTS_MAX_RECEIVE or 16, 'ItemButton', 'OpenMailAttachmentButton')
	end
end

--------------------------------------------------------------------------------
-- Quest giver
--------------------------------------------------------------------------------

local QUEST_PANELS = {
	'QuestFrameDetailPanel', 'QuestFrameRewardPanel',
	'QuestFrameProgressPanel', 'QuestFrameGreetingPanel',
}

local QUEST_BUTTONS = {
	'QuestFrameAcceptButton', 'QuestFrameDeclineButton',
	'QuestFrameCompleteButton', 'QuestFrameCompleteQuestButton',
	'QuestFrameGoodbyeButton', 'QuestFrameCancelButton',
}

-- Blizzard colors quest text dark brown for its parchment; on our dark panel
-- it goes white. Colored strings (links, completed objectives, item counts)
-- are left alone: only the dark ones are touched.
local function White(fontString)
	if fontString and fontString.SetTextColor then
		fontString:SetTextColor(1, 1, 1)
	end
end

local function WhiteIfDark(fontString)
	if not fontString or not fontString.GetTextColor then return end
	local r, g, b = fontString:GetTextColor()
	if r + g + b < 1.2 then White(fontString) end
end

local function IsInside(frame, ancestor)
	while frame do
		if frame == ancestor then return true end
		frame = frame:GetParent()
	end
	return false
end

-- strings QuestInfo_Display colors by material
local QUEST_INFO_TEXT = {
	'QuestInfoTitleHeader', 'QuestInfoDescriptionHeader',
	'QuestInfoObjectivesHeader', 'QuestInfoDescriptionText',
	'QuestInfoObjectivesText', 'QuestInfoGroupSize', 'QuestInfoRewardText',
	'QuestInfoTimerText', 'QuestInfoSpellObjectiveLearnLabel',
	'QuestInfoQuestType', 'QuestInfoRequiredMoneyText',
}

local QUEST_REWARD_TEXT = {
	'Header', 'ItemChooseText', 'ItemReceiveText', 'PlayerTitleText',
	'QuestSessionBonusReward',
}

local function WhitenQuestInfo(_, parentFrame)
	-- QuestInfo is shared with the quest log, which keeps its parchment
	local questFrame = _G.QuestFrame
	if not questFrame or not parentFrame or not IsInside(parentFrame, questFrame) then
		-- Blizzard only recolors when the material changes; make sure it
		-- does after we've been here, or the log inherits our white text
		if _G.QuestInfoFrame then _G.QuestInfoFrame.material = nil end
		return
	end

	for _, name in next, QUEST_INFO_TEXT do
		WhiteIfDark(_G[name])
	end

	local rewards = _G.QuestInfoRewardsFrame
	if rewards then
		for _, key in next, QUEST_REWARD_TEXT do
			WhiteIfDark(rewards[key])
		end
		WhiteIfDark(rewards.XPFrame and rewards.XPFrame.ReceiveText)
		local pool = rewards.spellHeaderPool
		if pool then pool.textR, pool.textG, pool.textB = 1, 1, 1 end
	end

	local objectives = _G.QuestInfoObjectivesFrame
	for _, objective in next, objectives and objectives.Objectives or {} do
		WhiteIfDark(objective)
	end

	if _G.QuestInfoFrame then _G.QuestInfoFrame.material = nil end
end

-- the greeting list bakes black into its quest titles; a fixed color
-- overrides the inline code, the same way Blizzard's high-contrast mode does
local function WhitenGreeting()
	local panel = _G.QuestFrameGreetingPanel
	local pool = panel and panel.titleButtonPool
	if not pool then return end
	for button in pool:EnumerateActive() do
		local text = button:GetFontString()
		if text then
			text:SetFixedColor(true)
			White(text)
		end
	end
end

local function WhitenQuestText()
	if QuestInfo_Display then
		hooksecurefunc('QuestInfo_Display', WhitenQuestInfo)
	end
	-- progress and greeting panels go through these two
	if QuestFrame_SetTextColor then
		hooksecurefunc('QuestFrame_SetTextColor', White)
	end
	if QuestFrame_SetTitleTextColor then
		hooksecurefunc('QuestFrame_SetTitleTextColor', White)
	end
	if QuestFrameProgressItems_Update then
		hooksecurefunc('QuestFrameProgressItems_Update', function()
			WhiteIfDark(_G.QuestProgressRequiredMoneyText)
		end)
	end

	local greeting = _G.QuestFrameGreetingPanel
	if greeting then greeting:HookScript('OnShow', WhitenGreeting) end
	if QuestFrameGreetingPanel_OnShow then
		hooksecurefunc('QuestFrameGreetingPanel_OnShow', WhitenGreeting)
	end
end

local function SkinQuest()
	local frame = Skin:Get('QuestFrame')
	if not frame then return end

	WhitenQuestText()

	Skin:Frame(frame)

	for _, name in next, QUEST_PANELS do
		Skin:Strip(_G[name])
	end
	Skin:Strip(Skin:Get('QuestNpcNameFrame'))

	for _, name in next, QUEST_BUTTONS do
		Skin:Button(Skin:Get(name))
	end

	-- items you hand in
	SkinSeries(MAX_REQUIRED_ITEMS or 6, 'ItemButton', 'QuestProgressItem')

	-- reward buttons are made on demand as quests are shown
	local rewards = _G.QuestInfoRewardsFrame
	if rewards and QuestInfo_GetRewardButton then
		hooksecurefunc('QuestInfo_GetRewardButton', function(_, index)
			Skin:ItemButton(rewards.RewardButtons and rewards.RewardButtons[index])
		end)
	end
end

--------------------------------------------------------------------------------
-- Gossip
--------------------------------------------------------------------------------

local function SkinGossip()
	local frame = Skin:Get('GossipFrame')
	if not frame then return end

	Skin:Frame(frame)
	Skin:Strip(frame.GreetingPanel or _G.GossipFrameGreetingPanel)
	Skin:Button(frame.GreetingPanel and frame.GreetingPanel.GoodbyeButton
		or _G.GossipFrameGoodbyeButton)

	-- greeting and option text is themed by the frame's text-contrast
	-- container, which reapplies its colors on every update
	if frame.UpdateFontStrings then
		hooksecurefunc(frame, 'UpdateFontStrings', function(self)
			for fontString in next, self.fontStrings or {} do
				fontString:SetFixedColor(true)
				White(fontString)
			end
		end)
		frame:UpdateFontStrings()
	end
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

Skin:Register(nil, SkinMerchant, 'Merchant')
Skin:Register(nil, SkinMail, 'Mail')
Skin:Register(nil, SkinQuest, 'Quest')
Skin:Register(nil, SkinGossip, 'Gossip')
