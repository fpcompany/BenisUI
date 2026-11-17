local _, ns = ...
local BenisUI = ns.BenisUI

local Bags = BenisUI:RegisterModule('Bags')
local Sets = BenisUI:GetModule('EquipmentSets')
local Skin = BenisUI.Skin

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

-- the tab count differs per client (retail: 6 character + 5 warband tabs,
-- Forever: 9 + 9), so walk the enum instead of assuming a range
local function CollectBankTabs(prefix)
	local bags = {}
	local index = 1
	while BagIndex[prefix .. index] do
		bags[index] = BagIndex[prefix .. index]
		index = index + 1
	end
	return bags
end

local CHARACTER_BANK_BAGS = CollectBankTabs('CharacterBankTab_')
local WARBAND_BANK_BAGS = CollectBankTabs('AccountBankTab_')

local ALL_BANK_BAGS = {}
for _, list in next, { CHARACTER_BANK_BAGS, WARBAND_BANK_BAGS } do
	for _, bagID in ipairs(list) do
		ALL_BANK_BAGS[#ALL_BANK_BAGS + 1] = bagID
	end
end

-- bank tabs whose deposit settings mark them as reagent tabs
local REAGENT_FLAG = (Enum.BagSlotFlags and Enum.BagSlotFlags.ClassReagents) or 128
local FetchPurchasedBankTabData = C_Bank and C_Bank.FetchPurchasedBankTabData

local function GetReagentFlaggedBags()
	local flagged = {}
	if FetchPurchasedBankTabData and Enum.BankType then
		for _, bankType in next, { Enum.BankType.Character, Enum.BankType.Account } do
			local tabs = FetchPurchasedBankTabData(bankType)
			if tabs then
				for _, data in ipairs(tabs) do
					if data.ID and bit.band(data.depositFlags or 0, REAGENT_FLAG) ~= 0 then
						flagged[data.ID] = true
					end
				end
			end
		end
	end
	return flagged
end

local EDGE_TEXTURE = 'Interface\\Buttons\\WHITE8X8'
local BORDER_THIN = 1
local BORDER_THICK = BORDER_THIN * 5 -- equipment set items
local FRAME_PADDING = 10
local HEADER_HEIGHT = 34
local FOOTER_HEIGHT = 26
local SECTION_GAP = 14 -- extra gap above a labeled section
local BAR_SIZE = 26 -- bag slot / bank tab buttons under the header
local BAR_SPACING = 4
local BAR_HEIGHT = BAR_SIZE + 2

-- Blizzard's equipped-bag buttons, adopted into the inventory bag bar
local BAG_SLOT_BUTTONS = {
	'CharacterBag0Slot', 'CharacterBag1Slot', 'CharacterBag2Slot', 'CharacterBag3Slot',
	'CharacterReagentBag0Slot',
}

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

--------------------------------------------------------------------------------
-- Stat-based upgrades (WoW Forever / Camelot)
--------------------------------------------------------------------------------

-- Forever (Interface 16001) is a vanilla-style ruleset: item level says little
-- about gear, so arrows come from comparing stats instead.
local IS_FOREVER = (select(4, GetBuildInfo()) or 0) < 20000
local GetItemStats = C_Item.GetItemStats or _G.GetItemStats
local GetInventoryItemLink = GetInventoryItemLink

-- Per-class stat weights. Only shaman is known; other classes get no arrows on
-- Forever. Any stat not listed but present counts OTHER_STAT_WEIGHT per point,
-- so any stats beat no stats. Armor is never weighed against stats: it only
-- breaks ties when the stat scores are equal.
local OTHER_STAT_WEIGHT = 1
local ARMOR_STAT = 'RESISTANCE0_NAME'
local CLASS_STAT_WEIGHTS = {
	-- WoW Forever enhancement guide:
	-- Strength = Attack Power > Intellect > Spell Power = Agility > Spirit,
	-- crit chance is very important (Flurry), hit is not a priority while leveling
	SHAMAN = {
		ITEM_MOD_STRENGTH_SHORT = 10,
		ITEM_MOD_ATTACK_POWER_SHORT = 10,
		ITEM_MOD_INTELLECT_SHORT = 8,
		ITEM_MOD_SPELL_POWER_SHORT = 6,
		ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 6,
		ITEM_MOD_AGILITY_SHORT = 6,
		ITEM_MOD_SPIRIT_SHORT = 2,
		ITEM_MOD_STAMINA_SHORT = 4,
		ITEM_MOD_CRIT_RATING_SHORT = 140, -- per 1% crit, roughly 20 Agility's crit plus Flurry
		ITEM_MOD_CRIT_MELEE_RATING_SHORT = 140,
		ITEM_MOD_HIT_RATING_SHORT = 15, -- per 1% hit, low while leveling
		ITEM_MOD_HIT_MELEE_RATING_SHORT = 15,
		ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10, -- weapon DPS
		[ARMOR_STAT] = 0, -- tie-breaker only, see ScoreLink
	},
}

local playerWeights
local function GetPlayerWeights()
	if playerWeights == nil then
		local _, classToken = UnitClass('player')
		playerWeights = CLASS_STAT_WEIGHTS[classToken] or false
	end
	return playerWeights
end

-- returns statScore, armor (0, 0 for nothing / unknown item)
local function ScoreLink(link, weights)
	local stats = link and GetItemStats(link)
	if not stats then return 0, 0 end

	local score = 0
	for stat, value in pairs(stats) do
		if stat ~= ARMOR_STAT then
			score = score + (weights[stat] or OTHER_STAT_WEIGHT) * value
		end
	end
	return score, stats[ARMOR_STAT] or 0
end

local function ScoreInvSlot(invSlot, weights)
	return ScoreLink(GetInventoryItemLink('player', invSlot), weights)
end

local function IsBetter(score, armor, otherScore, otherArmor)
	if score ~= otherScore then return score > otherScore end
	return armor > otherArmor
end

local function IsTwoHandEquipped()
	local link = GetInventoryItemLink('player', 16)
	if not link then return false end
	local _, _, _, equipLoc = GetItemInfoInstant(link)
	return equipLoc == 'INVTYPE_2HWEAPON'
end

local OFFHAND_LOCS = {
	INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true,
}

-- red tooltip text means the player can't use it (class, proficiency, level)
local function HasRedLine(data)
	local lines = data and data.lines
	if not lines then return false end
	for i = 2, #lines do
		local line = lines[i]
		for _, color in next, { line.leftColor, line.rightColor } do
			if color and color.r > 0.99 and color.g < 0.2 and color.b < 0.2 then
				return true
			end
		end
	end
	return false
end

local function IsBagItemUsable(bagID, slotID)
	if not (C_TooltipInfo and C_TooltipInfo.GetBagItem) then return true end
	return not HasRedLine(C_TooltipInfo.GetBagItem(bagID, slotID))
end

-- Forever keeps vanilla's weapon and armor skills: the skill is a spell, and
-- you can only wear the item once you know it (shaman/hunter mail at 40, ...)
local ArmorSub = Enum.ItemArmorSubclass or {}
local WeaponSub = Enum.ItemWeaponSubclass or {}
local SKILL_SPELLS = {
	[Enum.ItemClass.Armor] = {
		[ArmorSub.Cloth or 1] = 9078,
		[ArmorSub.Leather or 2] = 9077,
		[ArmorSub.Mail or 3] = 8737,
		[ArmorSub.Plate or 4] = 750,
		[ArmorSub.Shield or 6] = 9116,
	},
	[Enum.ItemClass.Weapon] = {
		[WeaponSub.Axe1H or 0] = 196,
		[WeaponSub.Axe2H or 1] = 197,
		[WeaponSub.Bows or 2] = 264,
		[WeaponSub.Guns or 3] = 266,
		[WeaponSub.Mace1H or 4] = 198,
		[WeaponSub.Mace2H or 5] = 199,
		[WeaponSub.Polearm or 6] = 200,
		[WeaponSub.Sword1H or 7] = 201,
		[WeaponSub.Sword2H or 8] = 202,
		[WeaponSub.Staff or 10] = 227,
		[WeaponSub.Unarmed or 13] = 15590, -- fist weapons
		[WeaponSub.Dagger or 15] = 1180,
		[WeaponSub.Thrown or 16] = 2567,
		[WeaponSub.Crossbow or 18] = 5011,
		[WeaponSub.Wand or 19] = 5009,
	},
}
-- classes whose relic slot takes this armor subclass (totems, idols, librams)
local RELIC_CLASS = {
	[ArmorSub.Totem or 9] = 'SHAMAN',
	[ArmorSub.Idol or 8] = 'DRUID',
	[ArmorSub.Libram or 7] = 'PALADIN',
}
local FISHING_POLE = WeaponSub.Fishingpole or 20

local DoesSpellExist = C_Spell and C_Spell.DoesSpellExist
local function KnowsSkill(spellID)
	-- a skill spell this client doesn't have can't be checked; let it pass
	if DoesSpellExist and not DoesSpellExist(spellID) then return true end
	return IsPlayerSpell(spellID)
end

-- can the player wear this at all, right now?
local function CanWear(link)
	local _, _, _, _, reqLevel = GetItemInfo(link)
	if reqLevel and reqLevel > UnitLevel('player') then return false end

	if not IS_FOREVER then return true end -- retail: the tooltip check covers it

	local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(link)
	if classID == Enum.ItemClass.Weapon and subclassID == FISHING_POLE then return false end

	local relicClass = classID == Enum.ItemClass.Armor and RELIC_CLASS[subclassID]
	if relicClass then
		return relicClass == select(2, UnitClass('player'))
	end

	local skills = SKILL_SPELLS[classID]
	local spellID = skills and skills[subclassID]
	return not spellID or KnowsSkill(spellID)
end

-- body armor tiers, lowest to highest; only the best one the player knows gets
-- arrows (a shaman stops seeing leather upgrades once mail is learned at 40)
local ARMOR_TIERS = {
	ArmorSub.Cloth or 1, ArmorSub.Leather or 2, ArmorSub.Mail or 3, ArmorSub.Plate or 4,
}
local ARMOR_TIER_RANK = {}
for rank, subclassID in ipairs(ARMOR_TIERS) do ARMOR_TIER_RANK[subclassID] = rank end

-- slots that take any armor type regardless of tier (cloaks are always cloth)
local TIERLESS_EQUIP_LOCS = {
	INVTYPE_CLOAK = true, INVTYPE_NECK = true, INVTYPE_FINGER = true,
	INVTYPE_TRINKET = true, INVTYPE_BODY = true, INVTYPE_TABARD = true,
}

-- rank of the highest armor skill the player knows, or nil when none of the
-- skill spells can be checked on this client (no restriction then)
local function GetBestArmorRank()
	local best
	for rank, subclassID in ipairs(ARMOR_TIERS) do
		local spellID = SKILL_SPELLS[Enum.ItemClass.Armor][subclassID]
		if (not DoesSpellExist or DoesSpellExist(spellID)) and IsPlayerSpell(spellID) then
			best = rank
		end
	end
	return best
end

-- is this the best armor type the player can wear (or not tiered armor at all)?
local function IsBestArmorType(link, equipLoc)
	if TIERLESS_EQUIP_LOCS[equipLoc] then return true end
	local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(link)
	if classID ~= Enum.ItemClass.Armor then return true end
	local rank = ARMOR_TIER_RANK[subclassID]
	if not rank then return true end -- shields, relics, misc
	local best = GetBestArmorRank()
	return not best or rank >= best
end

-- better stats than what it would replace, for the player's class?
local function IsStatUpgrade(link, equipLoc)
	local weights = GetPlayerWeights()
	if not weights then return false end

	local invSlots = EQUIP_LOC_SLOTS[equipLoc]
	if not invSlots then return false end

	local score, armor = ScoreLink(link, weights)
	if score <= 0 and armor <= 0 then return false end

	local otherScore, otherArmor
	if equipLoc == 'INVTYPE_2HWEAPON' then
		-- replaces both hands
		local mainScore, mainArmor = ScoreInvSlot(16, weights)
		local offScore, offArmor = ScoreInvSlot(17, weights)
		otherScore, otherArmor = mainScore + offScore, mainArmor + offArmor
	elseif OFFHAND_LOCS[equipLoc] and IsTwoHandEquipped() then
		-- an off-hand would replace the two-hander
		otherScore, otherArmor = ScoreInvSlot(16, weights)
	else
		if equipLoc == 'INVTYPE_WEAPON' and not (CanDualWield and CanDualWield()) then
			invSlots = { 16 }
		end
		-- compete with the weakest equipped piece in the slot group
		for _, invSlot in ipairs(invSlots) do
			local s, a = ScoreInvSlot(invSlot, weights)
			if not otherScore or IsBetter(otherScore, otherArmor, s, a) then
				otherScore, otherArmor = s, a
			end
		end
	end

	return IsBetter(score, armor, otherScore, otherArmor)
end

-- gear upgrade check shared by bag slots and quest rewards: stats on Forever,
-- item level on retail. isUsable is a function so the (costly) usability check
-- only runs once the item already looks like an upgrade.
local function IsUpgrade(link, equipLoc, itemLevel, isUsable)
	local better
	if IS_FOREVER then
		better = IsStatUpgrade(link, equipLoc)
	else
		better = IsItemLevelUpgrade(itemLevel, equipLoc)
	end
	return better and CanWear(link) and IsBestArmorType(link, equipLoc)
		and (not isUsable or isUsable())
end

-- for windows that only have a link (quest rewards, loot rolls)
local function IsLinkUpgrade(link, isUsable)
	if not link then return false end
	local _, _, _, equipLoc, _, classID = GetItemInfoInstant(link)
	local isGear = (classID == Enum.ItemClass.Weapon or classID == Enum.ItemClass.Armor)
		and not ITEMLEVEL_EXCLUDED_EQUIP_LOCS[equipLoc]
	if not isGear then return false end
	local itemLevel = C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)
	return IsUpgrade(link, equipLoc, itemLevel, isUsable) or false
end

-- green arrow in the top-left corner of an icon, created on first use
local function GetArrow(owner, icon)
	local arrow = owner.benisUpgradeIcon
	if not arrow and icon then
		arrow = owner:CreateTexture(nil, 'OVERLAY', nil, 7)
		arrow:SetAtlas('bags-greenarrow', true)
		arrow:SetPoint('TOPLEFT', icon, 'TOPLEFT', 1, -1)
		owner.benisUpgradeIcon = arrow
	end
	return arrow
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
		if slot.Background then slot.Background:Hide() end -- template slot art
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

	local size = view.config.slotSize
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

	local isUpgrade = isGear and IsUpgrade(info.hyperlink, equipLoc, itemLevel, function()
		return IsBagItemUsable(bagID, slotID)
	end) or false

	-- grey out junk and gear below the Hero/Myth upgrade tracks (crafted exempt);
	-- Forever has no upgrade tracks, and upgrades always stay saturated
	local lowTrack = isGear and not IS_FOREVER and not (isCrafted or HasKeepTrackWord(trackText))
	local desaturated = hasItem and (info.isLocked or isJunk or (lowTrack and not isUpgrade))

	slot.UpgradeIcon:SetShown(isUpgrade)

	SetItemButtonTexture(slot, icon)
	-- crop the bevel baked into Blizzard icon art (our border replaces it);
	-- redone every update since the empty-slot SetAtlas resets tex coords
	if hasItem and slot.icon then slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
	SetItemButtonCount(slot, info and info.stackCount or 0)
	slot.desaturated = desaturated -- applied in ApplySearchToSlot
	slot.itemID = hasItem and info.itemID or nil -- for the recipe filter
	slot.itemName = hasItem and info.itemName or nil

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

-- Recipe filter: while a recipe is selected in the crafting window, every item
-- that recipe does not use is greyed out and darkened (see BagsRecipe.lua).
-- itemIDs: [itemID] = true for reagents; names: [item name] = true for tools,
-- which the API only reports by name. nil clears the filter.
function Bags:SetRecipeFilter(itemIDs, names)
	self.recipeItems, self.recipeNames = itemIDs, names
	for _, view in ipairs(self.views) do
		if view.frame:IsShown() then
			self:ApplySearch(view)
		end
	end
end

function Bags:SlotIsRecipeItem(slot)
	return (slot.itemID and self.recipeItems[slot.itemID])
		or (slot.itemName and self.recipeNames and self.recipeNames[slot.itemName])
		or false
end

local RECIPE_DIM = 0.3 -- icon and border brightness of items the recipe doesn't use

function Bags:ApplySearchToSlot(slot)
	local query = slot.view.searchQuery
	local searching = query and query ~= ''
	local matches = not searching or self:SlotMatchesSearch(slot)

	-- a search overrides the recipe filter, so anything can still be looked up
	local dimmed = self.recipeItems ~= nil and not searching and slot.itemID ~= nil
		and not self:SlotIsRecipeItem(slot)

	-- hovering a bag / bank tab button dims every slot outside it
	local hoverBag = slot.view.hoverBag
	local outsideHover = hoverBag ~= nil and slot.BagID ~= hoverBag
	slot:SetAlpha(((searching and not matches) or outsideHover) and 0.15 or 1)

	-- while searching, found items lose their desaturation
	local desaturated = dimmed or (slot.desaturated and not (searching and matches))
	SetItemButtonDesaturated(slot, desaturated)
	local shade = dimmed and RECIPE_DIM or 1
	SetItemButtonTextureVertexColor(slot, shade, shade, shade)

	-- while searching, no slot shows a border
	local border = slot.qualityBorder
	if border.r then
		border:SetBackdropBorderColor(border.r * shade, border.g * shade, border.b * shade,
			searching and 0 or 1)
	end

	if slot.ilvlR then
		if desaturated then
			-- match the greyed icon: quality color reduced to its luminance
			local gray = (0.299 * slot.ilvlR + 0.587 * slot.ilvlG + 0.114 * slot.ilvlB) * shade
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

Bags.buyTabLabel = 'Buy Tab'

function Bags:UpdateBankFreeText(view)
	local bankFree, bankTotal = CountFree(CHARACTER_BANK_BAGS)
	local wbFree, wbTotal = CountFree(WARBAND_BANK_BAGS)
	view.freeText:SetFormattedText('Bank %d/%d free  —  Warband %d/%d free',
		bankFree, bankTotal, wbFree, wbTotal)
end

function Bags:UpdateFooter(view)
	if view.config.isBank then
		self:UpdateBankFreeText(view)

		-- buy-next-tab button for the active bank (the Reagents tab has none)
		local section = view.config.sections[view.activeSection or 1]
		local canBuy = section.bankType and C_Bank and C_Bank.CanPurchaseBankTab
			and C_Bank.CanPurchaseBankTab(section.bankType)
		if canBuy then
			local label = self.buyTabLabel
			local tabData = C_Bank.FetchNextPurchasableBankTabData(section.bankType)
			if tabData then
				view.buyTabButton:SetText(('%s: %s'):format(label, GetMoneyString(tabData.tabCost, true)))
			else
				view.buyTabButton:SetText(label)
			end
			-- Blizzard's purchase handler reads the bank to buy from here
			view.buyTabButton:SetAttribute('overrideBankType', section.bankType)
			view.buyTabButton:Show()
		else
			view.buyTabButton:Hide()
		end
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
	local slotSize = view.config.slotSize
	local step = slotSize + db.spacing
	local columns = view.config.columns
	local originY = HEADER_HEIGHT + BAR_HEIGHT + FRAME_PADDING

	if view.config.isBank then
		self:UpdateBankBar(view)
	end

	-- category view (BagsCategories.lua) has its own layout
	for _, label in pairs(view.categoryLabels or {}) do
		label:Hide()
	end
	if self.IsCategoryMode and self:IsCategoryMode(view) then
		for _, label in pairs(view.sectionLabels) do
			label:Hide()
		end
		return self:LayoutCategories(view)
	end

	local col, row = 0, 0
	local yOffset = 0 -- accumulated section label space

	-- resolve which bags each section actually owns right now (reagent-flagged
	-- bank tabs move from the Bank/Warband sections into the Reagents section)
	local reagentBags = view.config.isBank and GetReagentFlaggedBags() or nil
	local effectiveBags = {}
	for index, section in ipairs(view.config.sections) do
		local list = {}
		for _, bagID in ipairs(section.bags) do
			local isReagentTab = reagentBags and reagentBags[bagID]
			if section.onlyReagents then
				if isReagentTab then list[#list + 1] = bagID end
			elseif not (section.excludeReagents and isReagentTab) then
				list[#list + 1] = bagID
			end
		end
		effectiveBags[index] = list
	end

	for index, section in ipairs(view.config.sections) do
		local sectionBags = effectiveBags[index]
		-- with tabs, only the active section is laid out
		local isActive = not view.config.tabbed or index == view.activeSection

		local numSectionSlots = 0
		for _, bagID in ipairs(sectionBags) do
			numSectionSlots = numSectionSlots + GetContainerNumSlots(bagID)
		end

		local label = view.sectionLabels[index]
		if not isActive or numSectionSlots == 0 then
			if label then label:Hide() end
			for _, bagID in ipairs(sectionBags) do
				local bagSlots = view.slots[bagID]
				for slotID = 1, #bagSlots do
					bagSlots[slotID]:Hide()
				end
			end
		else
			-- tabs already name the section; a label would be redundant
			if section.label and not view.config.tabbed then
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

			for _, bagID in ipairs(sectionBags) do
				local numSlots = GetContainerNumSlots(bagID)
				local bagSlots = view.slots[bagID]

				for slotID = 1, numSlots do
					bagSlots[slotID] = bagSlots[slotID] or self:CreateSlot(view, bagID, slotID)
					local slot = bagSlots[slotID]
					slot:ClearAllPoints()
					slot:SetPoint('TOPLEFT', view.frame, 'TOPLEFT',
						FRAME_PADDING + col * step,
						-(originY + row * step + yOffset))
					slot:SetSize(slotSize, slotSize)
					slot:Show()

					col = col + 1
					if col >= columns then
						col, row = 0, row + 1
					end
				end
				for slotID = numSlots + 1, #bagSlots do
					bagSlots[slotID]:Hide()
				end
			end

			if col > 0 then
				col, row = 0, row + 1
			end
		end
	end

	view.frame:SetSize(
		FRAME_PADDING * 2 + columns * step - db.spacing,
		originY + row * step - db.spacing + yOffset + FRAME_PADDING + FOOTER_HEIGHT)
end

--------------------------------------------------------------------------------
-- Bag bar (equipped bags / bank tabs)
--------------------------------------------------------------------------------

local function nop() end

function Bags:SetHoverBag(view, bagID)
	view.hoverBag = bagID
	self:ApplySearch(view)
end

-- Square, flat bar button look shared by adopted bag slots and our tab buttons
local function StyleBarButton(button, icon)
	local bg = button:CreateTexture(nil, 'BACKGROUND', nil, -1)
	bg:SetAllPoints()
	bg:SetColorTexture(0.09, 0.09, 0.09, 0.9)

	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local highlight = button:GetHighlightTexture()
	if not highlight then
		button:SetHighlightTexture(EDGE_TEXTURE)
		highlight = button:GetHighlightTexture()
	end
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.2)
	highlight:SetBlendMode('BLEND')
	highlight:SetAlpha(1)

	Skin:Border(button)
end

-- Blizzard's own bag slot buttons (killed along with BagsBar by BottomPanel)
-- keep all their behavior: tooltip, drag a bag on to equip, drag off to
-- swap/unequip, drop an item on to put it in that bag, filter assignments.
function Bags:AdoptBagButton(view, button, previous)
	button:SetParent(view.bar)
	button:SetSize(BAR_SIZE, BAR_SIZE)
	button:Show()

	-- collapsing Blizzard's bag bar would hide it
	button.SetBarExpanded = nop

	-- BagsBar:Layout re-anchors the buttons; put ours back every time
	local anchorTo, anchorPoint, x = view.bar, 'LEFT', 0
	if previous then
		anchorTo, anchorPoint, x = previous, 'RIGHT', BAR_SPACING
	end
	local placing
	local function Place()
		placing = true
		button:ClearAllPoints()
		button:SetPoint('LEFT', anchorTo, anchorPoint, x, 0)
		placing = false
	end
	hooksecurefunc(button, 'SetPoint', function()
		if not placing then Place() end
	end)
	Place()

	-- square icon: drop the round mask and Blizzard's bag ring art
	local mask = button.CircleMask
	if mask then
		for _, key in ipairs({ 'icon', 'searchOverlay', 'ItemContextOverlay' }) do
			local texture = button[key]
			if texture and texture.RemoveMaskTexture then
				texture:RemoveMaskTexture(mask)
			end
		end
	end
	if button.IconBorder then button.IconBorder:SetAlpha(0) end
	if button.SlotHighlightTexture then button.SlotHighlightTexture:SetAlpha(0) end

	-- Blizzard re-applies the ring atlases on every update
	button.UpdateTextures = function(b)
		local normal = b:GetNormalTexture()
		if normal then normal:SetAlpha(0) end
		local pushed = b:GetPushedTexture()
		if pushed then pushed:SetAlpha(0) end
	end
	button:UpdateTextures()

	StyleBarButton(button, button.icon)

	-- a plain click would toggle Blizzard's (hidden) bag frame and close ours;
	-- keep only the "drop the held item into this bag" part
	button:SetScript('OnClick', function(b)
		if KeybindFrames_InQuickKeybindMode and KeybindFrames_InQuickKeybindMode() then return end
		b:PutItemInBag()
	end)

	button:HookScript('OnEnter', function(b)
		self:SetHoverBag(view, b:GetBagID())
	end)
	button:HookScript('OnLeave', function()
		self:SetHoverBag(view, nil)
	end)
end

function Bags:CreateBagBar(view)
	local bar = CreateFrame('Frame', nil, view.frame)
	bar:SetPoint('TOPLEFT', view.frame, 'TOPLEFT', FRAME_PADDING, -(HEADER_HEIGHT + 2))
	bar:SetPoint('TOPRIGHT', view.frame, 'TOPRIGHT', -FRAME_PADDING, -(HEADER_HEIGHT + 2))
	bar:SetHeight(BAR_SIZE)
	view.bar = bar

	if view.config.isBank then
		view.tabButtons = {}
		return
	end

	local previous
	for _, name in ipairs(BAG_SLOT_BUTTONS) do
		local button = _G[name]
		if button then
			self:AdoptBagButton(view, button, previous)
			previous = button
		end
	end
end

-- purchased bank tabs belonging to the active bank section
function Bags:GetSectionTabs(view)
	local tabs = {}
	if not (FetchPurchasedBankTabData and Enum.BankType) then return tabs end

	local section = view.config.sections[view.activeSection]
	local bankTypes = section.bankType and { section.bankType }
		or { Enum.BankType.Character, Enum.BankType.Account }

	for _, bankType in ipairs(bankTypes) do
		for _, data in ipairs(FetchPurchasedBankTabData(bankType) or {}) do
			local isReagentTab = bit.band(data.depositFlags or 0, REAGENT_FLAG) ~= 0
			local include
			if section.onlyReagents then
				include = isReagentTab
			else
				include = not (section.excludeReagents and isReagentTab)
			end
			if include then
				data.bankType = data.bankType or bankType
				tabs[#tabs + 1] = data
			end
		end
	end

	return tabs
end

local function ShowTabTooltip(button)
	local data = button.data
	if not data then return end

	GameTooltip:SetOwner(button, 'ANCHOR_TOP')
	local name = (data.name and data.name ~= '') and data.name or ('Tab ' .. button.index)
	GameTooltip:SetText(name, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)

	local flags = data.depositFlags
	if flags and Enum.BagSlotFlags then
		local expansion
		if Enum.BagSlotFlags.ExpansionCurrent and bit.band(flags, Enum.BagSlotFlags.ExpansionCurrent) ~= 0 then
			expansion = BANK_TAB_EXPANSION_FILTER_CURRENT
		elseif Enum.BagSlotFlags.ExpansionLegacy and bit.band(flags, Enum.BagSlotFlags.ExpansionLegacy) ~= 0 then
			expansion = BANK_TAB_EXPANSION_FILTER_LEGACY
		end
		if expansion and BANK_TAB_EXPANSION_ASSIGNMENT then
			GameTooltip:AddLine(BANK_TAB_EXPANSION_ASSIGNMENT:format(expansion), 1, 1, 1)
		end

		local list = ContainerFrameUtil_ConvertFilterFlagsToList
			and ContainerFrameUtil_ConvertFilterFlagsToList(flags)
		if list and BANK_TAB_DEPOSIT_ASSIGNMENTS then
			GameTooltip:AddLine(BANK_TAB_DEPOSIT_ASSIGNMENTS:format(list), 1, 1, 1, true)
		end
	end

	GameTooltip:AddLine('Click to edit name, icon and deposit settings', 0, 1, 0)
	GameTooltip:Show()
end

function Bags:CreateTabButton(view, index)
	local button = CreateFrame('Button', nil, view.bar)
	button:SetSize(BAR_SIZE, BAR_SIZE)
	button:SetPoint('LEFT', view.bar, 'LEFT', (index - 1) * (BAR_SIZE + BAR_SPACING), 0)
	button:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
	button.index = index

	button.icon = button:CreateTexture(nil, 'ARTWORK')
	button.icon:SetAllPoints()
	StyleBarButton(button, button.icon)

	button:SetScript('OnEnter', function(b)
		ShowTabTooltip(b)
		self:SetHoverBag(view, b.data and b.data.ID)
	end)
	button:SetScript('OnLeave', function()
		GameTooltip:Hide()
		self:SetHoverBag(view, nil)
	end)
	button:SetScript('OnClick', function(b)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
		self:ToggleTabSettings(view, b.data)
	end)

	view.tabButtons[index] = button
	return button
end

function Bags:UpdateBankBar(view)
	local tabs = self:GetSectionTabs(view)
	for index, data in ipairs(tabs) do
		local button = view.tabButtons[index] or self:CreateTabButton(view, index)
		button.data = data
		button.icon:SetTexture(data.icon or QUESTION_MARK_ICON or 134400)
		button:Show()
	end
	for index = #tabs + 1, #view.tabButtons do
		view.tabButtons[index].data = nil
		view.tabButtons[index]:Hide()
	end

	-- the settings popup holds a stale copy of the tab it edits
	local menu = self.tabSettingsMenu
	if menu and menu:IsShown() then
		menu:Hide()
	end
end

-- Blizzard's tab settings popup (name, icon, deposit filters) lives inside the
-- never-rendered BankPanel; lift it out and feed it the tab directly.
function Bags:GetTabSettingsMenu()
	if self.tabSettingsMenu then return self.tabSettingsMenu end

	local menu = BankPanel and BankPanel.TabSettingsMenu
	if not (menu and menu.Update) then return end

	menu:SetParent(UIParent)
	menu:SetFrameStrata('DIALOG')
	menu:SetClampedToScreen(true)
	self.tabSettingsMenu = menu
	return menu
end

function Bags:ToggleTabSettings(view, data)
	local menu = data and self:GetTabSettingsMenu()
	if not menu then return end

	if menu:IsShown() and menu.selectedTabData and menu.selectedTabData.ID == data.ID then
		menu:Hide()
		return
	end

	menu.selectedTabData = data
	menu:ClearAllPoints()
	menu:SetPoint('TOPLEFT', view.frame, 'TOPRIGHT', 4, 0)
	if menu:IsShown() then
		menu:Update()
	else
		menu:Show()
	end
end

--------------------------------------------------------------------------------
-- View frames
--------------------------------------------------------------------------------

function Bags:UpdateTabs(view)
	for index, tab in ipairs(view.tabs) do
		local active = index == view.activeSection
		tab:SetBackdropColor(active and 0.18 or 0.09, active and 0.18 or 0.09, active and 0.18 or 0.09, 1)
		if active then
			tab.text:SetTextColor(1, 0.82, 0.2)
		else
			tab.text:SetTextColor(0.6, 0.6, 0.6)
		end
	end
end

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

	Skin:Panel(frame)

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
	view.header = header
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

	if config.tabbed then
		view.activeSection = 1
		view.tabs = {}
		for index, section in ipairs(config.sections) do
			local tab = CreateFrame('Button', nil, header, 'BackdropTemplate')
			tab:SetSize(74, 20)
			if index == 1 then
				tab:SetPoint('LEFT', title, 'RIGHT', 12, 0)
			else
				tab:SetPoint('LEFT', view.tabs[index - 1], 'RIGHT', 4, 0)
			end
			tab:SetBackdrop({ bgFile = EDGE_TEXTURE, edgeFile = EDGE_TEXTURE, edgeSize = 1 })
			tab:SetBackdropBorderColor(0, 0, 0, 1)
			tab.text = tab:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
			tab.text:SetPoint('CENTER')
			tab.text:SetText(section.tabName or section.label)
			tab:SetScript('OnClick', function()
				view.activeSection = index
				self:UpdateTabs(view)
				self:Layout(view)
				self:UpdateAll(view)
			end)
			view.tabs[index] = tab
		end
		self:UpdateTabs(view)
	end

	local close = CreateFrame('Button', nil, header, 'UIPanelCloseButton')
	close:SetPoint('RIGHT', -2, 0)
	close:SetScript('OnClick', function() frame:Hide() end)

	local sort = CreateFrame('Button', nil, header, 'UIPanelButtonTemplate')
	sort:SetSize(50, 20)
	sort:SetPoint('RIGHT', close, 'LEFT', -4, 0)
	sort:SetText('Sort')
	sort:SetScript('OnClick', config.sortFunc)
	view.sortButton = sort

	local search = CreateFrame('EditBox', config.frameName .. 'SearchBox', header, 'SearchBoxTemplate')
	search:SetSize(150, 20)
	search:SetPoint('RIGHT', sort, 'LEFT', -10, 0)
	search:SetAutoFocus(false)
	search:HookScript('OnTextChanged', function(box)
		view.searchQuery = strtrim(box:GetText() or ''):lower()
		self:ApplySearch(view)
	end)
	view.searchBox = search

	if config.categories and self.CreateCategoryToggle then
		self:CreateCategoryToggle(view)
	end

	self:CreateBagBar(view)

	-- footer
	view.freeText = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
	view.freeText:SetPoint('BOTTOMLEFT', FRAME_PADDING, FRAME_PADDING)

	if config.isBank then
		-- purchases the next tab of whichever bank is active. PurchaseBankTab
		-- is protected: a popup opened from addon code is tainted and its
		-- accept gets blocked. Blizzard's script template opens the popup
		-- securely and takes the bank type from the 'overrideBankType'
		-- attribute (set in UpdateFooter), so the click handler stays theirs.
		local buy = CreateFrame('Button', nil, frame,
			'UIPanelButtonTemplate, BankPanelPurchaseButtonScriptTemplate')
		buy:SetSize(150, 20)
		buy:SetPoint('BOTTOMRIGHT', -FRAME_PADDING, FRAME_PADDING - 2)
		buy:Hide()
		view.buyTabButton = buy
	else
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
			-- sections may share bags (reagent-flagged tabs); never reset
			view.slots[bagID] = view.slots[bagID] or {}
			self.viewByBagID[bagID] = view
			if view.bagHolders and not view.bagHolders[bagID] then
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
		view.hoverBag = nil
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
		for _, view in ipairs(self.views) do -- bank too: its bags can change size
			if view.frame:IsShown() then
				self:Layout(view)
				self:UpdateAll(view)
			end
		end
	elseif event == 'BAG_UPDATE' then
		local view = self.viewByBagID[arg1]
		if view and view.frame:IsShown() then
			Sets:MarkDirty() -- an item may have moved; set locations follow it
			self:UpdateBag(view, arg1)
			-- in the category view a slot may now hold an item of another
			-- block; BAG_UPDATE_DELAYED doesn't fire on every client
			if self.IsCategoryMode and self:IsCategoryMode(view)
				and self:CategoriesChanged(view, arg1) then
				self:QueueCategoryLayout(view)
			end
		end
	elseif event == 'BAG_UPDATE_DELAYED' then
		-- in the category view an item that changed may belong to another group
		for _, view in ipairs(self.views) do
			if view.frame:IsShown() and self.IsCategoryMode and self:IsCategoryMode(view) then
				self:Layout(view)
			end
		end
		self:UpdateShownViews()
	elseif event == 'PLAYER_EQUIPMENT_CHANGED' or event == 'LEARNED_SPELL_IN_TAB'
		or event == 'LEARNED_SPELL_IN_SKILL_LINE' then
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

--------------------------------------------------------------------------------
-- Quest reward arrows (same upgrade rules as bag slots)
--------------------------------------------------------------------------------

local function GetRewardItem(button)
	local index = button:GetID()
	local rewardType = button.type -- 'choice' or 'reward'
	if not (index and rewardType) then return end

	local link, isUsable
	if _G.QuestInfoFrame and _G.QuestInfoFrame.questLog then
		link = GetQuestLogItemLink(rewardType, index)
		local getInfo = rewardType == 'choice' and GetQuestLogChoiceInfo or GetQuestLogRewardInfo
		if getInfo then isUsable = select(5, getInfo(index)) end
	else
		link = GetQuestItemLink(rewardType, index)
		isUsable = select(5, GetQuestItemInfo(rewardType, index))
	end
	return link, isUsable ~= false
end

local function UpdateRewardButton(button)
	local icon = button.Icon or (button:GetName() and _G[button:GetName() .. 'IconTexture'])
	local arrow = GetArrow(button, icon)
	if not arrow then return end

	local isUpgrade = false
	if button:IsShown() and (button.objectType == nil or button.objectType == 'item') then
		local link, usable = GetRewardItem(button)
		isUpgrade = usable and IsLinkUpgrade(link)
	end
	arrow:SetShown(isUpgrade)
end

local function UpdateQuestRewards()
	for _, frameName in next, { 'QuestInfoRewardsFrame', 'MapQuestInfoRewardsFrame' } do
		local rewards = _G[frameName]
		for _, button in next, rewards and rewards.RewardButtons or {} do
			UpdateRewardButton(button)
		end
	end
end

function Bags:HookQuestRewards()
	if QuestInfo_Display then
		hooksecurefunc('QuestInfo_Display', UpdateQuestRewards)
	end
end

--------------------------------------------------------------------------------
-- Loot roll arrows
--------------------------------------------------------------------------------

local function UpdateLootRollFrame(frame)
	local iconFrame = frame.IconFrame
	local icon = iconFrame and (iconFrame.Icon or _G[iconFrame:GetName() and iconFrame:GetName() .. 'Icon'])
	local arrow = GetArrow(iconFrame or frame, icon)
	if not arrow then return end

	local rollID = frame.rollID
	local link = rollID and frame:IsShown() and GetLootRollItemLink(rollID)
	arrow:SetShown(IsLinkUpgrade(link, function()
		if not (C_TooltipInfo and C_TooltipInfo.GetLootRollItem) then return true end
		return not HasRedLine(C_TooltipInfo.GetLootRollItem(rollID))
	end))
end

local function UpdateLootRolls()
	for i = 1, NUM_GROUP_LOOT_FRAMES or 4 do
		local frame = _G['GroupLootFrame' .. i]
		if frame then UpdateLootRollFrame(frame) end
	end
end

function Bags:HookLootRolls()
	for i = 1, NUM_GROUP_LOOT_FRAMES or 4 do
		local frame = _G['GroupLootFrame' .. i]
		if frame then frame:HookScript('OnShow', UpdateLootRollFrame) end
	end
	if GroupLootFrame_OpenNewFrame then
		hooksecurefunc('GroupLootFrame_OpenNewFrame', UpdateLootRolls)
	end
end

-- pieces the per-client bank variants (BagsForever.lua) build on
Bags.isForever = IS_FOREVER
Bags.CHARACTER_BANK_BAGS = CHARACTER_BANK_BAGS
Bags.BAR_SIZE = BAR_SIZE
Bags.BAR_SPACING = BAR_SPACING
Bags.StyleBarButton = StyleBarButton
Bags.CountFree = CountFree
Bags.REAGENT_BAG = REAGENT_BAG
Bags.HEADER_HEIGHT = HEADER_HEIGHT
Bags.BAR_HEIGHT = BAR_HEIGHT
Bags.FRAME_PADDING = FRAME_PADDING
Bags.FOOTER_HEIGHT = FOOTER_HEIGHT

function Bags:OnInit()
	self.db = BenisUI.db.bags
	self.views = {}
	self.viewByBagID = {}

	-- migrate earlier defaults (24: stacked layout, 14: first tabbed layout)
	if self.db.bankColumns == 24 or self.db.bankColumns == 14 then
		self.db.bankColumns = 21
	end

	self.inventory = self:CreateView({
		frameName = 'BenisUI_BagFrame',
		title = '|cff1784d1Benis|rUI Inventory',
		isBank = false,
		categories = true, -- category view toggle (BagsCategories.lua)
		columns = self.db.columns,
		slotSize = self.db.slotSize,
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

	local bankConfig = {
		frameName = 'BenisUI_BankFrame',
		title = '|cff1784d1Benis|rUI',
		isBank = true,
		tabbed = true,
		columns = self.db.bankColumns,
		slotSize = self.db.bankSlotSize,
		positionKey = 'bankPosition',
		defaultPosition = { point = 'TOPLEFT', x = 50, y = -80 },
		sections = {
			{ label = 'Bank', tabName = 'Bank', bags = CHARACTER_BANK_BAGS,
				excludeReagents = true,
				bankType = Enum.BankType and Enum.BankType.Character or 0 },
			{ label = 'Warband Bank', tabName = 'Warband', bags = WARBAND_BANK_BAGS,
				excludeReagents = true,
				bankType = Enum.BankType and Enum.BankType.Account or 2 },
			{ label = 'Reagents', tabName = 'Reagents', bags = ALL_BANK_BAGS,
				onlyReagents = true },
		},
		sortFunc = function()
			C_Container.SortBankBags()
			C_Container.SortAccountBankBags()
		end,
		onHidden = function()
			local menu = Bags.tabSettingsMenu
			if menu and menu:IsShown() then
				menu:Hide()
			end
			if Bags.bankIsOpen then
				CloseBank()
			end
		end,
	}
	-- per-client bank variants (BagsForever.lua) reshape the view here
	if self.CustomizeBankConfig then
		self:CustomizeBankConfig(bankConfig)
	end
	self.bank = self:CreateView(bankConfig)

	DisableBlizzardBags()
	self:HookOpenClose()
	self:HookQuestRewards()
	self:HookLootRolls()

	local listener = CreateFrame('Frame')
	for _, event in ipairs(BAG_EVENTS) do
		listener:RegisterEvent(event)
	end
	-- learning a skill (mail at 40) changes the best armor type; the event was
	-- renamed on retail, so register whichever this client has
	for _, event in ipairs({ 'LEARNED_SPELL_IN_TAB', 'LEARNED_SPELL_IN_SKILL_LINE' }) do
		pcall(listener.RegisterEvent, listener, event)
	end
	listener:SetScript('OnEvent', function(_, event, ...)
		self:OnEvent(event, ...)
	end)
end
