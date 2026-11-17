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
	text = text:gsub('|K.-|k', '') -- Battle.net name tokens
	text = text:gsub('|n', ' ')
	-- a stray pipe starts an escape the edit box chokes on, which can blank
	-- the whole text; doubled it shows as a plain |
	text = text:gsub('|', '||')
	return text
end

-- Every line a chat window shows is also kept here, so the copy window never
-- depends on the frame handing its history back (Midnight's chat frames
-- don't always do that).
local HISTORY_LINES = 500
local SECRET_LINE = '<message hidden by the game>'

local function RecordLine(chatFrame, text)
	local log = chatFrame.BenisUILog
	if not log then
		log = {}
		chatFrame.BenisUILog = log
	end
	if issecretvalue and issecretvalue(text) then
		log[#log + 1] = SECRET_LINE
	elseif type(text) == 'string' then
		log[#log + 1] = text
	else
		return
	end
	if #log > HISTORY_LINES * 1.2 then
		local trimmed = {}
		for i = #log - HISTORY_LINES + 1, #log do trimmed[#trimmed + 1] = log[i] end
		chatFrame.BenisUILog = trimmed
	end
end

local function CollectLines(chatFrame)
	local source = chatFrame.BenisUILog
	if not source or #source == 0 then
		source = {}
		local count = chatFrame.GetNumMessages and chatFrame:GetNumMessages() or 0
		for index = 1, count do
			local text = chatFrame:GetMessageInfo(index)
			source[#source + 1] = (issecretvalue and issecretvalue(text)) and SECRET_LINE or text
		end
	end

	local lines = {}
	for _, text in ipairs(source) do
		if text == SECRET_LINE then
			lines[#lines + 1] = text
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
	copyBox:SetPoint('TOPLEFT')
	copyBox:SetSize(600, 380) -- replaced by the real width once shown
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

	local tab = _G[chatFrame:GetName() .. 'Tab']
	local name = tab and tab:GetText() or chatFrame:GetName()
	copyFrame.title:SetText('|cff1784d1Benis|rUI Chat: ' .. name)

	copyFrame:Show()

	-- a scroll child with no width lays its text out into nothing; size it
	-- now that the panel is shown and measured
	local width = copyScroll:GetWidth()
	if width and width > 0 then copyBox:SetWidth(width) end

	local text = CollectLines(chatFrame)
	if text == '' then text = '(this window has no messages yet)' end
	copyBox.original = text
	copyBox:SetText(text)
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
		RecordLine(self, text)
		return original(self, text, ...)
	end
end

--------------------------------------------------------------------------------
-- Spam filter
--------------------------------------------------------------------------------

-- Gold sellers post community invites named after their site
-- ("[Join: WWW,XYZ,COM-Player buy&sell ...]"). No real player needs those in
-- public chat, so any message carrying a community or club-finder link is
-- dropped before it reaches a window.
local SPAM_EVENTS = {
	'CHAT_MSG_CHANNEL', 'CHAT_MSG_SAY', 'CHAT_MSG_YELL', 'CHAT_MSG_EMOTE',
	'CHAT_MSG_WHISPER',
}

local function IsJoinSpam(_, _, msg)
	if type(msg) ~= 'string' or (issecretvalue and issecretvalue(msg)) then return false end
	return msg:find('|HclubFinder:') ~= nil
		or msg:find('|HclubTicket:') ~= nil
		or msg:find('|Hcommunity') ~= nil
		or msg:find('%[Join: ') ~= nil
end

local function InstallSpamFilter()
	local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
	if not add then return end
	for _, event in next, SPAM_EVENTS do
		add(event, IsJoinSpam)
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

--------------------------------------------------------------------------------
-- Sent-message history
--------------------------------------------------------------------------------

-- Blizzard's own history stores each line with its channel prefix ("/g hi"),
-- so recalling one drags the input box back to the channel it was sent in.
-- Ours keeps only what was typed: Up/Down bring the text back and it goes to
-- whichever channel the box is on now. One list for every chat window, saved
-- account-wide.
local HISTORY_MAX = 50

local function OnHistoryLineAdded(editBox, line)
	-- Blizzard adds the line while the typed text is still in the box
	local text = editBox:GetText()
	if not text or strtrim(text) == '' then text = line end
	text = text and strtrim(text)

	-- only ours answers the arrows
	if editBox.ClearHistory then editBox:ClearHistory() end
	editBox.BenisUIHistoryIndex = 0
	editBox.BenisUIDraft = nil

	if not text or text == '' then return end

	local history = BenisUI.db.chat.history
	if history[#history] == text then return end
	history[#history + 1] = text
	while #history > HISTORY_MAX do
		table.remove(history, 1)
	end
end

local function OnHistoryArrow(editBox, key)
	if key ~= 'UP' and key ~= 'DOWN' then return end

	local history = BenisUI.db.chat.history
	local index = editBox.BenisUIHistoryIndex or 0 -- 0 is the unsent draft

	if key == 'UP' then
		if index >= #history then return end
		if index == 0 then editBox.BenisUIDraft = editBox:GetText() end
		index = index + 1
	else
		if index == 0 then return end
		index = index - 1
	end

	editBox.BenisUIHistoryIndex = index
	editBox:SetText(index == 0 and (editBox.BenisUIDraft or '') or history[#history - index + 1])
	editBox:SetCursorPosition(#editBox:GetText())
end

local function ResetHistoryWalk(editBox)
	editBox.BenisUIHistoryIndex = 0
	editBox.BenisUIDraft = nil
end

local function SkinEditBox(chatFrame, editBox)
	if not editBox or editBox.BenisUISkinned then return end

	Skin:EditBox(editBox) -- sets BenisUISkinned

	-- the template's ignoreArrows: Left/Right move the cursor, Up/Down walk
	-- the sent-message history
	editBox:SetAltArrowKeyMode(false)

	if editBox.ClearHistory then editBox:ClearHistory() end
	hooksecurefunc(editBox, 'AddHistoryLine', OnHistoryLineAdded)
	editBox:HookScript('OnArrowPressed', OnHistoryArrow)
	editBox:HookScript('OnEditFocusGained', ResetHistoryWalk)

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
	InstallSpamFilter()
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
	--
	-- The same box sets the screen clamp (UpdateClampOffsets measures it), so
	-- it has to be refit whenever Edit Mode re-measures. Left on Blizzard's
	-- -32px margin, a chat placed against the left edge gets clamped ~28px
	-- to the right on every load.
	local chatFrame = _G.DEFAULT_CHAT_FRAME
	local selection = chatFrame and chatFrame.Selection
	if selection then
		local function FitSelection()
			selection:ClearAllPoints()
			selection:SetPoint('TOPLEFT', chatFrame, 'TOPLEFT', -4, 24)
			selection:SetPoint('BOTTOMRIGHT', chatFrame, 'BOTTOMRIGHT', 4, -(6 + EDITBOX_HEIGHT))
			if chatFrame:GetLeft() then
				chatFrame:SetClampRectInsets(-4, 4, 24, -(6 + EDITBOX_HEIGHT))
			end
		end
		FitSelection()
		if chatFrame.AnchorSelectionFrame then
			hooksecurefunc(chatFrame, 'AnchorSelectionFrame', FitSelection)
		end
		if chatFrame.UpdateClampOffsets then
			hooksecurefunc(chatFrame, 'UpdateClampOffsets', FitSelection)
		end
	end

	-- Edit Mode owns the main window's size and reapplies its own on layout
	-- updates; put ours back afterwards. Resizing in Edit Mode itself wins:
	-- whatever size the window has on leaving Edit Mode becomes the saved one.
	--
	-- Its position is Edit Mode's too, but at login the window lands off its
	-- saved spot (clamped against Blizzard's wider box, or moved by the chat
	-- code's own position restore) until Edit Mode next applies its anchor.
	-- Put it back on the saved anchor the same way Edit Mode does.
	local function RestoreAnchor()
		local chat = _G.DEFAULT_CHAT_FRAME
		local info = chat and chat.systemInfo
		local anchor = info and info.anchorInfo
		if not anchor or InCombatLockdown() then return end
		if chat.IsInDefaultPosition and chat:IsInDefaultPosition() then return end
		local scale = chat:GetScale()
		chat:ClearAllPoints()
		chat:SetPoint(anchor.point, anchor.relativeTo, anchor.relativePoint,
			anchor.offsetX / scale, anchor.offsetY / scale)
		local anchor2 = info.anchorInfo2
		if anchor2 then
			chat:SetPoint(anchor2.point, anchor2.relativeTo, anchor2.relativePoint,
				anchor2.offsetX / scale, anchor2.offsetY / scale)
		end
	end

	ApplySavedSize()
	local sizer = CreateFrame('Frame')
	sizer:RegisterEvent('EDIT_MODE_LAYOUTS_UPDATED')
	sizer:RegisterEvent('PLAYER_ENTERING_WORLD')
	sizer:RegisterEvent('UPDATE_CHAT_WINDOWS')
	sizer:SetScript('OnEvent', function()
		C_Timer.After(0, function()
			ApplySavedSize()
			RestoreAnchor()
		end)
	end)
	if FCF_RestorePositionAndDimensions then
		hooksecurefunc('FCF_RestorePositionAndDimensions', function(chat)
			if chat == _G.DEFAULT_CHAT_FRAME then RestoreAnchor() end
		end)
	end
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

--------------------------------------------------------------------------------
-- /bait
--------------------------------------------------------------------------------

-- Sends a confidently wrong complaint to whichever channel the input box is
-- on. The level baits brag about a level ten above ours (capped) and claim to
-- be stuck 10-15 below it; the rest do the same with a skill or a gold total.
local BAIT_LEVEL_CAP = 60
local BAIT_LINE = 'How are people already %s? I %s but I\'m still %s. Yeah the game is ruined by exploiters.'

-- "I <activity> ..." - each one slow, pointless or worth no experience at all
local LEVEL_BAITS = {
	'kill critters in Elwynn for 8 hours every day',
	'only fight mobs 15 levels below me for 9 hours every day',
	'stay logged out in an inn 22 hours every day to stack rested exp',
	'duel outside Goldshire for 8 hours every day',
	'walk instead of run between quests for 10 hours every day',
	'fight with no weapon equipped for 8 hours every day',
	'rediscover every zone on the map for 7 hours every day',
	'do every grey quest in the starting zone for 8 hours every day',
	'run Ragefire Chasm solo for 12 hours every day',
	'pick Peacebloom for 8 hours every day',
	'save all my quests for one big hand-in, 8 hours every day for a month now,',
	'die on purpose and run back for 6 hours every day',
	'dance on the Ironforge mailbox for 8 hours every day',
	'only kill boars in the starting zone for 8 hours every day',
}

-- { what others "already" have, what we do about it, lowest and highest we claim to be stuck at }
local OTHER_BAITS = {
	{ '300 Fishing', 'fish in the Stormwind fountain for 8 hours every day', 12, 31, '%d' },
	{ '300 First Aid', 'bandage myself at full health for 6 hours every day', 1, 40, '%d' },
	{ '300 Cooking', 'cook Charred Wolf Meat for 8 hours every day', 20, 45, '%d' },
	{ '300 Herbalism', 'pick only Peacebloom for 9 hours every day', 35, 60, '%d' },
	{ '300 Mining', 'mine nothing but Copper for 8 hours every day', 40, 65, '%d' },
	{ '300 Lockpicking', 'pick the same practice lockbox for 7 hours every day', 60, 95, '%d' },
	{ 'riding an epic mount', 'vendor grey items from critters for 10 hours every day', 2, 9, 'at %d gold' },
	{ 'at max weapon skill', 'punch level 1 rabbits unarmed for 8 hours every day', 15, 50, 'at %d' },
	{ 'Exalted with Stormwind', 'kill Defias thugs outside Stormwind for 8 hours every day', 1, 1, 'Neutral' },
}

-- "I am going to make a reddit thread with petition to <idea>. Please upvote"
local REDDIT_LINE = 'I am going to make a reddit thread with petition to %s. Please upvote'
local REDDIT_BAITS = {
	'add Vulperas to Forever',
	'nerf hunters',
	'add flying mounts to Forever',
	'add a dungeon finder with teleports',
	'add a level 60 boost to the shop',
	'add the WoW Token',
	'remove world PvP',
	'make all loot personal',
	'add raid finder difficulty',
	'buff rogues',
	'remove the talent trees',
	'add heirlooms',
	'make mounts free at level 1',
	'remove the corpse run',
	'add pet battles',
	'let Alliance and Horde group together',
	'add Mythic+ to all dungeons',
	'remove professions because they are boring',
	'nerf %s', -- filled with a random classic class
	'make every class able to tank',
	'add transmog and a cash shop for it',
	'remove mana because drinking is not fun',
}

-- Hero classes that don't exist on Forever. %1$s is the class, %2$d the level
-- we insist unlocks it (always one we have already reached), %3$d our level.
local HERO_CLASSES = { 'Death Knight', 'Demon Hunter', 'Evoker' }
local HERO_BAITS = {
	'How do I unlock %1$s? You need level %2$d and I\'m already %3$d but the class is still not on my character screen.',
	'I hit level %2$d days ago and %1$s is still locked for me. Where is the quest? I\'m %3$d now and nothing.',
	'Is %1$s bugged? The requirement is level %2$d, I\'m %3$d and I still can\'t create one. Already opened 3 tickets.',
	'Why can everyone else make a %1$s? I\'m level %3$d, way past the %2$d you need, and the button is not even there.',
	'Can a GM unlock %1$s for me? I met the level %2$d requirement (I\'m %3$d) and relogged 20 times. Still nothing.',
	'Anyone else not getting the %1$s unlock at %2$d? I\'m %3$d. My friend got his at %2$d instantly.',
}

local function BuildHeroBait()
	local level = UnitLevel('player') or 1
	-- the "requirement" is the last multiple of five we passed
	local required = math.max(1, math.floor(level / 5) * 5)
	return HERO_BAITS[math.random(#HERO_BAITS)]:format(HERO_CLASSES[math.random(#HERO_CLASSES)], required, level)
end

local function BuildBait()
	local roll = math.random(4)
	if roll == 1 then
		return BuildHeroBait()
	elseif roll < 4 then
		local level = UnitLevel('player') or 1
		local theirs = math.min(level + 10, BAIT_LEVEL_CAP)
		local mine = math.max(1, level - math.random(10, 15))
		return BAIT_LINE:format(theirs .. '+', LEVEL_BAITS[math.random(#LEVEL_BAITS)], tostring(mine))
	end
	local bait = OTHER_BAITS[math.random(#OTHER_BAITS)]
	return BAIT_LINE:format(bait[1], bait[2], bait[5]:format(math.random(bait[3], bait[4])))
end

local CLASSIC_CLASSES = { 'warriors', 'paladins', 'hunters', 'rogues', 'priests', 'shamans', 'mages', 'warlocks', 'druids' }

local function BuildRedditBait()
	local idea = REDDIT_BAITS[math.random(#REDDIT_BAITS)]:format(CLASSIC_CLASSES[math.random(#CLASSIC_CLASSES)])
	return REDDIT_LINE:format(idea)
end

local function SendBait(text, editBox)
	editBox = editBox or (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow())
		or (_G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.editBox)

	local chatType = editBox and editBox:GetAttribute('chatType') or 'SAY'

	if chatType == 'BN_WHISPER' then
		local target = editBox:GetAttribute('tellTarget')
		local id = target and BNet_GetBNetIDAccount and BNet_GetBNetIDAccount(target)
		if id then (C_BattleNet and C_BattleNet.SendWhisper or BNSendWhisper)(id, text) end
		return
	end

	local target
	if chatType == 'WHISPER' then
		target = editBox:GetAttribute('tellTarget')
	elseif chatType == 'CHANNEL' then
		target = editBox:GetAttribute('channelTarget')
	end

	local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
	send(text, chatType, editBox and editBox.languageID or nil, target)
end

SLASH_BENISUIBAIT1 = '/bait'
SlashCmdList.BENISUIBAIT = function(_, editBox) SendBait(BuildBait(), editBox) end

SLASH_BENISUIREDDIT1 = '/reddit'
SlashCmdList.BENISUIREDDIT = function(_, editBox) SendBait(BuildRedditBait(), editBox) end
