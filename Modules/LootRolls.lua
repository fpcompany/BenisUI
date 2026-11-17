local _, ns = ...
local BenisUI = ns.BenisUI

-- Who rolled what on group loot. Every item up for a Need/Greed roll gets a
-- block in a small panel listing each player's choice (Need / Greed /
-- Disenchant / Transmog / Pass) and, once the roll is over, their number and
-- the winner. Blizzard's roll frame hides as soon as you click a button and
-- the numbers only come out after everyone has picked, so this is its own
-- panel rather than text on the roll frame.
--
-- The data comes from the loot chat lines ("X has selected Need for: [item]",
-- "Need Roll - 87 for [item] by X", "X won: [item]"). Those exist on every
-- client this addon runs on, unlike C_LootHistory whose shape differs between
-- retail and the vanilla-style clients. Patterns are built from the client's
-- own global strings, so they follow the locale.
--
-- Shift-drag the panel to move it. '/bui rolltest' fills it with fake rolls.
local LootRolls = BenisUI:RegisterModule('LootRolls')

local FONT = BenisUI.media.font
local Skin = BenisUI.Skin

local WIDTH = 260
local PADDING = 5
local ICON_SIZE = 18
local ROW_HEIGHT = 14
local ENTRY_GAP = 6
local TITLE_HEIGHT = 18
local KEEP_AFTER_DONE = 60 -- seconds a finished roll stays listed
local SHOW_RESULT_FOR = 8  -- seconds a finished roll stays expanded before collapsing
local GRACE = 10           -- seconds past the roll timer before giving up on a result

local CHOICES = {
	need = { label = NEED or 'Need', color = { 0.3, 0.85, 0.3 } },
	greed = { label = GREED or 'Greed', color = { 1, 0.82, 0 } },
	disenchant = { label = ROLL_DISENCHANT or 'Disenchant', color = { 0.7, 0.45, 1 } },
	transmog = { label = TRANSMOGRIFY or 'Transmog', color = { 1, 0.5, 0.8 } },
	pass = { label = PASS or 'Pass', color = { 0.55, 0.55, 0.55 } },
}
-- listing order inside an entry: best claim first
local CHOICE_RANK = { need = 1, greed = 2, transmog = 3, disenchant = 4, pass = 5 }

local entries = {} -- active and recently finished rolls, oldest first
local panel
local blocks = {}  -- per-entry display frames, reused
local ticker
local dismissed = false -- closed by hand; stays hidden until a new roll starts

--------------------------------------------------------------------------------
-- Chat parsing
--------------------------------------------------------------------------------

-- Each handler names a global format string and what its arguments mean, in
-- argument order (positional %2$s markers in the format are honored).
--   'name'  the player (absent on the "You ..." lines)
--   'link'  the item link
--   'roll'  the rolled number
local HANDLERS = {
	{ 'LOOT_ROLL_NEED', { 'name', 'link' }, choice = 'need' },
	{ 'LOOT_ROLL_GREED', { 'name', 'link' }, choice = 'greed' },
	{ 'LOOT_ROLL_DISENCHANT', { 'name', 'link' }, choice = 'disenchant' },
	{ 'LOOT_ROLL_TRANSMOG', { 'name', 'link' }, choice = 'transmog' },
	{ 'LOOT_ROLL_PASSED', { 'name', 'link' }, choice = 'pass' },
	{ 'LOOT_ROLL_PASSED_AUTO', { 'name', 'link' }, choice = 'pass' },
	{ 'LOOT_ROLL_PASSED_AUTO_FEMALE', { 'name', 'link' }, choice = 'pass' },
	{ 'LOOT_ROLL_NEED_SELF', { 'link' }, choice = 'need', self = true },
	{ 'LOOT_ROLL_GREED_SELF', { 'link' }, choice = 'greed', self = true },
	{ 'LOOT_ROLL_DISENCHANT_SELF', { 'link' }, choice = 'disenchant', self = true },
	{ 'LOOT_ROLL_TRANSMOG_SELF', { 'link' }, choice = 'transmog', self = true },
	{ 'LOOT_ROLL_PASSED_SELF', { 'link' }, choice = 'pass', self = true },
	{ 'LOOT_ROLL_PASSED_SELF_AUTO', { 'link' }, choice = 'pass', self = true },

	{ 'LOOT_ROLL_ROLLED_NEED', { 'roll', 'link', 'name' }, choice = 'need' },
	{ 'LOOT_ROLL_ROLLED_NEED_ROLE_BONUS', { 'roll', 'link', 'name' }, choice = 'need' },
	{ 'LOOT_ROLL_ROLLED_GREED', { 'roll', 'link', 'name' }, choice = 'greed' },
	{ 'LOOT_ROLL_ROLLED_DE', { 'roll', 'link', 'name' }, choice = 'disenchant' },
	{ 'LOOT_ROLL_ROLLED_TRANSMOG', { 'roll', 'link', 'name' }, choice = 'transmog' },

	{ 'LOOT_ROLL_WON', { 'name', 'link' }, won = true },
	{ 'LOOT_ROLL_YOU_WON', { 'link' }, won = true, self = true },
	-- retail's compact form ("X won: [item] (Need - 87)") when roll spam is off
	{ 'LOOT_ROLL_WON_NO_SPAM_NEED', { 'name', 'roll', 'link' }, won = true, choice = 'need' },
	{ 'LOOT_ROLL_WON_NO_SPAM_GREED', { 'name', 'roll', 'link' }, won = true, choice = 'greed' },
	{ 'LOOT_ROLL_WON_NO_SPAM_DE', { 'name', 'roll', 'link' }, won = true, choice = 'disenchant' },
	{ 'LOOT_ROLL_WON_NO_SPAM_TRANSMOG', { 'name', 'roll', 'link' }, won = true, choice = 'transmog' },
	{ 'LOOT_ROLL_YOU_WON_NO_SPAM_NEED', { 'roll', 'link' }, won = true, self = true, choice = 'need' },
	{ 'LOOT_ROLL_YOU_WON_NO_SPAM_GREED', { 'roll', 'link' }, won = true, self = true, choice = 'greed' },
	{ 'LOOT_ROLL_YOU_WON_NO_SPAM_DE', { 'roll', 'link' }, won = true, self = true, choice = 'disenchant' },
	{ 'LOOT_ROLL_YOU_WON_NO_SPAM_TRANSMOG', { 'roll', 'link' }, won = true, self = true, choice = 'transmog' },

	{ 'LOOT_ROLL_ALL_PASSED', { 'link' }, allPassed = true },
}

local function EscapeLiteral(text)
	return (text:gsub('[%^%$%(%)%%%.%[%]%*%+%-%?]', '%%%0'))
end

-- "%s has selected Need for: %s" -> "^(.-) has selected Need for: (.-)$" plus
-- which format argument each capture holds
local function ToPattern(format)
	local pattern, order = {}, {}
	local literal = 0 -- length of the fixed text; longer formats are tried first
	local pos, nextArg = 1, 1
	while true do
		local s, e, index, kind = format:find('%%(%d*%$?)([sd])', pos)
		if not s then break end
		local before = format:sub(pos, s - 1)
		literal = literal + #before
		pattern[#pattern + 1] = EscapeLiteral(before)
		pattern[#pattern + 1] = kind == 'd' and '(%d+)' or '(.-)'
		local n = tonumber(index:match('^(%d+)%$$'))
		if n then
			order[#order + 1] = n
		else
			order[#order + 1] = nextArg
			nextArg = nextArg + 1
		end
		pos = e + 1
	end
	local rest = format:sub(pos)
	literal = literal + #rest
	pattern[#pattern + 1] = EscapeLiteral(rest)
	return '^' .. table.concat(pattern) .. '$', order, literal
end

local parsers -- built on first use, sorted most specific first

local function BuildParsers()
	parsers = {}
	for _, handler in ipairs(HANDLERS) do
		local format = _G[handler[1]]
		if type(format) == 'string' and format ~= '' then
			local pattern, order, literal = ToPattern(format)
			local fields = handler[2]
			local argCount = 0
			for _, n in ipairs(order) do argCount = math.max(argCount, n) end
			-- newer clients lead the line with a clickable "[Loot]" link
			-- carrying the loot history ID:
			--   |HlootHistory:%d|h[Loot]|h: %s has selected Need for: %s
			-- that ID is the first argument and shifts everything after it
			if argCount == #fields + 1 and format:find('^|HlootHistory:%%') then
				fields = { 'history', unpack(fields) }
			end
			-- an unknown layout would put names where links go; skip it
			if argCount == #fields then
				parsers[#parsers + 1] = {
					pattern = pattern, order = order, literal = literal,
					fields = fields, handler = handler,
				}
			end
		end
	end
	-- "X automatically passed on: Y because ..." also fits "X passed on: Y",
	-- so the formats with more fixed text get the first try
	table.sort(parsers, function(a, b) return a.literal > b.literal end)
end

local function Parse(msg)
	if not parsers then BuildParsers() end
	for _, parser in ipairs(parsers) do
		local captures = { msg:match(parser.pattern) }
		if captures[1] then
			local args = {}
			for i, argIndex in ipairs(parser.order) do
				args[argIndex] = captures[i]
			end
			local result = { handler = parser.handler }
			for argIndex, field in ipairs(parser.fields) do
				result[field] = args[argIndex]
			end
			-- a real item link, never a stray name or number
			if result.link and result.link:find('|Hitem:', 1, true) then
				return result
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Roll state
--------------------------------------------------------------------------------

local function PlayerName()
	return UnitName('player')
end

-- chat names come as "Name" or "Name-Realm"; list them without our own realm
local function CleanName(name)
	local short, realm = name:match('^(.-)%-(.+)$')
	if short and realm == GetNormalizedRealmName() then
		return short
	end
	return name
end

local function ClassOf(name)
	local ok, _, class = pcall(UnitClass, name)
	if ok and class then return class end
	local short = name:match('^(.-)%-') or name
	if short ~= name then
		ok, _, class = pcall(UnitClass, short)
		if ok then return class end
	end
end

local function ItemName(link)
	return link and link:match('%[(.-)%]')
end

local function NewEntry(rollID, link, rollTime)
	local texture, name, _, quality = GetLootRollItemInfo(rollID)
	return {
		rollID = rollID,
		link = link,
		itemName = ItemName(link) or name,
		texture = texture,
		quality = quality,
		started = GetTime(),
		expires = GetTime() + (rollTime or 60000) / 1000,
		players = {}, -- [name] = { choice, roll, class }
	}
end

-- the entry a chat line refers to. Two copies of the same item can be up at
-- once, so prefer the oldest one still waiting on this kind of information.
local function FindEntry(link, accept)
	local itemName = ItemName(link)
	local fallback
	for _, entry in ipairs(entries) do
		if entry.link == link or (itemName and entry.itemName == itemName) then
			if accept(entry) then return entry end
			fallback = fallback or entry
		end
	end
	return fallback
end

local function GetPlayer(entry, name)
	local player = entry.players[name]
	if not player then
		player = { class = ClassOf(name) }
		entry.players[name] = player
	end
	return player
end

local function FinishEntry(entry)
	if entry.done then return end
	entry.done = true
	entry.doneAt = GetTime()
end

local Refresh -- display, defined below

local function OnLootMessage(msg)
	if type(msg) ~= 'string' then return end
	if issecretvalue and issecretvalue(msg) then return end

	local result = Parse(msg)
	if not result then return end
	local handler = result.handler

	local name = handler.self and PlayerName() or result.name
	name = name and CleanName(name)
	local roll = tonumber(result.roll)

	local entry
	if handler.won or handler.allPassed then
		entry = FindEntry(result.link, function(e) return not e.done end)
	elseif roll then
		entry = FindEntry(result.link, function(e)
			local player = e.players[name]
			return not (player and player.roll)
		end)
	else
		entry = FindEntry(result.link, function(e) return not e.players[name] end)
	end

	if not entry then
		-- rolled before we saw START_LOOT_ROLL (e.g. after a reload); keep it
		-- anyway so the result still shows
		entry = {
			link = result.link,
			itemName = ItemName(result.link),
			started = GetTime(),
			expires = GetTime() + 60,
			players = {},
		}
		local _, _, quality, _, _, _, _, _, _, texture = C_Item.GetItemInfo(result.link)
		entry.quality, entry.texture = quality, texture
		entries[#entries + 1] = entry
	end

	if name then
		local player = GetPlayer(entry, name)
		if handler.choice then player.choice = handler.choice end
		if roll then player.roll = roll end
		if handler.won then entry.winner = name end
	end
	if handler.won or handler.allPassed then
		FinishEntry(entry)
	end

	Refresh()
end

local function OnStartRoll(rollID, rollTime)
	for _, entry in ipairs(entries) do
		if entry.rollID == rollID then return end
	end
	local link = GetLootRollItemLink(rollID)
	if not link then return end
	entries[#entries + 1] = NewEntry(rollID, link, rollTime)
	dismissed = false
	Refresh()
end

local function Expire()
	local now = GetTime()
	for i = #entries, 1, -1 do
		local entry = entries[i]
		if not entry.done and now > entry.expires + GRACE then
			FinishEntry(entry) -- the result line never came
		end
		if entry.done and now > entry.doneAt + KEEP_AFTER_DONE then
			table.remove(entries, i)
		end
	end
end

--------------------------------------------------------------------------------
-- Display
--------------------------------------------------------------------------------

local function SavePosition()
	local point, _, _, x, y = panel:GetPoint()
	BenisUI.db.lootRolls.position = { point = point, x = x, y = y }
end

local function StartDrag()
	if IsShiftKeyDown() then panel:StartMoving() end
end

local function StopDrag()
	panel:StopMovingOrSizing()
	SavePosition()
end

local function NewText(parent, size, justify)
	local text = parent:CreateFontString(nil, 'OVERLAY')
	text:SetFont(FONT, size, 'OUTLINE')
	text:SetJustifyH(justify or 'LEFT')
	text:SetWordWrap(false)
	return text
end

local function CreateBlock()
	local block = CreateFrame('Frame', nil, panel)
	block:SetWidth(WIDTH - PADDING * 2)

	-- the item line; hovering it shows the item tooltip
	local header = CreateFrame('Button', nil, block)
	header:SetPoint('TOPLEFT')
	header:SetPoint('TOPRIGHT')
	header:SetHeight(ICON_SIZE)
	header:RegisterForDrag('LeftButton')
	header:SetScript('OnDragStart', StartDrag)
	header:SetScript('OnDragStop', StopDrag)
	header:SetScript('OnEnter', function(self)
		local link = self.link
		if not link then return end
		GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
		GameTooltip:SetHyperlink(link)
		-- a finished roll is collapsed to its winner; the full list is here
		if self.rollLines then
			GameTooltip:AddLine(' ')
			for _, line in ipairs(self.rollLines) do
				GameTooltip:AddDoubleLine(line[1], line[2],
					line[3], line[4], line[5], line[6], line[7], line[8])
			end
		end
		GameTooltip:Show()
	end)
	header:SetScript('OnLeave', function() GameTooltip:Hide() end)
	header:SetScript('OnClick', function(self)
		if self.link and IsModifiedClick() then HandleModifiedItemClick(self.link) end
	end)
	block.header = header

	local icon = header:CreateTexture(nil, 'ARTWORK')
	icon:SetSize(ICON_SIZE, ICON_SIZE)
	icon:SetPoint('LEFT')
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	block.icon = icon
	block.iconBorder = Skin:Border(header, 1, icon)

	local status = NewText(header, 11, 'RIGHT')
	status:SetPoint('RIGHT')
	block.status = status

	local item = NewText(header, 12)
	item:SetPoint('LEFT', icon, 'RIGHT', 5, 0)
	item:SetPoint('RIGHT', status, 'LEFT', -4, 0)
	block.item = item

	block.rows = {}
	return block
end

-- someone rolled a 1: point it out to the group
local function GroupChannel()
	if IsInRaid() then
		return 'RAID'
	elseif IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and not IsInGroup(LE_PARTY_CATEGORY_HOME) then
		return 'INSTANCE_CHAT'
	elseif IsInGroup() then
		return 'PARTY'
	end
end

local function Laugh(button)
	local entry, name = button.entry, button.name
	local player = entry and entry.players[name]
	if not player or player.laughed then return end
	player.laughed = true

	local msg = ('%s rolled a 1 on %s. LMAO'):format(name, entry.link or entry.itemName or 'loot')
	local channel = GroupChannel()
	if not channel then
		print('|cff1784d1Benis|rUI: ' .. msg) -- not grouped (e.g. /bui rolltest)
	elseif C_ChatInfo and C_ChatInfo.SendChatMessage then
		C_ChatInfo.SendChatMessage(msg, channel)
	else
		SendChatMessage(msg, channel)
	end
	Refresh()
end

local function CreateLaughButton(block, y)
	local button = CreateFrame('Button', nil, block)
	button:SetSize(30, ROW_HEIGHT - 1)
	button:SetPoint('TOPRIGHT', 0, y)
	Skin:Backdrop(button):SetFrameLevel(button:GetFrameLevel())
	local text = NewText(button, 10, 'CENTER')
	text:SetPoint('CENTER', 0, 0)
	text:SetText('LOL')
	text:SetTextColor(1, 0.82, 0)
	button:SetHighlightTexture(BenisUI.media.texture)
	button:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.15)
	button:SetScript('OnClick', Laugh)
	button:SetScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
		GameTooltip:SetText('Laugh at ' .. (self.name or '?') .. ' in group chat')
		GameTooltip:Show()
	end)
	button:SetScript('OnLeave', function() GameTooltip:Hide() end)
	return button
end

local function GetRow(block, index)
	local row = block.rows[index]
	if row then return row end

	row = {}
	local y = -(ICON_SIZE + 2 + (index - 1) * ROW_HEIGHT)
	row.name = NewText(block, 11)
	row.name:SetPoint('TOPLEFT', ICON_SIZE + 5, y)
	row.name:SetWidth(120)
	row.choice = NewText(block, 11)
	row.choice:SetPoint('TOPLEFT', ICON_SIZE + 130, y)
	row.laugh = CreateLaughButton(block, y)
	block.rows[index] = row
	return row
end

local function SortedPlayers(entry)
	local list = {}
	for name, player in pairs(entry.players) do
		list[#list + 1] = { name = name, player = player }
	end
	table.sort(list, function(a, b)
		local ra = CHOICE_RANK[a.player.choice] or 9
		local rb = CHOICE_RANK[b.player.choice] or 9
		if ra ~= rb then return ra < rb end
		local na, nb = a.player.roll or -1, b.player.roll or -1
		if na ~= nb then return na > nb end
		return a.name < b.name
	end)
	return list
end

-- '|cffrrggbb' for 0-1 color components
local function Hex(r, g, b)
	return ('|cff%02x%02x%02x'):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function ClassColor(class)
	local color = class and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
	if color then return color.r, color.g, color.b end
	return 0.9, 0.9, 0.9
end

local function FillBlock(block, entry)
	local now = GetTime()
	block.header.link = entry.link
	block.icon:SetTexture(entry.texture or 134400) -- question mark
	block.item:SetText(entry.itemName or entry.link)
	local r, g, b = 1, 1, 1
	if entry.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[entry.quality] then
		local color = ITEM_QUALITY_COLORS[entry.quality]
		r, g, b = color.r, color.g, color.b
	end
	block.item:SetTextColor(r, g, b)
	Skin:SetBorder(block.iconBorder, block.icon, 1, r * 0.6, g * 0.6, b * 0.6)

	local list = SortedPlayers(entry)

	-- a finished roll stays expanded for a few seconds so the numbers can be
	-- read, and as long as a rolled 1 is still waiting to be laughed at
	local collapse = entry.done and GetTime() - entry.doneAt > SHOW_RESULT_FOR
	if collapse then
		for _, item in ipairs(list) do
			if item.player.roll == 1 and not item.player.laughed then collapse = false end
		end
	end

	if collapse then
		-- collapsed to one line: who got it, with what
		local winner = entry.winner and entry.players[entry.winner]
		if winner then
			local cr, cg, cb = ClassColor(winner.class)
			local text = Hex(cr, cg, cb) .. entry.winner .. '|r'
			local choice = CHOICES[winner.choice]
			if winner.roll then
				text = text .. ' |cffffffff' .. winner.roll .. '|r'
			end
			if choice then
				local r2, g2, b2 = unpack(choice.color)
				text = text .. ' ' .. Hex(r2, g2, b2) .. choice.label .. '|r'
			end
			block.status:SetText(text)
		else
			local allPassed = #list > 0
			for _, item in ipairs(list) do
				if item.player.choice ~= 'pass' then allPassed = false end
			end
			block.status:SetText(allPassed and 'all passed' or 'done')
			block.status:SetTextColor(0.55, 0.55, 0.55)
		end

		local lines = {}
		for _, item in ipairs(list) do
			local player = item.player
			local choice = CHOICES[player.choice]
			local right = (choice and choice.label or '') .. (player.roll and (' ' .. player.roll) or '')
			local cr, cg, cb = ClassColor(player.class)
			local rr, rg, rb = 0.8, 0.8, 0.8
			if choice then rr, rg, rb = unpack(choice.color) end
			lines[#lines + 1] = { item.name, right, cr, cg, cb, rr, rg, rb }
		end
		block.header.rollLines = #lines > 0 and lines or nil
		list = {} -- no player rows
	elseif entry.done then
		block.header.rollLines = nil
		block.status:SetText(entry.winner and '' or 'done')
		block.status:SetTextColor(0.55, 0.55, 0.55)
	else
		block.header.rollLines = nil
		block.status:SetText(('%ds'):format(math.max(0, math.ceil(entry.expires - now))))
		block.status:SetTextColor(0.8, 0.8, 0.8)
	end

	for i, item in ipairs(list) do
		local row = GetRow(block, i)
		local player = item.player
		row.name:SetText(item.name)
		row.name:SetTextColor(ClassColor(player.class))
		if entry.winner == item.name then
			row.name:SetText('|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t ' .. item.name)
		end
		-- "Greed 87": the number follows the choice once the game reveals it
		local choice = CHOICES[player.choice]
		local text = choice and choice.label or ''
		if player.roll then
			local numberColor = player.roll == 1 and '|cffff4040' or '|cffffffff'
			text = text .. ' ' .. numberColor .. player.roll .. '|r'
		end
		row.choice:SetText(text)
		if choice then row.choice:SetTextColor(unpack(choice.color)) end
		row.laugh.entry, row.laugh.name = entry, item.name
		row.laugh:SetShown(player.roll == 1 and not player.laughed)
		row.name:Show()
		row.choice:Show()
	end
	for i = #list + 1, #block.rows do
		local row = block.rows[i]
		row.name:Hide()
		row.choice:Hide()
		row.laugh:Hide()
	end

	local height = ICON_SIZE + 2 + #list * ROW_HEIGHT
	block:SetHeight(height)
	return height
end

local function StopTicker()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
end

function Refresh()
	Expire()

	if #entries == 0 or dismissed then
		panel:Hide()
		StopTicker()
		return
	end

	local y = -(PADDING + TITLE_HEIGHT)
	for i, entry in ipairs(entries) do
		local block = blocks[i] or CreateBlock()
		blocks[i] = block
		block:ClearAllPoints()
		block:SetPoint('TOPLEFT', PADDING, y)
		y = y - FillBlock(block, entry) - ENTRY_GAP
		block:Show()
	end
	for i = #entries + 1, #blocks do
		blocks[i]:Hide()
	end

	panel:SetHeight(-y - ENTRY_GAP + PADDING)
	panel:Show()

	-- counts down the timers and drops finished rolls; only runs while shown
	if not ticker then
		ticker = C_Timer.NewTicker(1, Refresh)
	end
end

local function CreatePanel()
	panel = CreateFrame('Frame', 'BenisUILootRolls', UIParent, 'BackdropTemplate')
	panel:SetWidth(WIDTH)
	panel:SetFrameStrata('MEDIUM')
	panel:Hide()

	local saved = BenisUI.db.lootRolls.position
	if saved then
		panel:SetPoint(saved.point, UIParent, saved.point, saved.x, saved.y)
	else
		-- right of the roll frames, which sit above the action bars
		panel:SetPoint('BOTTOMLEFT', UIParent, 'BOTTOM', 200, 220)
	end

	Skin:Panel(panel)

	panel:SetMovable(true)
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	panel:RegisterForDrag('LeftButton')
	panel:SetScript('OnDragStart', StartDrag)
	panel:SetScript('OnDragStop', StopDrag)

	local title = NewText(panel, 12)
	title:SetPoint('TOPLEFT', PADDING, -PADDING - 3)
	title:SetText('|cff1784d1Loot|r Rolls')

	-- closing drops the finished rolls; rolls still running come back with
	-- the next roll that starts
	local close = CreateFrame('Button', nil, panel, 'UIPanelCloseButton')
	close:SetSize(22, 22)
	close:SetPoint('TOPRIGHT', 0, 0)
	close:SetScript('OnClick', function() LootRolls:Close() end)
end

function LootRolls:Close()
	for i = #entries, 1, -1 do
		if entries[i].done then table.remove(entries, i) end
	end
	dismissed = #entries > 0
	Refresh()
end

--------------------------------------------------------------------------------
-- Test data and init
--------------------------------------------------------------------------------

-- '/bui rolltest': two fake rolls, one finished and one still running
function LootRolls:Test()
	local me = PlayerName()
	local function Fake(link, players, winner, done, age)
		local _, _, quality, _, _, _, _, _, _, texture = C_Item.GetItemInfo(link)
		local entry = {
			link = link,
			itemName = ItemName(link),
			texture = texture,
			quality = quality or 3,
			started = GetTime(),
			expires = GetTime() + 45,
			players = {},
			winner = winner,
		}
		for name, data in pairs(players) do
			entry.players[name] = { choice = data[1], roll = data[2], class = data[3] }
		end
		if done then
			FinishEntry(entry)
			entry.doneAt = entry.doneAt - (age or 0)
		end
		entries[#entries + 1] = entry
	end

	dismissed = false
	-- finished a while ago: collapsed to the winner
	Fake('|cffa335ee|Hitem:12640::::::::60:::::|h[Lionheart Helm]|h|r', {
		Thrall = { 'need', 64, 'SHAMAN' },
		Jaina = { 'greed', 12, 'MAGE' },
	}, 'Thrall', true, 30)
	-- just finished, with a 1 to laugh at
	Fake('|cff0070dd|Hitem:13955::::::::60:::::|h[Stoneform Shoulders]|h|r', {
		[me] = { 'need', 87, select(2, UnitClass('player')) },
		Thrall = { 'need', 42, 'SHAMAN' },
		Jaina = { 'greed', 1, 'MAGE' },
		Anduin = { 'pass', nil, 'PRIEST' },
	}, me, true)
	Fake('|cff1eff00|Hitem:15248::::::::60:::::|h[Gleaming Throwing Axe]|h|r', {
		[me] = { 'greed' },
		Thrall = { 'pass', nil, 'SHAMAN' },
		Jaina = { 'greed', nil, 'MAGE' },
	})
	Refresh()
end

function LootRolls:OnInit()
	BenisUI.db.lootRolls = BenisUI.db.lootRolls or {}
	CreatePanel()

	local events = CreateFrame('Frame')
	events:RegisterEvent('START_LOOT_ROLL')
	events:RegisterEvent('CHAT_MSG_LOOT')
	events:SetScript('OnEvent', function(_, event, ...)
		if event == 'START_LOOT_ROLL' then
			OnStartRoll(...)
		elseif event == 'CHAT_MSG_LOOT' then
			OnLootMessage((...))
		end
	end)
end
