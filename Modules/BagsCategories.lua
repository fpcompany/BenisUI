local _, ns = ...
local BenisUI = ns.BenisUI

-- Category view for the inventory: instead of bag order, items are grouped
-- into labeled blocks (key items, class items, quest, equipment, ...) that
-- flow side by side and wrap like words in a line. Within a block items keep
-- their bag order, so the Sort button still decides the order, except that
-- all stacks of one item are shown together.
--
-- Toggled with the button next to Sort; remembered per character.
local Bags = BenisUI:GetModule('Bags')
if not Bags then return end

local GetContainerNumSlots = C_Container.GetContainerNumSlots
local GetContainerItemInfo = C_Container.GetContainerItemInfo
local GetContainerItemQuestInfo = C_Container.GetContainerItemQuestInfo
local GetItemInfoInstant = C_Item.GetItemInfoInstant
local GetItemInfo = C_Item.GetItemInfo or GetItemInfo
local IsItemKeystoneByID = C_Item.IsItemKeystoneByID

local ItemClass = Enum.ItemClass
local CLASS_CONSUMABLE = ItemClass.Consumable or 0
local CLASS_WEAPON = ItemClass.Weapon or 2
local CLASS_GEM = ItemClass.Gem or 3
local CLASS_ARMOR = ItemClass.Armor or 4
local CLASS_PROJECTILE = ItemClass.Projectile or 6
local CLASS_TRADEGOODS = ItemClass.Tradegoods or 7
local CLASS_ENHANCEMENT = ItemClass.ItemEnhancement or 8
local CLASS_QUIVER = ItemClass.Quiver or 11
local CLASS_QUEST = ItemClass.Questitem or 12
local CLASS_KEY = ItemClass.Key or 13
local CLASS_PROFESSION = ItemClass.Profession or 19
local FISHING_POLE = (Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Fishingpole) or 20

local MAX_FREE_SLOTS = 1 -- empty slot shown for splitting stacks
local BLOCK_GAP = 14 -- horizontal gap between blocks on one line
local LINE_GAP = 8 -- vertical gap between lines of blocks
local LABEL_GAP = 3 -- between a block's label and its slots

-- display order; `label` is the block heading
local CATEGORIES = {
	{ key = 'key', label = 'Key Items' },
	{ key = 'class', label = 'Class' },
	{ key = 'free', label = 'Free' },
	{ key = 'quest', label = 'Quest' },
	{ key = 'equipment', label = 'Equipment' },
	{ key = 'consumable', label = 'Consumables' },
	{ key = 'reagent', label = 'Reagents' },
	{ key = 'other', label = 'Other' },
	{ key = 'junk', label = 'Junk' },
}

-- never shown in the category view
local HIDDEN_ITEMS = {
	[5175] = true, -- Earth Totem
	[5176] = true, -- Fire Totem
	[5177] = true, -- Water Totem
	[5178] = true, -- Air Totem
}

-- always-carried utility items; fishing poles, keys and keystones are
-- detected on top of this list
local KEY_ITEMS = {
	[6948] = true, -- Hearthstone
	[2901] = true, -- Mining Pick
	[7005] = true, -- Skinning Knife
	[5956] = true, -- Blacksmith Hammer
	[6219] = true, -- Arclight Spanner
	[4471] = true, -- Flint and Tinder
	[6218] = true, -- Runed Copper Rod
	[6339] = true, -- Runed Silver Rod
	[11130] = true, -- Runed Golden Rod
	[11145] = true, -- Runed Truesilver Rod
	[16207] = true, -- Runed Arcanite Rod
}
local KEY_ITEM_NAMES = { -- for items whose ID differs per client
	['Hearthstone'] = true,
	['Cozy Sleeping Bag'] = true,
}

-- class reagents and tools. The Reagent item class is not used for this: the
-- client puts unrelated items (books, quest leftovers) in it, while real
-- class reagents like Fish Oil sit in Miscellaneous.
local CLASS_ITEMS = {
	[6265] = true, -- Soul Shard
	[5060] = true, -- Thieves' Tools
	-- shaman
	[17030] = true, -- Ankh
	[17057] = true, -- Shiny Fish Scales
	[17058] = true, -- Fish Oil
	-- mage
	[17020] = true, -- Arcane Powder
	[17031] = true, -- Rune of Teleportation
	[17032] = true, -- Rune of Portals
	-- priest / mage
	[17056] = true, -- Light Feather
	[17028] = true, -- Holy Candle
	[17029] = true, -- Sacred Candle
	-- paladin
	[17033] = true, -- Symbol of Divinity
	[21177] = true, -- Symbol of Kings
	-- druid
	[17021] = true, -- Wild Berries
	[17026] = true, -- Wild Thornroot
	[22147] = true, -- Flintweed Seed
	[22148] = true, -- Wild Quillvine
	[17034] = true, -- Maple Seed
	[17035] = true, -- Stranglethorn Seed
	[17036] = true, -- Ashwood Seed
	[17037] = true, -- Hornbeam Seed
	[17038] = true, -- Ironwood Seed
	-- rogue
	[5140] = true, -- Flash Powder
	[5530] = true, -- Blinding Powder
	-- warlock
	[5565] = true, -- Infernal Stone
	[16583] = true, -- Demonic Figurine
}
local CLASS_ITEM_NAMES = { -- same items by name, for clients with other IDs
	['Mana Agate'] = true, ['Mana Jade'] = true,
	['Mana Citrine'] = true, ['Mana Ruby'] = true,
	['Soul Shard'] = true, ["Thieves' Tools"] = true,
	['Ankh'] = true, ['Shiny Fish Scales'] = true, ['Fish Oil'] = true,
	['Arcane Powder'] = true, ['Rune of Teleportation'] = true, ['Rune of Portals'] = true,
	['Light Feather'] = true, ['Holy Candle'] = true, ['Sacred Candle'] = true,
	['Symbol of Divinity'] = true, ['Symbol of Kings'] = true,
	['Wild Berries'] = true, ['Wild Thornroot'] = true, ['Flintweed Seed'] = true,
	['Wild Quillvine'] = true, ['Maple Seed'] = true, ['Stranglethorn Seed'] = true,
	['Ashwood Seed'] = true, ['Hornbeam Seed'] = true, ['Ironwood Seed'] = true,
	['Flash Powder'] = true, ['Blinding Powder'] = true,
	['Infernal Stone'] = true, ['Demonic Figurine'] = true,
}
local CLASS_NAME_PATTERNS = {
	' Poison$', ' Poison [IVX]+$', -- rogue poisons, not "Elixir of Poison Resistance"
	'Healthstone', 'Soulstone', 'Spellstone', 'Firestone', -- warlock
}

local function IsClassItemName(name)
	if not name then return false end
	if CLASS_ITEM_NAMES[name] then return true end
	for _, pattern in ipairs(CLASS_NAME_PATTERNS) do
		if name:find(pattern) then return true end
	end
	return false
end

-- regular items an active quest asks for (Wolf Meat, Linen Cloth): they
-- carry no quest flag, so they are matched by name against the "item"
-- objectives in the quest log
local questItemNames = {} -- [name] = true
local questItemIDs = {}   -- [itemID] = true, when the client reports it

-- objective text is "8/8 Wolf Meat" on retail, "Wolf Meat: 8/8" on older
-- clients; strip the count either way to get the item name
local function ObjectiveItemName(text)
	local name = text:gsub('%d+%s*/%s*%d+', ''):gsub('^%s*:?%s*', ''):gsub('%s*:?%s*$', '')
	return name ~= '' and name or nil
end

local function ScanQuestItems()
	local names, ids = {}, {}
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		local questID = info and not info.isHeader and info.questID
		if questID and questID ~= 0 then
			for _, objective in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
				if objective.type == 'item' then
					local name = objective.text and ObjectiveItemName(objective.text)
					if name then names[name] = true end
					if objective.objectID then ids[objective.objectID] = true end
				end
			end
		end
	end

	local changed = false
	for name in pairs(names) do
		if not questItemNames[name] then changed = true end
	end
	for name in pairs(questItemNames) do
		if not names[name] then changed = true end
	end
	questItemNames, questItemIDs = names, ids
	return changed
end

-- old monster drops (Soft Bushy Tail) carry the Quest class but are plain
-- vendor items, so the class only counts for items that cannot be sold
local function IsQuestItem(bagID, slotID, classID, info)
	if classID == CLASS_QUEST and info.hasNoValue ~= false then return true end
	if questItemNames[info.itemName] or questItemIDs[info.itemID] then return true end
	local quest = GetContainerItemQuestInfo and GetContainerItemQuestInfo(bagID, slotID)
	return quest ~= nil and (quest.isQuestItem or quest.questID ~= nil)
end

-- returns the category key, or nil for an item that stays hidden
local function Categorize(bagID, slotID)
	local info = GetContainerItemInfo(bagID, slotID)
	if not (info and info.iconFileID) then return 'free' end

	local itemID, name = info.itemID, info.itemName
	if HIDDEN_ITEMS[itemID] then return nil end

	-- the reagent bag only ever holds crafting reagents
	if bagID == Bags.REAGENT_BAG then return 'reagent' end

	local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(itemID)

	if KEY_ITEMS[itemID] or KEY_ITEM_NAMES[name] or classID == CLASS_KEY
		or (classID == CLASS_WEAPON and subclassID == FISHING_POLE)
		or (IsItemKeystoneByID and IsItemKeystoneByID(itemID)) then
		return 'key'
	end

	if IsQuestItem(bagID, slotID, classID, info) then return 'quest' end

	if CLASS_ITEMS[itemID] or classID == CLASS_PROJECTILE
		or classID == CLASS_QUIVER or IsClassItemName(name) then
		return 'class'
	end

	if info.quality == Enum.ItemQuality.Poor then return 'junk' end

	if classID == CLASS_WEAPON or classID == CLASS_ARMOR or classID == CLASS_PROFESSION then
		return 'equipment'
	end

	-- an item that is both (raw fish you can eat or cook with) goes with the
	-- reagents: the reagent bag accepts it on this same flag, so its stacks
	-- there and in the normal bags end up in one block
	local isCraftingReagent = select(17, GetItemInfo(itemID))
	if isCraftingReagent then return 'reagent' end

	if classID == CLASS_CONSUMABLE then return 'consumable' end

	if classID == CLASS_TRADEGOODS or classID == CLASS_GEM or classID == CLASS_ENHANCEMENT then
		return 'reagent'
	end

	return 'other'
end

--------------------------------------------------------------------------------
-- Mode
--------------------------------------------------------------------------------

function Bags:IsCategoryMode(view)
	return view.config.categories and BenisUI.chardb.bags.categoryMode or false
end

function Bags:SetCategoryMode(view, enabled)
	BenisUI.chardb.bags.categoryMode = enabled
	self:UpdateCategoryToggle(view)
	if view.frame:IsShown() then
		self:Layout(view)
		self:UpdateAll(view)
	end
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

local function GetLabel(view, category)
	view.categoryLabels = view.categoryLabels or {}
	local label = view.categoryLabels[category.key]
	if not label then
		label = view.frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
		label:SetText(category.label)
		view.categoryLabels[category.key] = label
	end
	return label
end

-- keeps the bag order, but pulls every stack of an item up next to its first
-- stack: the sort leaves partial stacks of one item scattered across bags
local function ClusterByItem(group)
	local order, byItem = {}, {}
	for _, slot in ipairs(group) do
		local info = GetContainerItemInfo(slot.BagID, slot.SlotID)
		local id = info and info.itemID or slot
		local list = byItem[id]
		if not list then
			list = {}
			byItem[id] = list
			order[#order + 1] = list
		end
		list[#list + 1] = slot
	end
	local result = {}
	for _, list in ipairs(order) do
		for _, slot in ipairs(list) do
			result[#result + 1] = slot
		end
	end
	return result
end

-- true when a slot of the bag now holds something that belongs to another
-- block than the one it was placed in (an item looted into a slot that was
-- laid out for a used-up potion)
function Bags:CategoriesChanged(view, bagID)
	local bagSlots = view.slots[bagID]
	if not bagSlots then return false end
	for slotID = 1, GetContainerNumSlots(bagID) do
		local slot = bagSlots[slotID]
		if not slot or slot.categoryKey == nil then return true end
		if (Categorize(bagID, slotID) or false) ~= slot.categoryKey then return true end
	end
	return false
end

-- re-lays the view out once, on the next frame
function Bags:QueueCategoryLayout(view)
	if view.categoryLayoutPending then return end
	view.categoryLayoutPending = true
	C_Timer.After(0, function()
		view.categoryLayoutPending = false
		if view.frame:IsShown() and self:IsCategoryMode(view) then
			self:Layout(view)
			self:UpdateAll(view)
		end
	end)
end

function Bags:LayoutCategories(view)
	local db = self.db
	local slotSize = view.config.slotSize
	local step = slotSize + db.spacing
	local columns = view.config.columns
	local totalWidth = columns * step - db.spacing
	local originY = self.HEADER_HEIGHT + self.BAR_HEIGHT + self.FRAME_PADDING

	-- sort every slot into its category, in bag order
	local groups = {}
	for _, category in ipairs(CATEGORIES) do
		groups[category.key] = {}
	end

	for _, section in ipairs(view.config.sections) do
		for _, bagID in ipairs(section.bags) do
			local numSlots = GetContainerNumSlots(bagID)
			local bagSlots = view.slots[bagID]

			for slotID = 1, numSlots do
				bagSlots[slotID] = bagSlots[slotID] or self:CreateSlot(view, bagID, slotID)
				local slot = bagSlots[slotID]
				slot:Hide() -- shown again below if it gets a spot
				slot:SetSize(slotSize, slotSize)

				local key = Categorize(bagID, slotID)
				slot.categoryKey = key or false
				local group = key and groups[key]
				-- free slots only from the normal bags: the reagent bag
				-- can't take whatever is being split
				if key == 'free' and (bagID == self.REAGENT_BAG or #group >= MAX_FREE_SLOTS) then
					group = nil
				end
				if group then
					group[#group + 1] = slot
				end
			end
			for slotID = numSlots + 1, #bagSlots do
				bagSlots[slotID]:Hide()
			end
		end
	end

	-- flow the blocks: left to right, wrapping when a block doesn't fit
	local x, y, lineHeight = 0, 0, 0
	for _, category in ipairs(CATEGORIES) do
		local group = ClusterByItem(groups[category.key])
		local label = view.categoryLabels and view.categoryLabels[category.key]

		if #group == 0 then
			if label then label:Hide() end
		else
			label = GetLabel(view, category)
			local labelHeight = label:GetStringHeight()

			local cols = math.min(#group, columns)
			local rows = math.ceil(#group / columns)
			local blockWidth = math.max(cols * step - db.spacing, label:GetStringWidth())
			local blockHeight = labelHeight + LABEL_GAP + rows * step - db.spacing

			if x > 0 and x + blockWidth > totalWidth then
				x, y, lineHeight = 0, y + lineHeight + LINE_GAP, 0
			end

			local left = self.FRAME_PADDING + x
			local top = originY + y
			label:ClearAllPoints()
			label:SetPoint('TOPLEFT', view.frame, 'TOPLEFT', left, -top)
			label:Show()

			for index, slot in ipairs(group) do
				local col = (index - 1) % columns
				local row = math.floor((index - 1) / columns)
				slot:ClearAllPoints()
				slot:SetPoint('TOPLEFT', view.frame, 'TOPLEFT',
					left + col * step, -(top + labelHeight + LABEL_GAP + row * step))
				slot:Show()
			end

			lineHeight = math.max(lineHeight, blockHeight)
			x = x + blockWidth + BLOCK_GAP
		end
	end

	view.frame:SetSize(
		self.FRAME_PADDING * 2 + totalWidth,
		originY + y + lineHeight + self.FRAME_PADDING + self.FOOTER_HEIGHT)
end

--------------------------------------------------------------------------------
-- Header toggle
--------------------------------------------------------------------------------

local TOGGLE_ICON = 'Interface\\Icons\\INV_Misc_Bag_08'

function Bags:UpdateCategoryToggle(view)
	local button = view.categoryToggle
	if not button then return end
	local active = self:IsCategoryMode(view)
	button.icon:SetDesaturated(not active)
	button.icon:SetAlpha(active and 1 or 0.6)
end

local function ShowToggleTooltip(button)
	GameTooltip:SetOwner(button, 'ANCHOR_TOP')
	if Bags:IsCategoryMode(button.view) then
		GameTooltip:SetText('Category view')
		GameTooltip:AddLine('Click to show items in bag order', 0, 1, 0)
	else
		GameTooltip:SetText('Bag view')
		GameTooltip:AddLine('Click to group items by category', 0, 1, 0)
	end
	GameTooltip:Show()
end

-- called from CreateView for views with config.categories
function Bags:CreateCategoryToggle(view)
	local button = CreateFrame('Button', nil, view.header)
	button:SetSize(20, 20)
	button:SetPoint('RIGHT', view.sortButton, 'LEFT', -6, 0)
	button.view = view

	button.icon = button:CreateTexture(nil, 'ARTWORK')
	button.icon:SetAllPoints()
	button.icon:SetTexture(TOGGLE_ICON)
	self.StyleBarButton(button, button.icon)

	button:SetScript('OnClick', function(b)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
		self:SetCategoryMode(view, not self:IsCategoryMode(view))
		ShowToggleTooltip(b)
	end)
	button:SetScript('OnEnter', ShowToggleTooltip)
	button:SetScript('OnLeave', GameTooltip_Hide)

	-- the search box moves left to make room
	view.searchBox:ClearAllPoints()
	view.searchBox:SetPoint('RIGHT', button, 'LEFT', -10, 0)

	view.categoryToggle = button
	self:UpdateCategoryToggle(view)
end

-- the quest log changes in bursts; rescan once and only re-layout when the
-- set of wanted items actually changed
do
	local pending = false
	local function QueueScan()
		if pending then return end
		pending = true
		C_Timer.After(0.2, function()
			pending = false
			if ScanQuestItems() then
				for _, view in ipairs(Bags.views or {}) do
					if view.frame:IsShown() and Bags:IsCategoryMode(view) then
						Bags:Layout(view)
					end
				end
			end
		end)
	end

	local events = CreateFrame('Frame')
	for _, event in ipairs({ 'PLAYER_ENTERING_WORLD', 'QUEST_LOG_UPDATE' }) do
		events:RegisterEvent(event)
	end
	events:SetScript('OnEvent', QueueScan)
end
