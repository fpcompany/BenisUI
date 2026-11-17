local _, ns = ...
local BenisUI = ns.BenisUI

-- Item counts across characters for the item tooltip: every character's bags
-- and bank are snapshotted into the account-wide saved variables, so hovering
-- an item shows how many this character, its bank and the alts on the realm
-- hold. The bank can only be read while it is open, so its snapshot is from
-- the last visit; an alt's numbers are from its last login.
local ItemCounts = BenisUI:RegisterModule('ItemCounts')

local GetContainerNumSlots = C_Container.GetContainerNumSlots
local GetContainerItemInfo = C_Container.GetContainerItemInfo
local GetItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount

local BagIndex = Enum.BagIndex
local NUM_BAGS = NUM_TOTAL_EQUIPPED_BAG_SLOTS or 5 -- held bags + reagent bag

local function CollectBags(prefix)
	local bags, index = {}, 1
	while BagIndex[prefix .. index] do
		bags[#bags + 1] = BagIndex[prefix .. index]
		index = index + 1
	end
	return bags
end

local CARRIED_BAGS = {}
for bagID = BagIndex.Backpack, NUM_BAGS do
	CARRIED_BAGS[#CARRIED_BAGS + 1] = bagID
end
local BANK_BAGS = CollectBags('CharacterBankTab_')
local WARBAND_BAGS = CollectBags('AccountBankTab_') -- retail only, empty elsewhere

local bagLookup = {} -- [bagID] = 'bags' / 'bank' / 'warband'
for _, bagID in ipairs(CARRIED_BAGS) do bagLookup[bagID] = 'bags' end
for _, bagID in ipairs(BANK_BAGS) do bagLookup[bagID] = 'bank' end
for _, bagID in ipairs(WARBAND_BAGS) do bagLookup[bagID] = 'warband' end

local playerName, realmData, charData
local bankIsOpen = false

-- [itemID] = count over the given containers
local function Scan(bags)
	local counts = {}
	for _, bagID in ipairs(bags) do
		for slotID = 1, GetContainerNumSlots(bagID) or 0 do
			local info = GetContainerItemInfo(bagID, slotID)
			if info and info.itemID then
				counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
			end
		end
	end
	return counts
end

--------------------------------------------------------------------------------
-- Snapshots
--------------------------------------------------------------------------------

local dirty = {} -- [kind] = true, rescanned together on a short delay
local pending = false

local function Flush()
	pending = false
	if dirty.bags then
		charData.bags = Scan(CARRIED_BAGS)
	end
	-- bank containers read as empty while the bank is closed: never save that
	if bankIsOpen then
		if dirty.bank then
			charData.bank = Scan(BANK_BAGS)
		end
		if dirty.warband and #WARBAND_BAGS > 0 then
			BenisUI.db.itemCounts.warband = Scan(WARBAND_BAGS)
		end
	end
	wipe(dirty)
end

local function MarkDirty(kind)
	dirty[kind] = true
	if not pending then
		pending = true
		C_Timer.After(0.5, Flush)
	end
end

local events = {
	BAG_UPDATE = function(bagID)
		local kind = bagLookup[bagID]
		if kind then MarkDirty(kind) end
	end,
	BANKFRAME_OPENED = function()
		bankIsOpen = true
		MarkDirty('bank')
		MarkDirty('warband')
	end,
	BANKFRAME_CLOSED = function()
		Flush() -- catch changes made right before closing
		bankIsOpen = false
	end,
	PLAYER_LOGOUT = function() Flush() end, -- a pending rescan would be lost
	PLAYERBANKSLOTS_CHANGED = function() MarkDirty('bank') end,
	PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED = function() MarkDirty('warband') end,
}

function ItemCounts:OnInit()
	local db = BenisUI.db.itemCounts
	local realm = GetRealmName()
	playerName = UnitName('player')
	db.realms[realm] = db.realms[realm] or {}
	realmData = db.realms[realm]

	charData = realmData[playerName] or {}
	realmData[playerName] = charData
	charData.class = select(2, UnitClass('player'))
	charData.bags = charData.bags or {}
	charData.bank = charData.bank or {}
	MarkDirty('bags')

	local frame = CreateFrame('Frame')
	for event in pairs(events) do
		pcall(frame.RegisterEvent, frame, event) -- some events are retail only
	end
	frame:SetScript('OnEvent', function(_, event, ...)
		events[event](...)
	end)
end

--------------------------------------------------------------------------------
-- Tooltip
--------------------------------------------------------------------------------

local LABEL = { 1, 0.82, 0 } -- tooltip gold
local VALUE = { 1, 1, 1 }

local function ClassColor(class)
	local color = class and (C_ClassColor and C_ClassColor.GetClassColor(class)
		or RAID_CLASS_COLORS[class])
	if color then return color.r, color.g, color.b end
	return LABEL[1], LABEL[2], LABEL[3]
end

local function AddCount(tooltip, label, text, r, g, b)
	tooltip:AddDoubleLine(label, text, r or LABEL[1], g or LABEL[2], b or LABEL[3],
		VALUE[1], VALUE[2], VALUE[3])
end

local function Describe(bags, bank)
	if bags > 0 and bank > 0 then
		return string.format('%d  (bags %d, bank %d)', bags + bank, bags, bank)
	elseif bank > 0 then
		return string.format('%d  (bank)', bank)
	end
	return tostring(bags)
end

-- adds the count lines for an item; returns nothing when no one holds it
function ItemCounts:AddTooltipLines(tooltip, itemID)
	if not charData then return end

	-- this character's bags are read live, everything else from snapshots
	local bags = GetItemCount(itemID) or 0
	local bank = charData.bank[itemID] or 0
	local total = bags + bank
	local sources = (bags > 0 and 1 or 0) + (bank > 0 and 1 or 0)

	if bags > 0 then AddCount(tooltip, 'Total in bags:', bags) end
	if bank > 0 then AddCount(tooltip, 'In bank:', bank) end

	local alts = {}
	for name, data in pairs(realmData) do
		if name ~= playerName then
			local altBags = data.bags and data.bags[itemID] or 0
			local altBank = data.bank and data.bank[itemID] or 0
			if altBags + altBank > 0 then
				alts[#alts + 1] = { name = name, class = data.class, bags = altBags, bank = altBank }
			end
		end
	end
	table.sort(alts, function(a, b) return a.name < b.name end)
	for _, alt in ipairs(alts) do
		AddCount(tooltip, alt.name, Describe(alt.bags, alt.bank), ClassColor(alt.class))
		total = total + alt.bags + alt.bank
		sources = sources + 1
	end

	local warband = BenisUI.db.itemCounts.warband[itemID] or 0
	if warband > 0 then
		AddCount(tooltip, 'Warband bank:', warband)
		total = total + warband
		sources = sources + 1
	end

	if sources > 1 then
		AddCount(tooltip, 'Total:', total)
	end

	self:AddPriceLines(tooltip, itemID, total)
end

--------------------------------------------------------------------------------
-- Prices
--------------------------------------------------------------------------------

-- Auctionator already shows the per-item vendor and auction price; these lines
-- add what everything held is worth.
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

local function AuctionPrice(itemID)
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if not (api and api.GetAuctionPriceByItemID) then return end
	local ok, price = pcall(api.GetAuctionPriceByItemID, 'BenisUI', itemID)
	if ok and type(price) == 'number' and price > 0 then return price end
end

local function AddMoney(tooltip, label, copper)
	AddCount(tooltip, label, GetMoneyString(copper, true))
end

function ItemCounts:AddPriceLines(tooltip, itemID, total)
	local sellPrice = select(11, GetItemInfo(itemID))
	local auction = AuctionPrice(itemID)

	if total > 1 then
		if sellPrice and sellPrice > 0 then
			AddMoney(tooltip, string.format('Vendor total (%d):', total), sellPrice * total)
		end
		if auction then
			AddMoney(tooltip, string.format('Auction total (%d):', total), auction * total)
		end
	end
end
