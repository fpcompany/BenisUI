local _, ns = ...
local BenisUI = ns.BenisUI

-- Restyles the character (equipment) window: item level, enchant name and
-- socketed gems on each gear slot, fractional average item level and
-- secondary stat percentages.
local Character = BenisUI:RegisterModule('Character')

local Skin = BenisUI.Skin

local GetCurrentItemLevel = C_Item.GetCurrentItemLevel
local DoesItemExist = C_Item.DoesItemExist

local function GetQualityColor(quality)
	if quality then
		if ColorManager and ColorManager.GetColorDataForItemQuality then
			local data = ColorManager.GetColorDataForItemQuality(quality)
			if data and data.color then
				return data.color:GetRGB()
			end
		end

		local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
		if color then
			return color.r, color.g, color.b
		end
	end

	return 1, 1, 1
end

--------------------------------------------------------------------------------
-- Frame reskin (match the BenisUI bag frame)
--------------------------------------------------------------------------------

local function SkinCharacterFrame()
	local frame = _G.CharacterFrame
	if not frame then return end

	-- the generic pass covers the frame art, CharacterFrameInset and the portrait
	Skin:Frame(frame)
	Skin:Strip(_G.CharacterFrameInsetRight)
	Skin:Strip(_G.CharacterModelScene)
	Skin:Strip(_G.PaperDollSidebarTabs)

	local statsPane = _G.CharacterStatsPane
	if statsPane then
		Skin:Strip(statsPane)
		Skin:Kill(statsPane.ClassBackground)
		for _, key in next, { 'EnhancementsCategory', 'ItemLevelCategory', 'AttributesCategory' } do
			Skin:Strip(statsPane[key])
		end
	end

	-- solid dark ground behind the model (its backgrounds were stripped)
	local modelOverlay = _G.CharacterModelFrameBackgroundOverlay
	if modelOverlay then
		modelOverlay:SetColorTexture(0.03, 0.03, 0.03)
		modelOverlay:SetAlpha(1)
	end
end

--------------------------------------------------------------------------------
-- Gear slot info: item level, enchant name and socketed gems
--------------------------------------------------------------------------------

local GEM_SIZE = 14
local GEM_SPACING = 2
local MAX_GEMS = 4
local INFO_OFFSET = 6 -- gap between a slot and the text/gems beside it
local ENCHANT_WIDTH = 110 -- half the model area, minus margins

local EMPTY_SOCKET_TEXTURE = 'Interface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic'

-- "Enchanted: %s" split around the placeholder, so the enchant name can be
-- pulled out of the tooltip line whatever the client language
local enchantPrefix, enchantSuffix = '', ''
if type(ENCHANTED_TOOLTIP_LINE) == 'string' then
	enchantPrefix, enchantSuffix = ENCHANTED_TOOLTIP_LINE:match('^(.-)%%s(.-)$')
	enchantPrefix, enchantSuffix = enchantPrefix or '', enchantSuffix or ''
end

-- Which way the info hangs off the slot: left-column slots and the off hand
-- put it on their right, right-column slots and the main hand on their left
-- (the two weapon slots sit side by side, so each faces away from the other).
local function InfoOnRight(button)
	if button.IsLeftSide ~= nil then
		return button.IsLeftSide
	end
	return button:GetID() ~= INVSLOT_MAINHAND
end

local function CleanEnchantText(text)
	if enchantPrefix ~= '' and text:sub(1, #enchantPrefix) == enchantPrefix then
		text = text:sub(#enchantPrefix + 1)
	end
	if enchantSuffix ~= '' and text:sub(-#enchantSuffix) == enchantSuffix then
		text = text:sub(1, -#enchantSuffix - 1)
	end
	-- crafting quality icon that trails the enchant name
	text = text:gsub('|A:[^|]*|a', '')
	return strtrim(text)
end

local function GetEnchantText(invSlot)
	local data = C_TooltipInfo.GetInventoryItem('player', invSlot)
	local lines = data and data.lines
	if not lines then return end

	local enchantType = Enum.TooltipDataLineType and Enum.TooltipDataLineType.ItemEnchantmentPermanent
	for _, line in ipairs(lines) do
		local text = line.leftText
		if type(text) == 'string' and not (issecretvalue and issecretvalue(text)) then
			if line.type == enchantType or (enchantPrefix ~= '' and text:sub(1, #enchantPrefix) == enchantPrefix) then
				local cleaned = CleanEnchantText(text)
				if cleaned ~= '' then return cleaned end
			end
		end
	end
end

local function Gem_OnEnter(self)
	GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
	local _, gemLink = self.gemID and C_Item.GetItemGem(self.itemLink, self.index)
	if gemLink then
		GameTooltip:SetHyperlink(gemLink)
	elseif self.gemID then
		-- gem item data not cached yet; the ID is enough for a tooltip
		GameTooltip:SetItemByID(self.gemID)
	else
		GameTooltip:SetText(EMPTY_SOCKET_PRISMATIC or 'Empty socket', 1, 1, 1)
	end
	GameTooltip:Show()
end

local function Gem_OnLeave()
	GameTooltip:Hide()
end

local function CreateSlotInfo(button)
	local right = InfoOnRight(button)
	local side = right and 'LEFT' or 'RIGHT'
	local opposite = right and 'RIGHT' or 'LEFT'
	local dx = right and INFO_OFFSET or -INFO_OFFSET

	-- the weapon slots sit beside the bottom of the gear columns, so their
	-- info drops below the column bottoms instead of hugging the slot top
	local isWeapon = button.IsLeftSide == nil

	local enchant = button:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
	if isWeapon then
		enchant:SetPoint('TOP' .. side, button, opposite, dx, 3)
	else
		enchant:SetPoint('TOP' .. side, button, 'TOP' .. opposite, dx, -3)
	end
	enchant:SetWidth(ENCHANT_WIDTH)
	enchant:SetJustifyH(side)
	enchant:SetWordWrap(false)
	enchant:SetTextColor(0.1, 1, 0.1)

	local gems = {}
	for index = 1, MAX_GEMS do
		local gem = CreateFrame('Button', nil, button)
		gem:SetSize(GEM_SIZE, GEM_SIZE)
		if index == 1 and isWeapon then
			gem:SetPoint('TOP' .. side, enchant, 'BOTTOM' .. side, 0, -2)
		elseif index == 1 then
			gem:SetPoint('BOTTOM' .. side, button, 'BOTTOM' .. opposite, dx, 3)
		else
			gem:SetPoint(side, gems[index - 1], opposite, right and GEM_SPACING or -GEM_SPACING, 0)
		end

		gem.icon = gem:CreateTexture(nil, 'ARTWORK')
		gem.icon:SetAllPoints()
		gem.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		gem.border = gem:CreateTexture(nil, 'BACKGROUND')
		gem.border:SetPoint('TOPLEFT', -1, 1)
		gem.border:SetPoint('BOTTOMRIGHT', 1, -1)
		gem.border:SetColorTexture(0, 0, 0)

		gem.index = index
		gem:SetScript('OnEnter', Gem_OnEnter)
		gem:SetScript('OnLeave', Gem_OnLeave)
		gem:Hide()
		gems[index] = gem
	end

	local info = { enchant = enchant, gems = gems }
	button.BenisUIGear = info
	return info
end

local function ClearGems(info, fromIndex)
	for index = fromIndex or 1, MAX_GEMS do
		info.gems[index]:Hide()
	end
end

local function UpdateGems(button, info, link)
	local numSockets = C_Item.GetItemNumSockets(link) or 0
	numSockets = math.min(numSockets, MAX_GEMS)

	for index = 1, numSockets do
		local gem = info.gems[index]
		local gemID = C_Item.GetItemGemID(link, index)
		gem.itemLink = link
		gem.gemID = gemID

		if gemID then
			local gemItem = Item:CreateFromItemID(gemID)
			if not gemItem:IsItemDataCached() then
				gem.icon:SetTexture(nil)
			end
			gemItem:ContinueOnItemLoad(function()
				-- the slot may hold another item by the time the gem loads
				if button.BenisUIGearLink ~= link or gem.gemID ~= gemID then return end
				gem.icon:SetTexture(C_Item.GetItemIconByID(gemID))
			end)
		else
			gem.icon:SetTexture(EMPTY_SOCKET_TEXTURE)
		end
		gem:Show()
	end

	ClearGems(info, numSockets + 1)
end

local function UpdateSlotInfo(button)
	-- the same template also backs flyouts and other frames
	if button:GetParent() ~= _G.PaperDollItemsFrame then return end

	local text = button.BenisUIItemLevel
	if not text then
		text = button:CreateFontString(nil, 'OVERLAY', 'NumberFontNormalSmall')
		text:SetPoint('BOTTOM', 0, 2)
		button.BenisUIItemLevel = text
	end
	local info = button.BenisUIGear or CreateSlotInfo(button)

	local invSlot = button:GetID()
	local location = ItemLocation:CreateFromEquipmentSlot(invSlot)
	local link = GetInventoryItemLink('player', invSlot)
	button.BenisUIGearLink = link

	if not link or not (location and DoesItemExist(location)) then
		text:SetText('')
		info.enchant:SetText('')
		ClearGems(info)
		return
	end

	local itemLevel = GetCurrentItemLevel(location)
	if itemLevel and itemLevel > 1 then
		text:SetText(itemLevel)
		text:SetTextColor(GetQualityColor(GetInventoryItemQuality('player', invSlot)))
	else
		text:SetText('')
	end

	-- enchant and socket data need the item itself loaded
	local item = Item:CreateFromItemLink(link)
	item:ContinueOnItemLoad(function()
		if button.BenisUIGearLink ~= link then return end
		info.enchant:SetText(GetEnchantText(invSlot) or '')
		UpdateGems(button, info, link)
	end)
end

--------------------------------------------------------------------------------
-- Fractional stats pane values
--------------------------------------------------------------------------------

local function RestylePercentage(statFrame, _, _, isPercentage, numericValue)
	if isPercentage and type(numericValue) == 'number' and statFrame.Value then
		statFrame.Value:SetFormattedText('%.2f%%', numericValue)
	end
end

local function RestyleItemLevel(statFrame, unit)
	if unit ~= 'player' or not statFrame.Value then return end

	local _, avgItemLevelEquipped = GetAverageItemLevel()
	local minItemLevel = C_PaperDollInfo.GetMinItemLevel()
	local displayItemLevel = math.max(minItemLevel or 0, avgItemLevelEquipped or 0)

	statFrame.Value:SetFormattedText('%.2f', displayItemLevel)
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

function Character:OnInit()
	Skin:Register(nil, SkinCharacterFrame, 'Character')

	if PaperDollItemSlotButton_Update then
		hooksecurefunc('PaperDollItemSlotButton_Update', UpdateSlotInfo)
	end
	if PaperDollFrame_SetLabelAndText then
		hooksecurefunc('PaperDollFrame_SetLabelAndText', RestylePercentage)
	end
	if PaperDollFrame_SetItemLevel then
		hooksecurefunc('PaperDollFrame_SetItemLevel', RestyleItemLevel)
	end
end
