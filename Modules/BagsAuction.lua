local _, ns = ...
local BenisUI = ns.BenisUI

-- Auction filter for the inventory: a checkbox in the title bar greys out
-- every item that earns less than MIN_PROFIT more on the auction house (after
-- the auction house cut) than it sells for at a vendor. Auction prices come
-- from Auctionator; bound items and items Auctionator has no price for can't
-- be auctioned, so they're greyed out too.
local Bags = BenisUI:GetModule('Bags')
if not Bags then return end

local MIN_PROFIT = 100 -- copper, per item
local AH_CUT = 0.05

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

local function AuctionatorAPI()
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if api and api.GetAuctionPriceByItemID then return api end
end

local function AuctionPrice(api, link, itemID)
	-- gear prices depend on item level, so prefer the link
	if link and api.GetAuctionPriceByItemLink then
		local ok, price = pcall(api.GetAuctionPriceByItemLink, 'BenisUI', link)
		if ok and type(price) == 'number' and price > 0 then return price end
	end
	local ok, price = pcall(api.GetAuctionPriceByItemID, 'BenisUI', itemID)
	if ok and type(price) == 'number' and price > 0 then return price end
end

function Bags:IsAuctionFilterOn(view)
	return view.config.auctionFilter and BenisUI.chardb.bags.auctionFilter or false
end

-- true when the filter is on and the item isn't worth auctioning
function Bags:SlotIsUnprofitable(slot)
	if not (slot.itemID and self:IsAuctionFilterOn(slot.view)) then return false end
	if slot.isBound then return true end

	local api = AuctionatorAPI()
	if not api then return false end -- no data: grey nothing rather than everything

	local auction = AuctionPrice(api, slot.itemLink, slot.itemID)
	if not auction then return true end

	local vendor = select(11, GetItemInfo(slot.itemLink or slot.itemID)) or 0
	return auction * (1 - AH_CUT) - vendor < MIN_PROFIT
end

local function ShowTooltip(check)
	GameTooltip:SetOwner(check, 'ANCHOR_BOTTOM')
	GameTooltip:SetText('Auction filter')
	GameTooltip:AddLine(string.format(
		'Grey out items that make less than %s more on the auction house '
			.. '(after the %d%% cut) than at a vendor.',
		GetMoneyString(MIN_PROFIT, true), AH_CUT * 100), 1, 1, 1, true)
	if not AuctionatorAPI() then
		GameTooltip:AddLine('Auctionator is not loaded.', 1, 0.2, 0.2, true)
	end
	GameTooltip:Show()
end

function Bags:CreateAuctionFilter(view)
	local check = CreateFrame('CheckButton', nil, view.header, 'UICheckButtonTemplate')
	check:SetSize(22, 22)
	check:SetPoint('RIGHT', view.searchBox, 'LEFT', -24, 0)
	check:SetChecked(self:IsAuctionFilterOn(view))

	local label = check:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
	label:SetPoint('LEFT', check, 'RIGHT', 0, 1)
	label:SetText('AH')

	check:SetScript('OnClick', function(c)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
		BenisUI.chardb.bags.auctionFilter = c:GetChecked() and true or false
		self:ApplySearch(view)
	end)
	check:SetScript('OnEnter', ShowTooltip)
	check:SetScript('OnLeave', GameTooltip_Hide)

	view.auctionFilterCheck = check
end

-- re-grey when Auctionator finishes a scan; item info that wasn't cached yet
-- (vendor price) is covered by the regular bag updates
local function RegisterForPriceUpdates()
	local api = AuctionatorAPI()
	if not (api and api.RegisterForDBUpdate) then return end
	pcall(api.RegisterForDBUpdate, 'BenisUI', function()
		local view = Bags.inventory
		if view and view.frame:IsShown() and Bags:IsAuctionFilterOn(view) then
			Bags:ApplySearch(view)
		end
	end)
end

local loader = CreateFrame('Frame')
loader:RegisterEvent('PLAYER_LOGIN')
loader:SetScript('OnEvent', function(self)
	self:UnregisterEvent('PLAYER_LOGIN')
	RegisterForPriceUpdates()
end)
