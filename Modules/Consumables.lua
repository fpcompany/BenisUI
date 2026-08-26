local _, ns = ...
local BenisUI = ns.BenisUI

-- Small panel of three secure buttons showing the state of the bags'
-- consumables: a healing item (Healthstone preferred, then healing potions),
-- a combat/mana potion and food. Each button shows the best matching item
-- with its total count and cooldown and uses it on click; an empty category
-- shows a red placeholder icon. Modeled on ElvUI WindTools' consumables bar.
local Consumables = BenisUI:RegisterModule('Consumables')

local FONT = BenisUI.media.font
local TEXTURE = BenisUI.media.texture

local GetContainerNumSlots = C_Container.GetContainerNumSlots
local GetContainerItemInfo = C_Container.GetContainerItemInfo
local GetItemCooldown = C_Container.GetItemCooldown
local GetItemInfoInstant = C_Item.GetItemInfoInstant
local GetItemInfo = C_Item.GetItemInfo

local NUM_BAGS = NUM_TOTAL_EQUIPPED_BAG_SLOTS or 5

local BUTTON_SIZE = 30
local SPACING = 4
local PADDING = 5

local HEALTHSTONE = 5512

-- healing potions that should land in the heal slot rather than the generic
-- potion slot; anything named '<...> Healing Potion' / '<...> Health Potion'
-- is caught by the name fallback below, this list covers renames and
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
		key = 'heal',
		label = 'Healing',
		fallbackIcon = 'Interface\\Icons\\INV_Stone_04', -- healthstone
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
local found = { heal = {}, potion = {}, flask = {}, food = {} } -- [key][itemID] = { id, count }
local infoPending = false -- an item's GetItemInfo wasn't cached during the scan
local applyPending = false -- attribute changes blocked by combat

--------------------------------------------------------------------------------
-- Classification
--------------------------------------------------------------------------------

local function Classify(itemID)
	if itemID == HEALTHSTONE or HEALING_POTIONS[itemID] then
		return 'heal'
	end

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
				return 'heal'
			end
		end
		return 'potion'
	elseif subClassID == FLASK_SUBCLASS then
		return 'flask'
	elseif subClassID == Enum.ItemConsumableSubclass.Fooddrink then
		return 'food'
	end
end

local function ItemLevel(itemID)
	local level = select(4, GetItemInfo(itemID))
	if not level then infoPending = true end
	return level or 0
end

-- Healthstone beats everything in its slot (it's free); otherwise prefer the
-- higher item level, then the bigger stack
local function IsBetter(a, b)
	if not b then return true end
	if (a.id == HEALTHSTONE) ~= (b.id == HEALTHSTONE) then
		return a.id == HEALTHSTONE
	end
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

local function UpdateAll()
	ScanBags()
	for _, button in pairs(buttons) do
		UpdateButton(button)
	end
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

local function CreateButton(category, index)
	local button = CreateFrame('Button', 'BenisUIConsumable' .. category.key, panel,
		'SecureActionButtonTemplate')
	button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	button:SetPoint('LEFT', panel, 'LEFT', PADDING + (index - 1) * (BUTTON_SIZE + SPACING), 0)
	button.category = category

	button:SetAttribute('type', 'item')
	button:RegisterForClicks('AnyUp')

	local icon = button:CreateTexture(nil, 'ARTWORK')
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetAllPoints()
	button.icon = icon

	local border = CreateFrame('Frame', nil, button, 'BackdropTemplate')
	border:SetPoint('TOPLEFT', -1, 1)
	border:SetPoint('BOTTOMRIGHT', 1, -1)
	border:SetBackdrop({ edgeFile = TEXTURE, edgeSize = 1 })
	border:SetBackdropBorderColor(0, 0, 0, 1)

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

	local saved = BenisUI.db.consumables.position
	if saved then
		panel:SetPoint(saved.point, UIParent, saved.point, saved.x, saved.y)
	else
		-- above the bottom panel by default
		panel:SetPoint('BOTTOMRIGHT', UIParent, 'BOTTOMRIGHT', -2, 36)
	end

	-- same backdrop as the bottom panel
	panel:SetBackdrop({ bgFile = TEXTURE, edgeFile = TEXTURE, edgeSize = 1 })
	panel:SetBackdropColor(0.06, 0.06, 0.06, 0.94)
	panel:SetBackdropBorderColor(0, 0, 0, 1)

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

	for index, category in next, CATEGORIES do
		buttons[category.key] = CreateButton(category, index)
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
		end
	end)
end
