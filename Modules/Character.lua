local _, ns = ...
local BenisUI = ns.BenisUI

-- Restyles the character (equipment) window: item level on each gear slot,
-- fractional average item level and secondary stat percentages.
local Character = BenisUI:RegisterModule('Character')

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

local EDGE_TEXTURE = 'Interface\\Buttons\\WHITE8X8'

local function StripTextures(frame)
	if not frame then return end

	for _, region in next, { frame:GetRegions() } do
		if region.IsObjectType and region:IsObjectType('Texture') then
			region:SetTexture(nil)
			region:SetAlpha(0)
		end
	end

	if frame.NineSlice then
		frame.NineSlice:SetAlpha(0)
	end
end

local function SkinCharacterFrame()
	local frame = _G.CharacterFrame
	if not frame then return end

	StripTextures(frame)
	StripTextures(_G.CharacterFrameInset)
	StripTextures(_G.CharacterFrameInsetRight)
	StripTextures(_G.CharacterModelScene)
	StripTextures(_G.PaperDollSidebarTabs)

	if _G.CharacterFramePortrait then
		_G.CharacterFramePortrait:SetAlpha(0)
	end

	local statsPane = _G.CharacterStatsPane
	if statsPane then
		StripTextures(statsPane)
		if statsPane.ClassBackground then statsPane.ClassBackground:Hide() end
		for _, key in next, { 'EnhancementsCategory', 'ItemLevelCategory', 'AttributesCategory' } do
			StripTextures(statsPane[key])
		end
	end

	-- solid dark ground behind the model (its backgrounds were stripped)
	local modelOverlay = _G.CharacterModelFrameBackgroundOverlay
	if modelOverlay then
		modelOverlay:SetColorTexture(0.03, 0.03, 0.03)
		modelOverlay:SetAlpha(1)
	end

	-- same backdrop the bag frame uses
	local backdrop = CreateFrame('Frame', nil, frame, 'BackdropTemplate')
	backdrop:SetAllPoints()
	backdrop:SetFrameLevel(frame:GetFrameLevel())
	backdrop:SetBackdrop({
		bgFile = EDGE_TEXTURE,
		edgeFile = EDGE_TEXTURE,
		edgeSize = 1,
	})
	backdrop:SetBackdropColor(0.06, 0.06, 0.06, 0.94)
	backdrop:SetBackdropBorderColor(0, 0, 0, 1)
end

--------------------------------------------------------------------------------
-- Item level on gear slots
--------------------------------------------------------------------------------

local function UpdateSlotItemLevel(button)
	-- the same template also backs flyouts and other frames
	if button:GetParent() ~= _G.PaperDollItemsFrame then return end

	local text = button.BenisUIItemLevel
	if not text then
		text = button:CreateFontString(nil, 'OVERLAY', 'NumberFontNormalSmall')
		text:SetPoint('BOTTOM', 0, 2)
		button.BenisUIItemLevel = text
	end

	local invSlot = button:GetID()
	local location = ItemLocation:CreateFromEquipmentSlot(invSlot)
	if location and DoesItemExist(location) then
		local itemLevel = GetCurrentItemLevel(location)
		if itemLevel and itemLevel > 1 then
			text:SetText(itemLevel)
			text:SetTextColor(GetQualityColor(GetInventoryItemQuality('player', invSlot)))
			return
		end
	end

	text:SetText('')
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
	SkinCharacterFrame()

	if PaperDollItemSlotButton_Update then
		hooksecurefunc('PaperDollItemSlotButton_Update', UpdateSlotItemLevel)
	end
	if PaperDollFrame_SetLabelAndText then
		hooksecurefunc('PaperDollFrame_SetLabelAndText', RestylePercentage)
	end
	if PaperDollFrame_SetItemLevel then
		hooksecurefunc('PaperDollFrame_SetItemLevel', RestyleItemLevel)
	end
end
