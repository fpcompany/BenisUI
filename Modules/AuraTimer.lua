local _, ns = ...
local BenisUI = ns.BenisUI

-- Shared pieces for aura buttons drawn by the client's AuraContainer
-- (nameplate debuffs, party dispellables). Both are built once, on first use,
-- and are `nil` on a client without the API.
local AuraTimer = {}
BenisUI.AuraTimer = AuraTimer

local formatter, expiring

-- Seconds left as text: tenths under 10s, whole seconds after, then minutes
-- and hours. Rounded up, so the text never reads 0.0 while the aura lives.
function AuraTimer.Formatter()
	if formatter == nil then
		formatter = false
		if C_StringUtil and C_StringUtil.CreateNumericRuleFormatter then
			local ok, made = pcall(C_StringUtil.CreateNumericRuleFormatter)
			if ok and made then
				local up = Enum and Enum.NumericRuleFormatRounding
					and Enum.NumericRuleFormatRounding.Up or 1
				pcall(made.SetBreakpoints, made, {
					{ threshold = 0, step = 0.1, rounding = up, format = '%.1f' },
					{ threshold = 10, step = 1, rounding = up, format = '%.0f' },
					{ threshold = 60, format = '%.0fm',
						components = { { div = 60, step = 1, rounding = up } } },
					{ threshold = 3600, format = '%.0fh',
						components = { { div = 3600, step = 1, rounding = up } } },
				})
				formatter = made
			end
		end
	end
	return formatter or nil
end

-- Remaining fraction -> text colour, evaluated by the client against the
-- secret duration. Stepped: three colours, not a blend.
function AuraTimer.Expiring()
	if expiring == nil then
		expiring = false
		if C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor then
			local ok, curve = pcall(function()
				local c = C_CurveUtil.CreateColorCurve()
				if Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then
					c:SetType(Enum.LuaCurveType.Step)
				end
				c:AddPoint(0, CreateColor(1.00, 0.25, 0.25, 1))
				c:AddPoint(0.2, CreateColor(1.00, 0.90, 0.30, 1))
				c:AddPoint(0.5, CreateColor(1.00, 1.00, 1.00, 1))
				return c
			end)
			if ok and curve then expiring = curve end
		end
	end
	return expiring or nil
end

-- Binds `timer` as the button's countdown, coloured as it runs out. False when
-- the client has no text binding.
function AuraTimer.BindText(button, timer)
	if not button.SetDurationText then return false end
	local options = { textFormatter = AuraTimer.Formatter() }
	local curve = AuraTimer.Expiring()
	if curve and Enum and Enum.DurationTextBindingProperty then
		options.textColor = {
			curve = curve,
			property = Enum.DurationTextBindingProperty.RemainingPercent,
		}
	end
	return (pcall(button.SetDurationText, button, timer, options))
end
