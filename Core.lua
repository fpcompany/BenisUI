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
	questAutoComplete = true, -- turn in finished quests (never accepts new ones)
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
	lootRolls = {
		position = nil, -- { point, x, y } of the loot roll panel
	},
	chat = {
		size = nil, -- { width, height } of the main (docked) chat window
		history = {}, -- sent messages, oldest first, without their channel
	},
	nameplates = {
		enabled = true, -- false leaves Blizzard's nameplates alone
		debuffs = true, -- the player's own debuffs above each enemy
		buffs = true, -- buffs your group can dispel, above enemy players
		tank = 'auto', -- threat colours for a tank: 'on' / 'off' / 'auto' (spec or role)
		scale = nil, -- 0.5-3; nil follows the screen height
	},
	itemCounts = { -- item tooltip counts (ItemCounts.lua)
		realms = {}, -- [realm][character] = { class, bags = { [itemID] = n }, bank = {...} }
		warband = {}, -- [itemID] = n, retail warband bank
	},
	focusHighlight = {
		color = { 0.09, 0.52, 0.82 }, -- the BenisUI blue
		thickness = 2,
	},
}

-- per-character settings (equipment set IDs are per-character)
local charDefaults = {
	bags = {
		setHighlights = {}, -- [setID] = { enabled = bool, r, g, b (nil = quality color) }
		categoryMode = false, -- inventory grouped by category instead of bag order
	},
	chat = {
		fontSize = 12, -- every chat window; picking a size in the tab menu updates it
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
SlashCmdList.BENISUI = function(msg)
	local cmd = strtrim(msg or ''):lower()
	if cmd == 'skins' then
		BenisUI.Skin:ReportMissing()
		return
	elseif cmd == 'rolltest' then
		BenisUI:GetModule('LootRolls'):Test()
		return
	elseif cmd == 'autoquest' then
		BenisUI.db.questAutoComplete = not BenisUI.db.questAutoComplete
		print('|cff1784d1Benis|rUI: auto quest turn-in ' .. (BenisUI.db.questAutoComplete and 'on' or 'off'))
		return
	elseif cmd == 'qa' then
		local qa = BenisUI:GetModule('QuestAnnounce')
		qa.debug = not qa.debug
		print('|cff1784d1Benis|rUI: quest announce debug ' .. (qa.debug and 'on' or 'off'))
		return
	elseif cmd == 'plates' or cmd:find('^plates ') then
		BenisUI:GetModule('Nameplates'):Command(cmd:sub(8))
		return
	end

	ToggleAllBags()
end
