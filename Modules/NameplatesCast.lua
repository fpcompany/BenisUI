local _, ns = ...
local BenisUI = ns.BenisUI

-- The cast bar under a nameplate's health bar: gold while the cast can be
-- interrupted, red inside a red border while it cannot, the spell's icon to
-- the right spanning both bars, the name and the time left underneath.
--
-- On an enemy EVERY field of UnitCastingInfo / UnitChannelInfo is secret while
-- a cast runs and nil when none does, so nothing here ever looks at one. What
-- each field is allowed (ElvUI's retail cast bar is the working example):
--
--   name             `not name` -- truthiness is the one legal test, and it is
--                    what tells "casting" from "idle". Then SetText.
--   texture          SetTexture.
--   start / end      nothing, when secret. Progress comes from the DURATION
--                    OBJECT (UnitCastingDuration / UnitChannelDuration) handed
--                    to StatusBar:SetTimerDuration, and the client animates
--                    the bar. The numbers are used only when `issecretvalue`
--                    says they are plain.
--   notInterruptible a secret BOOLEAN, which throws on `if`. The red border
--                    takes it through SetAlphaFromBoolean (oUF's shield); the
--                    bar's colour through C_CurveUtil.EvaluateColorFromBoolean,
--                    whose channels SetVertexColor accepts. If that second
--                    door is ever shut the bar stays gold and the border still
--                    tells the truth, which is why there are two.
--
-- Note the positions: notInterruptible is return 8 of UnitCastingInfo and 7 of
-- UnitChannelInfo on WoW Forever and retail alike -- only what sits at 7 of
-- the former differs between them, and it is not read.
local Nameplates = BenisUI:GetModule('Nameplates')

local Secret, Plain = Nameplates.Secret, Nameplates.Plain

local CASTING = { 1.00, 0.81, 0.20 }
local LOCKED = { 0.78, 0.25, 0.25 }
local BROKEN = { 0.30, 0.30, 0.30 }

local castingColor = CreateColor and CreateColor(CASTING[1], CASTING[2], CASTING[3], 1)
local lockedColor = CreateColor and CreateColor(LOCKED[1], LOCKED[2], LOCKED[3], 1)

-- How long an interrupted bar stays up saying so.
local HOLD = 0.75

local INTERPOLATION = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
local DIRECTION = Enum and Enum.StatusBarTimerDirection or {}

local EVENTS = {
	'UNIT_SPELLCAST_START', 'UNIT_SPELLCAST_STOP', 'UNIT_SPELLCAST_FAILED',
	'UNIT_SPELLCAST_INTERRUPTED', 'UNIT_SPELLCAST_DELAYED',
	'UNIT_SPELLCAST_CHANNEL_START', 'UNIT_SPELLCAST_CHANNEL_STOP',
	'UNIT_SPELLCAST_CHANNEL_UPDATE',
	'UNIT_SPELLCAST_INTERRUPTIBLE', 'UNIT_SPELLCAST_NOT_INTERRUPTIBLE',
	-- retail only; the registration skips what a client does not know
	'UNIT_SPELLCAST_EMPOWER_START', 'UNIT_SPELLCAST_EMPOWER_STOP',
	'UNIT_SPELLCAST_EMPOWER_UPDATE',
}

local function Tint(bar, color)
	bar:GetStatusBarTexture():SetVertexColor(color[1], color[2], color[3])
end

-- `locked` is notInterruptible: plain, secret, or nil.
local function SetLocked(bar, locked)
	-- Read off the plate each time: hostility can change under a cast.
	if not bar.plate.hostile then
		-- A friend's cast is never ours to interrupt; ElvUI draws those plain.
		bar.Shield:SetAlpha(0)
		Tint(bar, CASTING)
		return
	end

	if not Secret(locked) then
		bar.Shield:SetAlpha(locked and 1 or 0)
		Tint(bar, locked and LOCKED or CASTING)
		return
	end

	bar.Shield:SetAlphaFromBoolean(locked, 1, 0)
	local painted = castingColor and C_CurveUtil and pcall(function()
		local color = C_CurveUtil.EvaluateColorFromBoolean(locked, lockedColor, castingColor)
		bar:GetStatusBarTexture():SetVertexColor(color.r, color.g, color.b)
	end)
	if not painted then Tint(bar, CASTING) end
end

-- Shows whatever the unit is casting right now. False when it is not.
local function Show(bar)
	local unit = bar.unit
	if not unit then return false end

	local name, _, texture, startTime, endTime, _, _, locked = UnitCastingInfo(unit)
	local channel = false
	if not name then
		name, _, texture, startTime, endTime, _, locked = UnitChannelInfo(unit)
		channel = true
	end
	if not name then return false end

	bar.hold = nil
	bar.channel = channel
	bar.duration, bar.start, bar.finish = nil, nil, nil

	bar.Text:SetText(name)
	bar.Time:SetText('')
	bar.Icon:SetTexture(texture)
	SetLocked(bar, locked)

	local duration
	if channel then
		duration = UnitChannelDuration and UnitChannelDuration(unit)
	else
		duration = UnitCastingDuration and UnitCastingDuration(unit)
	end

	if duration and bar.SetTimerDuration and pcall(bar.SetTimerDuration, bar, duration,
			INTERPOLATION, channel and DIRECTION.RemainingTime or DIRECTION.ElapsedTime) then
		bar.duration = duration
	else
		local from, to = Plain(startTime), Plain(endTime)
		if type(from) == 'number' and type(to) == 'number' and to > from then
			bar.start, bar.finish = from / 1000, to / 1000
			bar:SetMinMaxValues(0, bar.finish - bar.start)
			bar:SetValue(channel and bar.finish - GetTime() or GetTime() - bar.start)
		else
			-- Cannot be timed at all. A full bar still says "casting", and what.
			bar:SetMinMaxValues(0, 1)
			bar:SetValue(1)
		end
	end

	bar.sinceText, bar.sinceCheck = 1, 0
	bar:Show()
	return true
end

local function Interrupted(bar)
	if not bar:IsShown() then return end
	bar.duration, bar.start, bar.finish = nil, nil, nil
	bar.hold = GetTime() + HOLD
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)
	bar.Shield:SetAlpha(0)
	Tint(bar, BROKEN)
	bar.Text:SetText(INTERRUPTED or 'Interrupted')
	bar.Time:SetText('')
end

local function OnEvent(bar, event, unit)
	if unit ~= bar.unit then return end

	if event == 'UNIT_SPELLCAST_INTERRUPTED' then
		Interrupted(bar)
	elseif event == 'UNIT_SPELLCAST_INTERRUPTIBLE' then
		if not bar.hold then SetLocked(bar, false) end
	elseif event == 'UNIT_SPELLCAST_NOT_INTERRUPTIBLE' then
		if not bar.hold then SetLocked(bar, true) end
	elseif not Show(bar) and not bar.hold then
		-- Every other event is answered by asking again: a STOP for a cast
		-- that was already replaced must not take the new one down.
		bar:Hide()
	end
end

-- Runs only while the bar is shown.
local function OnUpdate(bar, elapsed)
	local now = GetTime()

	if bar.hold then
		if now >= bar.hold then
			bar.hold = nil
			bar:Hide()
		end
		return
	end

	if bar.finish then
		local left = bar.finish - now
		if left <= 0 then
			bar:Hide()
			return
		end
		bar:SetValue(bar.channel and left or now - bar.start)
	end

	bar.sinceText = bar.sinceText + elapsed
	if bar.sinceText >= 0.05 then
		bar.sinceText = 0
		if bar.finish then
			bar.Time:SetFormattedText('%.1f', bar.finish - now)
		elseif bar.duration then
			-- A secret number, formatted and drawn by the client.
			pcall(function()
				bar.Time:SetFormattedText('%.1f', bar.duration:GetRemainingDuration())
			end)
		end
	end

	-- The safety net for an end the events did not deliver: a bar the client
	-- animates has no deadline this side can see.
	bar.sinceCheck = bar.sinceCheck + elapsed
	if bar.sinceCheck >= 0.25 then
		bar.sinceCheck = 0
		local unit = bar.unit
		if not unit or (not UnitCastingInfo(unit) and not UnitChannelInfo(unit)) then
			bar:Hide()
		end
	end
end

function Nameplates.BuildCast(f, m)
	local health = f.Health

	local bar = Nameplates.Bar(f, m.width, m.cast)
	-- Border, one clear pixel, border.
	bar:SetPoint('TOPLEFT', health, 'BOTTOMLEFT', 0, -3)
	bar.Backdrop:SetVertexColor(0.08, 0.08, 0.08, 0.9)
	bar:Hide()

	-- The red border of a cast that cannot be interrupted, drawn over the
	-- black one. Its own frame, so one alpha is the whole answer.
	local shield = CreateFrame('Frame', nil, bar)
	shield:SetAllPoints(bar)
	Nameplates.Outline(shield, bar, 'OVERLAY', 1, 1.00, 0.15, 0.15, 1)
	shield:SetAlpha(0)
	bar.Shield = shield

	local text = CreateFrame('Frame', nil, bar)
	text:SetAllPoints(bar)
	text:SetFrameLevel(bar:GetFrameLevel() + 5)

	local time = text:CreateFontString(nil, 'OVERLAY')
	Nameplates.SetFont(time, m.small)
	time:SetPoint('TOPRIGHT', bar, 'BOTTOMRIGHT', 1, -3)
	time:SetJustifyH('RIGHT')
	bar.Time = time

	local name = text:CreateFontString(nil, 'OVERLAY')
	Nameplates.SetFont(name, m.small)
	name:SetPoint('TOPLEFT', bar, 'BOTTOMLEFT', 0, -3)
	name:SetPoint('TOPRIGHT', time, 'TOPLEFT', -2, 0)
	name:SetJustifyH('LEFT')
	bar.Text = name

	-- Square, from the top of the health bar to the bottom of this one.
	local size = m.health + 3 + m.cast
	local icon = bar:CreateTexture(nil, 'ARTWORK')
	icon:SetSize(size, size)
	icon:SetPoint('TOPLEFT', health, 'TOPRIGHT', 4, 0)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	Nameplates.Outline(bar, icon, 'BORDER', 1, 0, 0, 0, 1)
	bar.Icon = icon

	bar.plate = f
	bar:SetScript('OnEvent', OnEvent)
	bar:SetScript('OnUpdate', OnUpdate)
	f.Cast = bar
end

function Nameplates.AttachCast(f)
	local bar = f.Cast
	if not bar then return end
	bar.unit = f.unit
	bar.hold = nil
	bar:UnregisterAllEvents()
	Nameplates.RegisterUnitEvents(bar, EVENTS, f.unit)
	-- A plate can appear with its mob already mid-cast.
	if not Show(bar) then bar:Hide() end
end

function Nameplates.DetachCast(f)
	local bar = f.Cast
	if not bar then return end
	bar.unit = nil
	bar.hold = nil
	bar:UnregisterAllEvents()
	bar:Hide()
end
