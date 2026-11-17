local _, ns = ...
local BenisUI = ns.BenisUI

-- The player's own debuffs, in a row above an enemy's name, and the buffs on
-- an enemy player that your group can dispel, in a row above that: a cropped
-- icon in a black border, the stack count in its corner and
-- the seconds left in its middle, going from white to yellow to red as it runs
-- out.
--
-- Lua cannot do this. Wherever auras are secret -- every instance, every fight
-- that matters -- each C_UnitAuras call throws under taint, and ElvUI's own
-- aura element has nothing to read there. The door is the client's
-- `AuraContainer` widget (the one Plater draws enemy auras with): the addon
-- creates the container and says what to filter for, and the CLIENT creates
-- and fills the buttons. The addon supplies the regions, once, inside
-- `initializeFrame`; nothing ever comes back, and nothing needs to.
--
--   * 'HARMFUL|PLAYER' is filtered client-side, so "only mine" is expressible
--     although Lua can never ask whose a debuff is.
--   * 'HELPFUL|RAID_PLAYER_DISPELLABLE' likewise, for "can come off": Blizzard's
--     token for auras someone in the player's group can dispel, enrages on
--     enemies included (AuraUtil.AuraFilters). It is what Plater's purge icons
--     run on, so it holds on a hostile unit in combat, where isStealable and
--     dispelName are secret. Solo, the group is you: a class with no purge
--     sees an empty row.
--   * A button's regions may be touched ONLY inside initializeFrame. The
--     restriction lands the moment it returns, so everything a button will
--     ever look like is decided there, and each binding is its own pcall: an
--     error in that callback leaves a half-built button and no traceback.
--   * A container whose token stops resolving freezes in its last state, and
--     SetUnit with the token it already holds is a no-op. So a plate that
--     loses its unit is PARKED on a token that resolves to nobody, and a new
--     unit is followed by UpdateAllAuras.
local Nameplates = BenisUI:GetModule('Nameplates')

-- Resolves to nobody outside a 40-player raid; inside one the container is on
-- a hidden frame anyway.
local PARK = 'raid40'

-- what each row is filtered for, client-side
local DEBUFFS = 'HARMFUL|PLAYER'
local BUFFS = 'HELPFUL|RAID_PLAYER_DISPELLABLE'

local function InitializeButton(button, m)
	button:SetSize(m.auraWidth, m.auraHeight)

	local backdrop = button:CreateTexture(nil, 'BACKGROUND')
	backdrop:SetAllPoints(button)
	backdrop:SetColorTexture(0, 0, 0, 1)

	-- Inset a pixel, so the backdrop is the border.
	local icon = button:CreateTexture(nil, 'ARTWORK')
	icon:SetPoint('TOPLEFT', button, 'TOPLEFT', 1, -1)
	icon:SetPoint('BOTTOMRIGHT', button, 'BOTTOMRIGHT', -1, 1)
	-- Wider than tall: take the middle band of the art instead of squashing it.
	local band = 0.84 * m.auraHeight / m.auraWidth
	icon:SetTexCoord(0.08, 0.92, 0.5 - band / 2, 0.5 + band / 2)
	pcall(button.SetIcon, button, icon)

	local cooldown = CreateFrame('Cooldown', nil, button, 'CooldownFrameTemplate')
	cooldown:SetAllPoints(icon)
	cooldown:SetHideCountdownNumbers(true)
	if cooldown.SetDrawEdge then cooldown:SetDrawEdge(false) end
	if cooldown.SetReverse then cooldown:SetReverse(true) end
	pcall(button.SetDurationCooldown, button, cooldown)

	-- Above the swipe, or the numbers darken with the icon.
	local text = CreateFrame('Frame', nil, button)
	text:SetAllPoints(button)
	text:SetFrameLevel(cooldown:GetFrameLevel() + 2)

	local count = text:CreateFontString(nil, 'OVERLAY')
	Nameplates.SetFont(count, m.small)
	count:SetPoint('BOTTOMRIGHT', button, 'BOTTOMRIGHT', 2, -2)
	pcall(button.SetApplicationCount, button, count)

	local timer = text:CreateFontString(nil, 'OVERLAY')
	Nameplates.SetFont(timer, m.small)
	timer:SetPoint('CENTER', button, 'CENTER', 0, 1)

	local bound = BenisUI.AuraTimer.BindText(button, timer)
	if not bound then
		-- No text binding on this build: the cooldown's own numbers will do.
		cooldown:SetHideCountdownNumbers(false)
	end
end

-- The container, `false` when this client will not make one, nil to try again.
local function Create(f, filter)
	local m = Nameplates.Metrics()

	local ok, container = pcall(CreateFrame, 'AuraContainer', nil, f, 'CustomAuraContainerTemplate')
	if not ok or not container then
		-- Built on the first unit a plate carries that wants the row, which can be
		-- mid-fight. A refusal then is not a verdict on the client.
		if InCombatLockdown() then return nil end
		return false
	end

	container:SetSize(m.width, m.auraHeight)
	pcall(container.SetUnit, container, PARK)

	local layout = {
		elementWidth = m.auraWidth,
		elementHeight = m.auraHeight,
		elementSpacing = 2,
		lineSpacing = 2,
		groupSpacing = 2,
		groupLineSpacing = 2,
		-- One line: the row never grows a second storey over the plate above.
		maximumLineSize = m.width,
	}
	local options = {
		maxFrameCount = math.max(1, math.floor((m.width + 2) / (m.auraWidth + 2))),
		sortMethod = AuraContainerSortMethod and AuraContainerSortMethod.Default or nil,
		sortDirection = AuraContainerSortDirection and AuraContainerSortDirection.Normal or nil,
		initializeFrame = function(button) InitializeButton(button, m) end,
		layout = layout,
	}

	if not pcall(container.AddAuraGroup, container, filter, filter, options) then
		container:Hide()
		return false
	end
	pcall(container.SetAuraGroupLayout, container, filter, layout)
	pcall(container.SetEnabled, container, true)
	return container
end

local function Park(container)
	if container then pcall(container.SetUnit, container, PARK) end
end

local function Follow(container, unit)
	pcall(container.SetUnit, container, unit)
	pcall(container.UpdateAllAuras, container)
end

-- `key` is the field on the plate: f.Auras for debuffs, f.Buffs for buffs.
local function Row(f, key, filter, wanted)
	if not wanted then
		Park(f[key])
		return nil
	end
	if f[key] == nil then f[key] = Create(f, filter) end
	local container = f[key]
	if not container then return nil end
	Follow(container, f.unit)
	return container
end

function Nameplates.AttachAuras(f)
	local db = BenisUI.db.nameplates

	-- A friend on a frame that carried an enemy a moment ago parks the debuffs.
	local debuffs = Row(f, 'Auras', DEBUFFS, db.debuffs and f.hostile)
	-- Only enemies: a buff on a friend is nothing anyone wants dispelled.
	local buffs = Row(f, 'Buffs', BUFFS, db.buffs and f.isPlayer and f.hostile)

	if debuffs then
		debuffs:ClearAllPoints()
		debuffs:SetPoint('BOTTOMLEFT', f.Name, 'TOPLEFT', 0, 3)
	end
	if buffs then
		-- On top of the debuff row when there is one, so the two never overlap.
		buffs:ClearAllPoints()
		if debuffs then
			buffs:SetPoint('BOTTOMLEFT', debuffs, 'TOPLEFT', 0, 2)
		else
			buffs:SetPoint('BOTTOMLEFT', f.Name, 'TOPLEFT', 0, 3)
		end
	end
end

function Nameplates.DetachAuras(f)
	Park(f.Auras)
	Park(f.Buffs)
end
