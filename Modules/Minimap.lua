local _, ns = ...
local BenisUI = ns.BenisUI

-- Square minimap (ElvUI style): flat 1px border, zone text inside the map,
-- mouse-wheel zoom, and all minimap addon buttons collected into a bar
-- below the map instead of hugging the edge.
local MinimapMod = BenisUI:RegisterModule('Minimap')

local FONT = BenisUI.media.font
local TEXTURE = BenisUI.media.texture

local SQUARE_MASK = 130937 -- Interface\ChatFrame\ChatFrameBackground (what ElvUI uses)

local BUTTON_SIZE = 22
local BUTTON_SPACING = 2
local BUTTONS_PER_ROW = 6

local buttonBar
local collected = {} -- ordered list of adopted buttons
local collectedSet = {}

local hidden = CreateFrame('Frame')
hidden:Hide()

local function Kill(frame)
	if not frame then return end
	if frame.UnregisterAllEvents then
		frame:UnregisterAllEvents()
		frame:SetParent(hidden)
	end
	frame:Hide()
	if frame.SetAlpha then frame:SetAlpha(0) end
end

--------------------------------------------------------------------------------
-- Square map
--------------------------------------------------------------------------------

local function SquareMinimap()
	local minimap = _G.Minimap
	minimap:SetMaskTexture(SQUARE_MASK)

	-- LibDBIcon and friends ask this to know how to place edge buttons
	function _G.GetMinimapShape()
		return 'SQUARE'
	end

	local border = CreateFrame('Frame', nil, minimap, 'BackdropTemplate')
	border:SetPoint('TOPLEFT', -1, 1)
	border:SetPoint('BOTTOMRIGHT', 1, -1)
	border:SetFrameLevel(minimap:GetFrameLevel())
	border:SetBackdrop({ edgeFile = TEXTURE, edgeSize = 1 })
	border:SetBackdropBorderColor(0, 0, 0, 1)

	if _G.MinimapCompassTexture then _G.MinimapCompassTexture:SetAlpha(0) end

	local cluster = _G.MinimapCluster
	if cluster.BorderTop then cluster.BorderTop:SetAlpha(0) end
	if cluster.ZoneTextButton then Kill(cluster.ZoneTextButton) end

	Kill(minimap.ZoomIn)
	Kill(minimap.ZoomOut)
	Kill(_G.TimeManagerClockButton)
	Kill(_G.GameTimeFrame)
	Kill(_G.AddonCompartmentFrame)

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
	[130924] = true, -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight
}

local function CleanButton(button)
	for _, region in next, { button:GetRegions() } do
		if region.IsObjectType and region:IsObjectType('Texture') then
			local texture = region:GetTexture()
			if type(texture) == 'number' and KILL_TEXTURES[texture] then
				region:SetTexture(nil)
				region:Hide()
			elseif type(texture) == 'string' then
				local path = texture:lower()
				if path:find('trackingborder', 1, true) or path:find('ui%-minimap%-background') then
					region:SetTexture(nil)
					region:Hide()
				end
			end
		end
	end

	local icon = button.icon or button.Icon
	if icon and icon.SetTexCoord then
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		icon:ClearAllPoints()
		icon:SetPoint('TOPLEFT', 1, -1)
		icon:SetPoint('BOTTOMRIGHT', -1, 1)
	end
end

local function LayoutButtons()
	local index = 0
	for _, button in ipairs(collected) do
		if button:IsShown() then
			local row = math.floor(index / BUTTONS_PER_ROW)
			local col = index % BUTTONS_PER_ROW
			button:ClearAllPoints()
			button:SetPoint('TOPRIGHT', buttonBar, 'TOPRIGHT',
				-col * (BUTTON_SIZE + BUTTON_SPACING),
				-row * (BUTTON_SIZE + BUTTON_SPACING))
			index = index + 1
		end
	end

	local rows = math.max(1, math.ceil(index / BUTTONS_PER_ROW))
	buttonBar:SetHeight(rows * (BUTTON_SIZE + BUTTON_SPACING) - BUTTON_SPACING)
end

local function AdoptButton(button)
	if collectedSet[button] then return end
	collectedSet[button] = true
	collected[#collected + 1] = button

	button:SetParent(buttonBar)
	button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	button:SetFrameStrata('MEDIUM')
	CleanButton(button)

	-- keep the grid tidy when addons toggle their buttons
	button:HookScript('OnShow', LayoutButtons)
	button:HookScript('OnHide', LayoutButtons)
end

local function CollectButtons()
	for _, child in next, { _G.Minimap:GetChildren() } do
		local name = child.GetName and child:GetName()
		if name and name:find('LibDBIcon10_', 1, true) == 1 then
			AdoptButton(child)
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
			CollectButtons()
			-- addons register their minimap buttons at different times
			C_Timer.After(3, CollectButtons)
			C_Timer.After(10, CollectButtons)
		end
	end)
end
