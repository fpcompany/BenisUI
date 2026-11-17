local _, ns = ...
local BenisUI = ns.BenisUI

-- Replaces the player, target, focus and target-of-target frames.
-- Midnight (12.x) secrecy rules: UnitHealth/UnitPower/UnitClass/UnitName may
-- return secret values. Secrets are only ever stored, concatenated, passed to
-- functions or handed to widget APIs (StatusBar:SetValue, FontString:SetText)
-- -- never compared, indexed with, or used in arithmetic.
local UnitFrames = BenisUI:RegisterModule('UnitFrames')

local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitPowerType = UnitPowerType
local UnitClass = UnitClass
local UnitName = UnitName
local UnitLevel = UnitLevel
local UnitEffectiveLevel = UnitEffectiveLevel
local UnitIsPlayer = UnitIsPlayer
local UnitIsConnected = UnitIsConnected
local UnitIsTapDenied = UnitIsTapDenied
local UnitPlayerControlled = UnitPlayerControlled
local UnitReaction = UnitReaction
local AbbreviateNumbers = AbbreviateNumbers
local CreateAbbreviateConfig = CreateAbbreviateConfig

local issecret = issecretvalue or function() return false end

local WHITE8X8 = 'Interface\\Buttons\\WHITE8X8'
local Skin = BenisUI.Skin
local CIRCLE_MASK = 'Interface\\Masks\\CircleMaskScalable'
-- Expressway (bundled, same font ElvUI uses) has uniform stroke weights, so
-- the black outline renders evenly at small sizes
local FONT = 'Interface\\AddOns\\BenisUI\\Media\\Expressway.ttf'

--------------------------------------------------------------------------------
-- Number abbreviation (K / M), secret-safe: native AbbreviateNumbers was moved
-- to C++ in 12.0 and accepts secret numbers, returning secret strings.
--------------------------------------------------------------------------------

-- descending breakpoints; 4321 -> '4321', 658734 -> '658K', 6573400 -> '6.5M'
-- (K starts at 10k so low-level mobs show exact values instead of '1K')
local abbrevInfo = {
	breakpoints = {
		{ breakpoint = 1e12, abbreviation = 'T', significandDivisor = 1e11, fractionDivisor = 10, abbreviationIsGlobal = false },
		{ breakpoint = 1e9, abbreviation = 'B', significandDivisor = 1e8, fractionDivisor = 10, abbreviationIsGlobal = false },
		{ breakpoint = 1e6, abbreviation = 'M', significandDivisor = 1e5, fractionDivisor = 10, abbreviationIsGlobal = false },
		{ breakpoint = 1e4, abbreviation = 'K', significandDivisor = 1e3, fractionDivisor = 1, abbreviationIsGlobal = false },
	},
}

if CreateAbbreviateConfig then
	abbrevInfo.config = CreateAbbreviateConfig(abbrevInfo.breakpoints)
	wipe(abbrevInfo.breakpoints)
end

local function Short(value)
	return AbbreviateNumbers(value, abbrevInfo)
end

--------------------------------------------------------------------------------
-- Colors
--------------------------------------------------------------------------------

local COLOR_OFFLINE = { 0.5, 0.5, 0.5 }
local COLOR_TAPPED = { 0.55, 0.57, 0.61 }
local REACTION_HOSTILE = { 0.78, 0.25, 0.25 }
local REACTION_NEUTRAL = { 0.85, 0.77, 0.36 }
local REACTION_FRIENDLY = { 0.29, 0.69, 0.3 }

local STATUS_COMBAT = { 0.8, 0.1, 0.1 }
local STATUS_RESTING = { 1, 0.82, 0 }
local STATUS_NONE = { 1, 1, 1 }

local CLASS_POWER_COLORS = {
	COMBO_POINTS = { 1, 0.96, 0.41 },
	CHI = { 0.71, 1, 0.92 },
	HOLY_POWER = { 0.95, 0.9, 0.6 },
	SOUL_SHARDS = { 0.5, 0.32, 0.55 },
	ARCANE_CHARGES = { 0.1, 0.1, 0.98 },
	ESSENCE = { 0.4, 0.8, 0.9 },
}

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

local UNIT_LAYOUT = {
	player = {
		width = 240, height = 74, powerHeight = 16, circle = 30,
		nameSize = 13, healthSize = 19, powerSize = 12, levelSize = 13,
		point = { 'BOTTOM', -300, 280 },
	},
	target = {
		width = 240, height = 74, powerHeight = 16, circle = 30,
		nameSize = 13, healthSize = 19, powerSize = 12, levelSize = 13,
		point = { 'BOTTOM', 300, 280 },
	},
	focus = {
		width = 176, height = 56, powerHeight = 13, circle = 24,
		nameSize = 11, healthSize = 15, powerSize = 10, levelSize = 11,
		point = { 'BOTTOM', -520, 380 },
	},
	targettarget = {
		width = 150, height = 46, powerHeight = 11, circle = 20,
		nameSize = 10, healthSize = 13, powerSize = 9, levelSize = 10,
		point = { 'BOTTOM', 505, 235 },
	},
}

local frames = {} -- [unit] = frame

-- Font sizes are snapped to the physical pixel grid: a 19pt font at 0.7 UI
-- scale rasterizes at 13.3px, which smears the 1px outline unevenly. Rendering
-- at a whole number of pixels keeps the outline crisp.
local physicalHeight = select(2, GetPhysicalScreenSize())
local allTexts = {}

local function CrispFontSize(region, size)
	local factor = region:GetEffectiveScale() * physicalHeight / 768
	if factor <= 0 then return size end
	local pixels = math.max(8, math.floor(size * factor + 0.5))
	return pixels / factor
end

local function CreateText(parent, size, flags)
	local text = parent:CreateFontString(nil, 'OVERLAY')
	text:SetFont(FONT, CrispFontSize(parent, size), flags or 'OUTLINE')
	text:SetTextColor(1, 1, 1)
	text:SetWordWrap(false)
	allTexts[#allTexts + 1] = { text = text, size = size, flags = flags or 'OUTLINE' }
	return text
end

local function RefreshFonts()
	physicalHeight = select(2, GetPhysicalScreenSize())
	for _, entry in next, allTexts do
		entry.text:SetFont(FONT, CrispFontSize(entry.text, entry.size), entry.flags)
	end
end

-- white circle with a black ring, drawn from masked squares
local function CreateCircle(frame, diameter)
	local ring = frame:CreateTexture(nil, 'OVERLAY', nil, 5)
	ring:SetTexture(WHITE8X8)
	ring:SetVertexColor(0, 0, 0, 1)
	ring:SetSize(diameter, diameter)

	local ringMask = frame:CreateMaskTexture()
	ringMask:SetTexture(CIRCLE_MASK, 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE')
	ringMask:SetAllPoints(ring)
	ring:AddMaskTexture(ringMask)

	local bg = frame:CreateTexture(nil, 'OVERLAY', nil, 6)
	bg:SetTexture(WHITE8X8)
	bg:SetVertexColor(1, 1, 1, 1)
	bg:SetPoint('CENTER', ring)
	bg:SetSize(diameter - 3, diameter - 3)

	local bgMask = frame:CreateMaskTexture()
	bgMask:SetTexture(CIRCLE_MASK, 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE')
	bgMask:SetAllPoints(bg)
	bg:AddMaskTexture(bgMask)

	return ring, bg
end

--------------------------------------------------------------------------------
-- Updates
--------------------------------------------------------------------------------

-- Names are never cut off: WoW Forever names are two words and run long, so a
-- name that doesn't fit its line is stepped down a point at a time until it
-- does. Secret names (retail, in combat) can't be measured and keep the base
-- size.
local MIN_NAME_SIZE = 6

local function SetFittedText(text, value, size, flags)
	flags = flags or 'OUTLINE'
	text:SetFont(FONT, CrispFontSize(text, size), flags)
	text:SetText(value or '')
	if not value or issecret(value) then return end

	while size > MIN_NAME_SIZE do
		local truncated = text:IsTruncated()
		if issecret(truncated) or not truncated then break end
		size = size - 1
		text:SetFont(FONT, CrispFontSize(text, size), flags)
	end
end

-- WoW Forever (Interface 16001) is realmless and every character has a first
-- name and a surname: UnitName returns the surname where retail returns the
-- realm. Retail keeps showing the bare name.
local IS_FOREVER = (select(4, GetBuildInfo()) or 0) < 20000

local function FullName(unit)
	local name, surname = UnitName(unit)
	if not IS_FOREVER or not name or not surname then return name end
	if not issecret(surname) and surname == '' then return name end
	return name .. ' ' .. surname -- concatenation is secret-safe
end

local function UpdateName(frame)
	SetFittedText(frame.nameText, FullName(frame.unit), frame.nameSize)
end

local function UpdateHealth(frame)
	local unit = frame.unit
	local cur = UnitHealth(unit)
	local max = UnitHealthMax(unit)

	frame.health:SetMinMaxValues(0, max)
	frame.health:SetValue(cur)
	-- secret-safe: concatenation of secret strings is allowed
	frame.healthText:SetText(Short(cur) .. ' / ' .. Short(max))
end

local function UpdateHealthColor(frame)
	local unit = frame.unit
	local bar = frame.health

	if not UnitIsConnected(unit) then
		bar:SetStatusBarColor(unpack(COLOR_OFFLINE))
		return
	end

	if UnitIsPlayer(unit) then
		local _, classToken = UnitClass(unit)
		if classToken then
			if issecret(classToken) then
				-- C_ClassColor resolves secret class tokens (oUF/ElvUI pattern)
				local color = C_ClassColor.GetClassColor(classToken)
				if color then
					bar:SetStatusBarColor(color:GetRGB())
					return
				end
			else
				local color = RAID_CLASS_COLORS[classToken]
				if color then
					bar:SetStatusBarColor(color.r, color.g, color.b)
					return
				end
			end
		end
	elseif not UnitPlayerControlled(unit) and UnitIsTapDenied(unit) then
		bar:SetStatusBarColor(unpack(COLOR_TAPPED))
		return
	else
		local reaction = UnitReaction(unit, 'player')
		if reaction and not issecret(reaction) then
			if reaction <= 3 then
				bar:SetStatusBarColor(unpack(REACTION_HOSTILE))
			elseif reaction == 4 then
				bar:SetStatusBarColor(unpack(REACTION_NEUTRAL))
			else
				bar:SetStatusBarColor(unpack(REACTION_FRIENDLY))
			end
			return
		end
	end

	bar:SetStatusBarColor(unpack(REACTION_FRIENDLY))
end

local function UpdatePower(frame)
	local unit = frame.unit
	local powerType, powerToken = UnitPowerType(unit)
	local cur = UnitPower(unit, powerType)
	local max = UnitPowerMax(unit, powerType)

	local color = (powerToken and not issecret(powerToken) and PowerBarColor[powerToken])
		or PowerBarColor.MANA
	frame.power:SetStatusBarColor(color.r, color.g, color.b)

	frame.power:SetMinMaxValues(0, max)
	frame.power:SetValue(cur)

	if not issecret(max) and max == 0 then
		frame.powerText:SetText('')
	else
		frame.powerText:SetText(Short(cur) .. ' / ' .. Short(max))
	end
end

local function UpdateLevel(frame)
	local unit = frame.unit
	local level = (UnitEffectiveLevel and UnitEffectiveLevel(unit)) or UnitLevel(unit)

	if issecret(level) then
		frame.levelText:SetText(level)
	elseif level and level > 0 then
		frame.levelText:SetText(level)
	else
		frame.levelText:SetText('??')
	end
end

-- player only: level circle turns red in combat, yellow while resting
local function UpdatePlayerStatus()
	local frame = frames.player
	if not frame then return end

	if UnitAffectingCombat('player') then
		frame.levelBg:SetVertexColor(unpack(STATUS_COMBAT))
		frame.levelText:SetTextColor(1, 1, 1)
	elseif IsResting() then
		frame.levelBg:SetVertexColor(unpack(STATUS_RESTING))
		frame.levelText:SetTextColor(0, 0, 0)
	else
		frame.levelBg:SetVertexColor(unpack(STATUS_NONE))
		frame.levelText:SetTextColor(0, 0, 0)
	end
end

-- target only: loot bag icon while the target is a corpse you can loot.
-- CanLootUnit is missing on some clients and the GUID can be secret in
-- restricted content; either way the icon just stays hidden.
local CanLootUnit = CanLootUnit

local function UpdateLoot(frame)
	local icon = frame.lootIcon
	if not icon then return end

	local lootable = false
	if CanLootUnit and UnitExists(frame.unit) then
		local dead = UnitIsDead(frame.unit)
		local guid = UnitGUID(frame.unit)
		if not issecret(dead) and dead and guid and not issecret(guid) then
			local hasLoot, canLoot = CanLootUnit(guid)
			lootable = not issecret(hasLoot) and not issecret(canLoot)
				and hasLoot and canLoot or false
		end
	end
	icon:SetShown(lootable)
end

--------------------------------------------------------------------------------
-- Class power pips (combo points, chi, holy power, soul shards, arcane
-- charges, essence). Blizzard keeps these non-secret in Midnight.
--------------------------------------------------------------------------------

local CLASS_POWER = {
	ROGUE = { type = Enum.PowerType.ComboPoints, token = 'COMBO_POINTS' },
	DRUID = { type = Enum.PowerType.ComboPoints, token = 'COMBO_POINTS' },
	MONK = { type = Enum.PowerType.Chi, token = 'CHI' },
	PALADIN = { type = Enum.PowerType.HolyPower, token = 'HOLY_POWER' },
	WARLOCK = { type = Enum.PowerType.SoulShards, token = 'SOUL_SHARDS' },
	MAGE = { type = Enum.PowerType.ArcaneCharges, token = 'ARCANE_CHARGES' },
	EVOKER = { type = Enum.PowerType.Essence, token = 'ESSENCE' },
}

local function GetSpec()
	if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
		return C_SpecializationInfo.GetSpecialization()
	end
	return GetSpecialization and GetSpecialization()
end

local function UpdateClassPower()
	local frame = frames.player
	local pips = frame and frame.classPower
	if not pips then return end

	local _, playerClass = UnitClass('player')
	local info = CLASS_POWER[playerClass]
	if not info then pips:Hide() return end

	-- druid combo points only matter in cat form; arcane charges only as arcane
	if playerClass == 'DRUID' and UnitPowerType('player') ~= Enum.PowerType.Energy then
		pips:Hide()
		return
	end
	if playerClass == 'MAGE' and GetSpec() ~= 1 then
		pips:Hide()
		return
	end

	local cur = UnitPower('player', info.type)
	local max = UnitPowerMax('player', info.type)
	if issecret(cur) or issecret(max) or max == 0 then
		pips:Hide()
		return
	end

	local color = CLASS_POWER_COLORS[info.token]
	local width = (frame:GetWidth() - (max - 1) * 2) / max
	for i = 1, max do
		local pip = pips.segments[i]
		if not pip then
			pip = pips:CreateTexture(nil, 'ARTWORK')
			pip:SetTexture(WHITE8X8)
			pips.segments[i] = pip
		end
		pip:ClearAllPoints()
		pip:SetPoint('TOPLEFT', pips, 'TOPLEFT', (i - 1) * (width + 2), 0)
		pip:SetSize(width, pips:GetHeight())
		if i <= cur then
			pip:SetVertexColor(color[1], color[2], color[3], 1)
		else
			pip:SetVertexColor(0.15, 0.15, 0.15, 0.9)
		end
		pip:Show()
	end
	for i = max + 1, #pips.segments do
		pips.segments[i]:Hide()
	end

	pips:Show()
end

--------------------------------------------------------------------------------
-- Frame construction
--------------------------------------------------------------------------------

local function UpdateAll(frame)
	UpdateName(frame)
	UpdateHealthColor(frame)
	UpdateHealth(frame)
	UpdatePower(frame)
	UpdateLevel(frame)
	if frame.unit == 'player' then
		UpdatePlayerStatus()
		UpdateClassPower()
	end
	UpdateLoot(frame)
end

local function OnUnitEvent(frame, event)
	if event == 'UNIT_HEALTH' or event == 'UNIT_MAXHEALTH' then
		UpdateHealth(frame)
		UpdateLoot(frame)
	elseif event == 'UNIT_FLAGS' then
		UpdateLoot(frame)
	elseif event == 'UNIT_POWER_FREQUENT' or event == 'UNIT_MAXPOWER' then
		UpdatePower(frame)
		if frame.unit == 'player' then UpdateClassPower() end
	elseif event == 'UNIT_DISPLAYPOWER' then
		UpdatePower(frame)
		if frame.unit == 'player' then UpdateClassPower() end
	elseif event == 'UNIT_NAME_UPDATE' then
		UpdateName(frame)
		UpdateHealthColor(frame)
	elseif event == 'UNIT_LEVEL' then
		UpdateLevel(frame)
	elseif event == 'UNIT_FACTION' or event == 'UNIT_CONNECTION' then
		UpdateHealthColor(frame)
	end
end

local function SavePosition(frame)
	local point, _, _, x, y = frame:GetPoint()
	BenisUI.db.unitframes.positions[frame.unit] = { point = point, x = x, y = y }
end

local function CreateUnitFrame(unit)
	local layout = UNIT_LAYOUT[unit]
	local frame = CreateFrame('Button', 'BenisUI' .. unit .. 'Frame', UIParent,
		'SecureUnitButtonTemplate,BackdropTemplate')

	frame.unit = unit
	frame:SetSize(layout.width, layout.height)
	frame:SetFrameStrata('MEDIUM')

	local saved = BenisUI.db.unitframes.positions[unit]
	if saved then
		frame:SetPoint(saved.point, UIParent, saved.point, saved.x, saved.y)
	else
		local point = layout.point
		frame:SetPoint(point[1], UIParent, point[1], point[2], point[3])
	end

	-- secure click behaviour
	frame:SetAttribute('unit', unit)
	frame:SetAttribute('type1', 'target')
	frame:SetAttribute('type2', 'togglemenu')
	frame:SetAttribute('*type2', 'togglemenu')
	frame:RegisterForClicks('AnyUp')

	-- shift-drag to move (out of combat)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag('LeftButton')
	frame:SetScript('OnDragStart', function(self)
		if IsShiftKeyDown() and not InCombatLockdown() then
			self:StartMoving()
		end
	end)
	frame:SetScript('OnDragStop', function(self)
		self:StopMovingOrSizing()
		SavePosition(self)
	end)

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

	local name = CreateText(health, layout.nameSize)
	name:SetPoint('TOPLEFT', 6, -5)
	name:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -layout.circle * 0.6, -5)
	name:SetJustifyH('LEFT')
	frame.nameText = name
	frame.nameSize = layout.nameSize

	local healthText = CreateText(health, layout.healthSize)
	healthText:SetPoint('LEFT', frame, 'LEFT', 9,
		math.floor((layout.powerHeight - layout.nameSize) * 0.5 - 2 + 0.5))
	healthText:SetJustifyH('LEFT')
	frame.healthText = healthText

	local powerText = CreateText(power, layout.powerSize)
	powerText:SetPoint('LEFT', power, 'LEFT', 5, 0)
	powerText:SetJustifyH('LEFT')
	frame.powerText = powerText

	-- separate overlay frame so the circle draws above the status bars
	local overlay = CreateFrame('Frame', nil, frame)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(frame:GetFrameLevel() + 5)

	local ring, circleBg = CreateCircle(overlay, layout.circle)
	ring:SetPoint('CENTER', frame, 'TOPRIGHT', -4, -2)
	frame.levelBg = circleBg

	-- no outline on the level number; the circle gives contrast
	local levelText = CreateText(overlay, layout.levelSize, '')
	levelText:SetDrawLayer('OVERLAY', 7)
	levelText:SetPoint('CENTER', ring, 'CENTER', 0, 0)
	levelText:SetTextColor(0, 0, 0)
	frame.levelText = levelText

	if unit == 'target' then
		local lootIcon = overlay:CreateTexture(nil, 'OVERLAY', nil, 7)
		lootIcon:SetTexture('Interface\\GroupFrame\\UI-Group-MasterLooter')
		lootIcon:SetSize(18, 18)
		lootIcon:SetPoint('RIGHT', ring, 'LEFT', -2, 0)
		lootIcon:Hide()
		frame.lootIcon = lootIcon
		frame:RegisterUnitEvent('UNIT_FLAGS', unit)
	end

	-- unit events (targettarget gets none of these; it runs off a ticker)
	if unit ~= 'targettarget' then
		frame:RegisterUnitEvent('UNIT_HEALTH', unit)
		frame:RegisterUnitEvent('UNIT_MAXHEALTH', unit)
		frame:RegisterUnitEvent('UNIT_POWER_FREQUENT', unit)
		frame:RegisterUnitEvent('UNIT_MAXPOWER', unit)
		frame:RegisterUnitEvent('UNIT_DISPLAYPOWER', unit)
		frame:RegisterUnitEvent('UNIT_NAME_UPDATE', unit)
		frame:RegisterUnitEvent('UNIT_LEVEL', unit)
		frame:RegisterUnitEvent('UNIT_FACTION', unit)
		frame:RegisterUnitEvent('UNIT_CONNECTION', unit)
		frame:SetScript('OnEvent', OnUnitEvent)
	end

	if unit == 'player' then
		local pips = CreateFrame('Frame', nil, frame)
		pips:SetPoint('TOPLEFT', frame, 'BOTTOMLEFT', 0, -3)
		pips:SetPoint('TOPRIGHT', frame, 'BOTTOMRIGHT', 0, -3)
		pips:SetHeight(8)
		pips.segments = {}
		frame.classPower = pips
	end

	if unit == 'player' then
		frame:Show()
	else
		RegisterUnitWatch(frame)
	end

	return frame
end

--------------------------------------------------------------------------------
-- Blizzard frame removal (oUF-style: silence events, hide, reparent)
--------------------------------------------------------------------------------

local hiddenParent = CreateFrame('Frame', nil, UIParent)
hiddenParent:SetAllPoints()
hiddenParent:Hide()

local function HideBlizzardFrame(frame)
	if not frame then return end

	frame:UnregisterAllEvents()
	frame:Hide()
	frame:SetParent(hiddenParent)

	local health = frame.healthbar or frame.HealthBar
		or (frame.HealthBarsContainer and frame.HealthBarsContainer.healthbar)
	if health then health:UnregisterAllEvents() end

	local power = frame.manabar or frame.ManaBar
	if power then power:UnregisterAllEvents() end
end

-- shared with the party / raid frames (GroupFrames.lua)
UnitFrames.CreateText = CreateText
UnitFrames.SetFittedText = SetFittedText
UnitFrames.FullName = FullName
UnitFrames.Short = Short
UnitFrames.UpdateHealthColor = UpdateHealthColor
UnitFrames.HideBlizzardFrame = HideBlizzardFrame

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

function UnitFrames:OnInit()
	BenisUI.db.unitframes = BenisUI.db.unitframes or { positions = {} }
	BenisUI.db.unitframes.positions = BenisUI.db.unitframes.positions or {}

	HideBlizzardFrame(_G.PlayerFrame)
	HideBlizzardFrame(_G.TargetFrame)
	HideBlizzardFrame(_G.FocusFrame)

	for unit in pairs(UNIT_LAYOUT) do
		frames[unit] = CreateUnitFrame(unit)
	end

	local controller = CreateFrame('Frame')
	controller:RegisterEvent('PLAYER_ENTERING_WORLD')
	controller:RegisterEvent('PLAYER_TARGET_CHANGED')
	controller:RegisterEvent('PLAYER_FOCUS_CHANGED')
	controller:RegisterUnitEvent('UNIT_TARGET', 'target')
	controller:RegisterEvent('PLAYER_REGEN_DISABLED')
	controller:RegisterEvent('PLAYER_REGEN_ENABLED')
	controller:RegisterEvent('PLAYER_UPDATE_RESTING')
	controller:RegisterEvent('PLAYER_LEVEL_UP')
	controller:RegisterEvent('PLAYER_SPECIALIZATION_CHANGED')
	controller:RegisterEvent('UPDATE_SHAPESHIFT_FORM')
	controller:RegisterEvent('UI_SCALE_CHANGED')
	controller:RegisterEvent('DISPLAY_SIZE_CHANGED')
	controller:RegisterEvent('LOOT_OPENED')
	controller:RegisterEvent('LOOT_CLOSED')

	controller:SetScript('OnEvent', function(_, event)
		if event == 'PLAYER_ENTERING_WORLD' then
			for _, frame in pairs(frames) do
				UpdateAll(frame)
			end
		elseif event == 'PLAYER_TARGET_CHANGED' then
			UpdateAll(frames.target)
			UpdateAll(frames.targettarget)
		elseif event == 'PLAYER_FOCUS_CHANGED' then
			UpdateAll(frames.focus)
		elseif event == 'UNIT_TARGET' then
			UpdateAll(frames.targettarget)
		elseif event == 'PLAYER_REGEN_DISABLED' or event == 'PLAYER_REGEN_ENABLED'
			or event == 'PLAYER_UPDATE_RESTING' then
			UpdatePlayerStatus()
		elseif event == 'PLAYER_LEVEL_UP' then
			UpdateLevel(frames.player)
		elseif event == 'PLAYER_SPECIALIZATION_CHANGED' or event == 'UPDATE_SHAPESHIFT_FORM' then
			UpdatePower(frames.player)
			UpdateClassPower()
		elseif event == 'UI_SCALE_CHANGED' or event == 'DISPLAY_SIZE_CHANGED' then
			RefreshFonts()
		elseif event == 'LOOT_OPENED' or event == 'LOOT_CLOSED' then
			UpdateLoot(frames.target)
		end
	end)

	-- targettarget has no unit events of its own; poll while visible.
	-- A dead target is polled too: loot shows up a moment after the kill and
	-- goes away when someone else loots it, with no reliable event for either.
	C_Timer.NewTicker(0.3, function()
		local tot = frames.targettarget
		if tot and tot:IsShown() then
			UpdateAll(tot)
		end
		local target = frames.target
		if target and target:IsShown() then
			local dead = UnitIsDead('target')
			if not issecret(dead) and dead then
				UpdateLoot(target)
			end
		end
	end)
end
