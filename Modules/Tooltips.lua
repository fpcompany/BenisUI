local _, ns = ...
local BenisUI = ns.BenisUI

-- Spell and item IDs on tooltips, the way ElvUI does it on retail:
-- * spells/macros/items via TooltipDataProcessor post calls; items also get
--   their counts in bags, bank and on alts
-- * auras via Blizzard's tooltipShowAuraSpellIDs CVar -- aura data can be
--   secret in Midnight, so the native display is the reliable path
-- * spell chat links via SetItemRef
local Tooltips = BenisUI:RegisterModule('Tooltips')

local ID_FORMAT = '|cffca3c3c' .. (ID or 'ID') .. ':|r %d'

local function AddIDLine(tooltip, id)
	tooltip:AddLine(string.format(ID_FORMAT, id))
	tooltip:Show()
end

local function OnTooltipSetSpell(tooltip, data)
	if tooltip ~= GameTooltip or tooltip:IsForbidden() then return end

	local id
	if data and data.type == Enum.TooltipDataType.Spell then
		id = data.id
	elseif data and data.type == Enum.TooltipDataType.Macro then
		local info = tooltip:GetTooltipData()
		local line = info and info.lines and info.lines[1]
		id = line and line.tooltipID
	end

	if id then
		AddIDLine(tooltip, id)
	end
end

local function OnTooltipSetItem(tooltip, data)
	if tooltip:IsForbidden() then return end
	if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
	if data and data.id then
		-- counts in bags, bank and on alts (ItemCounts.lua)
		local counts = BenisUI:GetModule('ItemCounts')
		if counts then
			counts:AddTooltipLines(tooltip, data.id)
		end
		AddIDLine(tooltip, data.id)
	end
end

function Tooltips:OnInit()
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, OnTooltipSetSpell)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Macro, OnTooltipSetSpell)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltipSetItem)

	-- Blizzard resets this to 0 between sessions
	SetCVar('tooltipShowAuraSpellIDs', 1)

	-- clicked spell links open in ItemRefTooltip, which the post call skips
	hooksecurefunc('SetItemRef', function(link)
		local spellID = link and string.match(link, '^spell:(%d+)')
		if spellID and not ItemRefTooltip:IsForbidden() then
			AddIDLine(ItemRefTooltip, spellID)
		end
	end)
end
