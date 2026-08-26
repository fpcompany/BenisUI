local ADDON_NAME, ns = ...

local BenisUI = {}
ns.BenisUI = BenisUI
_G.BenisUI = BenisUI

BenisUI.modules = {}

BenisUI.media = {
	font = 'Interface\\AddOns\\BenisUI\\Media\\Expressway.ttf',
	texture = 'Interface\\Buttons\\WHITE8X8',
}

function BenisUI:RegisterModule(name)
	local module = {}
	self.modules[name] = module
	return module
end

function BenisUI:GetModule(name)
	return self.modules[name]
end

local defaults = {
	bags = {
		columns = 12,
		bankColumns = 21,
		slotSize = 37,
		bankSlotSize = 36,
		spacing = 4,
		position = nil, -- { point = 'BOTTOMRIGHT', x = -50, y = 120 }
		bankPosition = nil,
	},
	unitframes = {
		positions = {}, -- [unit] = { point, x, y }
	},
	consumables = {
		position = nil, -- { point = 'BOTTOMRIGHT', x, y }
	},
}

-- per-character settings (equipment set IDs are per-character)
local charDefaults = {
	bags = {
		setHighlights = {}, -- [setID] = { enabled = bool, r, g, b (nil = quality color) }
	},
}

local function CopyDefaults(src, dst)
	if type(dst) ~= 'table' then dst = {} end
	for key, value in pairs(src) do
		if type(value) == 'table' then
			dst[key] = CopyDefaults(value, dst[key])
		elseif dst[key] == nil then
			dst[key] = value
		end
	end
	return dst
end

local loader = CreateFrame('Frame')
loader:RegisterEvent('ADDON_LOADED')
loader:RegisterEvent('PLAYER_LOGIN')
loader:SetScript('OnEvent', function(_, event, arg1)
	if event == 'ADDON_LOADED' and arg1 == ADDON_NAME then
		BenisUIDB = CopyDefaults(defaults, BenisUIDB)
		BenisUI.db = BenisUIDB
		BenisUICharDB = CopyDefaults(charDefaults, BenisUICharDB)
		BenisUI.chardb = BenisUICharDB
	elseif event == 'PLAYER_LOGIN' then
		for _, module in pairs(BenisUI.modules) do
			if module.OnInit then module:OnInit() end
		end
	end
end)

SLASH_BENISUI1 = '/benisui'
SLASH_BENISUI2 = '/bui'
SlashCmdList.BENISUI = function()
	ToggleAllBags()
end
