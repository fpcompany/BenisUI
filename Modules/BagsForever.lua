local _, ns = ...
local BenisUI = ns.BenisUI

-- WoW Forever (Camelot) bank variant of the Bags module.
--
-- Forever runs the modern bank API with vanilla rules: there is no warband
-- bank and no reagent tabs, and a "bank tab" is a bag slot. Tab 1 is the base
-- bank; tabs 2..N are purchased slots that each hold a bag item, stored in the
-- Characterbanktab pseudo-container at slot <tab index>. So instead of
-- retail's Bank/Warband/Reagents tabs and tab-settings buttons, the bank is a
-- single section with a row of bag slots.
local Bags = BenisUI:GetModule('Bags')
if not (Bags and Bags.isForever) then return end

local BagIndex = Enum.BagIndex
local BANK_TYPE = Enum.BankType and Enum.BankType.Character or 0
local BANK_BAG_CONTAINER = BagIndex.Characterbanktab or -2 -- holds the bank's bag items
local BANK_BAGS = Bags.CHARACTER_BANK_BAGS -- [tab index] = container ID

local BAR_SIZE, BAR_SPACING = Bags.BAR_SIZE, Bags.BAR_SPACING
local EMPTY_BAG_ICON = 'Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag'

Bags.buyTabLabel = 'Buy Bag Slot'

function Bags:CustomizeBankConfig(config)
	config.title = '|cff1784d1Benis|rUI Bank'
	config.tabbed = false
	config.sections = {
		{ bags = BANK_BAGS, bankType = BANK_TYPE },
	}
	config.sortFunc = function() C_Container.SortBankBags() end
end

function Bags:UpdateBankFreeText(view)
	local free, total = Bags.CountFree(BANK_BAGS)
	view.freeText:SetFormattedText('%d/%d free', free, total)
end

--------------------------------------------------------------------------------
-- Bank bag slots
--------------------------------------------------------------------------------

local function ShowBagTooltip(button)
	GameTooltip:SetOwner(button, 'ANCHOR_TOP')
	if not button.purchased then
		GameTooltip:SetText(BANK_BAG_PURCHASE or 'Purchasable bag slot')
	elseif not GameTooltip:SetBagItem(BANK_BAG_CONTAINER, button.index) then
		GameTooltip:SetText(BANK_BAG or 'Bank bag slot')
	end
	GameTooltip:Show()
end

-- picks the bag up, or drops the held bag / swaps with it
local function PickupBag(button)
	if button.purchased then
		C_Container.PickupContainerItem(BANK_BAG_CONTAINER, button.index)
	end
end

local function CreateBagButton(view, index)
	local button = CreateFrame('Button', nil, view.bar)
	button:SetSize(BAR_SIZE, BAR_SIZE)
	-- slot 1 is the base bank and has no bag, so the row starts at index 2
	button:SetPoint('LEFT', view.bar, 'LEFT', (index - 2) * (BAR_SIZE + BAR_SPACING), 0)
	button:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
	button:RegisterForDrag('LeftButton')
	button.index = index

	button.icon = button:CreateTexture(nil, 'ARTWORK')
	button.icon:SetAllPoints()
	Bags.StyleBarButton(button, button.icon)

	button:SetScript('OnEnter', function(b)
		ShowBagTooltip(b)
		Bags:SetHoverBag(view, b.purchased and BANK_BAGS[b.index] or nil)
	end)
	button:SetScript('OnLeave', function()
		GameTooltip:Hide()
		Bags:SetHoverBag(view, nil)
	end)
	button:SetScript('OnClick', PickupBag)
	button:SetScript('OnDragStart', PickupBag)
	button:SetScript('OnReceiveDrag', PickupBag)

	view.bagButtons[index] = button
	return button
end

function Bags:UpdateBankBar(view)
	view.bagButtons = view.bagButtons or {}

	local maxSlots = math.min(C_Bank.FetchMaxNumBankTabs(BANK_TYPE) or 0, #BANK_BAGS)
	local numPurchased = C_Bank.FetchNumPurchasedBankTabs(BANK_TYPE) or 0

	for index = 2, maxSlots do
		local button = view.bagButtons[index] or CreateBagButton(view, index)
		button.purchased = index <= numPurchased

		local icon
		if button.purchased then
			local location = ItemLocation:CreateFromBagAndSlot(BANK_BAG_CONTAINER, index)
			icon = C_Item.DoesItemExist(location) and C_Item.GetItemIcon(location)
		end
		button.icon:SetTexture(icon or EMPTY_BAG_ICON)
		button.icon:SetDesaturated(not button.purchased)
		if button.purchased then
			button.icon:SetVertexColor(1, 1, 1)
		else
			button.icon:SetVertexColor(0.6, 0.15, 0.15) -- not bought yet
		end
		button:Show()

		if GameTooltip:IsOwned(button) then
			ShowBagTooltip(button)
		end
	end
	for index, button in pairs(view.bagButtons) do
		if index > maxSlots then button:Hide() end
	end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

-- equipping, swapping or removing a bank bag changes the slot layout, which
-- the shared handler only refreshes item contents for
local listener = CreateFrame('Frame')
listener:RegisterEvent('PLAYERBANKSLOTS_CHANGED')
listener:SetScript('OnEvent', function()
	local view = Bags.bank
	if view and view.frame:IsShown() then
		Bags:Layout(view)
		Bags:UpdateAll(view)
	end
end)
