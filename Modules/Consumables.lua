local _, ns = ...
local BenisUI = ns.BenisUI

-- Small panel of secure buttons showing the state of the bags' consumables:
-- a Healthstone, a healing potion, a combat/mana potion, a flask and food.
-- Each button shows the best matching item of its category with the total
-- count and cooldown and uses it on click; categories with nothing in the
-- bags are hidden and the panel shrinks to fit. Modeled on ElvUI WindTools'
-- consumables bar.
local Consumables = BenisUI:RegisterModule('Consumables')

local FONT = BenisUI.media.font
local Skin = BenisUI.Skin

local GetContainerNumSlots = C_Container.GetContainerNumSlots
local GetContainerItemInfo = C_Container.GetContainerItemInfo
local GetItemCooldown = C_Container.GetItemCooldown
local GetItemInfoInstant = C_Item.GetItemInfoInstant
local GetItemInfo = C_Item.GetItemInfo

local NUM_BAGS = NUM_TOTAL_EQUIPPED_BAG_SLOTS or 5

local BUTTON_SIZE = 30
local SPACING = 4
local PADDING = 5

-- Healthstone gets its own slot so it doesn't hide the healing potions; the
-- name fallback below catches any variant the ID list misses
local HEALTHSTONES = {
	[5512] = true, -- Healthstone
}

local HEALTHSTONE_PATTERN = 'Healthstone'

-- healing potions that should land in the healing potion slot rather than the
-- generic potion slot; anything named '<...> Healing Potion' / '<...> Health
-- Potion' is caught by the name fallback below, this list covers renames and
-- non-enUS clients
local HEALING_POTIONS = {
	[211878] = true, [211879] = true, [211880] = true, -- Algari Healing Potion
	[207021] = true, [207022] = true, [207023] = true, -- Dreamwalker's Healing Potion
	[191378] = true, [191379] = true, [191380] = true, -- Refreshing Healing Potion
	[187802] = true, -- Cosmic Healing Potion
	[171267] = true, -- Spiritual Healing Potion
}

local HEAL_NAME_PATTERNS = {
	'Healing Potion',
	'Health Potion', -- Midnight naming (e.g. Silvermoon Health Potion)
	'Healing Draught',
}

local FLASK_SUBCLASS = Enum.ItemConsumableSubclass
	and (Enum.ItemConsumableSubclass.Flask or Enum.ItemConsumableSubclass.FlasksPhials) or 3

local CATEGORIES = {
	{
		key = 'healthstone',
		label = 'Healthstone',
		fallbackIcon = 'Interface\\Icons\\INV_Stone_04',
		lowCount = 0, -- Healthstones are unique, one is a full stack
	},
	{
		key = 'healpotion',
		label = 'Healing Potions',
		fallbackIcon = 'Interface\\Icons\\INV_Potion_51',
		lowCount = 3,
	},
	{
		key = 'potion',
		label = 'Combat / Mana Potions',
		fallbackIcon = 'Interface\\Icons\\INV_Potion_76',
		lowCount = 5,
	},
	{
		key = 'flask',
		label = 'Flasks & Phials',
		fallbackIcon = 'Interface\\Icons\\INV_Alchemy_EndlessFlask_06',
		lowCount = 1,
	},
	{
		key = 'food',
		label = 'Food',
		fallbackIcon = 'Interface\\Icons\\INV_Misc_Food_15',
		lowCount = 10,
	},
}

local panel
local buttons = {} -- [key] = button
local found = {} -- [category key][itemID] = { id, count }
for _, category in next, CATEGORIES do
	found[category.key] = {}
end
local infoPending = false -- an item's GetItemInfo wasn't cached during the scan
local applyPending = false -- attribute changes blocked by combat
local layoutPending = false -- show/hide/reposition blocked by combat
local appliedLayout -- which categories the current layout has visible

--------------------------------------------------------------------------------
-- Classification
--------------------------------------------------------------------------------

local function Classify(itemID)
	if HEALTHSTONES[itemID] then return 'healthstone' end
	if HEALING_POTIONS[itemID] then return 'healpotion' end

	local _, _, _, _, _, classID, subClassID = GetItemInfoInstant(itemID)
	if classID ~= Enum.ItemClass.Consumable then return end

	if subClassID == Enum.ItemConsumableSubclass.Potion then
		local name = GetItemInfo(itemID)
		if not name then
			infoPending = true
			return
		end
		for _, pattern in next, HEAL_NAME_PATTERNS do
			if name:find(pattern, 1, true) then
				return 'healpotion'
			end
		end
		return 'potion'
	elseif subClassID == FLASK_SUBCLASS then
		return 'flask'
	elseif subClassID == Enum.ItemConsumableSubclass.Fooddrink then
		return 'food'
	end

	-- Healthstone sits outside the potion subclass, so catch renamed or
	-- non-enUS variants by name
	local name = GetItemInfo(itemID)
	if not name then
		infoPending = true
		return
	end
	if name:find(HEALTHSTONE_PATTERN, 1, true) then
		return 'healthstone'
	end
end

local function ItemLevel(itemID)
	local level = select(4, GetItemInfo(itemID))
	if not level then infoPending = true end
	return level or 0
end

-- prefer the higher item level, then the bigger stack
local function IsBetter(a, b)
	if not b then return true end
	local levelA, levelB = ItemLevel(a.id), ItemLevel(b.id)
	if levelA ~= levelB then return levelA > levelB end
	return a.count > b.count
end

local function ScanBags()
	infoPending = false
	for _, items in pairs(found) do
		wipe(items)
	end

	for bagID = 0, NUM_BAGS do
		for slotID = 1, GetContainerNumSlots(bagID) do
			local info = GetContainerItemInfo(bagID, slotID)
			if info and info.itemID then
				local category = Classify(info.itemID)
				if category then
					local entry = found[category][info.itemID]
					if entry then
						entry.count = entry.count + info.stackCount
					else
						found[category][info.itemID] = { id = info.itemID, count = info.stackCount }
					end
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Button state
--------------------------------------------------------------------------------

local function UpdateCooldown(button)
	if button.entry then
		local start, duration, enable = GetItemCooldown(button.entry.id)
		CooldownFrame_Set(button.cooldown, start, duration, enable)
	else
		button.cooldown:Clear()
	end
end

local function ApplyAttribute(button)
	local want = button.entry and ('item:' .. button.entry.id) or nil
	if button.appliedItem == want then return end
	if InCombatLockdown() then
		applyPending = true
		return
	end
	button:SetAttribute('item', want)
	button.appliedItem = want
end

local function UpdateButton(button)
	local best
	for _, entry in pairs(found[button.category.key]) do
		if IsBetter(entry, best) then best = entry end
	end
	button.entry = best

	if best then
		button.icon:SetTexture(select(5, GetItemInfoInstant(best.id)))
		button.icon:SetDesaturated(false)
		button.icon:SetVertexColor(1, 1, 1)
		button.count:SetText(best.count)
		if best.count <= button.category.lowCount then
			button.count:SetTextColor(1, 0.82, 0)
		else
			button.count:SetTextColor(1, 1, 1)
		end
	else
		-- only seen when the category empties mid-fight: the button can't be
		-- hidden until combat ends, so show it greyed out and empty
		button.icon:SetTexture(button.category.fallbackIcon)
		button.icon:SetDesaturated(true)
		button.icon:SetVertexColor(1, 0.35, 0.35)
		button.count:SetText('0')
		button.count:SetTextColor(1, 0.3, 0.3)
	end

	ApplyAttribute(button)
	UpdateCooldown(button)

	if GameTooltip:IsOwned(button) then
		button:GetScript('OnEnter')(button)
	end
end

-- Pack the buttons of the categories we actually have items for, left to
-- right, and size the panel around them; hide it entirely when the bags hold
-- none of them. Secure buttons can't be shown, hidden or moved in combat, so
-- a change that lands mid-fight waits for PLAYER_REGEN_ENABLED.
local function LayoutButtons()
	local layout = ''
	for _, category in ipairs(CATEGORIES) do
		layout = layout .. (buttons[category.key].entry and '1' or '0')
	end
	if layout == appliedLayout then return end

	if InCombatLockdown() then
		layoutPending = true
		return
	end

	local shown = 0
	for _, category in ipairs(CATEGORIES) do
		local button = buttons[category.key]
		if button.entry then
			button:ClearAllPoints()
			button:SetPoint('LEFT', panel, 'LEFT', PADDING + shown * (BUTTON_SIZE + SPACING), 0)
			button:Show()
			shown = shown + 1
		else
			button:Hide()
		end
	end

	if shown > 0 then
		panel:SetSize(
			PADDING * 2 + shown * BUTTON_SIZE + (shown - 1) * SPACING,
			BUTTON_SIZE + PADDING * 2)
		panel:Show()
	else
		panel:Hide()
	end

	appliedLayout = layout
end

local function UpdateAll()
	ScanBags()
	for _, button in pairs(buttons) do
		UpdateButton(button)
	end
	LayoutButtons()
end

--------------------------------------------------------------------------------
-- Tooltip
--------------------------------------------------------------------------------

local function ButtonOnEnter(self)
	GameTooltip:SetOwner(self, 'ANCHOR_TOP')
	if self.entry then
		GameTooltip:SetItemByID(self.entry.id)

		-- list the rest of the category under the item tooltip
		local others = {}
		for _, entry in pairs(found[self.category.key]) do
			if entry ~= self.entry then
				others[#others + 1] = entry
			end
		end
		if #others > 0 then
			table.sort(others, IsBetter)
			GameTooltip:AddLine(' ')
			GameTooltip:AddLine('Also in bags:', 0.7, 0.7, 0.7)
			for _, entry in next, others do
				local name = GetItemInfo(entry.id) or ('item:' .. entry.id)
				GameTooltip:AddDoubleLine(name, entry.count, 1, 1, 1, 1, 1, 1)
			end
		end
	else
		GameTooltip:SetText(self.category.label)
		GameTooltip:AddLine('None in bags!', 1, 0.3, 0.3)
	end
	GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Frames
--------------------------------------------------------------------------------

local function SavePosition()
	local point, _, _, x, y = panel:GetPoint()
	BenisUI.db.consumables.position = { point = point, x = x, y = y }
end

local function CreateButton(category)
	local button = CreateFrame('Button', 'BenisUIConsumable' .. category.key, panel,
		'SecureActionButtonTemplate')
	button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	button:Hide() -- LayoutButtons places and shows the ones we have items for
	button.category = category

	button:SetAttribute('type', 'item')
	button:RegisterForClicks('AnyUp')

	local icon = button:CreateTexture(nil, 'ARTWORK')
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetAllPoints()
	button.icon = icon

	Skin:Border(button)

	local cooldown = CreateFrame('Cooldown', nil, button, 'CooldownFrameTemplate')
	cooldown:SetAllPoints(icon)
	cooldown:SetDrawEdge(false)
	button.cooldown = cooldown

	local count = button:CreateFontString(nil, 'OVERLAY')
	count:SetFont(FONT, 12, 'OUTLINE')
	count:SetPoint('BOTTOMRIGHT', 1, 1)
	button.count = count

	local highlight = button:CreateTexture(nil, 'HIGHLIGHT')
	highlight:SetColorTexture(1, 1, 1, 0.2)
	highlight:SetAllPoints()

	button:SetScript('OnEnter', ButtonOnEnter)
	button:SetScript('OnLeave', function() GameTooltip:Hide() end)

	-- shift-dragging a button moves the whole panel
	button:RegisterForDrag('LeftButton')
	button:SetScript('OnDragStart', function()
		if IsShiftKeyDown() and not InCombatLockdown() then
			panel:StartMoving()
		end
	end)
	button:SetScript('OnDragStop', function()
		panel:StopMovingOrSizing()
		SavePosition()
	end)

	return button
end

local function CreatePanel()
	panel = CreateFrame('Frame', 'BenisUIConsumablesPanel', UIParent, 'BackdropTemplate')
	panel:SetSize(
		PADDING * 2 + #CATEGORIES * BUTTON_SIZE + (#CATEGORIES - 1) * SPACING,
		BUTTON_SIZE + PADDING * 2)
	panel:SetFrameStrata('LOW')
	panel:Hide() -- the first scan sizes and shows it

	local saved = BenisUI.db.consumables.position
	if saved then
		panel:SetPoint(saved.point, UIParent, saved.point, saved.x, saved.y)
	else
		-- above the bottom panel by default
		panel:SetPoint('BOTTOMRIGHT', UIParent, 'BOTTOMRIGHT', -2, 36)
	end

	Skin:Panel(panel)

	-- shift-drag to move (out of combat), like the unit frames
	panel:SetMovable(true)
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	panel:RegisterForDrag('LeftButton')
	panel:SetScript('OnDragStart', function(self)
		if IsShiftKeyDown() and not InCombatLockdown() then
			self:StartMoving()
		end
	end)
	panel:SetScript('OnDragStop', function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)

	for _, category in ipairs(CATEGORIES) do
		buttons[category.key] = CreateButton(category)
	end
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

function Consumables:OnInit()
	BenisUI.db.consumables = BenisUI.db.consumables or {}

	CreatePanel()

	local rescanQueued = false
	local function QueueRescan()
		if rescanQueued then return end
		rescanQueued = true
		C_Timer.After(0.25, function()
			rescanQueued = false
			UpdateAll()
		end)
	end

	local events = CreateFrame('Frame')
	events:RegisterEvent('PLAYER_ENTERING_WORLD')
	events:RegisterEvent('BAG_UPDATE_DELAYED')
	events:RegisterEvent('GET_ITEM_INFO_RECEIVED')
	events:RegisterEvent('BAG_UPDATE_COOLDOWN')
	events:RegisterEvent('SPELL_UPDATE_COOLDOWN')
	events:RegisterEvent('PLAYER_REGEN_ENABLED')
	events:SetScript('OnEvent', function(_, event)
		if event == 'PLAYER_ENTERING_WORLD' or event == 'BAG_UPDATE_DELAYED' then
			UpdateAll()
		elseif event == 'GET_ITEM_INFO_RECEIVED' then
			if infoPending then QueueRescan() end
		elseif event == 'BAG_UPDATE_COOLDOWN' or event == 'SPELL_UPDATE_COOLDOWN' then
			for _, button in pairs(buttons) do
				UpdateCooldown(button)
			end
		elseif event == 'PLAYER_REGEN_ENABLED' then
			if applyPending then
				applyPending = false
				for _, button in pairs(buttons) do
					ApplyAttribute(button)
				end
			end
			if layoutPending then
				layoutPending = false
				LayoutButtons()
			end
		end
	end)
end
