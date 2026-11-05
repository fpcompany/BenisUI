local _, ns = ...
local BenisUI = ns.BenisUI

-- Draws a strong border around your focus on Blizzard's compact party and
-- raid frames. Those frames are protected but not forbidden: adding a child
-- frame and toggling it is allowed, even in combat, as long as the protected
-- frame itself is never moved, resized, shown or hidden by addon code.
local FocusHighlight = BenisUI:RegisterModule('FocusHighlight')

local Skin = BenisUI.Skin

-- every compact unit frame the hook has seen that belongs to a group frame
local frames = setmetatable({}, { __mode = 'k' })

-- Nameplates and arena frames run through the same CompactUnitFrame code;
-- only the player's own group should get the border.
local function IsGroupFrame(frame)
	local unit = frame.displayedUnit or frame.unit
	if type(unit) ~= 'string' then return false end
	return unit == 'player' or unit:find('^party') ~= nil or unit:find('^raid') ~= nil
end

local function UpdateBorder(frame)
	if frame:IsForbidden() then return end

	local border = frame.BenisUIFocusBorder
	if not IsGroupFrame(frame) then
		if border then border:Hide() end
		return
	end

	frames[frame] = true

	local db = BenisUI.db.focusHighlight
	if not border then
		border = Skin:Border(frame, db.thickness)
		border:SetFrameLevel(frame:GetFrameLevel() + 10)
		border:Hide()
		frame.BenisUIFocusBorder = border
	end
	local color = db.color
	Skin:SetBorder(border, frame, db.thickness, color[1], color[2], color[3])

	if UnitExists('focus') and UnitIsUnit(frame.displayedUnit, 'focus') then
		border:Show()
	else
		border:Hide()
	end
end

local function UpdateAllBorders()
	for frame in next, frames do
		UpdateBorder(frame)
	end
end

function FocusHighlight:OnInit()
	-- runs on every target change and full refresh of a compact frame, so the
	-- border follows frames as they are reassigned to other units
	if CompactUnitFrame_UpdateSelectionHighlight then
		hooksecurefunc('CompactUnitFrame_UpdateSelectionHighlight', UpdateBorder)
	end

	-- compact frames don't listen for focus changes themselves
	local watcher = CreateFrame('Frame')
	watcher:RegisterEvent('PLAYER_FOCUS_CHANGED')
	watcher:SetScript('OnEvent', UpdateAllBorders)
end
