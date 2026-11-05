local _, ns = ...
local BenisUI = ns.BenisUI

-- Inspect window: item level on every gear slot plus the inspected
-- character's average equipped item level next to the weapon slots.
local Inspect = BenisUI:RegisterModule('Inspect')

local GetDetailedItemLevelInfo = C_Item.GetDetailedItemLevelInfo
local GetInspectItemLevel = C_PaperDollInfo.GetInspectItemLevel

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
-- Item level on gear slots
--------------------------------------------------------------------------------

local function SetSlotItemLevel(button, link, itemLevel)
	local text = button.BenisUIItemLevel
	if not text then
		text = button:CreateFontString(nil, 'OVERLAY', 'NumberFontNormalSmall')
		text:SetPoint('BOTTOM', 0, 2)
		button.BenisUIItemLevel = text
	end

	if itemLevel and itemLevel > 1 then
		text:SetText(itemLevel)
		text:SetTextColor(GetQualityColor(C_Item.GetItemQualityByID(link)))
	else
		text:SetText('')
	end
end

local function UpdateSlotItemLevel(button)
	local unit = _G.InspectFrame and _G.InspectFrame.unit
	local link = unit and GetInventoryItemLink(unit, button:GetID())
	button.BenisUIItemLink = link

	if not link then
		SetSlotItemLevel(button, nil, nil)
		return
	end

	-- item data may still be on its way from the server the first time we
	-- see this item; wait for it rather than showing nothing
	local item = Item:CreateFromItemLink(link)
	if item:IsItemEmpty() then
		SetSlotItemLevel(button, nil, nil)
		return
	end

	item:ContinueOnItemLoad(function()
		-- the slot may have been refreshed with another item meanwhile
		if button.BenisUIItemLink ~= link then return end
		SetSlotItemLevel(button, link, GetDetailedItemLevelInfo(link))
	end)
end

--------------------------------------------------------------------------------
-- Average item level
--------------------------------------------------------------------------------

local average

local function CreateAverageDisplay()
	local anchor = _G.InspectMainHandSlot
	if not anchor then return end

	-- lives on the main hand button so it draws above that slot's frame art
	local label = anchor:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
	label:SetPoint('BOTTOMRIGHT', anchor, 'LEFT', -12, 1)
	label:SetJustifyH('RIGHT')
	label:SetText(STAT_AVERAGE_ITEM_LEVEL or 'Item Level')

	local value = anchor:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightLarge')
	value:SetPoint('TOPRIGHT', anchor, 'LEFT', -12, -1)
	value:SetJustifyH('RIGHT')

	average = { label = label, value = value }
end

local function UpdateAverageItemLevel()
	if not average then return end

	local unit = _G.InspectFrame and _G.InspectFrame.unit
	local itemLevel = unit and GetInspectItemLevel(unit)
	if itemLevel and itemLevel > 0 then
		average.value:SetFormattedText('%.2f', itemLevel)
		average.label:Show()
	else
		-- nothing useful yet (data still arriving); hide rather than show 0
		average.value:SetText('')
		average.label:Hide()
	end
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

local function Setup()
	CreateAverageDisplay()

	if InspectPaperDollItemSlotButton_Update then
		hooksecurefunc('InspectPaperDollItemSlotButton_Update', UpdateSlotItemLevel)
	end
	-- runs on show, INSPECT_READY and level changes: the same moments the
	-- inspect data becomes (or stops being) valid
	if InspectPaperDollFrame_SetLevel then
		hooksecurefunc('InspectPaperDollFrame_SetLevel', UpdateAverageItemLevel)
	end
end

function Inspect:OnInit()
	if C_AddOns.IsAddOnLoaded('Blizzard_InspectUI') then
		Setup()
	else
		local waiter = CreateFrame('Frame')
		waiter:RegisterEvent('ADDON_LOADED')
		waiter:SetScript('OnEvent', function(self, _, addon)
			if addon == 'Blizzard_InspectUI' then
				self:UnregisterAllEvents()
				Setup()
			end
		end)
	end
end
