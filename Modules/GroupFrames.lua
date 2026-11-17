local _, ns = ...
local BenisUI = ns.BenisUI

-- Party and raid frames. Each member is a flat bar in the house style: the
-- health bar fills the frame in the class color, with name, online dot, life
-- number, role, level and PvP flag on top, and a thin mana (or rage / energy)
-- bar underneath. No portraits.
--
-- Members are spawned by SecureGroupHeaderTemplate so the roster can change in
-- combat. Party members stack downward; in a raid every group is its own
-- header (a column growing down) and the groups line up left to right.
--
-- Same secrecy rules as UnitFrames.lua: secret values are only stored,
-- concatenated or handed to widget APIs.
local GroupFrames = BenisUI:RegisterModule('GroupFrames')
local UnitFrames = BenisUI:GetModule('UnitFrames')

local Skin = BenisUI.Skin
local CreateText = UnitFrames.CreateText
local SetFittedText = UnitFrames.SetFittedText
local FullName = UnitFrames.FullName
local Short = UnitFrames.Short
local UpdateHealthColor = UnitFrames.UpdateHealthColor
local HideBlizzardFrame = UnitFrames.HideBlizzardFrame

local UnitExists = UnitExists
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitLevel = UnitLevel
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitPowerType = UnitPowerType
local UnitIsConnected = UnitIsConnected
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsPVP = UnitIsPVP
local UnitIsPVPFreeForAll = UnitIsPVPFreeForAll
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local InCombatLockdown = InCombatLockdown

local issecret = issecretvalue or function() return false end

local WHITE8X8 = 'Interface\\Buttons\\WHITE8X8'

local LAYOUT = {
	party = {
		width = 180, height = 48, powerHeight = 7, nameSize = 12, healthSize = 14, smallSize = 10,
		-- debuffs the player can dispel, in a row off the right edge
		dispel = { size = 30, max = 4, timerSize = 11 },
		point = { 'TOPLEFT', 20, -220 },
	},
	raid = {
		width = 100, height = 40, powerHeight = 5, nameSize = 10, healthSize = 11, smallSize = 9,
		-- below the party block: Edit Mode shows both previews at once
		point = { 'TOPLEFT', 20, -400 },
	},
}

local COLOR_ONLINE = { 0.25, 0.9, 0.35 }
local COLOR_OFFLINE = { 0.45, 0.45, 0.45 }
local COLOR_PVP = { 1, 0.3, 0.3 }

local ROLES = {
	TANK = { 'T', 0.35, 0.65, 1 },
	HEALER = { 'H', 0.35, 1, 0.45 },
	DAMAGER = { 'D', 1, 0.4, 0.4 },
}

local RAID_GROUPS = NUM_RAID_GROUPS or 8
local GROUP_SIZE = MEMBERS_PER_RAID_GROUP or 5
local GROUPS_PER_ROW = 4 -- raid groups side by side before a new line starts
local GROUP_ROW_GAP = 12 -- between the lines (group 1 and group 5)

-- members share a border line, so a column is a little shorter than n frames
local function ColumnHeight(layout, members)
	return members * (layout.height - 1) + 1
end

local buttons = {} -- every styled member button

--------------------------------------------------------------------------------
-- Dispellable debuffs
--------------------------------------------------------------------------------

-- Same door as NameplatesAuras.lua: the client's AuraContainer reads the
-- (secret) auras and fills the buttons; Lua only shapes them, once, inside
-- initializeFrame. 'HARMFUL|RAID' is "debuffs the player can dispel", filtered
-- client-side. The border takes the dispel type's colour (magic blue, curse
-- purple, ...), also set by the client.

local DISPEL_GROUP = 'dispel'
local PARK = 'raid40' -- a token that resolves to nobody while in a party

local function InitializeDispelButton(button, d)
	button:SetSize(d.size, d.size)

	local base = button:CreateTexture(nil, 'BACKGROUND', nil, 0)
	base:SetAllPoints(button)
	base:SetColorTexture(0, 0, 0, 1)

	-- white, recoloured per dispel type; hidden for a type it has no colour for
	local border = button:CreateTexture(nil, 'BACKGROUND', nil, 1)
	border:SetAllPoints(button)
	border:SetTexture(WHITE8X8)
	local style = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
	pcall(button.AddDispelTypeTexture, button, border, {
		style = style and style.PreserveAsset or 3,
	})

	local icon = button:CreateTexture(nil, 'ARTWORK')
	icon:SetPoint('TOPLEFT', 2, -2)
	icon:SetPoint('BOTTOMRIGHT', -2, 2)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	pcall(button.SetIcon, button, icon)

	local cooldown = CreateFrame('Cooldown', nil, button, 'CooldownFrameTemplate')
	cooldown:SetAllPoints(icon)
	cooldown:SetHideCountdownNumbers(true)
	if cooldown.SetDrawEdge then cooldown:SetDrawEdge(false) end
	if cooldown.SetReverse then cooldown:SetReverse(true) end
	pcall(button.SetDurationCooldown, button, cooldown)

	-- above the swipe, or the numbers darken with the icon
	local text = CreateFrame('Frame', nil, button)
	text:SetAllPoints(button)
	text:SetFrameLevel(cooldown:GetFrameLevel() + 2)

	local count = CreateText(text, d.timerSize - 1)
	count:SetPoint('BOTTOMRIGHT', button, 'BOTTOMRIGHT', 1, 1)
	pcall(button.SetApplicationCount, button, count)

	local timer = CreateText(text, d.timerSize)
	timer:SetPoint('CENTER', button, 'CENTER', 0, 1)
	if not BenisUI.AuraTimer.BindText(button, timer) then
		cooldown:SetHideCountdownNumbers(false)
	end
end

-- built out of combat with the button; false when the client won't make one
local function CreateDispels(frame, d)
	local ok, container = pcall(CreateFrame, 'AuraContainer', nil, frame,
		'CustomAuraContainerTemplate')
	if not ok or not container then return false end

	local width = d.max * (d.size + 2) - 2
	container:SetPoint('LEFT', frame, 'RIGHT', 3, 0)
	container:SetSize(width, d.size)
	pcall(container.SetUnit, container, PARK)

	local layout = {
		elementWidth = d.size,
		elementHeight = d.size,
		elementSpacing = 2,
		lineSpacing = 2,
		groupSpacing = 2,
		groupLineSpacing = 2,
		maximumLineSize = width,
	}
	local options = {
		maxFrameCount = d.max,
		sortMethod = AuraContainerSortMethod and AuraContainerSortMethod.Default or nil,
		sortDirection = AuraContainerSortDirection and AuraContainerSortDirection.Normal or nil,
		initializeFrame = function(button) InitializeDispelButton(button, d) end,
		layout = layout,
	}
	if not pcall(container.AddAuraGroup, container, DISPEL_GROUP, 'HARMFUL|RAID', options) then
		container:Hide()
		return false
	end
	pcall(container.SetAuraGroupLayout, container, DISPEL_GROUP, layout)
	pcall(container.SetEnabled, container, true)
	return container
end

-- the token ('party1') can stay while the person behind it changes, and
-- SetUnit with the same token is a no-op, so every refresh re-reads in full
local function UpdateDispels(frame)
	local container = frame.dispels
	if not container then return end
	pcall(container.SetUnit, container, frame.unit or PARK)
	pcall(container.UpdateAllAuras, container)
end

--------------------------------------------------------------------------------
-- Updates
--------------------------------------------------------------------------------

local function UpdateHealth(frame)
	local unit = frame.unit
	local cur = UnitHealth(unit)

	frame.health:SetMinMaxValues(0, UnitHealthMax(unit))
	frame.health:SetValue(cur)

	if not UnitIsConnected(unit) then
		frame.healthText:SetText('Offline')
		return
	end

	local dead = UnitIsDeadOrGhost(unit)
	if not issecret(dead) and dead then
		frame.healthText:SetText('Dead')
	else
		frame.healthText:SetText(Short(cur))
	end
end

local function UpdatePower(frame)
	local unit = frame.unit
	local powerType, powerToken = UnitPowerType(unit)
	local color = (powerToken and not issecret(powerToken) and PowerBarColor[powerToken])
		or PowerBarColor.MANA

	frame.power:SetStatusBarColor(color.r, color.g, color.b)
	frame.power:SetMinMaxValues(0, UnitPowerMax(unit, powerType))
	frame.power:SetValue(UnitPower(unit, powerType))
end

local function UpdateConnection(frame)
	local color = UnitIsConnected(frame.unit) and COLOR_ONLINE or COLOR_OFFLINE
	frame.statusDot:SetVertexColor(color[1], color[2], color[3])
	UpdateHealthColor(frame) -- class color, grey while offline
	UpdateHealth(frame)
end

local function UpdateLevel(frame)
	local level = UnitLevel(frame.unit)

	if issecret(level) then
		frame.levelText:SetText(level)
	elseif level and level > 0 then
		frame.levelText:SetText(level)
	else
		frame.levelText:SetText('??') -- out of range members report 0
	end
end

local function UpdateRole(frame)
	local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(frame.unit)
	local info = role and not issecret(role) and ROLES[role]

	if info then
		frame.roleText:SetText(info[1])
		frame.roleText:SetTextColor(info[2], info[3], info[4])
	else
		frame.roleText:SetText('')
	end
end

local function UpdatePvP(frame)
	local unit = frame.unit
	local ffa = UnitIsPVPFreeForAll(unit)
	local pvp = UnitIsPVP(unit)

	if not issecret(ffa) and ffa then
		frame.pvpText:SetText('FFA')
	elseif not issecret(pvp) and pvp then
		frame.pvpText:SetText('PvP')
	else
		frame.pvpText:SetText('')
	end
end

local function UpdateAll(frame)
	local unit = frame.unit
	if not unit or not UnitExists(unit) then return end

	SetFittedText(frame.nameText, FullName(unit), frame.nameSize)
	UpdateConnection(frame)
	UpdatePower(frame)
	UpdateLevel(frame)
	UpdateRole(frame)
	UpdatePvP(frame)
	UpdateDispels(frame)
end

local function OnEvent(frame, event)
	if not frame.unit then return end

	if event == 'UNIT_HEALTH' or event == 'UNIT_MAXHEALTH' then
		UpdateHealth(frame)
	elseif event == 'UNIT_POWER_UPDATE' or event == 'UNIT_MAXPOWER'
		or event == 'UNIT_DISPLAYPOWER' then
		UpdatePower(frame)
	elseif event == 'UNIT_CONNECTION' then
		UpdateConnection(frame)
	elseif event == 'UNIT_LEVEL' then
		UpdateLevel(frame)
	elseif event == 'UNIT_FACTION' then
		UpdatePvP(frame)
	else -- UNIT_NAME_UPDATE: class and the rest arrive with the name
		UpdateAll(frame)
	end
end

local UNIT_EVENTS = {
	'UNIT_HEALTH', 'UNIT_MAXHEALTH', 'UNIT_CONNECTION', 'UNIT_LEVEL',
	'UNIT_FACTION', 'UNIT_NAME_UPDATE',
	'UNIT_POWER_UPDATE', 'UNIT_MAXPOWER', 'UNIT_DISPLAYPOWER',
}

-- the header hands buttons their unit ('party2', 'raid17') as the roster moves
local function OnAttributeChanged(frame, name, value)
	if name ~= 'unit' or frame.unit == value then return end
	frame.unit = value

	frame:UnregisterAllEvents()
	if not value then UpdateDispels(frame) end -- park it
	if value then
		for _, event in ipairs(UNIT_EVENTS) do
			frame:RegisterUnitEvent(event, value)
		end
		UpdateAll(frame)
	end
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function StopMoving(anchor)
	anchor.moving = nil
	anchor:StopMovingOrSizing()
	local point, _, _, x, y = anchor:GetPoint()
	BenisUI.db.unitframes.positions[anchor.key] = { point = point, x = x, y = y }
end

-- The look of one member, shared by the real buttons and the Edit Mode
-- preview cells. `frame` needs BackdropTemplate.
local function BuildBar(frame, layout)
	frame:SetSize(layout.width, layout.height)

	-- black border + black body (the visible black is the missing health)
	Skin:Panel(frame):SetBackdropColor(0, 0, 0, 1)

	local health = CreateFrame('StatusBar', nil, frame)
	health:SetStatusBarTexture(WHITE8X8)
	health:SetPoint('TOPLEFT', 1, -1)
	health:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -1, layout.powerHeight + 2)
	frame.health = health

	local power = CreateFrame('StatusBar', nil, frame)
	power:SetStatusBarTexture(WHITE8X8)
	power:SetPoint('TOPLEFT', frame, 'BOTTOMLEFT', 1, layout.powerHeight + 1)
	power:SetPoint('BOTTOMRIGHT', -1, 1)
	frame.power = power

	-- online / offline dot, black-edged so it reads on any class color
	local dotEdge = health:CreateTexture(nil, 'OVERLAY', nil, 1)
	dotEdge:SetTexture(WHITE8X8)
	dotEdge:SetVertexColor(0, 0, 0)
	dotEdge:SetSize(8, 8)
	dotEdge:SetPoint('TOPLEFT', 5, -6)

	local dot = health:CreateTexture(nil, 'OVERLAY', nil, 2)
	dot:SetTexture(WHITE8X8)
	dot:SetPoint('TOPLEFT', dotEdge, 'TOPLEFT', 1, -1)
	dot:SetPoint('BOTTOMRIGHT', dotEdge, 'BOTTOMRIGHT', -1, 1)
	frame.statusDot = dot

	-- the name gets the whole top line; everything else sits on the bottom one
	local name = CreateText(health, layout.nameSize)
	name:SetPoint('LEFT', dotEdge, 'RIGHT', 4, 0)
	name:SetPoint('RIGHT', health, 'RIGHT', -4, 0)
	name:SetJustifyH('LEFT')
	frame.nameText = name
	frame.nameSize = layout.nameSize

	local healthText = CreateText(health, layout.healthSize)
	healthText:SetPoint('BOTTOMLEFT', 5, 3)
	healthText:SetJustifyH('LEFT')
	frame.healthText = healthText

	-- bottom right, reading left to right: PvP flag, role, level
	local level = CreateText(health, layout.smallSize)
	level:SetPoint('BOTTOMRIGHT', -5, 4)
	level:SetJustifyH('RIGHT')
	frame.levelText = level

	local role = CreateText(health, layout.smallSize)
	role:SetPoint('RIGHT', level, 'LEFT', -4, 0)
	role:SetJustifyH('RIGHT')
	frame.roleText = role

	local pvp = CreateText(health, layout.smallSize)
	pvp:SetPoint('RIGHT', role, 'LEFT', -4, 0)
	pvp:SetJustifyH('RIGHT')
	pvp:SetTextColor(unpack(COLOR_PVP))
	frame.pvpText = pvp

	-- the bar covers the button, so the hover tint lives on the bar and is
	-- toggled by hand
	local highlight = health:CreateTexture(nil, 'OVERLAY', nil, 0)
	highlight:SetColorTexture(1, 1, 1, 0.12)
	highlight:SetAllPoints()
	highlight:Hide()
	frame.highlight = highlight
end

local function StyleButton(frame, layout, anchor)
	if frame.BenisUIStyled then return end
	frame.BenisUIStyled = true
	buttons[#buttons + 1] = frame

	BuildBar(frame, layout)
	frame:RegisterForClicks('AnyUp')
	if layout.dispel then frame.dispels = CreateDispels(frame, layout.dispel) end

	local highlight = frame.highlight
	frame:HookScript('OnEnter', function() highlight:Show() end)
	frame:HookScript('OnLeave', function() highlight:Hide() end)

	-- shift-drag any member to move the whole block (out of combat)
	frame:RegisterForDrag('LeftButton')
	frame:SetScript('OnDragStart', function()
		if IsShiftKeyDown() and not InCombatLockdown() then
			anchor.moving = true
			anchor:StartMoving()
		end
	end)
	frame:SetScript('OnDragStop', function()
		if not anchor.moving then return end
		StopMoving(anchor)
	end)

	frame:HookScript('OnAttributeChanged', OnAttributeChanged)
	frame:HookScript('OnShow', UpdateAll)
	frame:SetScript('OnEvent', OnEvent)

	OnAttributeChanged(frame, 'unit', frame:GetAttribute('unit'))
end

local function CreateAnchor(key)
	local layout = LAYOUT[key]
	local anchor = CreateFrame('Frame', 'BenisUI' .. key .. 'Anchor', UIParent)
	anchor.key = key
	anchor:SetSize(layout.width, layout.height)
	anchor:SetMovable(true)
	anchor:SetClampedToScreen(true)

	local saved = BenisUI.db.unitframes.positions[key]
	if saved then
		anchor:SetPoint(saved.point, UIParent, saved.point, saved.x, saved.y)
	else
		local point = layout.point
		anchor:SetPoint(point[1], UIParent, point[1], point[2], point[3])
	end

	return anchor
end

-- Blizzard's party and raid frames are gone, and with them their Edit Mode
-- handles. While Edit Mode is open each block shows a stand-in instead: a
-- full-size preview (4 party members, 8 groups of 5) built from the same bars
-- as the real thing and filled with made-up members. Dragging it moves the
-- block, group or no group.
local PREVIEW_MEMBERS = {
	{ 'Aldric Stonehelm', 'WARRIOR', 'TANK', 'RAGE' },
	{ 'Seraphine Dawnwhisper', 'PRIEST', 'HEALER', 'MANA' },
	{ 'Corvin Ashgrove', 'MAGE', 'DAMAGER', 'MANA' },
	{ 'Nyssa Quickblade', 'ROGUE', 'DAMAGER', 'ENERGY' },
	{ 'Thorne Wildmane', 'DRUID', 'HEALER', 'MANA' },
	{ 'Brakka Longshot', 'HUNTER', 'DAMAGER', 'MANA' },
	{ 'Elowen Brightshield', 'PALADIN', 'TANK', 'MANA' },
	{ 'Mordane Vex', 'WARLOCK', 'DAMAGER', 'MANA' },
	{ 'Kaz Stormcaller', 'SHAMAN', 'HEALER', 'MANA' },
}

local function FillPreview(cell, index)
	local member = PREVIEW_MEMBERS[(index - 1) % #PREVIEW_MEMBERS + 1]
	local name, class, role, powerToken = unpack(member)
	local offline = index % 13 == 0
	local dead = not offline and index % 11 == 0
	local maxHealth = 2400 + (index * 37) % 900
	local health = (offline or dead) and 0 or math.floor(maxHealth * (1 - (index * 7 % 10) * 0.06))

	SetFittedText(cell.nameText, name, cell.nameSize)

	local color = offline and COLOR_OFFLINE or RAID_CLASS_COLORS[class]
	cell.health:SetStatusBarColor(color.r or color[1], color.g or color[2], color.b or color[3])
	cell.health:SetMinMaxValues(0, maxHealth)
	cell.health:SetValue(offline and maxHealth or health)
	cell.healthText:SetText(offline and 'Offline' or dead and 'Dead' or Short(health))

	local dot = offline and COLOR_OFFLINE or COLOR_ONLINE
	cell.statusDot:SetVertexColor(dot[1], dot[2], dot[3])

	local powerColor = PowerBarColor[powerToken] or PowerBarColor.MANA
	cell.power:SetStatusBarColor(powerColor.r, powerColor.g, powerColor.b)
	cell.power:SetMinMaxValues(0, 100)
	cell.power:SetValue(offline and 0 or 100 - (index * 17) % 70)

	cell.levelText:SetText(60 - index % 4)
	local info = ROLES[role]
	cell.roleText:SetText(info[1])
	cell.roleText:SetTextColor(info[2], info[3], info[4])
	cell.pvpText:SetText(index % 3 == 0 and 'PvP' or '')
end

local function CreateMover(anchor, label, columns, rows)
	local perLine = math.min(columns, GROUPS_PER_ROW)
	local lines = math.ceil(columns / perLine)
	local layout = LAYOUT[anchor.key]
	local mover = CreateFrame('Frame', nil, UIParent)
	mover:SetFrameStrata('HIGH')
	mover:SetPoint('TOPLEFT', anchor, 'TOPLEFT')
	local lineHeight = ColumnHeight(layout, rows)
	mover:SetSize(perLine * layout.width, lines * lineHeight + (lines - 1) * GROUP_ROW_GAP)
	mover:Hide()

	local cells = {}
	for column = 1, columns do
		for row = 1, rows do
			local cell = CreateFrame('Frame', nil, mover, 'BackdropTemplate')
			BuildBar(cell, layout)
			local line = math.floor((column - 1) / perLine)
			cell:SetPoint('TOPLEFT', ((column - 1) % perLine) * layout.width,
				-line * (lineHeight + GROUP_ROW_GAP) - (row - 1) * (layout.height - 1))
			cell.index = (column - 1) * rows + row
			cells[#cells + 1] = cell
		end
	end

	-- filled on show: names are fitted to the line, which needs a laid-out frame
	mover:SetScript('OnShow', function()
		for _, cell in ipairs(cells) do
			FillPreview(cell, cell.index)
		end
	end)

	-- the house blue outline and a label mark it as a handle
	local outline = Skin:Border(mover)
	outline:SetFrameLevel(mover:GetFrameLevel() + 10)
	Skin:SetBorder(outline, mover, 1, 0.09, 0.52, 0.82)

	local title = CreateText(outline, 12)
	title:SetPoint('BOTTOMLEFT', mover, 'TOPLEFT', 0, 4)
	title:SetText(label)

	mover:EnableMouse(true)
	mover:RegisterForDrag('LeftButton')
	mover:SetScript('OnDragStart', function()
		if InCombatLockdown() then return end
		anchor.moving = true
		anchor:StartMoving()
	end)
	mover:SetScript('OnDragStop', function()
		if anchor.moving then StopMoving(anchor) end
	end)
	mover:SetScript('OnHide', function()
		if anchor.moving then StopMoving(anchor) end
	end)

	return mover
end

local function WatchEditMode(movers)
	local manager = _G.EditModeManagerFrame
	if not (manager and EventRegistry) then return end

	local function Refresh()
		local active = manager.IsEditModeActive and manager:IsEditModeActive()
		for _, mover in ipairs(movers) do
			mover:SetShown(active and true or false)
		end
	end

	EventRegistry:RegisterCallback('EditMode.Enter', Refresh, movers)
	EventRegistry:RegisterCallback('EditMode.Exit', Refresh, movers)
	Refresh()
end

-- runs in the restricted environment for every button the header creates
local INIT_BUTTON = [[
	local header = self:GetParent()
	self:SetWidth(header:GetAttribute('buiWidth'))
	self:SetHeight(header:GetAttribute('buiHeight'))
	self:SetAttribute('*type1', 'target')
	self:SetAttribute('*type2', 'togglemenu')
]]

local function CreateHeader(name, layout, anchor, count, visibility, attributes)
	local header = CreateFrame('Frame', name, UIParent, 'SecureGroupHeaderTemplate')
	header:SetFrameStrata('MEDIUM')

	header:SetAttribute('template', 'SecureUnitButtonTemplate,BackdropTemplate')
	header:SetAttribute('buiWidth', layout.width)
	header:SetAttribute('buiHeight', layout.height)
	header:SetAttribute('initialConfigFunction', INIT_BUTTON)
	-- grow down; a 1px overlap makes neighbours share one border line
	header:SetAttribute('point', 'TOP')
	header:SetAttribute('yOffset', 1)
	for key, value in pairs(attributes) do
		header:SetAttribute(key, value)
	end

	-- force every button into existence now, so none has to be styled in combat
	header:Show()
	header:SetAttribute('startingIndex', 1 - count)
	header:SetAttribute('startingIndex', 1)

	for i = 1, count do
		local button = header:GetAttribute('child' .. i) or header[i]
			or _G[name .. 'UnitButton' .. i]
		if button then StyleButton(button, layout, anchor) end
	end

	RegisterStateDriver(header, 'visibility', visibility)

	return header
end

local function HideBlizzard()
	local party = _G.PartyFrame
	if party then
		HideBlizzardFrame(party)
		if party.PartyMemberFramePool then
			for member in party.PartyMemberFramePool:EnumerateActive() do
				HideBlizzardFrame(member)
			end
		end
	end

	for i = 1, 4 do
		HideBlizzardFrame(_G['PartyMemberFrame' .. i])
	end

	HideBlizzardFrame(_G.CompactPartyFrame)
	-- the raid manager (the tab on the screen edge) stays for markers and
	-- ready checks; only the frames it would show are taken away
	HideBlizzardFrame(_G.CompactRaidFrameContainer)
end

local function Build()
	HideBlizzard()

	local partyAnchor = CreateAnchor('party')
	local party = CreateHeader('BenisUIParty', LAYOUT.party, partyAnchor, GROUP_SIZE,
		'[group:raid] hide; [group:party] show; hide',
		{ showParty = true, showPlayer = false, showRaid = false })
	party:SetPoint('TOPLEFT', partyAnchor, 'TOPLEFT')

	-- one header per raid group: members grow down, groups grow to the right,
	-- four to a line, then a second line starts under the first with a gap.
	-- An empty group's header collapses, so each line stays packed.
	local raidAnchor = CreateAnchor('raid')
	local previous
	for group = 1, RAID_GROUPS do
		local header = CreateHeader('BenisUIRaidGroup' .. group, LAYOUT.raid, raidAnchor,
			GROUP_SIZE, '[group:raid] show; hide',
			{ showRaid = true, showParty = false, groupFilter = tostring(group) })
		if (group - 1) % GROUPS_PER_ROW == 0 then
			local line = (group - 1) / GROUPS_PER_ROW
			header:SetPoint('TOPLEFT', raidAnchor, 'TOPLEFT', 0,
				-line * (ColumnHeight(LAYOUT.raid, GROUP_SIZE) + GROUP_ROW_GAP))
		else
			header:SetPoint('TOPLEFT', previous, 'TOPRIGHT')
		end
		previous = header
	end

	WatchEditMode({
		CreateMover(partyAnchor, 'Party', 1, GROUP_SIZE - 1),
		CreateMover(raidAnchor, 'Raid', RAID_GROUPS, GROUP_SIZE),
	})
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

function GroupFrames:OnInit()
	BenisUI.db.unitframes = BenisUI.db.unitframes or { positions = {} }
	BenisUI.db.unitframes.positions = BenisUI.db.unitframes.positions or {}

	local controller = CreateFrame('Frame')
	controller:RegisterEvent('PLAYER_ENTERING_WORLD')
	controller:RegisterEvent('GROUP_ROSTER_UPDATE')
	-- not every client has role assignment
	pcall(controller.RegisterEvent, controller, 'PLAYER_ROLES_ASSIGNED')

	local built = false
	controller:SetScript('OnEvent', function(self, event)
		if event == 'PLAYER_REGEN_ENABLED' then
			self:UnregisterEvent(event)
		end
		if not built then
			if InCombatLockdown() then return end
			built = true
			Build()
		end
		for _, button in ipairs(buttons) do
			if button:IsVisible() then UpdateAll(button) end
		end
	end)

	-- secure headers can't be set up in combat (e.g. a /reload mid-fight)
	if InCombatLockdown() then
		controller:RegisterEvent('PLAYER_REGEN_ENABLED')
	else
		built = true
		Build()
	end
end
