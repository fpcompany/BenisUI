local _, ns = ...
local BenisUI = ns.BenisUI

-- Recipe filter for the Bags module: while a recipe is selected in the
-- crafting window, inventory and bank only show that recipe's reagents and
-- tools normally; everything else is greyed out and darkened.
--
-- Retail and WoW Forever share the Professions frame, so the selected recipe
-- is read from its schematic form on both.
local Bags = BenisUI:GetModule('Bags')
if not Bags then return end

local PROFESSIONS_ADDON = 'Blizzard_Professions'
local TOOL_REQUIREMENT = Enum.RecipeRequirementType and Enum.RecipeRequirementType.Totem or 1

-- returns [itemID] = true for every reagent, [name] = true for required tools
-- (vanilla-style tools like a Blacksmith Hammer sit in the bags, but the API
-- only names them), or nil when the recipe uses no bag items at all
local function CollectRecipeItems(form)
	local schematic = form.recipeSchematic
	if not (schematic and form:GetRecipeInfo()) then return end

	local itemIDs, names, found = {}, {}, false
	for _, slotSchematic in ipairs(schematic.reagentSlotSchematics or {}) do
		for _, reagent in ipairs(slotSchematic.reagents or {}) do
			if reagent.itemID then
				itemIDs[reagent.itemID] = true
				found = true
			end
		end
	end

	local getRequirements = C_TradeSkillUI and C_TradeSkillUI.GetRecipeRequirements
	local requirements = getRequirements and schematic.recipeID and getRequirements(schematic.recipeID)
	for _, requirement in ipairs(requirements or {}) do
		if requirement.type == TOOL_REQUIREMENT and requirement.name then
			names[requirement.name] = true
			found = true
		end
	end

	if found then return itemIDs, names end
end

local function Refresh(form)
	if form:IsVisible() then
		Bags:SetRecipeFilter(CollectRecipeItems(form))
	else
		Bags:SetRecipeFilter(nil)
	end
end

local function HookProfessions()
	local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
	local form = page and page.SchematicForm
	if not (form and form.Init) then return end

	-- every way of picking a recipe ends in the form's Init, which also runs
	-- each time the form is shown again
	hooksecurefunc(form, 'Init', Refresh)
	form:HookScript('OnHide', Refresh) -- window closed or switched to another tab
	Refresh(form)
end

local IsAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or _G.IsAddOnLoaded
if IsAddOnLoaded(PROFESSIONS_ADDON) then
	HookProfessions()
else
	local loader = CreateFrame('Frame')
	loader:RegisterEvent('ADDON_LOADED')
	loader:SetScript('OnEvent', function(self, _, addon)
		if addon == PROFESSIONS_ADDON then
			self:UnregisterEvent('ADDON_LOADED')
			HookProfessions()
		end
	end)
end
