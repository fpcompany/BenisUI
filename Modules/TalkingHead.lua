local _, ns = ...
local BenisUI = ns.BenisUI

-- Auto-skips the talking head widget (the animated NPC portrait that pops up
-- with voiced dialogue) and cuts its voice line short. Driven by the
-- TALKINGHEAD_REQUESTED game event rather than hooks into Blizzard's frame
-- code, so it doesn't care what the talking head addon or its methods are
-- called this expansion. The chat-log transcript is untouched.
local TalkingHead = BenisUI:RegisterModule('TalkingHead')

local function Dismiss()
	local frame = _G.TalkingHeadFrame
	if not frame or not frame:IsShown() then return end
	if frame.CloseImmediately then
		frame:CloseImmediately()
	elseif frame.Close then
		frame:Close()
	else
		frame:Hide()
	end
end

-- disabling the dialog sound channel stops the line that just started
-- playing; re-enable shortly after so other NPC voiceovers stay audible
local restoreTimer
local function CutVoiceLine()
	if not GetCVarBool('Sound_EnableDialog') and not restoreTimer then
		return -- dialog audio is off anyway; don't fight the user's setting
	end
	SetCVar('Sound_EnableDialog', 0)
	if restoreTimer then restoreTimer:Cancel() end
	restoreTimer = C_Timer.NewTimer(1, function()
		restoreTimer = nil
		SetCVar('Sound_EnableDialog', 1)
	end)
end

-- belt and suspenders: if the frame re-shows itself for queued lines without
-- a new TALKINGHEAD_REQUESTED, catch it via OnShow
local hooked = false
local function TryHookFrame()
	if hooked then return end
	local frame = _G.TalkingHeadFrame
	if not frame then return end
	hooked = true
	frame:HookScript('OnShow', function()
		CutVoiceLine()
		C_Timer.After(0, Dismiss)
	end)
end

function TalkingHead:OnInit()
	local events = CreateFrame('Frame')
	if not pcall(events.RegisterEvent, events, 'TALKINGHEAD_REQUESTED') then
		print('|cff1784d1Benis|rUI: TALKINGHEAD_REQUESTED event no longer exists; talking head auto-skip is inactive')
		return
	end
	events:SetScript('OnEvent', function()
		CutVoiceLine()
		-- let Blizzard's handler show the frame first, then dismiss it;
		-- the second pass catches lines that start with a delay
		C_Timer.After(0, function()
			TryHookFrame()
			Dismiss()
		end)
		C_Timer.After(0.3, Dismiss)
	end)

	TryHookFrame()
end
