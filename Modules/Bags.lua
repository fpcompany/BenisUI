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
local CloseBank = (C_Bank and C_Bank.CloseBankFrame) or CloseBankFrame

local BagIndex = Enum.BagIndex
local BACKPACK = BagIndex.Backpack -- 0
local REAGENT_BAG = BagIndex.ReagentBag -- 5
local NUM_BAGS = NUM_TOTAL_EQUIPPED_BAG_SLOTS or 5 -- 1-4 held bags + reagent bag

local HELD_BAGS = {} -- backpack + held bags, no reagent bag
for bagID = BACKPACK, NUM_BAGS do
	if bagID ~= REAGENT_BAG then
		HELD_BAGS[#HELD_BAGS + 1] = bagID
	end
end

local CHARACTER_BANK_BAGS = {}
for bagID = BagIndex.CharacterBankTab_1 or 6, BagIndex.CharacterBankTab_6 or 11 do
	CHARACTER_BANK_BAGS[#CHARACTER_BANK_BAGS + 1] = bagID
end

local WARBAND_BANK_BAGS = {}
for bagID = BagIndex.AccountBankTab_1 or 12, BagIndex.AccountBankTab_5 or 16 do
	WARBAND_BANK_BAGS[#WARBAND_BANK_BAGS + 1] = bagID
end

local EDGE_TEXTURE = 'Interface\\Buttons\\WHITE8X8'
local BORDER_THIN = 1
local BORDER_THICK = BORDER_THIN * 5 -- equipment set items
local FRAME_PADDING = 10
local HEADER_HEIGHT = 34
local FOOTER_HEIGHT = 26
local SECTION_GAP = 14 -- extra gap above a labeled section

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
-- Blizzard frame suppression
--------------------------------------------------------------------------------

-- Blizzard's container/bank frames keep running their open/close state machine
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

	local bank = _G.BankFrame
	if bank then
		DisableBlizzardFrame(bank)
		bank.GetRight = function() return 0 end -- UIPanel layout math needs a number
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

function Bags:CreateSlot(view, bagID, slotID)
	local name = ('%sBag%dSlot%d'):format(view.config.frameName, bagID, slotID)
	local slot

	if view.config.isBank then
		-- BankPanelItemButtonMixin resolves everything from these fields
		slot = CreateFrame('ItemButton', name, view.frame, 'BankItemButtonTemplate')
		slot.bankTabID = bagID
		slot.containerSlotID = slotID
		slot.itemLocation = ItemLocation:CreateFromBagAndSlot(bagID, slotID)
	else
		-- ContainerFrameItemButtonMixin resolves its bag from the parent's
		-- frame ID, so tooltips, clicks, drag, splitting and selling all work
		-- without touching secure fields.
		slot = CreateFrame('ItemButton', name, view.bagHolders[bagID], 'ContainerFrameItemButtonTemplate')
		slot:SetID(slotID)
	end

	slot.view = view
	slot.BagID = bagID -- our bookkeeping; never write slot.bagID (taint)
	slot.SlotID = slotID

	local size = self.db.slotSize
	slot:SetSize(size, size)

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
	glint:SetSize(size * 1.3, size * 1.3)
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

	-- marching ants ring for special items (sprite sheet, see the ants driver)
	local ants = slot.qualityBorder:CreateTexture(nil, 'OVERLAY', nil, 2)
	ants:SetTexture('Interface\\SpellActivationOverlay\\IconAlertAnts')
	ants:SetPoint('CENTER')
	ants:SetSize(size + 6, size + 6)
	ants:Hide()
	slot.ants = ants

	-- template decorations we do not drive
	if slot.NewItemTexture then slot.NewItemTexture:Hide() end
	if slot.BattlepayItemTexture then slot.BattlepayItemTexture:Hide() end

	-- green up-arrow: container template ships one, bank template does not
	if slot.UpgradeIcon then
		slot.UpgradeIcon:ClearAllPoints()
	else
		slot.UpgradeIcon = slot.qualityBorder:CreateTexture(nil, 'OVERLAY')
		slot.UpgradeIcon:SetAtlas('bags-greenarrow', true)
	end
	slot.UpgradeIcon:SetPoint('TOPLEFT', slot, 'TOPLEFT', 1, -1)
	slot.UpgradeIcon:Hide()

	SetSlotBorder(slot, BORDER_THIN, EMPTY_R, EMPTY_G, EMPTY_B)

	return slot
end

function Bags:UpdateSlot(slot)
	local view = slot.view
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

	slot.UpgradeIcon:SetShown(isGear and IsItemLevelUpgrade(itemLevel, equipLoc))

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
		view.activeAnts[slot.ants] = true
	else
		slot.specialGlint.spin:Stop()
		slot.specialGlint.pulse:Stop()
		slot.specialGlint:Hide()
		slot.ants:Hide()
		view.activeAnts[slot.ants] = nil
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

	for term in slot.view.searchQuery:gmatch('%S+') do
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
	local query = slot.view.searchQuery
	local searching = query and query ~= ''
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

function Bags:ApplySearch(view)
	for _, bagSlots in pairs(view.slots) do
		for _, slot in ipairs(bagSlots) do
			if slot:IsShown() then
				self:ApplySearchToSlot(slot)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Updates
--------------------------------------------------------------------------------

function Bags:UpdateBag(view, bagID)
	local bagSlots = view.slots[bagID]
	if not bagSlots then return end

	for slotID = 1, GetContainerNumSlots(bagID) do
		local slot = bagSlots[slotID]
		if slot and slot:IsShown() then
			self:UpdateSlot(slot)
		end
	end
end

function Bags:UpdateAll(view)
	Sets:MarkDirty()
	for bagID in pairs(view.slots) do
		self:UpdateBag(view, bagID)
	end
	self:UpdateFooter(view)
end

function Bags:UpdateShownViews()
	for _, view in ipairs(self.views) do
		if view.frame:IsShown() then
			self:UpdateAll(view)
		end
	end
end

function Bags:UpdateCooldowns()
	for _, view in ipairs(self.views) do
		if view.frame:IsShown() then
			for bagID, bagSlots in pairs(view.slots) do
				for slotID = 1, GetContainerNumSlots(bagID) do
					local slot = bagSlots[slotID]
					if slot and slot:IsShown() and slot.UpdateCooldown and slot.Cooldown then
						slot:UpdateCooldown(GetContainerItemInfo(bagID, slotID) ~= nil)
					end
				end
			end
		end
	end
end

local function CountFree(bags)
	local free, total = 0, 0
	for _, bagID in ipairs(bags) do
		local numSlots = GetContainerNumSlots(bagID)
		if numSlots > 0 then
			total = total + numSlots
			free = free + (GetContainerNumFreeSlots(bagID) or 0)
		end
	end
	return free, total
end

function Bags:UpdateFooter(view)
	if view.config.isBank then
		local bankFree, bankTotal = CountFree(CHARACTER_BANK_BAGS)
		local wbFree, wbTotal = CountFree(WARBAND_BANK_BAGS)
		view.freeText:SetFormattedText('Bank %d/%d free  —  Warband %d/%d free',
			bankFree, bankTotal, wbFree, wbTotal)
	else
		local free, total = CountFree(HELD_BAGS)
		view.freeText:SetFormattedText('%d/%d free', free, total)
		view.moneyText:SetText(GetMoneyString(GetMoney(), true))
	end
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

function Bags:Layout(view)
	local db = self.db
	local step = db.slotSize + db.spacing
	local columns = view.config.columns
	local originY = HEADER_HEIGHT + FRAME_PADDING

	local col, row = 0, 0
	local yOffset = 0 -- accumulated section label space

	for index, section in ipairs(view.config.sections) do
		local numSectionSlots = 0
		for _, bagID in ipairs(section.bags) do
			numSectionSlots = numSectionSlots + GetContainerNumSlots(bagID)
		end

		local label = view.sectionLabels[index]
		if numSectionSlots == 0 then
			if label then label:Hide() end
		else
			if section.label then
				if not label then
					label = view.frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
					label:SetText(section.label)
					view.sectionLabels[index] = label
				end
				label:ClearAllPoints()
				label:SetPoint('TOPLEFT', view.frame, 'TOPLEFT',
					FRAME_PADDING, -(originY + row * step + yOffset + SECTION_GAP))
				label:Show()
				yOffset = yOffset + SECTION_GAP + label:GetStringHeight() + 4
			end

			for _, bagID in ipairs(section.bags) do
				local numSlots = GetContainerNumSlots(bagID)
				local bagSlots = view.slots[bagID]

				for slotID = 1, numSlots do
					bagSlots[slotID] = bagSlots[slotID] or self:CreateSlot(view, bagID, slotID)
					local slot = bagSlots[slotID]
					slot:ClearAllPoints()
					slot:SetPoint('TOPLEFT', view.frame, 'TOPLEFT',
						FRAME_PADDING + col * step,
						-(originY + row * step + yOffset))
					slot:SetSize(db.slotSize, db.slotSize)
					slot:Show()

					col = col + 1
					if col >= columns then
						col, row = 0, row + 1
					end
				end
			end

			if col > 0 then
				col, row = 0, row + 1
			end
		end

		-- hide slots beyond each bag's current size (or entire unpurchased bags)
		for _, bagID in ipairs(section.bags) do
			local numSlots = GetContainerNumSlots(bagID)
			local bagSlots = view.slots[bagID]
			for slotID = numSlots + 1, #bagSlots do
				bagSlots[slotID]:Hide()
			end
		end
	end

	view.frame:SetSize(
		FRAME_PADDING * 2 + columns * step - db.spacing,
		originY + row * step - db.spacing + yOffset + FRAME_PADDING + FOOTER_HEIGHT)
end

--------------------------------------------------------------------------------
-- View frames
--------------------------------------------------------------------------------

function Bags:CreateView(config)
	local db = self.db
	local view = {
		config = config,
		slots = {},
		activeAnts = {},
		sectionLabels = {},
		searchQuery = '',
	}

	local frame = CreateFrame('Frame', config.frameName, UIParent, 'BackdropTemplate')
	view.frame = frame

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

	local pos = db[config.positionKey]
	if pos then
		frame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
	else
		local default = config.defaultPosition
		frame:SetPoint(default.point, UIParent, default.point, default.x, default.y)
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
		db[config.positionKey] = { point = point, x = x, y = y }
	end)

	local title = header:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
	title:SetPoint('LEFT', FRAME_PADDING, 0)
	title:SetText(config.title)

	local close = CreateFrame('Button', nil, header, 'UIPanelCloseButton')
	close:SetPoint('RIGHT', -2, 0)
	close:SetScript('OnClick', function() frame:Hide() end)

	local sort = CreateFrame('Button', nil, header, 'UIPanelButtonTemplate')
	sort:SetSize(50, 20)
	sort:SetPoint('RIGHT', close, 'LEFT', -4, 0)
	sort:SetText('Sort')
	sort:SetScript('OnClick', config.sortFunc)

	local search = CreateFrame('EditBox', config.frameName .. 'SearchBox', header, 'SearchBoxTemplate')
	search:SetSize(150, 20)
	search:SetPoint('RIGHT', sort, 'LEFT', -10, 0)
	search:SetAutoFocus(false)
	search:HookScript('OnTextChanged', function(box)
		view.searchQuery = strtrim(box:GetText() or ''):lower()
		self:ApplySearch(view)
	end)
	view.searchBox = search

	-- footer
	view.freeText = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
	view.freeText:SetPoint('BOTTOMLEFT', FRAME_PADDING, FRAME_PADDING)

	if not config.isBank then
		view.moneyText = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
		view.moneyText:SetPoint('BOTTOMRIGHT', -FRAME_PADDING, FRAME_PADDING)
	end

	-- drives the marching ants sprite sheet; parented to the view frame so it
	-- only runs while that frame is open
	local antsDriver = CreateFrame('Frame', nil, frame)
	local AnimateTexCoords = TextureUtil and TextureUtil.AnimateTexCoords
	if AnimateTexCoords then
		antsDriver:SetScript('OnUpdate', function(_, elapsed)
			for texture in pairs(view.activeAnts) do
				AnimateTexCoords(texture, 256, 256, 48, 48, 22, elapsed, 0.01)
			end
		end)
	end

	-- slot storage per bag; inventory additionally needs an ID-carrying holder
	-- per bag for the container item button mixin
	if not config.isBank then
		view.bagHolders = {}
	end
	for _, section in ipairs(config.sections) do
		for _, bagID in ipairs(section.bags) do
			view.slots[bagID] = {}
			self.viewByBagID[bagID] = view
			if view.bagHolders then
				local holder = CreateFrame('Frame', nil, frame)
				holder:SetID(bagID)
				holder:SetAllPoints()
				view.bagHolders[bagID] = holder
			end
		end
	end

	frame:SetScript('OnShow', function()
		PlaySound(SOUNDKIT.IG_BACKPACK_OPEN)
		self:Layout(view)
		self:UpdateAll(view)
	end)

	frame:SetScript('OnHide', function()
		PlaySound(SOUNDKIT.IG_BACKPACK_CLOSE)
		config.onHidden()
	end)

	tinsert(UISpecialFrames, config.frameName)
	tinsert(self.views, view)

	return view
end

--------------------------------------------------------------------------------
-- Open/close syncing
--------------------------------------------------------------------------------

function Bags:Sync()
	if IsBagOpen(BACKPACK) then
		self.inventory.frame:Show()
	else
		self.inventory.frame:Hide()
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
	'BANKFRAME_OPENED',
	'BANKFRAME_CLOSED',
	'PLAYERBANKSLOTS_CHANGED',
	'BANK_TABS_CHANGED',
	'BANK_TAB_SETTINGS_UPDATED',
}

function Bags:OnEvent(event, arg1, arg2)
	if event == 'BANKFRAME_OPENED' then
		self.bankIsOpen = true
		self.bank.frame:Show()
		return
	elseif event == 'BANKFRAME_CLOSED' then
		self.bankIsOpen = false
		self.bank.frame:Hide()
		return
	end

	if event == 'BAG_CONTAINER_UPDATE' then
		if self.inventory.frame:IsShown() then
			self:Layout(self.inventory)
			self:UpdateAll(self.inventory)
		end
	elseif event == 'BAG_UPDATE' then
		local view = self.viewByBagID[arg1]
		if view and view.frame:IsShown() then
			Sets:MarkDirty() -- an item may have moved; set locations follow it
			self:UpdateBag(view, arg1)
		end
	elseif event == 'BAG_UPDATE_DELAYED' then
		self:UpdateShownViews()
	elseif event == 'PLAYER_EQUIPMENT_CHANGED' then
		self:UpdateShownViews() -- equipped ilvls changed; recompute upgrade arrows
	elseif event == 'BAG_UPDATE_COOLDOWN' then
		self:UpdateCooldowns()
	elseif event == 'ITEM_LOCK_CHANGED' then
		local view = self.viewByBagID[arg1]
		local slot = arg2 and view and view.slots[arg1] and view.slots[arg1][arg2]
		if slot and view.frame:IsShown() then
			self:UpdateSlot(slot)
		end
	elseif event == 'PLAYERBANKSLOTS_CHANGED' then
		if self.bank.frame:IsShown() then
			self:UpdateAll(self.bank)
		end
	elseif event == 'BANK_TABS_CHANGED' or event == 'BANK_TAB_SETTINGS_UPDATED' then
		if self.bank.frame:IsShown() then
			self:Layout(self.bank)
			self:UpdateAll(self.bank)
		end
	elseif event == 'PLAYER_MONEY' then
		if self.inventory.frame:IsShown() then
			self:UpdateFooter(self.inventory)
		end
	end
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

function Bags:OnInit()
	self.db = BenisUI.db.bags
	self.views = {}
	self.viewByBagID = {}

	self.inventory = self:CreateView({
		frameName = 'BenisUI_BagFrame',
		title = '|cff1784d1Benis|rUI Inventory',
		isBank = false,
		columns = self.db.columns,
		positionKey = 'position',
		defaultPosition = { point = 'BOTTOMRIGHT', x = -50, y = 120 },
		sections = {
			{ bags = HELD_BAGS },
			{ label = 'Reagents', bags = { REAGENT_BAG } },
		},
		sortFunc = function() C_Container.SortBags() end,
		onHidden = function()
			-- keep Blizzard's open/close state in sync when closed via X or ESC
			if IsBagOpen(BACKPACK) then
				CloseAllBags()
			end
		end,
	})

	self.bank = self:CreateView({
		frameName = 'BenisUI_BankFrame',
		title = '|cff1784d1Benis|rUI Bank',
		isBank = true,
		columns = self.db.bankColumns,
		positionKey = 'bankPosition',
		defaultPosition = { point = 'TOPLEFT', x = 50, y = -80 },
		sections = {
			{ label = 'Bank', bags = CHARACTER_BANK_BAGS },
			{ label = 'Warband Bank', bags = WARBAND_BANK_BAGS },
		},
		sortFunc = function()
			C_Container.SortBankBags()
			C_Container.SortAccountBankBags()
		end,
		onHidden = function()
			if Bags.bankIsOpen then
				CloseBank()
			end
		end,
	})

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
