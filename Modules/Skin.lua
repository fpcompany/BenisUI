local _, ns = ...
local BenisUI = ns.BenisUI

-- Shared skinning API: one definition of the BenisUI window look (flat dark
-- body, 1px black border) plus the plumbing to put it on Blizzard frames,
-- whether they exist at login or arrive with a load-on-demand addon.
--
-- Only touch textures and alpha on Blizzard frames. Moving, hiding or
-- reparenting a protected frame taints it, so Strip/Panel deliberately never
-- call SetPoint or Hide on the frame they are handed.
local Skin = {}
BenisUI.Skin = Skin

local TEXTURE = BenisUI.media.texture

-- the house palette: everything below defaults to these, and callers override
-- on the returned frame when a specific spot wants something else
local BODY = { 0.06, 0.06, 0.06, 0.94 }
local BORDER = { 0, 0, 0, 1 }

Skin.body = BODY
Skin.border = BORDER

--------------------------------------------------------------------------------
-- Registry
--------------------------------------------------------------------------------

local ready = false -- PLAYER_LOGIN has fired
local queued = {} -- [addon name or false] = { { func, label }, ... }

local function Run(entry)
	local ok, err = pcall(entry.func)
	if not ok then
		print(('|cff1784d1Benis|rUI: skin "%s" failed: %s'):format(entry.label, err))
	end
end

local function Flush(key)
	local list = queued[key]
	if not list then return end
	queued[key] = nil
	for _, entry in ipairs(list) do
		Run(entry)
	end
end

-- Register(nil, func) runs the skin at login; Register('Blizzard_X', func)
-- runs it when that addon loads. Every skin is pcall'd, so one frame Blizzard
-- renamed in a patch can't take the rest of the UI down with it.
function Skin:Register(addon, func, label)
	local entry = { func = func, label = label or addon or 'core' }

	if ready and (not addon or C_AddOns.IsAddOnLoaded(addon)) then
		Run(entry)
		return
	end

	local key = addon or false
	queued[key] = queued[key] or {}
	table.insert(queued[key], entry)
end

local dispatcher = CreateFrame('Frame')
dispatcher:RegisterEvent('PLAYER_LOGIN')
dispatcher:RegisterEvent('ADDON_LOADED')
dispatcher:SetScript('OnEvent', function(_, event, addon)
	if event == 'PLAYER_LOGIN' then
		ready = true
		Flush(false)
		-- a load-on-demand addon can already be up before login
		for key in next, queued do
			if key and C_AddOns.IsAddOnLoaded(key) then Flush(key) end
		end
	elseif ready then
		Flush(addon)
	end
end)

--------------------------------------------------------------------------------
-- Primitives
--------------------------------------------------------------------------------

local hidden = CreateFrame('Frame')
hidden:Hide()

-- Take a frame out of the UI for good: our own frames and Blizzard leaf art
-- only, never anything protected.
function Skin:Kill(frame)
	if not frame then return end
	if frame.UnregisterAllEvents then
		frame:UnregisterAllEvents()
		frame:SetParent(hidden)
	end
	frame:Hide()
	if frame.SetAlpha then frame:SetAlpha(0) end
end

-- window art Blizzard hangs off frame keys, where GetRegions() can't reach it
-- BorderFrame is deliberately absent: some templates park the close button and
-- tabs inside it, and fading the frame takes its children with it
local ART_KEYS = {
	'NineSlice', 'Bg', 'BG', 'Background', 'TitleBg', 'TopTileStreaks',
}

-- Blanks every texture on a frame, leaving font strings and child frames
-- alone. Safe on protected frames: textures aren't protected.
function Skin:Strip(frame)
	if not frame then return end

	-- some named "frames" are bare textures (e.g. MerchantItem1NameFrame)
	if not frame.GetRegions then
		if frame.IsObjectType and frame:IsObjectType('Texture') then
			frame:SetTexture(nil)
			frame:SetAlpha(0)
		end
		return
	end

	for _, region in next, { frame:GetRegions() } do
		if region.IsObjectType and region:IsObjectType('Texture') then
			region:SetTexture(nil)
			region:SetAlpha(0)
		end
	end

	for _, key in next, ART_KEYS do
		local art = frame[key]
		if art and art.SetAlpha then art:SetAlpha(0) end
	end
end

-- A child frame carrying the house backdrop, hugging `anchor` (the parent by
-- default) with `inset` pixels of bleed. Returned so callers can re-level or
-- recolor it.
function Skin:Backdrop(parent, anchor, inset)
	anchor, inset = anchor or parent, inset or 0

	local backdrop = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
	backdrop:SetPoint('TOPLEFT', anchor, 'TOPLEFT', -inset, inset)
	backdrop:SetPoint('BOTTOMRIGHT', anchor, 'BOTTOMRIGHT', inset, -inset)
	backdrop:SetBackdrop({ bgFile = TEXTURE, edgeFile = TEXTURE, edgeSize = 1 })
	backdrop:SetBackdropColor(unpack(BODY))
	backdrop:SetBackdropBorderColor(unpack(BORDER))

	return backdrop
end

-- The house panel look. Frames of ours built on BackdropTemplate take it
-- directly; anything else (most Blizzard frames) gets a child frame carrying
-- it. Either way the frame holding the backdrop comes back.
function Skin:Panel(frame)
	if not frame.SetBackdrop then
		local backdrop = Skin:Backdrop(frame)
		backdrop:SetFrameLevel(frame:GetFrameLevel())
		return backdrop
	end

	frame:SetBackdrop({ bgFile = TEXTURE, edgeFile = TEXTURE, edgeSize = 1 })
	frame:SetBackdropColor(unpack(BODY))
	frame:SetBackdropBorderColor(unpack(BORDER))

	return frame
end

-- A 1px black outline hugging `anchor` (the parent by default), with no body.
function Skin:Border(parent, size, anchor)
	size = size or 1

	local border = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
	Skin:SetBorder(border, anchor or parent, size)

	return border
end

-- Re-anchors and recolors an outline made by Skin:Border. The backdrop is only
-- rebuilt when the size actually changes, so this is cheap to call per update.
function Skin:SetBorder(border, anchor, size, r, g, b)
	if border.edgeSize ~= size then
		border.edgeSize = size
		border:SetBackdrop({ edgeFile = TEXTURE, edgeSize = size })
		border:ClearAllPoints()
		border:SetPoint('TOPLEFT', anchor, 'TOPLEFT', -size, size)
		border:SetPoint('BOTTOMRIGHT', anchor, 'BOTTOMRIGHT', size, -size)
	end

	border:SetBackdropBorderColor(r or BORDER[1], g or BORDER[2], b or BORDER[3], 1)
end

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

local missing = {} -- Blizzard globals a skin asked for and didn't get

-- Resolve a Blizzard global by name, remembering the misses. Frame names move
-- between patches; '/bui skins' lists what this client didn't have so a rename
-- shows up as a report instead of a window that silently stayed ugly.
function Skin:Get(name)
	local frame = _G[name]
	if not frame then
		missing[#missing + 1] = name
	end
	return frame
end

function Skin:ReportMissing()
	if #missing == 0 then
		print('|cff1784d1Benis|rUI: every frame the skins asked for was found.')
		return
	end

	print(('|cff1784d1Benis|rUI: %d frame(s) not found on this client:'):format(#missing))
	for _, name in ipairs(missing) do
		print('  ' .. name)
	end
end

local function BlankTexture(texture)
	if not texture then return end
	texture:SetTexture(nil)
	texture:SetAlpha(0)
end

local STATE_TEXTURES = {
	'GetNormalTexture', 'GetPushedTexture', 'GetDisabledTexture', 'GetHighlightTexture',
}

local function BlankStateTextures(button)
	for _, getter in next, STATE_TEXTURES do
		if button[getter] then BlankTexture(button[getter](button)) end
	end
end

-- Blizzard's chunky gold buttons, flattened. The backdrop sits a level below
-- the button so its label still draws on top.
function Skin:Button(button)
	if not button or button.BenisUISkinned then return end
	button.BenisUISkinned = true

	Skin:Strip(button)
	BlankStateTextures(button)

	local backdrop = Skin:Backdrop(button)
	backdrop:SetFrameLevel(math.max(0, button:GetFrameLevel() - 1))
	backdrop:SetBackdropColor(0.12, 0.12, 0.12, 1)
	button.BenisUIBackdrop = backdrop

	local highlight = button:CreateTexture(nil, 'HIGHLIGHT')
	highlight:SetColorTexture(1, 1, 1, 0.15)
	highlight:SetAllPoints()

	local text = button.GetFontString and button:GetFontString()
	if text then text:SetTextColor(1, 1, 1) end
end

local TAB_ART = {
	'Left', 'Middle', 'Right',
	'LeftActive', 'MiddleActive', 'RightActive',
	'LeftDisabled', 'MiddleDisabled', 'RightDisabled',
	'LeftHighlight', 'MiddleHighlight', 'RightHighlight',
}

local TAB_ACTIVE = 0.18
local TAB_IDLE = 0.09

function Skin:Tab(tab)
	if not tab or tab.BenisUISkinned then return end
	tab.BenisUISkinned = true

	Skin:Strip(tab)
	for _, key in next, TAB_ART do
		BlankTexture(tab[key])
	end
	BlankStateTextures(tab)

	local backdrop = Skin:Backdrop(tab)
	backdrop:SetFrameLevel(math.max(0, tab:GetFrameLevel() - 1))
	backdrop:SetBackdropColor(TAB_IDLE, TAB_IDLE, TAB_IDLE, 1)
	tab.BenisUIBackdrop = backdrop

	local highlight = tab:CreateTexture(nil, 'HIGHLIGHT')
	highlight:SetColorTexture(1, 1, 1, 0.1)
	highlight:SetAllPoints()
end

-- Blizzard marks the selected tab by swapping the textures we just removed, so
-- follow its own bookkeeping and recolor our backdrop instead.
local function UpdateTabColors(frame)
	if not frame or not frame.numTabs then return end

	local name = frame.GetName and frame:GetName()
	for index = 1, frame.numTabs do
		local tab = (frame.Tabs and frame.Tabs[index]) or (name and _G[name .. 'Tab' .. index])
		local backdrop = tab and tab.BenisUIBackdrop
		if backdrop then
			local shade = frame.selectedTab == index and TAB_ACTIVE or TAB_IDLE
			backdrop:SetBackdropColor(shade, shade, shade, 1)
		end
	end
end

if PanelTemplates_UpdateTabs then
	hooksecurefunc('PanelTemplates_UpdateTabs', UpdateTabColors)
end

-- Icon buttons: crop the icon, drop the slot art, add the house border. Never
-- Strip these -- the icon is a region and Strip would blank it too.
function Skin:ItemButton(button)
	if not button or button.BenisUISkinned then return end
	button.BenisUISkinned = true

	local name = button.GetName and button:GetName()
	local icon = button.icon or button.Icon or (name and _G[name .. 'IconTexture'])
	if icon then
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end

	BlankTexture(button.GetNormalTexture and button:GetNormalTexture())
	if name then
		BlankTexture(_G[name .. 'SlotTexture'])
		BlankTexture(_G[name .. 'NormalTexture'])
	end
	if button.IconBorder then button.IconBorder:SetAlpha(0) end
	if button.NineSlice then button.NineSlice:SetAlpha(0) end

	local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
	if highlight then highlight:SetColorTexture(1, 1, 1, 0.2) end

	Skin:Border(button, 1, icon)
end

function Skin:EditBox(box)
	if not box or box.BenisUISkinned then return end
	box.BenisUISkinned = true

	-- Not Skin:Strip: the blinking cursor and the selection highlight are
	-- textures on the edit box too, and blanking every region takes them out.
	-- Template art (InputBoxTemplate, the chat input's borders and focus
	-- glow) all sits in the BACKGROUND and BORDER layers, so only those go.
	for _, region in next, { box:GetRegions() } do
		if region.IsObjectType and region:IsObjectType('Texture') then
			local layer = region:GetDrawLayer()
			if layer == 'BACKGROUND' or layer == 'BORDER' then
				BlankTexture(region)
			end
		end
	end

	local name = box.GetName and box:GetName()
	if name then
		for _, part in next, { 'Left', 'Middle', 'Mid', 'Right' } do
			BlankTexture(_G[name .. part])
		end
	end
	for _, key in next, { 'Left', 'Middle', 'Mid', 'Right', 'focusLeft', 'focusMid', 'focusRight' } do
		BlankTexture(box[key])
	end

	local backdrop = Skin:Backdrop(box)
	backdrop:SetFrameLevel(math.max(0, box:GetFrameLevel() - 1))
	backdrop:SetBackdropColor(0.03, 0.03, 0.03, 1)
end

--------------------------------------------------------------------------------
-- Generic window handler
--------------------------------------------------------------------------------

-- Blizzard settled retail windows onto a handful of templates, so most of them
-- come down to these keys. Anything a window does beyond this is a per-frame
-- skin on top of Skin:Frame, not instead of it.
local INSET_KEYS = { 'Inset', 'InsetFrame', 'LeftInset', 'RightInset', 'BottomInset' }
local PORTRAIT_KEYS = { 'PortraitContainer', 'Portrait', 'portrait', 'PortraitFrame' }

-- Strips a Blizzard window down to the house panel: art off, portrait hidden,
-- backdrop behind everything. `insets` names extra child frames to strip.
-- Returns the backdrop frame. Leaves the close button stock, like the bag
-- window it's matching.
function Skin:Frame(frame, insets)
	if not frame or frame.BenisUISkinned then return end
	frame.BenisUISkinned = true

	local name = frame.GetName and frame:GetName()

	Skin:Strip(frame)
	for _, key in next, INSET_KEYS do
		Skin:Strip(frame[key])
	end
	if name then Skin:Strip(_G[name .. 'Inset']) end
	if insets then
		for _, key in next, insets do
			Skin:Strip(frame[key])
		end
	end

	for _, key in next, PORTRAIT_KEYS do
		local portrait = frame[key]
		if portrait and portrait.SetAlpha then portrait:SetAlpha(0) end
	end
	if name and _G[name .. 'Portrait'] then _G[name .. 'Portrait']:SetAlpha(0) end

	return Skin:Panel(frame)
end
