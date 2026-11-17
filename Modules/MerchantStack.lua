local _, ns = ...
local BenisUI = ns.BenisUI

-- Shift + right-click an item at a merchant buys a full stack right away,
-- skipping the quantity window. The amount is capped by the merchant's
-- stock and by what you can afford (gold and currency/item costs).
local MerchantStack = BenisUI:RegisterModule('MerchantStack')

-- price is for one purchase of `stackCount` items (e.g. 5 per click)
local function ItemInfo(index)
	if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
		local info = C_MerchantFrame.GetItemInfo(index)
		if info then
			return info.price, info.stackCount, info.numAvailable, info.isPurchasable, info.hasExtendedCost
		end
	end
	if GetMerchantItemInfo then
		local _, _, price, stackCount, numAvailable, isPurchasable, _, extendedCost = GetMerchantItemInfo(index)
		return price, stackCount, numAvailable, isPurchasable, extendedCost
	end
end

local function OwnedCost(link)
	if link and link:find('currency:') then
		local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfoFromLink(link)
		return info and info.quantity
	elseif link then
		local getCount = (C_Item and C_Item.GetItemCount) or GetItemCount
		return getCount(link)
	end
	-- honor/arena points on old clients come with no link
	return nil
end

-- how many purchases (of stackCount items each) the extended cost allows
local function AffordableExtended(index)
	local limit = math.huge
	for i = 1, (GetMerchantItemCostInfo(index) or 0) do
		local _, value, link = GetMerchantItemCostItem(index, i)
		local owned = OwnedCost(link)
		if value and value > 0 and owned then
			limit = math.min(limit, math.floor(owned / value))
		end
	end
	return limit
end

local function BuyStack(index)
	local price, stackCount, numAvailable, isPurchasable, extendedCost = ItemInfo(index)
	if not price or isPurchasable == false then return end
	stackCount = math.max(stackCount or 1, 1)

	local amount = GetMerchantItemMaxStack(index) or stackCount
	if numAvailable and numAvailable >= 0 then
		amount = math.min(amount, numAvailable * stackCount)
	end
	if price > 0 then
		amount = math.min(amount, math.floor(GetMoney() / price) * stackCount)
	end
	if extendedCost then
		amount = math.min(amount, AffordableExtended(index) * stackCount)
	end
	-- whole purchases only
	amount = math.floor(amount / stackCount) * stackCount
	if amount < 1 then
		UIErrorsFrame:AddMessage(ERR_NOT_ENOUGH_MONEY or 'Not enough money', 1, 0.1, 0.1)
		return
	end
	BuyMerchantItem(index, amount)
end

local function HookButton(button)
	if not button or button.buiStackHooked then return end
	button.buiStackHooked = true
	local original = button:GetScript('OnClick')
	button:SetScript('OnClick', function(self, mouse, ...)
		if mouse == 'RightButton' and IsShiftKeyDown()
			and MerchantFrame and MerchantFrame.selectedTab == 1 then
			if StackSplitFrame and StackSplitFrame:IsShown() then StackSplitFrame:Hide() end
			BuyStack(self:GetID())
			return
		end
		if original then return original(self, mouse, ...) end
	end)
end

local function HookAll()
	for index = 1, MERCHANT_ITEMS_PER_PAGE or 10 do
		HookButton(_G['MerchantItem' .. index .. 'ItemButton'])
	end
end

function MerchantStack:OnInit()
	HookAll()
	-- buttons may be created later on some clients
	local events = CreateFrame('Frame')
	events:RegisterEvent('MERCHANT_SHOW')
	events:SetScript('OnEvent', HookAll)
end
