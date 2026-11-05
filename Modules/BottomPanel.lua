local _, ns = ...
local BenisUI = ns.BenisUI

-- Bottom-right panel holding a bags button, the (relocated) Blizzard micro
-- menu buttons and an FPS readout. Replaces the default bag bar and the
-- micro menu container.
local BottomPanel = BenisUI:RegisterModule('BottomPanel')

local FONT = BenisUI.media.font
local Skin = BenisUI.Skin

local PANEL_HEIGHT = 30
local MICRO_SCALE = 0.62
local FPS_WIDTH = 52

-- superset across game versions; only the ones that exist get placed
local MICRO_BUTTONS = {
	'CharacterMicroButton',
	'ProfessionMicroButton',
	'PlayerSpellsMicroButton',
	'SpellbookMicroButton',
	'TalentMicroButton',
	'AchievementMicroButton',
	'QuestLogMicroButton',
	'GuildMicroButton',
	'LFDMicroButton',
	'CollectionsMicroButton',
	'EJMicroButton',
	'StoreMicroButton',
	'HousingMicroButton',
	'MainMenuMicroButton',
	'HelpMicroButton',
}

local panel

local hidden = CreateFrame('Frame')
hidden:Hide()

local function Kill(frame)
	if not frame then return end
	frame:UnregisterAllEvents()
	frame:Hide()
	frame:SetParent(hidden)
end

--------------------------------------------------------------------------------
-- Bags button
--------------------------------------------------------------------------------

local function CreateBagsButton()
	local button = CreateFrame('Button', 'BenisUIBagsButton', panel)
	button:SetSize(22, 22)
	button:SetPoint('LEFT', panel, 'LEFT', 5, 0)

	local icon = button:CreateTexture(nil, 'ARTWORK')
	icon:SetTexture('Interface\\Buttons\\Button-Backpack-Up')
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetAllPoints()

	Skin:Border(button)

	local highlight = button:CreateTexture(nil, 'HIGHLIGHT')
	highlight:SetColorTexture(1, 1, 1, 0.2)
	highlight:SetAllPoints()

	button:SetScript('OnClick', function()
		ToggleAllBags()
	end)
	button:SetScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, 'ANCHOR_TOP')
		GameTooltip:SetText(BAGSLOT or 'Bags')
		GameTooltip:Show()
	end)
	button:SetScript('OnLeave', function()
		GameTooltip:Hide()
	end)

	return button
end

--------------------------------------------------------------------------------
-- Micro menu
--------------------------------------------------------------------------------

local function LayoutMicroButtons()
	local x = 34 -- room for the bags button
	for _, name in next, MICRO_BUTTONS do
		local button = _G[name]
		if button and button:IsShown() then
			button:SetParent(panel)
			button:SetScale(MICRO_SCALE)
			button:ClearAllPoints()
			-- coordinates are in the button's scaled space
			button:SetPoint('BOTTOMLEFT', panel, 'BOTTOMLEFT', x / MICRO_SCALE, 2 / MICRO_SCALE)
			x = x + button:GetWidth() * MICRO_SCALE + 1
		end
	end

	panel:SetWidth(x + FPS_WIDTH + 8)
end

local function SetupMicroMenu()
	for _, name in next, MICRO_BUTTONS do
		local button = _G[name]
		if button then
			button:SetParent(panel)
		end
	end

	LayoutMicroButtons()

	-- Blizzard re-anchors the buttons on various events; take them back
	if _G.UpdateMicroButtons then
		hooksecurefunc('UpdateMicroButtons', LayoutMicroButtons)
	end
	local microMenu = _G.MicroMenu
	if microMenu and microMenu.Layout then
		hooksecurefunc(microMenu, 'Layout', LayoutMicroButtons)
	end

	Kill(_G.MicroMenuContainer)
	Kill(_G.BagsBar)
	Kill(_G.MicroButtonAndBagsBar)

	-- the LFG queue eye normally lives on the micro menu
	local queue = _G.QueueStatusButton
	if queue then
		queue:SetParent(panel)
		queue:SetScale(0.55)
		queue:ClearAllPoints()
		queue:SetPoint('RIGHT', panel, 'RIGHT', (-FPS_WIDTH - 4) / 0.55, 0)
	end
end

--------------------------------------------------------------------------------
-- FPS
--------------------------------------------------------------------------------

local function CreateFPS()
	local text = panel:CreateFontString(nil, 'OVERLAY')
	text:SetFont(FONT, 12, 'OUTLINE')
	text:SetPoint('RIGHT', panel, 'RIGHT', -8, 0)
	text:SetJustifyH('RIGHT')
	text:SetTextColor(1, 1, 1)

	C_Timer.NewTicker(0.5, function()
		text:SetFormattedText('%.0f fps', GetFramerate())
	end)
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

function BottomPanel:OnInit()
	panel = CreateFrame('Frame', 'BenisUIBottomPanel', UIParent, 'BackdropTemplate')
	panel:SetSize(420, PANEL_HEIGHT)
	panel:SetPoint('BOTTOMRIGHT', UIParent, 'BOTTOMRIGHT', -2, 2)
	panel:SetFrameStrata('LOW')

	Skin:Panel(panel)

	CreateBagsButton()
	SetupMicroMenu()
	CreateFPS()

	-- re-run once late: some buttons (store/help) settle after login
	C_Timer.After(2, LayoutMicroButtons)
end
