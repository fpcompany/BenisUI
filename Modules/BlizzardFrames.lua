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

local function SkinQuest()
	local frame = Skin:Get('QuestFrame')
	if not frame then return end

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
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

Skin:Register(nil, SkinMerchant, 'Merchant')
Skin:Register(nil, SkinMail, 'Mail')
Skin:Register(nil, SkinQuest, 'Quest')
Skin:Register(nil, SkinGossip, 'Gossip')
