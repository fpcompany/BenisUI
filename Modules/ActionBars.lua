local _, ns = ...
local BenisUI = ns.BenisUI

-- Flat ElvUI-style skin for the Blizzard action bars: cropped icons with a
-- 1px black border, no slot/frame art, no gryphons, clean hotkey/count fonts.
-- Bar layout and paging stay with Blizzard (Edit Mode still works).
local ActionBars = BenisUI:RegisterModule('ActionBars')

local FONT = BenisUI.media.font
local TEXTURE = BenisUI.media.texture

local BUTTON_GROUPS = {
	{ prefix = 'ActionButton', count = 12 },
	{ prefix = 'MultiBarBottomLeftButton', count = 12 },
	{ prefix = 'MultiBarBottomRightButton', count = 12 },
	{ prefix = 'MultiBarRightButton', count = 12 },
	{ prefix = 'MultiBarLeftButton', count = 12 },
	{ prefix = 'MultiBar5Button', count = 12 },
	{ prefix = 'MultiBar6Button', count = 12 },
	{ prefix = 'MultiBar7Button', count = 12 },
	{ prefix = 'StanceButton', count = 10 },
	{ prefix = 'PetActionButton', count = 10 },
}

-- Blizzard re-applies slot art through UpdateButtonArt; keep it stripped
local function StripArt(button)
	local normal = button:GetNormalTexture()
	if normal then normal:SetAlpha(0) end
	if button.SlotArt then button.SlotArt:SetAlpha(0) end
	if button.SlotBackground then button.SlotBackground:SetAlpha(0) end
end

local function SkinButton(button, name)
	if not button or button.BenisUISkinned then return end
	button.BenisUISkinned = true

	local icon = button.icon or _G[name .. 'Icon']
	if icon then
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		if button.IconMask and icon.RemoveMaskTexture then
			icon:RemoveMaskTexture(button.IconMask)
		end
	end

	StripArt(button)
	if button.UpdateButtonArt then
		hooksecurefunc(button, 'UpdateButtonArt', StripArt)
	end

	local pushed = button:GetPushedTexture()
	if pushed then pushed:SetColorTexture(1, 1, 1, 0.15) end
	local highlight = button:GetHighlightTexture()
	if highlight then highlight:SetColorTexture(1, 1, 1, 0.15) end
	local checked = button:GetCheckedTexture()
	if checked then checked:SetColorTexture(1, 1, 1, 0.2) end

	if button.Border then button.Border:SetAlpha(0) end
	if button.Name then button.Name:SetAlpha(0) end -- macro names

	if button.HotKey then
		button.HotKey:SetFont(FONT, 11, 'OUTLINE')
		button.HotKey:ClearAllPoints()
		button.HotKey:SetPoint('TOPRIGHT', -2, -2)
	end
	if button.Count then
		button.Count:SetFont(FONT, 13, 'OUTLINE')
	end

	local border = CreateFrame('Frame', nil, button, 'BackdropTemplate')
	if icon then
		border:SetPoint('TOPLEFT', icon, -1, 1)
		border:SetPoint('BOTTOMRIGHT', icon, 1, -1)
	else
		border:SetAllPoints()
	end
	border:SetBackdrop({ edgeFile = TEXTURE, edgeSize = 1 })
	border:SetBackdropBorderColor(0, 0, 0, 1)
end

local function HideBarArt()
	local bar = _G.MainMenuBar
	if not bar then return end

	for _, key in next, { 'EndCaps', 'BorderArt', 'Background' } do
		local art = bar[key]
		if art then
			art:SetAlpha(0)
			if art.Hide then art:Hide() end
		end
	end
end

function ActionBars:OnInit()
	HideBarArt()

	for _, group in next, BUTTON_GROUPS do
		for i = 1, group.count do
			local name = group.prefix .. i
			SkinButton(_G[name], name)
		end
	end
end
