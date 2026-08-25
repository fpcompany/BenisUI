local _, ns = ...
local BenisUI = ns.BenisUI

-- Tracks which bag slots hold equipment set items and adds per-set highlight
-- controls (checkbox + color swatch) to the Blizzard Equipment Manager.
local Sets = BenisUI:RegisterModule('EquipmentSets')

local GetEquipmentSetIDs = C_EquipmentSet.GetEquipmentSetIDs
local GetItemLocations = C_EquipmentSet.GetItemLocations

Sets.map = {} -- [bagID][slotID] = { setID, ... }
Sets.dirty = true

--------------------------------------------------------------------------------
-- Membership map
--------------------------------------------------------------------------------

function Sets:MarkDirty()
	self.dirty = true
end

function Sets:Rebuild()
	self.dirty = false
	wipe(self.map)

	local setIDs = GetEquipmentSetIDs()
	if not setIDs then return end

	for _, setID in ipairs(setIDs) do
		local locations = GetItemLocations(setID)
		if locations then
			for _, location in pairs(locations) do
				if type(location) == 'number' and location > 0 then
					local data = EquipmentManager_GetLocationData(location)
					if data.isBags and not data.isBank and data.bag and data.slot then
						local bagMap = self.map[data.bag]
						if not bagMap then
							bagMap = {}
							self.map[data.bag] = bagMap
						end
						local list = bagMap[data.slot]
						if not list then
							list = {}
							bagMap[data.slot] = list
						end
						list[#list + 1] = setID
					end
				end
			end
		end
	end
end

function Sets:GetConfig(setID, create)
	local highlights = BenisUI.chardb.bags.setHighlights
	local config = highlights[setID]
	if not config and create then
		config = { enabled = true }
		highlights[setID] = config
	end
	return config
end

-- Returns highlighted, r, g, b. Colors are nil when the set has no custom
-- color (caller falls back to the item quality color).
function Sets:GetHighlight(bagID, slotID)
	if self.dirty then
		self:Rebuild()
	end

	local list = self.map[bagID] and self.map[bagID][slotID]
	if not list then return false end

	for _, setID in ipairs(list) do
		local config = self:GetConfig(setID)
		if not config or config.enabled then
			if config then
				return true, config.r, config.g, config.b
			end
			return true
		end
	end

	return false
end

-- lowercased set names for the bag search corpus, or nil if not in any set
function Sets:GetSetNamesText(bagID, slotID)
	if self.dirty then
		self:Rebuild()
	end

	local list = self.map[bagID] and self.map[bagID][slotID]
	if not list then return nil end

	local text = 'set'
	for _, setID in ipairs(list) do
		local name = C_EquipmentSet.GetEquipmentSetInfo(setID)
		if name then
			text = text .. ' ' .. name:lower()
		end
	end
	return text
end

--------------------------------------------------------------------------------
-- Equipment Manager row widgets
--------------------------------------------------------------------------------

local function RefreshBags()
	local Bags = BenisUI:GetModule('Bags')
	if Bags and Bags.frame and Bags.frame:IsShown() then
		Bags:UpdateAll()
	end
end

local function OpenColorPicker(setID, swatchTexture)
	local config = Sets:GetConfig(setID, true)
	local function apply(r, g, b)
		config.r, config.g, config.b = r, g, b
		swatchTexture:SetVertexColor(r, g, b)
		RefreshBags()
	end

	ColorPickerFrame:SetupColorPickerAndShow({
		r = config.r or 1,
		g = config.g or 1,
		b = config.b or 1,
		hasOpacity = false,
		swatchFunc = function()
			apply(ColorPickerFrame:GetColorRGB())
		end,
		cancelFunc = function(previous)
			apply(previous.r, previous.g, previous.b)
		end,
	})
end

local function Widget_OnEnter(self)
	GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
	GameTooltip:SetText(self.tooltip, 1, 1, 1)
	GameTooltip:Show()
end

local function DecorateRow(button)
	local check = button.BenisUISetCheck
	if not check then
		check = CreateFrame('CheckButton', nil, button, 'UICheckButtonTemplate')
		check:SetSize(16, 16)
		check:SetPoint('TOPRIGHT', -2, 1)
		check.tooltip = 'BenisUI: highlight this set in bags'
		check:SetScript('OnEnter', Widget_OnEnter)
		check:SetScript('OnLeave', GameTooltip_Hide)
		check:SetScript('OnClick', function(self)
			if not button.setID then return end
			local config = Sets:GetConfig(button.setID, true)
			config.enabled = self:GetChecked() and true or false
			RefreshBags()
		end)
		button.BenisUISetCheck = check

		local swatch = CreateFrame('Button', nil, button)
		swatch:SetSize(12, 12)
		swatch:SetPoint('RIGHT', check, 'LEFT', -1, 0)
		swatch.tooltip = 'BenisUI: highlight color'
		local border = swatch:CreateTexture(nil, 'BACKGROUND')
		border:SetAllPoints()
		border:SetColorTexture(0, 0, 0)
		swatch.color = swatch:CreateTexture(nil, 'ARTWORK')
		swatch.color:SetPoint('TOPLEFT', 1, -1)
		swatch.color:SetPoint('BOTTOMRIGHT', -1, 1)
		swatch.color:SetColorTexture(1, 1, 1)
		swatch:SetScript('OnEnter', Widget_OnEnter)
		swatch:SetScript('OnLeave', GameTooltip_Hide)
		swatch:SetScript('OnClick', function()
			if button.setID then
				OpenColorPicker(button.setID, swatch.color)
			end
		end)
		button.BenisUISetSwatch = swatch
	end

	local setID = button.setID
	if setID then
		local config = Sets:GetConfig(setID)
		check:SetChecked(not config or config.enabled)
		if config and config.r then
			button.BenisUISetSwatch.color:SetVertexColor(config.r, config.g, config.b)
		else
			button.BenisUISetSwatch.color:SetVertexColor(1, 1, 1)
		end
		check:Show()
		button.BenisUISetSwatch:Show()
	else
		-- the "New Set" row
		check:Hide()
		button.BenisUISetSwatch:Hide()
	end
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

function Sets:OnInit()
	if PaperDollEquipmentManagerPane_InitButton then
		hooksecurefunc('PaperDollEquipmentManagerPane_InitButton', DecorateRow)
	end

	local listener = CreateFrame('Frame')
	listener:RegisterEvent('EQUIPMENT_SETS_CHANGED')
	listener:SetScript('OnEvent', function()
		self:MarkDirty()
		RefreshBags()
	end)
end
