local _, ns = ...
local BenisUI = ns.BenisUI

-- Nameplates in the ElvUI manner: a flat bar inside a one-pixel black border
-- on a dark backdrop, the name above it on the left and the level on the
-- right, health percent on the bar, a thin cast bar under it with the spell's
-- icon beside both (NameplatesCast.lua), the player's own debuffs in a row on
-- top and an enemy player's dispellable buffs above those (NameplatesAuras.lua), a white glow round the target and every other
-- plate dimmed while there is one.
--
-- None of ElvUI's code or art is here; the look is rebuilt from WHITE8X8 and
-- the bundled font. What IS taken from ElvUI, deliberately, is its map of what
-- an addon may do with a nameplate unit's values on the 12.x client, which
-- WoW Forever shares -- its retail branches are the working example. The
-- rules this module is written to:
--
--   PASS THROUGH, NEVER LOOK AT (secret on an enemy):
--     UnitName                     -> FontString:SetText
--     UnitHealth / UnitHealthMax   -> StatusBar:SetMinMaxValues / SetValue
--     UnitHealthPercent(u, true, ScaleTo100)
--                                  -> SetFormattedText('%d%%', v)
--     every UnitCastingInfo field  -> SetText / SetTexture; `not name` is the
--                                     one legal test (NameplatesCast.lua)
--     UnitIsUnit(u, 'target')      -> SetAlphaFromBoolean, never `if`
--     UnitClass's token            -> C_ClassColor.GetClassColor when secret
--
--   BRANCH ON (ElvUI indexes tables and does arithmetic with all of these):
--     UnitCanAttack, UnitIsPlayer, UnitPlayerControlled, UnitIsTapDenied,
--     UnitReaction, UnitThreatSituation, UnitClassification,
--     UnitEffectiveLevel, GetRaidTargetIndex
--
-- The second list is ElvUI's word, not something measured per API on each
-- client. So every one of them still goes through `Yes` / `Plain` below, which
-- ask `issecretvalue` first: if one turns out secret somewhere, the plate
-- loses that one decoration (a threat colour, a level) instead of throwing in
-- the middle of a fight.
local Nameplates = BenisUI:RegisterModule('Nameplates')

local UnitFrames = BenisUI:GetModule('UnitFrames')
-- 'Name Surname' on WoW Forever, the bare name on retail
local FullName = UnitFrames and UnitFrames.FullName or UnitName

local issecretvalue = issecretvalue

local function Secret(v)
	return issecretvalue ~= nil and issecretvalue(v) == true
end

-- A plain truthy. A secret boolean throws on the boolean test itself, so a
-- value that may be one is never put in an `if` without this.
local function Yes(v)
	if Secret(v) then return false end
	return v and true or false
end

-- The value when it is there and readable, nil otherwise. `== nil` is legal on
-- a secret; everything after it is not.
local function Plain(v)
	if v == nil or Secret(v) then return nil end
	return v
end

-- Shows `region` at `on` when the boolean is true and `off` when it is not,
-- whether or not Lua is allowed to know which. SetAlphaFromBoolean is the
-- widget's own door for a secret boolean (oUF's cast shield uses it).
local function AlphaFromBool(region, value, on, off)
	if Secret(value) then
		region:SetAlphaFromBoolean(value, on, off)
	else
		region:SetAlpha(value and on or off)
	end
end

Nameplates.Secret, Nameplates.Yes, Nameplates.Plain = Secret, Yes, Plain
Nameplates.AlphaFromBool = AlphaFromBool

local function Settings()
	return BenisUI.db.nameplates
end

--------------------------------------------------------------------------------
-- Style
--------------------------------------------------------------------------------

local TEXTURE = BenisUI.media.texture
local FONT = BenisUI.media.font

-- the unit frames' palette, so a mob is the same red on its plate and its frame
local TAPPED = { 0.55, 0.57, 0.61 }
local HOSTILE = { 0.78, 0.25, 0.25 }
local NEUTRAL = { 0.85, 0.77, 0.36 }
local FRIENDLY = { 0.29, 0.69, 0.3 }

-- By UnitThreatSituation: 0 on its list, 1 above the tank but not attacked,
-- 2 attacked without the most threat, 3 securely its target. For anyone but a
-- tank "it is on me" is the bad end; for a tank it is the good one.
local THREAT_GOOD = { 0.20, 0.86, 0.20 }
local THREAT_GOOD_SHIFT = { 1.00, 0.86, 0.20 }
local THREAT_BAD_SHIFT = { 1.00, 0.60, 0.20 }
local THREAT_BAD = { 1.00, 0.20, 0.20 }
local THREAT = {
	[false] = { [0] = THREAT_GOOD, THREAT_GOOD_SHIFT, THREAT_BAD_SHIFT, THREAT_BAD },
	[true] = { [0] = THREAT_BAD, THREAT_BAD_SHIFT, THREAT_GOOD_SHIFT, THREAT_GOOD },
}

-- The backdrop behind a bar is the bar's own colour at this strength, so an
-- emptied bar still says whose it is.
local BACKDROP = 0.35
local BACKDROP_PLAIN = { 0.08, 0.08, 0.08 }
-- every plate but the target's, while there is a target
local DIMMED = 0.65
local HOVER = 0.20

local CLASSIFICATION = { elite = '+', rareelite = 'R+', rare = 'R' }

-- Sizes, in PHYSICAL pixels. Plate frames ignore their parent's scale and sit
-- at 768/height, so one unit is one pixel and a border is exactly one of them
-- at any resolution -- which is the whole of the thin-border look. Size
-- therefore cannot ride the frame scale; it rides `scale`.
local metrics

local function Round(v) return math.floor(v + 0.5) end

local function Metrics()
	if metrics then return metrics end

	local _, height = GetPhysicalScreenSize()
	if type(height) ~= 'number' or height <= 0 then height = 1080 end

	-- 150x10 is ElvUI's plate, drawn for 1080 lines. Left alone it is a sliver
	-- on anything taller, so the default grows with the screen in quarters.
	local s = Settings().scale or math.max(1, Round(height / 1080 * 4) / 4)

	metrics = {
		pixel = 768 / height,
		scale = s,
		width = Round(150 * s),
		health = Round(10 * s),
		cast = Round(8 * s),
		font = math.max(9, Round(11 * s)),
		small = math.max(8, Round(10 * s)),
		auraWidth = Round(22 * s),
		auraHeight = Round(16 * s),
		raidIcon = Round(22 * s),
	}
	return metrics
end

Nameplates.Metrics = Metrics

-- sizes are already whole pixels here, so the outline stays even
local function SetFont(fontString, size)
	fontString:SetFont(FONT, size, 'OUTLINE')
	fontString:SetShadowOffset(0, 0)
	fontString:SetWordWrap(false)
end

local function Line(parent, layer, r, g, b, a)
	local line = parent:CreateTexture(nil, layer)
	line:SetColorTexture(r, g, b, a or 1)
	-- Left on, the client rounds a one-pixel line onto the grid of a plate
	-- that moves in fractions, and it flickers between one pixel and two.
	if line.SetSnapToPixelGrid then
		line:SetSnapToPixelGrid(false)
		line:SetTexelSnappingBias(0)
	end
	return line
end

-- Four one-pixel lines round `region`, `distance` pixels out: 1 hugs it.
-- Bare textures rather than Skin:Border: a BackdropTemplate edge is sized in
-- the frame's own units and these have to stay one physical pixel.
local function Outline(parent, region, layer, distance, r, g, b, a)
	local o, i = distance, distance - 1

	local top = Line(parent, layer, r, g, b, a)
	top:SetPoint('BOTTOMLEFT', region, 'TOPLEFT', -o, i)
	top:SetPoint('BOTTOMRIGHT', region, 'TOPRIGHT', o, i)
	top:SetHeight(1)

	local bottom = Line(parent, layer, r, g, b, a)
	bottom:SetPoint('TOPLEFT', region, 'BOTTOMLEFT', -o, -i)
	bottom:SetPoint('TOPRIGHT', region, 'BOTTOMRIGHT', o, -i)
	bottom:SetHeight(1)

	local left = Line(parent, layer, r, g, b, a)
	left:SetPoint('TOPRIGHT', region, 'TOPLEFT', -i, i)
	left:SetPoint('BOTTOMRIGHT', region, 'BOTTOMLEFT', -i, -i)
	left:SetWidth(1)

	local right = Line(parent, layer, r, g, b, a)
	right:SetPoint('TOPLEFT', region, 'TOPRIGHT', i, i)
	right:SetPoint('BOTTOMLEFT', region, 'BOTTOMRIGHT', i, -i)
	right:SetWidth(1)
end

-- A flat status bar on a dark backdrop inside a black one-pixel border.
local function Bar(parent, width, height)
	local bar = CreateFrame('StatusBar', nil, parent)
	bar:SetSize(width, height)
	bar:SetStatusBarTexture(TEXTURE)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)

	local fill = bar:GetStatusBarTexture()
	if fill and fill.SetDrawLayer then fill:SetDrawLayer('ARTWORK') end

	bar.Backdrop = bar:CreateTexture(nil, 'BACKGROUND')
	bar.Backdrop:SetAllPoints(bar)
	bar.Backdrop:SetColorTexture(1, 1, 1, 1)
	bar.Backdrop:SetVertexColor(BACKDROP_PLAIN[1], BACKDROP_PLAIN[2], BACKDROP_PLAIN[3], 0.9)

	Outline(bar, bar, 'BORDER', 1, 0, 0, 0, 1)

	-- A little light on top and shade underneath, over the filled part only.
	-- Flat is the look; dead flat reads as a rectangle somebody forgot.
	if fill and CreateColor then
		local shade = bar:CreateTexture(nil, 'ARTWORK', nil, 1)
		shade:SetAllPoints(fill)
		shade:SetColorTexture(1, 1, 1, 1)
		if not pcall(shade.SetGradient, shade, 'VERTICAL',
				CreateColor(0, 0, 0, 0.22), CreateColor(1, 1, 1, 0.10)) then
			shade:Hide()
		end
	end

	return bar
end

Nameplates.SetFont, Nameplates.Outline, Nameplates.Bar = SetFont, Outline, Bar

--------------------------------------------------------------------------------
-- One plate
--------------------------------------------------------------------------------

-- nameplate base frame -> our frame on it. Base frames are recycled by the
-- client for the life of the session, so ours are built once and re-pointed.
local frames = {}

-- defined with the handlers it dispatches to, further down
local OnPlateEvent

local function Build(plate)
	local m = Metrics()

	local f = CreateFrame('Frame', nil, plate)
	f:SetIgnoreParentScale(true)
	f:SetScale(m.pixel)
	f:SetPoint('CENTER', plate, 'CENTER', 0, 0)
	f:SetSize(m.width + 2, m.health + 2)
	f:Hide()

	local health = Bar(f, m.width, m.health)
	health:SetPoint('CENTER', f, 'CENTER', 0, 0)
	f.Health = health

	-- Target glow: a white line just outside the border and two fainter ones
	-- beyond it. One frame, so one alpha lights or clears all twelve lines.
	local glow = CreateFrame('Frame', nil, f)
	glow:SetAllPoints(health)
	glow:SetFrameLevel(math.max(0, health:GetFrameLevel() - 1))
	Outline(glow, health, 'BACKGROUND', 2, 1, 1, 1, 0.95)
	Outline(glow, health, 'BACKGROUND', 3, 1, 1, 1, 0.40)
	Outline(glow, health, 'BACKGROUND', 4, 1, 1, 1, 0.15)
	glow:SetAlpha(0)
	f.Glow = glow

	local hover = health:CreateTexture(nil, 'OVERLAY')
	hover:SetAllPoints(health)
	hover:SetColorTexture(1, 1, 1, 1)
	hover:SetBlendMode('ADD')
	hover:SetAlpha(0)
	f.Hover = hover

	-- text lives on a frame above the bars, or the fill would draw over it
	local text = CreateFrame('Frame', nil, f)
	text:SetAllPoints(health)
	text:SetFrameLevel(health:GetFrameLevel() + 5)

	local level = text:CreateFontString(nil, 'OVERLAY')
	SetFont(level, m.font)
	level:SetPoint('BOTTOMRIGHT', health, 'TOPRIGHT', 1, 3)
	level:SetJustifyH('RIGHT')
	f.Level = level

	-- Anchored on both sides, so a long name is cut by the client where the
	-- level begins. It has to be the client: a secret name cannot be measured
	-- or trimmed from here.
	local name = text:CreateFontString(nil, 'OVERLAY')
	SetFont(name, m.font)
	name:SetPoint('BOTTOMLEFT', health, 'TOPLEFT', 0, 3)
	name:SetPoint('BOTTOMRIGHT', level, 'BOTTOMLEFT', -2, 0)
	name:SetJustifyH('LEFT')
	f.Name = name

	local percent = text:CreateFontString(nil, 'OVERLAY')
	SetFont(percent, m.font)
	percent:SetPoint('CENTER', health, 'CENTER', 0, 0)
	f.Percent = percent

	local raidIcon = text:CreateTexture(nil, 'OVERLAY')
	raidIcon:SetTexture('Interface\\TargetingFrame\\UI-RaidTargetingIcons')
	raidIcon:SetSize(m.raidIcon, m.raidIcon)
	raidIcon:SetPoint('RIGHT', health, 'LEFT', -5, 0)
	raidIcon:Hide()
	f.RaidIcon = raidIcon

	-- what the mouse can hit: the name, the bar and the cast bar, with a
	-- little room round them
	local hit = CreateFrame('Frame', nil, f)
	hit:SetPoint('TOPLEFT', health, 'TOPLEFT', -6, m.font + 6)
	hit:SetPoint('BOTTOMRIGHT', health, 'BOTTOMRIGHT', 6, -(m.cast + 8))
	f.HitArea = hit

	if Nameplates.BuildCast then Nameplates.BuildCast(f, m) end

	f:SetScript('OnEvent', OnPlateEvent)
	frames[plate] = f
	return f
end

--------------------------------------------------------------------------------
-- What a plate shows
--------------------------------------------------------------------------------

local tankAnswer, tankAsked = false, -math.huge

-- Who counts as a tank when the setting says 'auto': the spec where there are
-- specs, an assigned group role where there are those, and on WoW Forever --
-- which has neither -- the PenisRoles addon if it is loaded, since that is
-- where its players mark who tanks.
local function AutoTank()
	local spec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization
		and C_SpecializationInfo.GetSpecialization()
		or GetSpecialization and GetSpecialization()
	local specRole = C_SpecializationInfo and C_SpecializationInfo.GetSpecializationRole
		or GetSpecializationRole
	if spec and specRole and Plain(specRole(spec)) == 'TANK' then return true end

	if UnitGroupRolesAssigned and Plain(UnitGroupRolesAssigned('player')) == 'TANK' then
		return true
	end

	local roles = _G.PenisRoles
	return type(roles) == 'table' and type(roles.IsTank) == 'function'
		and roles.IsTank('player') == true
end

local function IsTank()
	local mode = Settings().tank
	if mode ~= 'auto' then return mode == 'on' end

	-- asked for every plate on every sweep; the answer changes with a respec
	local now = GetTime()
	if now - tankAsked >= 1 then
		tankAsked = now
		local ok, tank = pcall(AutoTank)
		tankAnswer = ok and tank == true
	end
	return tankAnswer
end

-- r, g, b -- which are SECRET when the class token was: the client resolves a
-- secret token to a colour, and the colour can then only be handed on.
local function ClassColor(unit)
	local _, token = UnitClass(unit)
	if not token then return end

	if Secret(token) then
		local color = C_ClassColor and C_ClassColor.GetClassColor(token)
		if color then return color:GetRGB() end
		return
	end

	local color = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[token]
	if color then return color.r, color.g, color.b end
end

local function ReactionColor(f)
	local reaction = Plain(UnitReaction(f.unit, 'player'))
	local color
	if not reaction then
		color = f.hostile and HOSTILE or FRIENDLY
	elseif reaction <= 3 then
		color = HOSTILE
	elseif reaction == 4 then
		color = NEUTRAL
	else
		color = FRIENDLY
	end
	return color[1], color[2], color[3]
end

local function HealthColor(f)
	local unit = f.unit
	local controlled = Yes(UnitPlayerControlled(unit))

	if not controlled and Yes(UnitIsTapDenied(unit)) then
		return TAPPED[1], TAPPED[2], TAPPED[3]
	end

	if f.hostile and not controlled then
		local status = Plain(UnitThreatSituation('player', unit))
		local color = status and THREAT[IsTank()][status]
		if color then return color[1], color[2], color[3] end
	end

	if f.isPlayer then
		local r, g, b = ClassColor(unit)
		if r then return r, g, b end
	end

	return ReactionColor(f)
end

local function UpdateColor(f)
	local r, g, b = HealthColor(f)

	if Secret(r) then
		-- a class colour the client would not name: no arithmetic, no cache
		f.r = nil
		f.Health:SetStatusBarColor(r, g, b)
		f.Health.Backdrop:SetVertexColor(BACKDROP_PLAIN[1], BACKDROP_PLAIN[2], BACKDROP_PLAIN[3], 0.9)
		return
	end

	if r == f.r and g == f.g and b == f.b then return end
	f.r, f.g, f.b = r, g, b
	f.Health:SetStatusBarColor(r, g, b)
	f.Health.Backdrop:SetVertexColor(r * BACKDROP, g * BACKDROP, b * BACKDROP, 0.9)
end

local percentCurve

-- 0..1 -> 0..100, evaluated by the client against the secret health. Blizzard
-- ships one; a build that does not is given the same two points.
local function PercentCurve()
	if percentCurve == nil then
		percentCurve = CurveConstants and CurveConstants.ScaleTo100 or false
		if not percentCurve and C_CurveUtil and C_CurveUtil.CreateCurve then
			local ok, curve = pcall(function()
				local c = C_CurveUtil.CreateCurve()
				c:AddPoint(0, 0)
				c:AddPoint(1, 100)
				return c
			end)
			percentCurve = ok and curve or false
		end
	end
	return percentCurve
end

local function UpdateHealth(f)
	local unit = f.unit
	f.Health:SetMinMaxValues(0, UnitHealthMax(unit))
	f.Health:SetValue(UnitHealth(unit))

	local curve = UnitHealthPercent and PercentCurve()
	if curve then
		f.Percent:SetFormattedText('%d%%', UnitHealthPercent(unit, true, curve))
	else
		f.Percent:SetText('')
	end
end

local function UpdateName(f)
	f.Name:SetText(FullName(f.unit) or '')

	local r, g, b
	if f.isPlayer then r, g, b = ClassColor(f.unit) end
	if not r then r, g, b = ReactionColor(f) end

	if Secret(r) then
		f.Name:SetTextColor(r, g, b)
	else
		-- Lifted toward white: the saturated reaction red is a bar colour, and
		-- at eleven pixels over a dungeon floor it is hard to read as text.
		f.Name:SetTextColor(r + (1 - r) * 0.35, g + (1 - g) * 0.35, b + (1 - b) * 0.35)
	end
end

local difficultyColor = GetCreatureDifficultyColor or GetQuestDifficultyColor

local function UpdateLevel(f)
	local unit = f.unit
	local level = Plain((UnitEffectiveLevel or UnitLevel)(unit))
	if type(level) ~= 'number' then
		f.Level:SetText('')
		return
	end

	if level <= 0 then
		-- a skull: too far above the player for the client to say
		f.Level:SetText('??')
		f.Level:SetTextColor(1, 0.2, 0.2)
		return
	end

	local suffix = CLASSIFICATION[Plain(UnitClassification(unit)) or ''] or ''
	f.Level:SetText(level .. suffix)

	local color = difficultyColor and difficultyColor(level)
	if color then
		f.Level:SetTextColor(color.r, color.g, color.b)
	else
		f.Level:SetTextColor(1, 1, 1)
	end
end

local function UpdateRaidIcon(f)
	local index = Plain(GetRaidTargetIndex(f.unit))
	if index and SetRaidTargetIconTexture then
		SetRaidTargetIconTexture(f.RaidIcon, index)
		f.RaidIcon:Show()
	else
		f.RaidIcon:Hide()
	end
end

local function UpdateTarget(f)
	local isTarget = UnitIsUnit(f.unit, 'target')
	AlphaFromBool(f.Glow, isTarget, 1, 0)
	if Yes(UnitExists('target')) then
		AlphaFromBool(f, isTarget, 1, DIMMED)
	else
		f:SetAlpha(1)
	end
end

-- Hostility and "is a player" can change under a token that stays put (a duel
-- ending, a mob turning), so they are re-read with the faction event.
local function UpdateKind(f)
	f.hostile = Yes(UnitCanAttack('player', f.unit))
	f.isPlayer = Yes(UnitIsPlayer(f.unit))
end

local function UpdateAll(f)
	UpdateKind(f)
	f.r = nil
	UpdateColor(f)
	UpdateHealth(f)
	UpdateName(f)
	UpdateLevel(f)
	UpdateRaidIcon(f)
	UpdateTarget(f)
end

local HANDLERS = {
	UNIT_HEALTH = UpdateHealth,
	UNIT_MAXHEALTH = UpdateHealth,
	UNIT_NAME_UPDATE = UpdateName,
	UNIT_LEVEL = UpdateLevel,
	UNIT_CLASSIFICATION_CHANGED = UpdateLevel,
	UNIT_THREAT_LIST_UPDATE = UpdateColor,
	UNIT_THREAT_SITUATION_UPDATE = UpdateColor,
	UNIT_FACTION = function(f)
		UpdateKind(f)
		UpdateColor(f)
		UpdateName(f)
		if Nameplates.AttachAuras then Nameplates.AttachAuras(f) end
	end,
}

function OnPlateEvent(f, event, unit)
	if unit ~= f.unit then return end
	local handler = HANDLERS[event]
	if handler then handler(f) end
end

-- An event name a client does not know makes RegisterUnitEvent throw (retail
-- and WoW Forever do not have the same list). Each is tried once, on the
-- first plate, and remembered.
local known = {}

local function RegisterUnitEvents(frame, events, unit)
	for i = 1, #events do
		local event = events[i]
		if known[event] == nil then
			known[event] = pcall(frame.RegisterUnitEvent, frame, event, unit)
		elseif known[event] then
			frame:RegisterUnitEvent(event, unit)
		end
	end
end

Nameplates.RegisterUnitEvents = RegisterUnitEvents

local PLATE_EVENTS = {}
for event in pairs(HANDLERS) do PLATE_EVENTS[#PLATE_EVENTS + 1] = event end

--------------------------------------------------------------------------------
-- Blizzard's own plate
--------------------------------------------------------------------------------

-- Blizzard's unit frame is pooled: one is acquired onto the base frame every
-- time a unit lands on it. oUF's answer, which ElvUI ships on this client, is
-- to hide it and take its events away on every add; the frame is never
-- reparented (unlike UnitFrames.HideBlizzardFrame -- it goes back to a pool),
-- and what Blizzard re-registers on the next unit is Blizzard's business. Its
-- children are left listening: a hidden cast bar costs nothing, and a plate
-- this module declines (below) gets its frame back whole.
local hooked = setmetatable({}, { __mode = 'k' })

local function KeepHidden(unitFrame)
	local plate = unitFrame:GetParent()
	local ours = plate and frames[plate]
	-- `plate.UnitFrame == unitFrame`: on Acquire the frame is shown while
	-- still parented to the LAST base frame it served, which may be showing
	-- one of ours with a different unit frame by now.
	if ours and ours.active and plate.UnitFrame == unitFrame then
		unitFrame:Hide()
	end
end

local function HideBlizzard(plate)
	local unitFrame = plate.UnitFrame
	if not unitFrame then return false end

	if not hooked[unitFrame] then
		hooked[unitFrame] = true
		-- a CVar or resolution change runs CompactUnitFrame_UpdateAll over
		-- every plate, which shows the frame again on top of ours
		unitFrame:HookScript('OnShow', KeepHidden)
	end

	unitFrame:UnregisterAllEvents()
	unitFrame:Hide()
	return true
end

-- A soft-interact game object (fishing bobber, herb, chest) has no health or
-- level; it gets a plate only to carry the interact icon.
local function IsGameObject(unit)
	if UnitIsGameObject ~= nil and Yes(UnitIsGameObject(unit)) then return true end
	local guid = Plain(UnitGUID(unit))
	return guid ~= nil and guid:match('^GameObject%-') ~= nil
end

-- The player's own plate carries the class resource bars, a widgets-only
-- plate is an objective marker with no unit worth drawing, and a game object
-- is not a unit at all. All stay Blizzard's.
local function LeftAlone(unit)
	if Yes(UnitIsUnit(unit, 'player')) then return true end
	if IsGameObject(unit) then return true end
	return UnitNameplateShowsWidgetsOnly ~= nil and Yes(UnitNameplateShowsWidgetsOnly(unit))
end

--------------------------------------------------------------------------------
-- Driver
--------------------------------------------------------------------------------

local function Detach(f)
	if not f.active then return end
	f.active = false
	f.unit = nil
	f:UnregisterAllEvents()
	f:Hide()
	if Nameplates.DetachCast then Nameplates.DetachCast(f) end
	if Nameplates.DetachAuras then Nameplates.DetachAuras(f) end
end

local function Attach(f, unit, plate)
	f.unit = unit
	f.active = true
	f:UnregisterAllEvents()
	RegisterUnitEvents(f, PLATE_EVENTS, unit)

	f:SetAlpha(1)
	f.Hover:SetAlpha(0)
	UpdateAll(f)
	f:Show()

	-- Only now, and only here: tainted code may move a plate's hit area on the
	-- tick its unit is assigned and at no other time in combat.
	if plate.SetAllHitTestPoints then
		pcall(function()
			plate:ClearAllHitTestPoints()
			plate:SetAllHitTestPoints(f.HitArea)
		end)
	end

	if Nameplates.AttachCast then Nameplates.AttachCast(f) end
	if Nameplates.AttachAuras then Nameplates.AttachAuras(f) end
end

local function PlateFor(unit)
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
	-- nil for a forbidden plate (friendly players inside an instance): those
	-- are not ours to touch and stay as Blizzard draws them
	return ok and plate or nil
end

local function Added(unit)
	local plate = PlateFor(unit)
	if not plate then return end

	if LeftAlone(unit) then
		local f = frames[plate]
		if f then Detach(f) end
		return
	end

	local f = frames[plate] or Build(plate)
	Attach(f, unit, plate)

	if not HideBlizzard(plate) and C_Timer then
		-- our handler ran before Blizzard's acquired its frame; next frame it
		-- is there
		C_Timer.After(0, function()
			if f.active and f.unit == unit then HideBlizzard(plate) end
		end)
	end
end

local function Removed(unit)
	local plate = PlateFor(unit)
	local f = plate and frames[plate]
	if f then
		Detach(f)
		return
	end
	for _, other in pairs(frames) do
		if other.unit == unit then Detach(other) end
	end
end

local function EachActive(fn)
	for _, f in pairs(frames) do
		if f.active then fn(f) end
	end
end

local hovering = false
local sinceHover, sinceSweep = 0, 0

local function OnUpdate(_, elapsed)
	sinceHover = sinceHover + elapsed
	if sinceHover >= 0.1 then
		sinceHover = 0
		-- Nothing fires when the mouse LEAVES a unit, so this is polled. The
		-- comparison may be secret; the alpha takes it either way.
		if Yes(UnitExists('mouseover')) then
			hovering = true
			EachActive(function(f)
				AlphaFromBool(f.Hover, UnitIsUnit('mouseover', f.unit), HOVER, 0)
			end)
		elseif hovering then
			hovering = false
			EachActive(function(f) f.Hover:SetAlpha(0) end)
		end
	end

	sinceSweep = sinceSweep + elapsed
	if sinceSweep >= 0.5 then
		sinceSweep = 0
		-- tapping and leaving a threat list fire nothing reliable per plate
		EachActive(UpdateColor)
	end
end

local function Recolor()
	tankAsked = -math.huge
	EachActive(function(f)
		f.r = nil
		UpdateColor(f)
	end)
end

function Nameplates:OnInit()
	local db = Settings()
	if db.tank ~= 'auto' and db.tank ~= 'on' and db.tank ~= 'off' then db.tank = 'auto' end
	if type(db.scale) ~= 'number' or db.scale < 0.5 or db.scale > 3 then db.scale = nil end

	-- off means Blizzard's plates are never touched this session
	if not db.enabled then return end

	local driver = CreateFrame('Frame')
	driver:RegisterEvent('NAME_PLATE_UNIT_ADDED')
	driver:RegisterEvent('NAME_PLATE_UNIT_REMOVED')
	driver:RegisterEvent('PLAYER_TARGET_CHANGED')
	driver:RegisterEvent('RAID_TARGET_UPDATE')
	driver:RegisterEvent('PLAYER_REGEN_ENABLED')
	driver:RegisterEvent('PLAYER_ENTERING_WORLD')
	driver:SetScript('OnUpdate', OnUpdate)

	driver:SetScript('OnEvent', function(_, event, unit)
		if event == 'NAME_PLATE_UNIT_ADDED' then
			Added(unit)
		elseif event == 'NAME_PLATE_UNIT_REMOVED' then
			Removed(unit)
		elseif event == 'PLAYER_TARGET_CHANGED' then
			EachActive(UpdateTarget)
		elseif event == 'RAID_TARGET_UPDATE' then
			EachActive(UpdateRaidIcon)
		elseif event == 'PLAYER_REGEN_ENABLED' then
			EachActive(UpdateColor)
		elseif event == 'PLAYER_ENTERING_WORLD' then
			-- Plates already up after a /reload. Token indices are sparse and
			-- outrun the frame list, so the token space is what gets walked.
			for i = 1, 40 do
				local token = 'nameplate' .. i
				if Yes(UnitExists(token)) then Added(token) end
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- /bui plates
--------------------------------------------------------------------------------

local function Say(text)
	print('|cff1784d1Benis|rUI: ' .. text)
end

local RELOAD = ' Type /reload to apply.'

function Nameplates:Command(input)
	local db = Settings()
	local command, value = (input or ''):lower():match('^%s*(%S*)%s*(%S*)')

	if command == 'on' or command == 'off' then
		db.enabled = command == 'on'
		Say('nameplates ' .. command .. '.' .. RELOAD)
	elseif command == 'scale' then
		local scale = tonumber(value)
		if value == 'auto' then
			db.scale = nil
			Say('nameplate scale follows the screen.' .. RELOAD)
		elseif scale and scale >= 0.5 and scale <= 3 then
			db.scale = scale
			Say('nameplate scale ' .. scale .. '.' .. RELOAD)
		else
			Say('nameplate scale is a number from 0.5 to 3, or auto. Now: '
				.. (db.scale or ('auto (' .. Metrics().scale .. ')')))
		end
	elseif command == 'debuffs' and (value == 'on' or value == 'off') then
		db.debuffs = value == 'on'
		Say('your debuffs on nameplates ' .. value .. '.' .. RELOAD)
	elseif command == 'buffs' and (value == 'on' or value == 'off') then
		db.buffs = value == 'on'
		Say('dispellable buffs on enemy players ' .. value .. '.' .. RELOAD)
	elseif command == 'tank' and (value == 'on' or value == 'off' or value == 'auto') then
		db.tank = value
		Recolor()
		Say('nameplate threat colours for a tank: ' .. value .. '.')
	else
		Say('/bui plates on | off -- these nameplates, or the default ones')
		Say('/bui plates scale <0.5-3 | auto> -- size; borders stay one pixel')
		Say('/bui plates debuffs on | off -- your debuffs above each enemy')
		Say('/bui plates buffs on | off -- dispellable buffs above enemy players')
		Say('/bui plates tank on | off | auto -- green when it is ON you, not off you')
	end
end

-- our frame on a nameplate base frame, once one has been built
function Nameplates.GetFrame(plate)
	return frames[plate]
end
