local _, ns = ...
local BenisUI = ns.BenisUI

local Bags = BenisUI:RegisterModule('Bags')
local Sets = BenisUI:GetModule('EquipmentSets')

local GetContainerNumSlots = C_Container.GetContainerNumSlots
local GetContainerNumFreeSlots = C_Container.GetContainerNumFreeSlots
local GetContainerItemInfo = C_Container.GetContainerItemInfo
local GetItemInfoInstant = C_Item.GetItemInfoInstant
local GetItemInfo = C_Item.GetItemInfo
local IsItemKeystoneByID = C_Item.IsItemKeystoneByID
local IsBoundToAccountUntilEquip = C_Item.IsBoundToAccountUntilEquip
local GetCurrentItemLevel = C_Item.GetCurrentItemLevel
local DoesItemExist = C_Item.DoesItemExist

local BACKPACK = Enum.BagIndex.Backpack -- 0
local REAGENT_BAG = Enum.BagIndex.ReagentBag -- 5
local NUM_BAGS = NUM_TOTAL_EQUIPPED_BAG_SLOTS or 5 -- 1-4 held bags + reagent bag

local EDGE_TEXTURE = 'Interface\\Buttons\\WHITE8X8'
local BORDER_THIN = 1
local BORDER_THICK = BORDER_THIN * 5 -- equipment set items
local FRAME_PADDING = 10
local HEADER_HEIGHT = 34
local FOOTER_HEIGHT = 26
local SECTION_GAP = 14 -- extra gap above the reagent section

local EMPTY_R, EMPTY_G, EMPTY_B = 0.22, 0.22, 0.22

-- items that get the animated sparkle overlay, with their tint
local SPECIAL_ITEMS = {
	[265714] = { r = 1, g = 0.55, b = 0.1 }, -- Trovehunter's Bounty (treasure trove map)
}
local KEYSTONE_COLOR = { r = 0.5, g = 0.65, b = 1 } -- arcane blue

local function GetSpecialColor(itemID)
	local color = SPECIAL_ITEMS[itemID]
	if color then return color end
	if itemID and IsItemKeystoneByID(itemID) then
		return KEYSTONE_COLOR
	end
end

local function GetQualityColor(quality)
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

	return 1, 1, 1
end

-- armor pieces that have no meaningful item level
local ITEMLEVEL_EXCLUDED_EQUIP_LOCS = {
	INVTYPE_BAG = true,
	INVTYPE_BODY = true, -- shirt
	INVTYPE_TABARD = true,
}

-- returns itemLevel (or nil), isGear, equipLoc
local function GetSlotItemLevel(bagID, slotID, hyperlink)
	local _, _, _, equipLoc, _, classID = GetItemInfoInstant(hyperlink)

	local isGear = (classID == Enum.ItemClass.Weapon or classID == Enum.ItemClass.Armor)
		and not ITEMLEVEL_EXCLUDED_EQUIP_LOCS[equipLoc]
	local isProfessionTool = classID == Enum.ItemClass.Profession

	if not (isGear or isProfessionTool) then return nil, false, equipLoc end

	local location = ItemLocation:CreateFromBagAndSlot(bagID, slotID)
	if DoesItemExist(location) then
		local itemLevel = GetCurrentItemLevel(location)
		if itemLevel and itemLevel > 1 then
			return itemLevel, isGear, equipLoc
		end
	end

	return nil, isGear, equipLoc
end

-- inventory slots a bag item competes with, per equip location
local EQUIP_LOC_SLOTS = {
	INVTYPE_HEAD = {1}, INVTYPE_NECK = {2}, INVTYPE_SHOULDER = {3},
	INVTYPE_CHEST = {5}, INVTYPE_ROBE = {5}, INVTYPE_WAIST = {6},
	INVTYPE_LEGS = {7}, INVTYPE_FEET = {8}, INVTYPE_WRIST = {9},
	INVTYPE_HAND = {10}, INVTYPE_FINGER = {11, 12}, INVTYPE_TRINKET = {13, 14},
	INVTYPE_CLOAK = {15},
	INVTYPE_WEAPON = {16, 17},
	INVTYPE_2HWEAPON = {16},
	INVTYPE_WEAPONMAINHAND = {16},
	INVTYPE_WEAPONOFFHAND = {17},
	INVTYPE_SHIELD = {17},
	INVTYPE_HOLDABLE = {17},
	INVTYPE_RANGED = {16},
	INVTYPE_RANGEDRIGHT = {16},
}

local function GetEquippedItemLevel(invSlot)
	local location = ItemLocation:CreateFromEquipmentSlot(invSlot)
	if DoesItemExist(location) then
		return GetCurrentItemLevel(location) or 0
	end
	return 0 -- empty slot: anything is an upgrade
end

-- higher item level than the weakest equipped item this piece competes with?
local function IsItemLevelUpgrade(itemLevel, equipLoc)
	local invSlots = itemLevel and EQUIP_LOC_SLOTS[equipLoc]
	if not invSlots then return false end

	local lowest
	for _, invSlot in ipairs(invSlots) do
		local equipped = GetEquippedItemLevel(invSlot)
		if not lowest or equipped < lowest then
			lowest = equipped
		end
	end

	return lowest ~= nil and itemLevel > lowest
end

-- extra search words per equip location, on top of the localized slot name
local EQUIP_LOC_EXTRA_WORDS = {
	INVTYPE_FINGER = 'ring',
	INVTYPE_WAIST = 'belt',
	INVTYPE_FEET = 'boots',
	INVTYPE_HAND = 'gloves',
	INVTYPE_WRIST = 'bracers',
	INVTYPE_CLOAK = 'cloak',
	INVTYPE_HEAD = 'helm',
	INVTYPE_SHOULDER = 'shoulders',
}

-- upgrade tracks that keep gear saturated; extend for non-English clients
local KEEP_TRACK_WORDS = { 'Hero', 'Myth' }
local UPGRADE_LINE_TYPE = Enum.TooltipDataLineType and Enum.TooltipDataLineType.ItemUpgradeLevel
local CRAFTED_LINE_TYPE = Enum.TooltipDataLineType and Enum.TooltipDataLineType.ProfessionCraftingQuality

-- returns upgradeTrackText ("Upgrade Level: Hero 4/6" or nil), isCrafted
local function ScanTooltip(bagID, slotID)
	if not (UPGRADE_LINE_TYPE and C_TooltipInfo and C_TooltipInfo.GetBagItem) then
		return nil, false
	end

	local trackText, isCrafted
	local data = C_TooltipInfo.GetBagItem(bagID, slotID)
	local lines = data and data.lines
	if lines then
		for i = 1, #lines do
			local line = lines[i]
			if line.type == UPGRADE_LINE_TYPE then
				trackText = line.leftText
			elseif line.type == CRAFTED_LINE_TYPE then
				isCrafted = true
			end
		end
	end

	return trackText, isCrafted
end

local function HasKeepTrackWord(trackText)
	if not trackText then return false end
	for _, word in ipairs(KEEP_TRACK_WORDS) do
		if trackText:find(word, 1, true) then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- Blizzard bag suppression
--------------------------------------------------------------------------------

-- Blizzard's container frames keep running their open/close state machine
-- (IsBagOpen, merchant/mail auto-open, ESC handling) but are never rendered:
-- with all anchor points cleared a frame is not drawn even while shown.
local function DisableBlizzardFrame(frame)
	if not frame then return end

	frame:UnregisterAllEvents()
	frame:SetScript('OnShow', nil)
	frame:SetScript('OnHide', nil)
	frame:ClearAllPoints()

	hooksecurefunc(frame, 'SetPoint', frame.ClearAllPoints)
end

local function DisableBlizzardBags()
	for i = 1, NUM_CONTAINER_FRAMES do
		DisableBlizzardFrame(_G['ContainerFrame' .. i])
	end

	local combined = _G.ContainerFrameCombinedBags
	if combined then
		DisableBlizzardFrame(combined)
		-- keeps the combined frame's item pool valid when a bag is added while
		-- it has never been shown (same fix ElvUI ships)
		combined:RegisterEvent('BAG_CONTAINER_UPDATE')
	end
end

--------------------------------------------------------------------------------
-- Slot borders
--------------------------------------------------------------------------------

local function SetSlotBorder(slot, size, r, g, b)
	local border = slot.qualityBorder

	if border.edgeSize ~= size then
		border.edgeSize = size
		border:SetBackdrop({ edgeFile = EDGE_TEXTURE, edgeSize = size })
		border:ClearAllPoints()
		border:SetPoint('TOPLEFT', slot, 'TOPLEFT', -size, size)
		border:SetPoint('BOTTOMRIGHT', slot, 'BOTTOMRIGHT', size, -size)
	end

	border.r, border.g, border.b = r, g, b
	border:SetBackdropBorderColor(r, g, b, 1)
end

--------------------------------------------------------------------------------
-- Slot creation / update
--------------------------------------------------------------------------------

function Bags:CreateSlot(bagID, slotID)
	local holder = self.bagHolders[bagID]
	local name = ('BenisUI_Bag%dSlot%d'):format(bagID, slotID)
	local slot = CreateFrame('ItemButton', name, holder, 'ContainerFrameItemButtonTemplate')

	-- The container mixin resolves its bag from the parent's frame ID
	-- (ContainerFrameItemButtonMixin:GetBagID), so tooltips, clicks, drag,
	-- splitting and selling all work without touching secure fields.
	slot:SetID(slotID)
	slot.BagID = bagID -- our bookkeeping; never write slot.bagID (taint)
	slot.SlotID = slotID

	slot:SetSize(self.db.slotSize, self.db.slotSize)

	if slot.ClearNormalTexture then
		slot:ClearNormalTexture()
	end

	slot.bg = slot:CreateTexture(nil, 'BACKGROUND', nil, -1)
	slot.bg:SetAllPoints()
	slot.bg:SetColorTexture(0.09, 0.09, 0.09, 0.9)

	slot.qualityBorder = CreateFrame('Frame', nil, slot, 'BackdropTemplate')
	slot.qualityBorder:SetFrameLevel(slot:GetFrameLevel() + 1)

	-- parented to the border frame so it renders above the cooldown swipe
	slot.itemLevel = slot.qualityBorder:CreateFontString(nil, 'OVERLAY', 'NumberFontNormalSmall')
	slot.itemLevel:SetPoint('BOTTOMRIGHT', slot, 'BOTTOMRIGHT', -2, 2)

	-- pulsing glow for openable containers (lockboxes, caches, clams...)
	slot.openableGlow = slot.qualityBorder:CreateTexture(nil, 'OVERLAY')
	slot.openableGlow:SetAtlas('bags-glow-white')
	slot.openableGlow:SetAllPoints(slot)
	slot.openableGlow:SetBlendMode('ADD')
	slot.openableGlow:SetVertexColor(1, 0.82, 0.2)
	slot.openableGlow:Hide()

	local pulse = slot.openableGlow:CreateAnimationGroup()
	pulse:SetLooping('BOUNCE')
	local alpha = pulse:CreateAnimation('Alpha')
	alpha:SetFromAlpha(0.2)
	alpha:SetToAlpha(0.9)
	alpha:SetDuration(0.6)
	slot.openableGlow.pulse = pulse

	-- rotating glint + pulse for special items (keystone, trove maps)
	local glint = slot.qualityBorder:CreateTexture(nil, 'OVERLAY', nil, 1)
	glint:SetAtlas('bags-glow-flash')
	glint:SetPoint('CENTER')
	glint:SetSize(self.db.slotSize * 1.3, self.db.slotSize * 1.3)
	glint:SetBlendMode('ADD')
	glint:Hide()
	slot.specialGlint = glint

	local spin = glint:CreateAnimationGroup()
	spin:SetLooping('REPEAT')
	local rotation = spin:CreateAnimation('Rotation')
	rotation:SetDegrees(-360)
	rotation:SetDuration(4)
	glint.spin = spin

	local glintPulse = glint:CreateAnimationGroup()
	glintPulse:SetLooping('BOUNCE')
	local glintAlpha = glintPulse:CreateAnimation('Alpha')
	glintAlpha:SetFromAlpha(0.35)
	glintAlpha:SetToAlpha(1)
	glintAlpha:SetDuration(0.8)
	glint.pulse = glintPulse

	-- marching ants ring for special items (sprite sheet, see AntsDriver)
	local ants = slot.qualityBorder:CreateTexture(nil, 'OVERLAY', nil, 2)
	ants:SetTexture('Interface\\SpellActivationOverlay\\IconAlertAnts')
	ants:SetPoint('CENTER')
	ants:SetSize(self.db.slotSize + 6, self.db.slotSize + 6)
	ants:Hide()
	slot.ants = ants

	-- template decorations we do not drive
	if slot.NewItemTexture then slot.NewItemTexture:Hide() end
	if slot.BattlepayItemTexture then slot.BattlepayItemTexture:Hide() end

	-- the template's green up-arrow; we drive it ourselves
	if slot.UpgradeIcon then
		slot.UpgradeIcon:ClearAllPoints()
		slot.UpgradeIcon:SetPoint('TOPLEFT', 1, -1)
		slot.UpgradeIcon:Hide()
	end

	SetSlotBorder(slot, BORDER_THIN, EMPTY_R, EMPTY_G, EMPTY_B)

	return slot
end

function Bags:UpdateSlot(slot)
	local bagID, slotID = slot.BagID, slot.SlotID
	local info = GetContainerItemInfo(bagID, slotID)
	local icon = info and info.iconFileID
	local quality = info and info.quality
	local hasItem = icon ~= nil

	local isJunk = quality == Enum.ItemQuality.Poor

	local itemLevel, isGear, equipLoc, trackText, isCrafted
	if hasItem and info.hyperlink then
		itemLevel, isGear, equipLoc = GetSlotItemLevel(bagID, slotID, info.hyperlink)
		trackText, isCrafted = ScanTooltip(bagID, slotID)
	end

	-- grey out junk and gear below the Hero/Myth upgrade tracks (crafted exempt)
	local lowTrack = isGear and not (isCrafted or HasKeepTrackWord(trackText))
	local desaturated = hasItem and (info.isLocked or isJunk or lowTrack)

	if slot.UpgradeIcon then
		slot.UpgradeIcon:SetShown(isGear and IsItemLevelUpgrade(itemLevel, equipLoc))
	end

	SetItemButtonTexture(slot, icon)
	SetItemButtonCount(slot, info and info.stackCount or 0)
	slot.desaturated = desaturated -- applied in ApplySearchToSlot

	local special = hasItem and GetSpecialColor(info.itemID)
	if special then
		slot.specialGlint:SetVertexColor(special.r, special.g, special.b)
		slot.specialGlint:Show()
		if not slot.specialGlint.spin:IsPlaying() then
			slot.specialGlint.spin:Play()
			slot.specialGlint.pulse:Play()
		end
		slot.ants:Show()
		self.activeAnts[slot.ants] = true
	else
		slot.specialGlint.spin:Stop()
		slot.specialGlint.pulse:Stop()
		slot.specialGlint:Hide()
		slot.ants:Hide()
		self.activeAnts[slot.ants] = nil
	end

	local openable = hasItem and info.hasLoot and not info.isLocked and not special
	if openable then
		slot.openableGlow:Show()
		if not slot.openableGlow.pulse:IsPlaying() then
			slot.openableGlow.pulse:Play()
		end
	else
		slot.openableGlow.pulse:Stop()
		slot.openableGlow:Hide()
	end

	if slot.UpdateCooldown and slot.Cooldown then
		slot:UpdateCooldown(hasItem)
	end

	if hasItem and quality then
		local r, g, b = GetQualityColor(quality)
		local highlighted, setR, setG, setB = Sets:GetHighlight(bagID, slotID)
		if highlighted then
			SetSlotBorder(slot, BORDER_THICK, setR or r, setG or g, setB or b)
		else
			SetSlotBorder(slot, BORDER_THIN, r, g, b)
		end

		if itemLevel then
			slot.itemLevel:SetText(itemLevel)
			slot.ilvlR, slot.ilvlG, slot.ilvlB = r, g, b
		else
			slot.itemLevel:SetText('')
			slot.ilvlR = nil
		end
	else
		SetSlotBorder(slot, BORDER_THIN, EMPTY_R, EMPTY_G, EMPTY_B)
		slot.itemLevel:SetText('')
		slot.ilvlR = nil
	end

	-- search corpus: everything a query term can match against
	if hasItem then
		local parts = {}
		parts[#parts + 1] = (info.itemName or ''):lower()
		if trackText then parts[#parts + 1] = trackText:lower() end
		if isCrafted then parts[#parts + 1] = 'crafted' end
		if isJunk then parts[#parts + 1] = 'junk' end
		if info.hasLoot then parts[#parts + 1] = 'openable' end

		-- unbound bind-on-equip: "warband" if it warbinds until equipped, else "boe"
		if not info.isBound and info.hyperlink then
			local bindType = select(14, GetItemInfo(info.hyperlink))
			if bindType == Enum.ItemBind.OnEquip then
				local location = ItemLocation:CreateFromBagAndSlot(bagID, slotID)
				if IsBoundToAccountUntilEquip and DoesItemExist(location)
					and IsBoundToAccountUntilEquip(location) then
					parts[#parts + 1] = 'warband'
				else
					parts[#parts + 1] = 'boe'
				end
			end
		end
		if special and IsItemKeystoneByID(info.itemID) then parts[#parts + 1] = 'keystone' end

		local qualityName = quality and _G['ITEM_QUALITY' .. quality .. '_DESC']
		if qualityName then parts[#parts + 1] = qualityName:lower() end

		if equipLoc and equipLoc ~= '' then
			local slotName = _G[equipLoc] -- e.g. INVTYPE_FINGER -> "Finger"
			if type(slotName) == 'string' then parts[#parts + 1] = slotName:lower() end
			local extra = EQUIP_LOC_EXTRA_WORDS[equipLoc]
			if extra then parts[#parts + 1] = extra end
		end

		if isGear and info.hyperlink then
			local stats = C_Item.GetItemStats(info.hyperlink)
			if stats then
				for statToken in pairs(stats) do
					local label = _G[statToken] -- e.g. "Critical Strike"
					if type(label) == 'string' then
						parts[#parts + 1] = label:lower()
					end
				end
			end
		end

		local setNames = Sets:GetSetNamesText(bagID, slotID)
		if setNames then parts[#parts + 1] = setNames end

		slot.searchText = table.concat(parts, ' ')
		slot.searchItemLevel = itemLevel
	else
		slot.searchText = nil
		slot.searchItemLevel = nil
	end

	self:ApplySearchToSlot(slot)
end

--------------------------------------------------------------------------------
-- Search
--------------------------------------------------------------------------------

function Bags:SlotMatchesSearch(slot)
	if not slot.searchText then return false end -- empty slots never match

	for term in self.searchQuery:gmatch('%S+') do
		local minLevel = tonumber(term)
		if minLevel then
			if (slot.searchItemLevel or 0) < minLevel then
				return false
			end
		elseif not slot.searchText:find(term, 1, true) then
			return false
		end
	end

	return true
end

function Bags:ApplySearchToSlot(slot)
	local searching = self.searchQuery and self.searchQuery ~= ''
	local matches = not searching or self:SlotMatchesSearch(slot)

	slot:SetAlpha((searching and not matches) and 0.15 or 1)

	-- while searching, found items lose their desaturation
	local desaturated = slot.desaturated and not (searching and matches)
	SetItemButtonDesaturated(slot, desaturated)

	-- while searching, no slot shows a border
	local border = slot.qualityBorder
	if border.r then
		border:SetBackdropBorderColor(border.r, border.g, border.b, searching and 0 or 1)
	end

	if slot.ilvlR then
		if desaturated then
			-- match the greyed icon: quality color reduced to its luminance
			local gray = 0.299 * slot.ilvlR + 0.587 * slot.ilvlG + 0.114 * slot.ilvlB
			slot.itemLevel:SetTextColor(gray, gray, gray)
		else
			slot.itemLevel:SetTextColor(slot.ilvlR, slot.ilvlG, slot.ilvlB)
		end
	end
end

function Bags:ApplySearch()
	for bagID = BACKPACK, NUM_BAGS do
		local bagSlots = self.slots[bagID]
		if bagSlots then
			for slotID = 1, GetContainerNumSlots(bagID) do
				local slot = bagSlots[slotID]
				if slot and slot:IsShown() then
					self:ApplySearchToSlot(slot)
				end
			end
		end
	end
end

function Bags:UpdateBag(bagID)
	local bagSlots = self.slots[bagID]
	if not bagSlots then return end

	for slotID = 1, GetContainerNumSlots(bagID) do
		local slot = bagSlots[slotID]
		if slot and slot:IsShown() then
			self:UpdateSlot(slot)
		end
	end
end

function Bags:UpdateAll()
	Sets:MarkDirty()
	for bagID = BACKPACK, NUM_BAGS do
		self:UpdateBag(bagID)
	end
	self:UpdateFooter()
end

function Bags:UpdateCooldowns()
	for bagID = BACKPACK, NUM_BAGS do
		local bagSlots = self.slots[bagID]
		if bagSlots then
			for slotID = 1, GetContainerNumSlots(bagID) do
				local slot = bagSlots[slotID]
				if slot and slot:IsShown() and slot.UpdateCooldown and slot.Cooldown then
					slot:UpdateCooldown(GetContainerItemInfo(bagID, slotID) ~= nil)
				end
			end
		end
	end
end

function Bags:UpdateFooter()
	local free, total = 0, 0
	for bagID = BACKPACK, NUM_BAGS do
		if bagID ~= REAGENT_BAG then
			local numSlots = GetContainerNumSlots(bagID)
			if numSlots > 0 then
				total = total + numSlots
				free = free + (GetContainerNumFreeSlots(bagID) or 0)
			end
		end
	end

	self.freeText:SetFormattedText('%d/%d free', free, total)
	self.moneyText:SetText(GetMoneyString(GetMoney(), true))
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

function Bags:Layout()
	local db = self.db
	local step = db.slotSize + db.spacing
	local columns = db.columns
	local originY = HEADER_HEIGHT + FRAME_PADDING

	local col, row = 0, 0
	local function place(slot)
		slot:ClearAllPoints()
		slot:SetPoint('TOPLEFT', self.frame, 'TOPLEFT',
			FRAME_PADDING + col * step,
			-(originY + row * step))
		slot:SetSize(db.slotSize, db.slotSize)
		slot:Show()

		col = col + 1
		if col >= columns then
			col, row = 0, row + 1
		end
	end

	for bagID = BACKPACK, NUM_BAGS do
		if bagID ~= REAGENT_BAG then
			local numSlots = GetContainerNumSlots(bagID)
			local bagSlots = self.slots[bagID]

			for slotID = 1, numSlots do
				bagSlots[slotID] = bagSlots[slotID] or self:CreateSlot(bagID, slotID)
				place(bagSlots[slotID])
			end
			for slotID = numSlots + 1, #bagSlots do
				bagSlots[slotID]:Hide()
			end
		end
	end
	if col > 0 then
		col, row = 0, row + 1
	end

	local reagentSlots = GetContainerNumSlots(REAGENT_BAG)
	local reagentOffset = 0
	if reagentSlots > 0 then
		reagentOffset = SECTION_GAP + self.reagentLabel:GetStringHeight() + 4
		self.reagentLabel:ClearAllPoints()
		self.reagentLabel:SetPoint('TOPLEFT', self.frame, 'TOPLEFT',
			FRAME_PADDING, -(originY + row * step + SECTION_GAP))
		self.reagentLabel:Show()

		local bagSlots = self.slots[REAGENT_BAG]
		for slotID = 1, reagentSlots do
			bagSlots[slotID] = bagSlots[slotID] or self:CreateSlot(REAGENT_BAG, slotID)
			local slot = bagSlots[slotID]
			slot:ClearAllPoints()
			slot:SetPoint('TOPLEFT', self.frame, 'TOPLEFT',
				FRAME_PADDING + col * step,
				-(originY + row * step + reagentOffset))
			slot:SetSize(db.slotSize, db.slotSize)
			slot:Show()

			col = col + 1
			if col >= columns then
				col, row = 0, row + 1
			end
		end
		if col > 0 then
			col, row = 0, row + 1
		end
	else
		self.reagentLabel:Hide()
		local bagSlots = self.slots[REAGENT_BAG]
		for slotID = 1, #bagSlots do
			bagSlots[slotID]:Hide()
		end
	end

	self.frame:SetSize(
		FRAME_PADDING * 2 + columns * step - db.spacing,
		originY + row * step - db.spacing + reagentOffset + FRAME_PADDING + FOOTER_HEIGHT)
end

--------------------------------------------------------------------------------
-- Main frame
--------------------------------------------------------------------------------

function Bags:CreateBagFrame()
	local db = self.db
	local frame = CreateFrame('Frame', 'BenisUI_BagFrame', UIParent, 'BackdropTemplate')
	self.frame = frame

	frame:Hide()
	frame:SetFrameStrata('HIGH')
	frame:SetToplevel(true)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)

	frame:SetBackdrop({
		bgFile = EDGE_TEXTURE,
		edgeFile = EDGE_TEXTURE,
		edgeSize = 1,
	})
	frame:SetBackdropColor(0.06, 0.06, 0.06, 0.94)
	frame:SetBackdropBorderColor(0, 0, 0, 1)

	local pos = db.position
	if pos then
		frame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
	else
		frame:SetPoint('BOTTOMRIGHT', UIParent, 'BOTTOMRIGHT', -50, 120)
	end

	-- title bar (drag handle)
	local header = CreateFrame('Frame', nil, frame)
	header:SetPoint('TOPLEFT')
	header:SetPoint('TOPRIGHT')
	header:SetHeight(HEADER_HEIGHT)
	header:EnableMouse(true)
	header:RegisterForDrag('LeftButton')
	header:SetScript('OnDragStart', function() frame:StartMoving() end)
	header:SetScript('OnDragStop', function()
		frame:StopMovingOrSizing()
		local point, _, _, x, y = frame:GetPoint()
		db.position = { point = point, x = x, y = y }
	end)

	local title = header:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
	title:SetPoint('LEFT', FRAME_PADDING, 0)
	title:SetText('|cff1784d1Benis|rUI Inventory')

	local close = CreateFrame('Button', nil, header, 'UIPanelCloseButton')
	close:SetPoint('RIGHT', -2, 0)
	close:SetScript('OnClick', function() CloseAllBags() end)

	local sort = CreateFrame('Button', nil, header, 'UIPanelButtonTemplate')
	sort:SetSize(50, 20)
	sort:SetPoint('RIGHT', close, 'LEFT', -4, 0)
	sort:SetText('Sort')
	sort:SetScript('OnClick', function() C_Container.SortBags() end)

	local search = CreateFrame('EditBox', 'BenisUI_BagSearchBox', header, 'SearchBoxTemplate')
	search:SetSize(150, 20)
	search:SetPoint('RIGHT', sort, 'LEFT', -10, 0)
	search:SetAutoFocus(false)
	search:HookScript('OnTextChanged', function(box)
		self.searchQuery = strtrim(box:GetText() or ''):lower()
		self:ApplySearch()
	end)
	self.searchBox = search

	-- footer
	self.freeText = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
	self.freeText:SetPoint('BOTTOMLEFT', FRAME_PADDING, FRAME_PADDING)

	self.moneyText = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
	self.moneyText:SetPoint('BOTTOMRIGHT', -FRAME_PADDING, FRAME_PADDING)

	self.reagentLabel = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
	self.reagentLabel:SetText('Reagents')

	-- drives the marching ants sprite sheet; parented to the bag frame so it
	-- only runs while the bags are open
	self.activeAnts = {}
	local antsDriver = CreateFrame('Frame', nil, frame)
	local AnimateTexCoords = TextureUtil and TextureUtil.AnimateTexCoords
	if AnimateTexCoords then
		antsDriver:SetScript('OnUpdate', function(_, elapsed)
			for texture in pairs(self.activeAnts) do
				AnimateTexCoords(texture, 256, 256, 48, 48, 22, elapsed, 0.01)
			end
		end)
	end

	-- one holder per bag: the container item button mixin reads the bag ID
	-- from its parent's frame ID
	self.bagHolders = {}
	self.slots = {}
	for bagID = BACKPACK, NUM_BAGS do
		local holder = CreateFrame('Frame', nil, frame)
		holder:SetID(bagID)
		holder:SetAllPoints()
		self.bagHolders[bagID] = holder
		self.slots[bagID] = {}
	end

	frame:SetScript('OnShow', function()
		PlaySound(SOUNDKIT.IG_BACKPACK_OPEN)
		self:Layout()
		self:UpdateAll()
	end)

	frame:SetScript('OnHide', function()
		PlaySound(SOUNDKIT.IG_BACKPACK_CLOSE)
		-- keep Blizzard's open/close state in sync when closed via X or ESC
		if IsBagOpen(BACKPACK) then
			CloseAllBags()
		end
	end)

	tinsert(UISpecialFrames, 'BenisUI_BagFrame')
end

--------------------------------------------------------------------------------
-- Open/close syncing
--------------------------------------------------------------------------------

function Bags:Sync()
	if IsBagOpen(BACKPACK) then
		self.frame:Show()
	else
		self.frame:Hide()
	end
end

function Bags:HookOpenClose()
	local function sync() self:Sync() end

	hooksecurefunc('ToggleBackpack', sync)
	hooksecurefunc('ToggleAllBags', sync)
	hooksecurefunc('OpenAllBags', sync)
	hooksecurefunc('CloseAllBags', sync)
	hooksecurefunc('OpenBackpack', sync)
	hooksecurefunc('CloseBackpack', sync)
	hooksecurefunc('OpenBag', sync)
	hooksecurefunc('CloseBag', sync)
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local BAG_EVENTS = {
	'BAG_CONTAINER_UPDATE',
	'BAG_UPDATE',
	'BAG_UPDATE_DELAYED',
	'BAG_UPDATE_COOLDOWN',
	'ITEM_LOCK_CHANGED',
	'PLAYER_EQUIPMENT_CHANGED',
	'PLAYER_MONEY',
}

function Bags:OnEvent(event, arg1, arg2)
	if not self.frame:IsShown() then return end -- OnShow does a full refresh

	if event == 'BAG_CONTAINER_UPDATE' then
		self:Layout()
		self:UpdateAll()
	elseif event == 'BAG_UPDATE' then
		if self.slots[arg1] then
			Sets:MarkDirty() -- an item may have moved; set locations follow it
			self:UpdateBag(arg1)
		end
	elseif event == 'BAG_UPDATE_DELAYED' then
		self:UpdateAll()
	elseif event == 'PLAYER_EQUIPMENT_CHANGED' then
		self:UpdateAll() -- equipped ilvls changed; recompute upgrade arrows
	elseif event == 'BAG_UPDATE_COOLDOWN' then
		self:UpdateCooldowns()
	elseif event == 'ITEM_LOCK_CHANGED' then
		local slot = arg2 and self.slots[arg1] and self.slots[arg1][arg2]
		if slot then
			self:UpdateSlot(slot)
		end
	elseif event == 'PLAYER_MONEY' then
		self:UpdateFooter()
	end
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

function Bags:OnInit()
	self.db = BenisUI.db.bags

	self:CreateBagFrame()

	DisableBlizzardBags()
	self:HookOpenClose()

	local listener = CreateFrame('Frame')
	for _, event in ipairs(BAG_EVENTS) do
		listener:RegisterEvent(event)
	end
	listener:SetScript('OnEvent', function(_, event, ...)
		self:OnEvent(event, ...)
	end)
end
