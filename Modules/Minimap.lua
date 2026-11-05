local _, ns = ...
local BenisUI = ns.BenisUI

-- Square minimap (ElvUI style): flat 1px border, zone text inside the map,
-- mouse-wheel zoom, and all minimap addon buttons collected into a bar
-- below the map instead of hugging the edge.
local MinimapMod = BenisUI:RegisterModule('Minimap')

local FONT = BenisUI.media.font
local Skin = BenisUI.Skin

local SQUARE_MASK = 130937 -- Interface\ChatFrame\ChatFrameBackground (what ElvUI uses)

local BUTTON_SIZE = 22
local BUTTON_SPACING = 2
local BUTTONS_PER_ROW = 6

local buttonBar
local collected = {} -- ordered list of adopted buttons
local collectedSet = {}
local layingOut = false
local layoutQueued = false

--------------------------------------------------------------------------------
-- Square map
--------------------------------------------------------------------------------

-- grow the map to fill the cluster instead of the small default 140x140
local function ResizeMinimap()
	local minimap = _G.Minimap
	local cluster = _G.MinimapCluster

	local size = math.floor(cluster:GetWidth() + 0.5) - 2
	if size < 100 then size = 190 end

	-- avoid re-running from our own SetSize via the cluster Layout hook
	if math.abs(minimap:GetWidth() - size) < 0.5 then return end

	minimap:SetSize(size, size)
	minimap:ClearAllPoints()
	minimap:SetPoint('BOTTOM', cluster, 'BOTTOM', 0, 1)

	-- blips/rendering only pick up a new size after a zoom change
	local zoom = minimap:GetZoom()
	minimap:SetZoom(zoom + (zoom < minimap:GetZoomLevels() - 1 and 1 or -1))
	minimap:SetZoom(zoom)
end

local function SquareMinimap()
	local minimap = _G.Minimap
	minimap:SetMaskTexture(SQUARE_MASK)

	-- LibDBIcon and friends ask this to know how to place edge buttons
	function _G.GetMinimapShape()
		return 'SQUARE'
	end

	Skin:Border(minimap):SetFrameLevel(minimap:GetFrameLevel())

	if _G.MinimapCompassTexture then _G.MinimapCompassTexture:SetAlpha(0) end

	local cluster = _G.MinimapCluster
	if cluster.BorderTop then cluster.BorderTop:SetAlpha(0) end
	if cluster.ZoneTextButton then Skin:Kill(cluster.ZoneTextButton) end

	Skin:Kill(minimap.ZoomIn)
	Skin:Kill(minimap.ZoomOut)
	Skin:Kill(_G.TimeManagerClockButton)
	Skin:Kill(_G.GameTimeFrame)
	Skin:Kill(_G.AddonCompartmentFrame)

	ResizeMinimap()
	if cluster.Layout then
		hooksecurefunc(cluster, 'Layout', ResizeMinimap)
	end

	-- zoom with the mouse wheel instead of the (hidden) buttons
	minimap:EnableMouseWheel(true)
	minimap:SetScript('OnMouseWheel', function(self, delta)
		local zoom = self:GetZoom()
		if delta > 0 then
			self:SetZoom(math.min(self:GetZoomLevels() - 1, zoom + 1))
		elseif zoom > 0 then
			self:SetZoom(zoom - 1)
		end
	end)
end

--------------------------------------------------------------------------------
-- Zone text inside the map
--------------------------------------------------------------------------------

local zoneText

local function UpdateZoneText()
	zoneText:SetText(GetMinimapZoneText() or '')
end

local function CreateZoneText()
	local holder = CreateFrame('Frame', nil, _G.Minimap)
	holder:SetFrameLevel(_G.Minimap:GetFrameLevel() + 10)
	holder:SetPoint('TOPLEFT', 4, -4)
	holder:SetPoint('TOPRIGHT', -4, -4)
	holder:SetHeight(14)

	zoneText = holder:CreateFontString(nil, 'OVERLAY')
	zoneText:SetFont(FONT, 11, 'OUTLINE')
	zoneText:SetAllPoints()
	zoneText:SetJustifyH('CENTER')
	zoneText:SetTextColor(1, 1, 1)
	zoneText:SetWordWrap(false)
end

--------------------------------------------------------------------------------
-- Addon button bar below the map
--------------------------------------------------------------------------------

-- fileIDs of the round chrome LibDBIcon-style buttons carry around
local KILL_TEXTURES = {
	[136430] = true, -- Interface\Minimap\MiniMap-TrackingBorder
	[136467] = true, -- Interface\Minimap\UI-Minimap-Background
}

local function IsChromeTexture(texture)
	if type(texture) == 'number' then
		return KILL_TEXTURES[texture]
	elseif type(texture) == 'string' then
		local path = texture:lower()
		return path:find('trackingborder', 1, true) or path:find('ui%-minimap%-background')
	end
end

-- manual minimap buttons (no LibDBIcon) are recognized by their round
-- tracking-border chrome
local function HasChromeTexture(button)
	for _, region in next, { button:GetRegions() } do
		if region.IsObjectType and region:IsObjectType('Texture') and IsChromeTexture(region:GetTexture()) then
			return true
		end
	end
end

local function CleanButton(button)
	local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
	local pushed = button.GetPushedTexture and button:GetPushedTexture()

	local icon = button.icon or button.Icon
	for _, region in next, { button:GetRegions() } do
		if region.IsObjectType and region:IsObjectType('Texture') then
			if IsChromeTexture(region:GetTexture()) then
				region:SetTexture(nil)
				region:Hide()
			elseif not icon and region ~= highlight and region ~= pushed then
				-- hand-rolled buttons keep their icon as an anonymous texture
				icon = region
			end
		end
	end

	if icon and icon.SetTexCoord then
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		icon:ClearAllPoints()
		icon:SetPoint('TOPLEFT', button, 'TOPLEFT', 1, -1)
		icon:SetPoint('BOTTOMRIGHT', button, 'BOTTOMRIGHT', -1, 1)
	end
end

local function LayoutButtons()
	layingOut = true
	layoutQueued = false

	local index = 0
	for _, button in ipairs(collected) do
		local background = button.BenisUIBackground
		if button:IsShown() then
			local row = math.floor(index / BUTTONS_PER_ROW)
			local col = index % BUTTONS_PER_ROW
			local scale = button:GetScale()
			button:ClearAllPoints()
			-- offsets are in the button's scaled space
			button:SetPoint('TOPRIGHT', buttonBar, 'TOPRIGHT',
				-col * (BUTTON_SIZE + BUTTON_SPACING) / scale,
				-row * (BUTTON_SIZE + BUTTON_SPACING) / scale)
			if background then background:Show() end
			index = index + 1
		elseif background then
			background:Hide()
		end
	end

	local rows = math.max(1, math.ceil(index / BUTTONS_PER_ROW))
	buttonBar:SetHeight(rows * (BUTTON_SIZE + BUTTON_SPACING) - BUTTON_SPACING)

	layingOut = false
end

-- some addons re-anchor their button onto the minimap edge after login;
-- pull it back into the grid whenever that happens
local function OnAdoptedSetPoint()
	if layingOut or layoutQueued then return end
	layoutQueued = true
	C_Timer.After(0, LayoutButtons)
end

local function AdoptButton(button)
	if collectedSet[button] then return end
	collectedSet[button] = true
	collected[#collected + 1] = button

	button:SetParent(buttonBar)
	button:SetFrameStrata('MEDIUM')
	button:SetFrameLevel(10)

	if button == _G.ExpansionLandingPageMinimapButton then
		-- its layered art ignores SetSize; shrink the whole thing instead
		local width = button:GetWidth()
		if width and width > BUTTON_SIZE then
			button:SetScale(BUTTON_SIZE / width)
		end
	else
		button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
		CleanButton(button)
	end

	-- solid black slot behind the button
	local background = Skin:Backdrop(buttonBar, button, 1)
	background:SetFrameLevel(1)
	background:SetBackdropColor(0, 0, 0, 1)
	button.BenisUIBackground = background

	hooksecurefunc(button, 'SetPoint', OnAdoptedSetPoint)
	button:HookScript('OnShow', OnAdoptedSetPoint)
	button:HookScript('OnHide', OnAdoptedSetPoint)
end

local function CollectButtons()
	for _, child in next, { _G.Minimap:GetChildren() } do
		if not collectedSet[child] and child:IsObjectType('Button') then
			local name = child.GetName and child:GetName()
			if (name and name:find('LibDBIcon10_', 1, true) == 1) or HasChromeTexture(child) then
				AdoptButton(child)
			end
		end
	end

	local expansion = _G.ExpansionLandingPageMinimapButton
	if expansion then
		AdoptButton(expansion)
	end

	-- tracking selector joins the bar too
	local tracking = _G.MinimapCluster.Tracking or _G.MinimapCluster.TrackingFrame
	if tracking then
		if tracking.Background then tracking.Background:Hide() end
		if tracking.Button then
			AdoptButton(tracking.Button)
		end
	end

	LayoutButtons()
end

local function CreateButtonBar()
	buttonBar = CreateFrame('Frame', 'BenisUIMinimapButtonBar', UIParent)
	buttonBar:SetPoint('TOPRIGHT', _G.Minimap, 'BOTTOMRIGHT', 0, -6)
	buttonBar:SetPoint('TOPLEFT', _G.Minimap, 'BOTTOMLEFT', 0, -6)
	buttonBar:SetHeight(BUTTON_SIZE)
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

function MinimapMod:OnInit()
	SquareMinimap()
	CreateZoneText()
	CreateButtonBar()

	local events = CreateFrame('Frame')
	events:RegisterEvent('PLAYER_ENTERING_WORLD')
	events:RegisterEvent('ZONE_CHANGED')
	events:RegisterEvent('ZONE_CHANGED_INDOORS')
	events:RegisterEvent('ZONE_CHANGED_NEW_AREA')
	events:SetScript('OnEvent', function(_, event)
		UpdateZoneText()
		if event == 'PLAYER_ENTERING_WORLD' then
			ResizeMinimap()
			CollectButtons()
			-- addons register their minimap buttons at different times
			C_Timer.After(3, CollectButtons)
			C_Timer.After(10, CollectButtons)
		end
	end)
end
