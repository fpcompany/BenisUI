local _, ns = ...
local BenisUI = ns.BenisUI

-- Flat ElvUI-style skin for the Blizzard action bars: cropped icons with a
-- 1px black border, no slot/frame art, no gryphons, clean hotkey/count fonts.
-- Bar layout and paging stay with Blizzard (Edit Mode still works).
local ActionBars = BenisUI:RegisterModule('ActionBars')

local FONT = BenisUI.media.font
local Skin = BenisUI.Skin

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

	Skin:Border(button, 1, icon)
end

--------------------------------------------------------------------------------
-- Empty-slot fading
--------------------------------------------------------------------------------

-- bars whose empty slots are invisible until the bar is hovered, a spell is
-- being dragged or Edit Mode is open; stance/pet bars already hide their
-- unused buttons themselves
local FADE_PREFIXES = {
	ActionButton = true,
	MultiBarBottomLeftButton = true,
	MultiBarBottomRightButton = true,
	MultiBarRightButton = true,
	MultiBarLeftButton = true,
	MultiBar5Button = true,
	MultiBar6Button = true,
	MultiBar7Button = true,
}

local fadeBars = {} -- [bar frame] = { buttons }
local gridShown = false -- a spell/item is being dragged
local pollTicker

local function InEditMode()
	return EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive
		and EditModeManagerFrame:IsEditModeActive()
end

local function UpdateBarEmpties(bar, buttons)
	local reveal = bar.BenisUIMouseOver or gridShown or InEditMode()
	for _, button in next, buttons do
		if button.action and not HasAction(button.action) then
			button:SetAlpha(reveal and 1 or 0)
		else
			button:SetAlpha(1)
		end
	end
end

local function UpdateAllEmpties()
	for bar, buttons in pairs(fadeBars) do
		UpdateBarEmpties(bar, buttons)
	end
end

local function OnButtonEnter(button)
	local bar = button:GetParent()
	local buttons = fadeBars[bar]
	if not buttons or bar.BenisUIMouseOver then return end
	bar.BenisUIMouseOver = true
	UpdateBarEmpties(bar, buttons)

	-- OnLeave doesn't fire when the mouse exits through a gap between
	-- buttons, so poll the bar bounds while any bar is revealed
	if not pollTicker then
		pollTicker = C_Timer.NewTicker(0.2, function()
			local active = false
			for pollBar, pollButtons in pairs(fadeBars) do
				if pollBar.BenisUIMouseOver then
					if pollBar:IsMouseOver() then
						active = true
					else
						pollBar.BenisUIMouseOver = nil
						UpdateBarEmpties(pollBar, pollButtons)
					end
				end
			end
			if not active then
				pollTicker:Cancel()
				pollTicker = nil
			end
		end)
	end
end

local function SetupEmptyFade(button, prefix)
	if not button or not FADE_PREFIXES[prefix] then return end
	local bar = button:GetParent()
	if not bar then return end

	local buttons = fadeBars[bar]
	if not buttons then
		buttons = {}
		fadeBars[bar] = buttons
	end
	buttons[#buttons + 1] = button
	button:HookScript('OnEnter', OnButtonEnter)
end

-- the dividers between main bar buttons are pooled NineSlice frames that
-- UpdateDividers re-acquires on every layout pass
local function HideDividers(bar)
	for _, key in next, { 'HorizontalDividersPool', 'VerticalDividersPool' } do
		local pool = bar[key]
		if pool then
			for divider in pool:EnumerateActive() do
				divider:Hide()
			end
		end
	end
end

local function HideBarArt()
	-- retail calls it MainMenuBar; Forever (Camelot) calls it MainActionBar
	local bar = _G.MainActionBar or _G.MainMenuBar
	if not bar then return end

	for _, key in next, { 'EndCaps', 'BorderArt', 'Background' } do
		local art = bar[key]
		if art then
			art:SetAlpha(0)
			if art.Hide then art:Hide() end
		end
	end

	-- Forever's gryphons are their own Edit Mode systems that re-show
	-- themselves on resize/Edit Mode, so keep the caps themselves invisible
	local caps = bar.EndCaps
	if caps then
		if caps.LeftEndCap then caps.LeftEndCap:SetAlpha(0) end
		if caps.RightEndCap then caps.RightEndCap:SetAlpha(0) end
	end

	if bar.UpdateDividers then
		HideDividers(bar)
		hooksecurefunc(bar, 'UpdateDividers', HideDividers)
	end
end

function ActionBars:OnInit()
	HideBarArt()

	for _, group in next, BUTTON_GROUPS do
		for i = 1, group.count do
			local name = group.prefix .. i
			SkinButton(_G[name], name)
			SetupEmptyFade(_G[name], group.prefix)
		end
	end

	local events = CreateFrame('Frame')
	events:RegisterEvent('PLAYER_ENTERING_WORLD')
	events:RegisterEvent('ACTIONBAR_SLOT_CHANGED')
	events:RegisterEvent('ACTIONBAR_PAGE_CHANGED')
	events:RegisterEvent('UPDATE_BONUS_ACTIONBAR')
	events:RegisterEvent('ACTIONBAR_SHOWGRID')
	events:RegisterEvent('ACTIONBAR_HIDEGRID')
	events:SetScript('OnEvent', function(_, event)
		if event == 'ACTIONBAR_SHOWGRID' then
			gridShown = true
		elseif event == 'ACTIONBAR_HIDEGRID' then
			gridShown = false
		end
		UpdateAllEmpties()
	end)

	-- Edit Mode needs every slot visible for placing/arranging
	if EditModeManagerFrame then
		EditModeManagerFrame:HookScript('OnShow', UpdateAllEmpties)
		EditModeManagerFrame:HookScript('OnHide', UpdateAllEmpties)
	end

	UpdateAllEmpties()
end
