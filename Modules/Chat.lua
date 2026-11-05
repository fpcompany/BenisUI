local _, ns = ...
local BenisUI = ns.BenisUI

-- Restyles the chat windows to the house look: Blizzard's frame art, side
-- button bar and scrollbar gone, a flat dark panel behind the text, text-only
-- tabs and a flat input box. Each window gets a small copy button that opens
-- its history in a plain-text window so lines can be selected and copied.
--
-- The input box also gets normal arrow-key behavior: Blizzard's template sets
-- ignoreArrows, which is why Left/Right don't move the cursor without Alt.
local Chat = BenisUI:RegisterModule('Chat')

local FONT = BenisUI.media.font
local Skin = BenisUI.Skin

local CHAT_ALPHA = 0.7 -- the chat panel is see-through, unlike windows
local DEFAULT_FONT_SIZE = 12
local TAB_FONT_SIZE = 11
local EDITBOX_HEIGHT = 20

local MIN_WIDTH, MIN_HEIGHT = 200, 80
local MAX_WIDTH, MAX_HEIGHT = 1200, 900

local hidden = CreateFrame('Frame')
hidden:Hide()

-- Out of sight but still registered for events and still a valid anchor:
-- Blizzard code keeps calling into these, it just never shows them again.
local function Park(frame)
	if not frame then return end
	frame:SetParent(hidden)
	frame:SetAlpha(0)
end

--------------------------------------------------------------------------------
-- Copy window
--------------------------------------------------------------------------------

local copyFrame, copyBox, copyScroll

-- Chat lines are full of escape sequences an edit box would show raw or copy
-- as junk; boil them down to what was actually readable.
local function PlainText(text)
	text = text:gsub('|T.-|t', '') -- textures (raid marks, role icons)
	text = text:gsub('|A.-|a', '') -- atlases
	text = text:gsub('|H.-|h(.-)|h', '%1') -- links: keep the [label]
	text = text:gsub('|c%x%x%x%x%x%x%x%x', '')
	text = text:gsub('|cn.-:', '') -- named colors: |cnCOLOR_NAME:text|r
	text = text:gsub('|r', '')
	return text
end

local function CollectLines(chatFrame)
	local lines = {}
	for index = 1, chatFrame:GetNumMessages() do
		local text = chatFrame:GetMessageInfo(index)
		if issecretvalue and issecretvalue(text) then
			lines[#lines + 1] = '<message hidden by the game>'
		elseif type(text) == 'string' then
			lines[#lines + 1] = PlainText(text)
		end
	end
	return table.concat(lines, '\n')
end

local function ScrollToBottom()
	copyScroll:SetVerticalScroll(copyScroll:GetVerticalScrollRange())
end

local function CreateCopyFrame()
	copyFrame = CreateFrame('Frame', 'BenisUIChatCopyFrame', UIParent, 'BackdropTemplate')
	copyFrame:Hide()
	copyFrame:SetSize(640, 420)
	copyFrame:SetPoint('CENTER')
	copyFrame:SetFrameStrata('DIALOG')
	copyFrame:SetToplevel(true)
	copyFrame:SetMovable(true)
	copyFrame:SetClampedToScreen(true)
	copyFrame:EnableMouse(true)
	Skin:Panel(copyFrame)
	tinsert(UISpecialFrames, 'BenisUIChatCopyFrame')

	local header = CreateFrame('Frame', nil, copyFrame)
	header:SetPoint('TOPLEFT')
	header:SetPoint('TOPRIGHT')
	header:SetHeight(26)
	header:EnableMouse(true)
	header:RegisterForDrag('LeftButton')
	header:SetScript('OnDragStart', function() copyFrame:StartMoving() end)
	header:SetScript('OnDragStop', function() copyFrame:StopMovingOrSizing() end)

	local title = header:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
	title:SetPoint('LEFT', 8, 0)
	copyFrame.title = title

	local hint = header:CreateFontString(nil, 'OVERLAY')
	hint:SetFont(FONT, 11, 'OUTLINE')
	hint:SetTextColor(0.6, 0.6, 0.6)
	hint:SetPoint('LEFT', title, 'RIGHT', 10, 0)
	hint:SetText('Ctrl+A to select all, Ctrl+C to copy')

	local close = CreateFrame('Button', nil, header, 'UIPanelCloseButton')
	close:SetPoint('RIGHT', -2, 0)
	close:SetScript('OnClick', function() copyFrame:Hide() end)

	copyScroll = CreateFrame('ScrollFrame', nil, copyFrame)
	copyScroll:SetPoint('TOPLEFT', 8, -30)
	copyScroll:SetPoint('BOTTOMRIGHT', -8, 8)
	copyScroll:EnableMouse(true)
	copyScroll:EnableMouseWheel(true)
	copyScroll:SetScript('OnMouseWheel', function(self, delta)
		local offset = self:GetVerticalScroll() - delta * 42
		self:SetVerticalScroll(math.max(0, math.min(offset, self:GetVerticalScrollRange())))
	end)

	local inset = Skin:Backdrop(copyFrame, copyScroll, 4)
	inset:SetBackdropColor(0.03, 0.03, 0.03, 1)

	copyBox = CreateFrame('EditBox', nil, copyScroll)
	copyBox:SetMultiLine(true)
	copyBox:SetAutoFocus(false)
	copyBox:SetMaxLetters(0)
	copyBox:SetFont(FONT, 13, '')
	copyBox:SetTextColor(1, 1, 1)
	copyBox:SetWidth(copyScroll:GetWidth())
	copyScroll:SetScrollChild(copyBox)
	copyScroll:SetScript('OnSizeChanged', function(_, width) copyBox:SetWidth(width) end)

	copyBox:SetScript('OnEscapePressed', function() copyFrame:Hide() end)
	-- edit boxes have no select-all of their own
	copyBox:SetScript('OnKeyDown', function(self, key)
		if key == 'A' and IsControlKeyDown() then self:HighlightText() end
	end)
	-- read-only: typing would only scramble the log
	copyBox:SetScript('OnTextChanged', function(self, userInput)
		if userInput then self:SetText(self.original or '') end
	end)
	-- keep the cursor in view when moving it with the keyboard
	copyBox:SetScript('OnCursorChanged', function(_, _, y, _, height)
		y = -y
		local offset = copyScroll:GetVerticalScroll()
		local visible = copyScroll:GetHeight()
		if y < offset then
			copyScroll:SetVerticalScroll(y)
		elseif y + height > offset + visible then
			copyScroll:SetVerticalScroll(math.min(y + height - visible, copyScroll:GetVerticalScrollRange()))
		end
	end)
	-- clicking anywhere in the panel focuses the text, not just on a line
	copyScroll:SetScript('OnMouseDown', function() copyBox:SetFocus() end)
	copyFrame:SetScript('OnHide', function() copyBox:ClearFocus() end)
end

function Chat:ShowCopy(chatFrame)
	if not copyFrame then CreateCopyFrame() end

	local text = CollectLines(chatFrame)
	copyBox.original = text
	copyBox:SetText(text)

	local tab = _G[chatFrame:GetName() .. 'Tab']
	local name = tab and tab:GetText() or chatFrame:GetName()
	copyFrame.title:SetText('|cff1784d1Benis|rUI Chat: ' .. name)

	copyFrame:Show()
	copyBox:SetFocus()
	copyBox:SetCursorPosition(#text)
	-- the scroll range only updates once the text is laid out
	C_Timer.After(0, ScrollToBottom)
end

local function CreateCopyButton(chatFrame)
	local button = CreateFrame('Button', nil, chatFrame)
	button:SetSize(18, 18)
	button:SetPoint('TOPRIGHT', chatFrame, 'TOPRIGHT', -16, 2)
	button:SetFrameLevel(chatFrame:GetFrameLevel() + 5)
	button:SetAlpha(0.35)

	local icon = button:CreateTexture(nil, 'ARTWORK')
	icon:SetTexture('Interface\\Buttons\\UI-GuildButton-PublicNote-Up')
	icon:SetAllPoints()

	button:SetScript('OnClick', function() Chat:ShowCopy(chatFrame) end)
	button:SetScript('OnEnter', function(self)
		self:SetAlpha(1)
		GameTooltip:SetOwner(self, 'ANCHOR_TOPLEFT')
		GameTooltip:SetText('Copy chat')
		GameTooltip:Show()
	end)
	button:SetScript('OnLeave', function(self)
		self:SetAlpha(0.35)
		GameTooltip:Hide()
	end)
end

--------------------------------------------------------------------------------
-- Resizing
--------------------------------------------------------------------------------

-- Docked windows all follow the dock's primary window (ChatFrame1), which Edit
-- Mode places and sizes. Sizing is done with plain SetSize rather than
-- StartSizing so the Edit Mode anchor (bottom-left by default) stays put and
-- the window grows up and to the right from the top-right grip.
local function SizingTarget(chatFrame)
	if chatFrame.isDocked and GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK.primary then
		return GENERAL_CHAT_DOCK.primary
	end
	return chatFrame
end

local function ApplySavedSize()
	local size = BenisUI.db.chat.size
	local primary = _G.DEFAULT_CHAT_FRAME
	if size and primary then
		primary:SetSize(size[1], size[2])
	end
end

local function SaveSize(target)
	if target == _G.DEFAULT_CHAT_FRAME then
		BenisUI.db.chat.size = { math.floor(target:GetWidth()), math.floor(target:GetHeight()) }
	elseif FCF_SavePositionAndDimensions then
		FCF_SavePositionAndDimensions(target)
	end
end

local function SizingUpdate(grip)
	local target = grip.target
	local scale = target:GetEffectiveScale()
	local x, y = GetCursorPosition()
	local width = grip.startWidth + (x - grip.startX) / scale
	local height = grip.startHeight + (y - grip.startY) / scale
	target:SetSize(
		math.max(MIN_WIDTH, math.min(MAX_WIDTH, width)),
		math.max(MIN_HEIGHT, math.min(MAX_HEIGHT, height))
	)
end

local function CreateResizeGrip(chatFrame)
	local grip = CreateFrame('Button', nil, chatFrame)
	grip:SetSize(14, 14)
	grip:SetPoint('TOPRIGHT', chatFrame, 'TOPRIGHT', 4, 4)
	grip:SetFrameLevel(chatFrame:GetFrameLevel() + 5)
	grip:SetAlpha(0.35)

	local texture = grip:CreateTexture(nil, 'ARTWORK')
	texture:SetTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up')
	texture:SetTexCoord(0, 1, 1, 0) -- the art points bottom-right; flip it up
	texture:SetAllPoints()

	grip:SetScript('OnEnter', function(self) self:SetAlpha(1) end)
	grip:SetScript('OnLeave', function(self)
		if not self.target then self:SetAlpha(0.35) end
	end)
	grip:SetScript('OnMouseDown', function(self, button)
		if button ~= 'LeftButton' then return end
		local target = SizingTarget(chatFrame)
		self.target = target
		self.startX, self.startY = GetCursorPosition()
		self.startWidth, self.startHeight = target:GetSize()
		self:SetScript('OnUpdate', SizingUpdate)
	end)
	grip:SetScript('OnMouseUp', function(self)
		if not self.target then return end
		self:SetScript('OnUpdate', nil)
		SaveSize(self.target)
		self.target = nil
		if not self:IsMouseOver() then self:SetAlpha(0.35) end
	end)
end

--------------------------------------------------------------------------------
-- Channel names
--------------------------------------------------------------------------------

-- '[1. General - Dun Morogh]' -> '[1]'. The link stays, so clicking the tag
-- still opens a reply to that channel.
local function ShortenChannels(text)
	return (text:gsub('|Hchannel:(.-)|h%[(%d+)%..-%]|h', '|Hchannel:%1|h[%2]|h'))
end

local function WrapAddMessage(chatFrame)
	local original = chatFrame.AddMessage
	chatFrame.AddMessage = function(self, text, ...)
		-- Midnight hands some lines over as secret values; those can't be
		-- read or rewritten, so they go through untouched
		if not (issecretvalue and issecretvalue(text)) and type(text) == 'string' then
			text = ShortenChannels(text)
		end
		return original(self, text, ...)
	end
end

--------------------------------------------------------------------------------
-- Chat windows
--------------------------------------------------------------------------------

local function SkinTab(tab)
	if not tab or tab.BenisUISkinned then return end
	tab.BenisUISkinned = true

	-- keep the new-message glow and the whisper conversation icon
	for _, region in next, { tab:GetRegions() } do
		if region:IsObjectType('Texture') and region ~= tab.glow and region ~= tab.conversationIcon then
			region:SetTexture(nil)
			region:SetAlpha(0)
		end
	end

	local text = tab.Text or tab:GetFontString()
	if text then
		text:SetFont(FONT, TAB_FONT_SIZE, 'OUTLINE')
		text:SetShadowOffset(0, 0)
	end
end

local function SkinEditBox(chatFrame, editBox)
	if not editBox or editBox.BenisUISkinned then return end

	Skin:EditBox(editBox) -- sets BenisUISkinned

	-- the template's ignoreArrows: Left/Right move the cursor, Up/Down walk
	-- the sent-message history
	editBox:SetAltArrowKeyMode(false)

	-- the default anchor hangs off the scrollbar we park; tie it to the chat
	editBox:ClearAllPoints()
	editBox:SetPoint('TOPLEFT', chatFrame, 'BOTTOMLEFT', -4, -6)
	editBox:SetPoint('TOPRIGHT', chatFrame, 'BOTTOMRIGHT', 4, -6)
	editBox:SetHeight(EDITBOX_HEIGHT)

	local _, size = chatFrame:GetFont()
	Chat:SetEditBoxFontSize(editBox, size)
end

function Chat:SetEditBoxFontSize(editBox, size)
	size = size or DEFAULT_FONT_SIZE
	editBox:SetFont(FONT, size, '')
	for _, key in next, { 'header', 'headerSuffix', 'languageHeader' } do
		local fontString = editBox[key]
		if fontString then
			fontString:SetFont(FONT, size, '')
		end
	end
end

local function SkinChatFrame(chatFrame)
	if not chatFrame or chatFrame.BenisUISkinned then return end
	chatFrame.BenisUISkinned = true

	local name = chatFrame:GetName()

	for _, texture in next, CHAT_FRAME_TEXTURES or {} do
		local region = _G[name .. texture]
		if region then
			region:SetTexture(nil)
			region:SetAlpha(0)
		end
	end

	Park(chatFrame.buttonFrame or _G[name .. 'ButtonFrame'])
	Park(chatFrame.ScrollBar)

	-- the jump-to-bottom arrow hangs off the resize grip, which sits on
	-- Blizzard's (now invisible) border art outside the text area; tuck it
	-- into the panel's bottom-right corner instead
	local scrollDown = chatFrame.ScrollToBottomButton
	if scrollDown then
		scrollDown:ClearAllPoints()
		scrollDown:SetPoint('BOTTOMRIGHT', chatFrame, 'BOTTOMRIGHT', 0, 0)
	end

	-- a flat panel with a little bleed so the text doesn't touch the edge;
	-- it hides with the window, so only the selected docked tab draws one
	local backdrop = Skin:Backdrop(chatFrame, nil, 4)
	backdrop:SetFrameLevel(math.max(0, chatFrame:GetFrameLevel() - 1))
	backdrop:SetBackdropColor(Skin.body[1], Skin.body[2], Skin.body[3], CHAT_ALPHA)

	local _, size = chatFrame:GetFont()
	chatFrame:SetFont(FONT, size or 14, '')
	chatFrame:SetShadowOffset(1, -1)
	chatFrame:SetShadowColor(0, 0, 0, 1)

	SkinTab(_G[name .. 'Tab'])
	SkinEditBox(chatFrame, chatFrame.editBox or _G[name .. 'EditBox'])
	CreateCopyButton(chatFrame)
	CreateResizeGrip(chatFrame)

	-- the combat log builds its own lines; only chat windows get shortened
	if chatFrame ~= _G.ChatFrame2 then WrapAddMessage(chatFrame) end
end

-- The chat font size is ours, not Blizzard's: Blizzard reapplies its
-- server-stored size on every UPDATE_CHAT_WINDOWS, which arrives after login,
-- so ours goes back on right after it.
local function ApplyFontSize()
	local size = BenisUI.chardb.chat.fontSize or DEFAULT_FONT_SIZE
	for _, name in next, CHAT_FRAMES or {} do
		local chatFrame = _G[name]
		if chatFrame and chatFrame.BenisUISkinned then
			local file, _, flags = chatFrame:GetFont()
			chatFrame:SetFont(file or FONT, size, flags or '')
			local editBox = chatFrame.editBox
			if editBox and editBox.BenisUISkinned then
				Chat:SetEditBoxFontSize(editBox, size)
			end
		end
	end
end

local function SkinAll()
	for _, name in next, CHAT_FRAMES or {} do
		SkinChatFrame(_G[name])
	end
end

-- Blizzard colors the selected tab's text gold; selected is white, the rest
-- grey. Whisper tabs keep their own channel color.
local function UpdateTabColors(tab, selected)
	if not tab.BenisUISkinned or tab.selectedColorTable then return end
	local text = tab:GetFontString()
	if not text then return end
	if selected then
		text:SetTextColor(1, 1, 1)
	else
		text:SetTextColor(0.6, 0.6, 0.6)
	end
end

function Chat:OnInit()
	SkinAll()
	ApplyFontSize()

	local fonts = CreateFrame('Frame')
	fonts:RegisterEvent('UPDATE_CHAT_WINDOWS')
	fonts:SetScript('OnEvent', function() C_Timer.After(0, ApplyFontSize) end)

	-- the tab menu's Font Size sets the size for every window
	if FCF_SetChatWindowFontSize then
		hooksecurefunc('FCF_SetChatWindowFontSize', function(_, _, size)
			if type(size) == 'number' and size > 0 then
				BenisUI.chardb.chat.fontSize = size
			end
			ApplyFontSize()
		end)
	end

	-- Edit Mode's box around the chat is a fixed margin that leaves room for
	-- Blizzard's side buttons, tab art and input border, none of which we
	-- show. Fit it to what's actually drawn: the tab row, the panel's bleed
	-- and the input box underneath. Edit Mode snaps by this box, so docking
	-- the chat to a screen edge now puts the panel itself against it.
	local selection = _G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.Selection
	if selection then
		selection:ClearAllPoints()
		selection:SetPoint('TOPLEFT', _G.DEFAULT_CHAT_FRAME, 'TOPLEFT', -4, 24)
		selection:SetPoint('BOTTOMRIGHT', _G.DEFAULT_CHAT_FRAME, 'BOTTOMRIGHT', 4, -(6 + EDITBOX_HEIGHT))
	end

	-- Edit Mode owns the main window's size and reapplies its own on layout
	-- updates; put ours back afterwards. Resizing in Edit Mode itself wins:
	-- whatever size the window has on leaving Edit Mode becomes the saved one.
	ApplySavedSize()
	local sizer = CreateFrame('Frame')
	sizer:RegisterEvent('EDIT_MODE_LAYOUTS_UPDATED')
	sizer:RegisterEvent('PLAYER_ENTERING_WORLD')
	sizer:SetScript('OnEvent', function() C_Timer.After(0, ApplySavedSize) end)
	if EventRegistry then
		EventRegistry:RegisterCallback('EditMode.Exit', function()
			if BenisUI.db.chat.size then SaveSize(_G.DEFAULT_CHAT_FRAME) end
		end, Chat)
	end

	-- the side buttons (social, channels, voice) sit on parked or loose frames
	Park(_G.ChatFrameMenuButton)
	Park(_G.ChatFrameChannelButton)
	Park(_G.ChatFrameToggleVoiceDeafenButton)
	Park(_G.ChatFrameToggleVoiceMuteButton)
	Park(_G.QuickJoinToastButton)

	-- whisper / pet battle windows are created on demand
	if FCF_OpenTemporaryWindow then
		hooksecurefunc('FCF_OpenTemporaryWindow', function()
			SkinAll()
			ApplyFontSize()
		end)
	end

	if FCFTab_UpdateColors then
		hooksecurefunc('FCFTab_UpdateColors', UpdateTabColors)
		local selected = GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow
			and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
		for _, name in next, CHAT_FRAMES or {} do
			local chatFrame, tab = _G[name], _G[name .. 'Tab']
			if chatFrame and tab then
				UpdateTabColors(tab, chatFrame == selected or not chatFrame.isDocked)
			end
		end
	end

	-- the combat log's filter bar
	Skin:Strip(_G.CombatLogQuickButtonFrame_Custom)
end
