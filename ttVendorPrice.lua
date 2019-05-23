local format = string.format;
local unpack = unpack;

-- Addon
local modName = ...;
local ttvp = CreateFrame("Frame",modName);

-- Register with TipTac core addon if available
if (TipTac) then
	TipTac:RegisterElement(ttvp,"VendorPrice");
end

-- Options without TipTac. If the base TipTac addon is used, the global TipTac_Config table is used instead
local cfg = {
	if_enable = true,
	if_infoColor = { 0.2, 0.6, 1 },
	if_itemQualityBorder = true,

	if_showCurrencyId = true,					-- Az: no option for this added to TipTac/options yet!
	if_showAchievementIdAndCategory = false,	-- Az: no option for this added to TipTac/options yet!
	if_showIcon = true,
	if_smartIcons = true,
	if_borderlessIcons = false,
	if_iconSize = 42,
};

-- Tooltips to Hook into -- MUST be a GameTooltip widget -- If the main TipTac is installed, the TT_TipsToModify is used instead
local tipsToModify = {
	"GameTooltip",
	"ItemRefTooltip",
};
-- Tips which will have an icon
local tipsToAddIcon = {
	["GameTooltip"] = true,
	["ItemRefTooltip"] = true,
};

-- Tables
local LinkTypeFuncs = {};
local criteriaList = {};	-- Used for Achievement criterias
local tipDataAdded = {};	-- Sometimes, OnTooltipSetItem/Spell is called before the tip has been filled using SetHyperlink, we use the array to test if the tooltip has had data added

-- Colors for achivements
local COLOR_COMPLETE = { 0.25, 0.75, 0.25 };
local COLOR_INCOMPLETE = { 0.5, 0.5, 0.5 };

-- Colored text string (red/green)
local BoolCol = { [false] = "|cffff8080", [true] = "|cff80ff80" };

--------------------------------------------------------------------------------------------------------
--                                         Create Tooltip Icon                                        --
--------------------------------------------------------------------------------------------------------

-- Set Texture and Text
local function SetIconTextureAndText(self,texture,count)
	if (texture) then
		self.ttIcon:SetTexture(texture ~= "" and texture or "Interface\\Icons\\INV_Misc_QuestionMark");
		self.ttCount:SetText(count);
		self.ttIcon:Show();
	else
		self.ttIcon:Hide();
		self.ttCount:SetText("");
	end
end

-- Create Icon with Counter Text for Tooltip
function ttvp:CreateTooltipIcon(tip)
	tip.ttIcon = tip:CreateTexture(nil,"BACKGROUND");
	tip.ttIcon:SetPoint("TOPRIGHT",tip,"TOPLEFT",0,-2.5);
	tip.ttIcon:Hide();

	tip.ttCount = tip:CreateFontString(nil,"ARTWORK");
	tip.ttCount:SetTextColor(1,1,1);
	tip.ttCount:SetPoint("BOTTOMRIGHT",tip.ttIcon,"BOTTOMRIGHT",-3,3);
end

--------------------------------------------------------------------------------------------------------
--                                         TipTacItemRef Frame                                        --
--------------------------------------------------------------------------------------------------------

ttvp:RegisterEvent("VARIABLES_LOADED");

-- Resolves the given table array of string names into their global objects
local function ResolveGlobalNamedObjects(tipTable)
	local resolved = {};
	for index, tipName in ipairs(tipTable) do
		-- lookup the global object from this name, assign false if nonexistent, to preserve the table entry
		local tip = (_G[tipName] or false);

		-- Check if this object has already been resolved. This can happen for thing like AtlasLoot, which sets AtlasLootTooltip = GameTooltip
		if (resolved[tip]) then
			tip = false;
		elseif (tip) then
			resolved[tip] = index;
		end

		-- Assign the resolved object or false back into the table array
		tipTable[index] = tip;
	end
end

-- OnEvent
ttvp:SetScript("OnEvent",function(self,event,...)
	-- What tipsToModify to use, TipTac's main addon, or our own?
	if (TipTac and TipTac.tipsToModify) then
		tipsToModify = TipTac.tipsToModify;
	else
		ResolveGlobalNamedObjects(tipsToModify)
	end

	-- Use TipTac settings if installed
	if (TipTac_Config) then
		cfg = TipTac_Config;
	end

	-- Hook tips and apply settings
	self:DoHooks();
	self:OnApplyConfig();

	-- Cleanup; we no longer need to receive any events
	self:UnregisterAllEvents();
	self:SetScript("OnEvent",nil);
end);

-- Apply Settings -- It seems this may be called from TipTac:OnApplyConfig() before we have received our VARIABLES_LOADED, so ensure we have created the tip objects
function ttvp:OnApplyConfig()
	local gameFont = GameFontNormal:GetFont();
	for index, tip in ipairs(tipsToModify) do
		if (type(tip) == "table") and (tipsToAddIcon[tip:GetName()]) and (tip.ttIcon) then
			if (cfg.if_showIcon) then
				tip.ttIcon:SetSize(cfg.if_iconSize,cfg.if_iconSize);
				tip.ttCount:SetFont(gameFont,(cfg.if_iconSize / 3),"OUTLINE");
				tip.SetIconTextureAndText = SetIconTextureAndText;
				if (cfg.if_borderlessIcons) then
					tip.ttIcon:SetTexCoord(0.07,0.93,0.07,0.93);
				else
					tip.ttIcon:SetTexCoord(0,1,0,1);
				end
			elseif (tip.SetIconTextureAndText) then
				tip.ttIcon:Hide();
				tip.SetIconTextureAndText = nil;
			end
		end
	end
end

--------------------------------------------------------------------------------------------------------
--                                       HOOK: Tooltip Functions                                      --
--------------------------------------------------------------------------------------------------------

-- HOOK: ItemRefTooltip + GameTooltip: SetHyperlink
local function SetHyperlink_Hook(self,hyperLink)
	if (cfg.if_enable) and (not tipDataAdded[self]) then
		local refString = hyperLink:match("|H([^|]+)|h") or hyperLink;
		local linkType = refString:match("^[^:]+");
		-- Call Tip Type Func
		if (LinkTypeFuncs[linkType]) and (self:NumLines() > 0) then
			tipDataAdded[self] = "hyperlink";
			LinkTypeFuncs[linkType](self,refString,(":"):split(refString));
		end
	end
end

-- OnTooltipSetItem
local function OnTooltipSetItem(self,...)
	if (cfg.if_enable) and (not tipDataAdded[self]) then
		local _, link = self:GetItem();
		if (link) then
			local linkType, id = link:match("H?(%a+):(%d+)");
			if (id) then
				tipDataAdded[self] = linkType;
				LinkTypeFuncs.item(self,link,linkType,id);
			end
		end
	end
end

-- OnTooltipSetSpell
local function OnTooltipSetSpell(self,...)
	if (cfg.if_enable) and (not tipDataAdded[self]) then
		local _, id = self:GetSpell();	-- [18.07.19] 8.0/BfA: "dropped second parameter (nameSubtext)"
		if (id) then
			tipDataAdded[self] = "spell";
			LinkTypeFuncs.spell(self,nil,"spell",id);
		end
	end
end

-- OnTooltipCleared
local function OnTooltipCleared(self)
	tipDataAdded[self] = nil;
	if (self.SetIconTextureAndText) then
		self:SetIconTextureAndText();
	end
end

-- HOOK: Apply hooks for all the tooltips to modify -- Only hook GameTooltip objects
function ttvp:DoHooks()
	for index, tip in ipairs(tipsToModify) do
		if (type(tip) == "table") and (type(tip.GetObjectType) == "function") and (tip:GetObjectType() == "GameTooltip") then
			if (tipsToAddIcon[tip:GetName()]) then
				self:CreateTooltipIcon(tip);
			end
			hooksecurefunc(tip,"SetHyperlink",SetHyperlink_Hook);
			tip:HookScript("OnTooltipSetItem",OnTooltipSetItem);
			tip:HookScript("OnTooltipCleared",OnTooltipCleared);
		end
	end
end

--------------------------------------------------------------------------------------------------------
--                                        Smart Icon Evaluation                                       --
--------------------------------------------------------------------------------------------------------

-- returns true if an icon should be displayed
local function SmartIconEvaluation(tip,linkType)
	local owner = tip:GetOwner();
	-- No Owner?
	if (not owner) then
		return false;
	-- Item
	elseif (linkType == "item") then
		if (owner.hasItem or owner.action or owner.icon or owner.texture) then
			return false;
		end
	-- Spell
	elseif (linkType == "spell") then
		if (owner.action or owner.icon) then
			return false;
		end
	-- Achievement
--	elseif (linkType == "achievement") then
--		if (owner.icon) then
--			return false;
--		end
	end

	-- IconTexture sub texture
	local ownerName = owner:GetName();
	if (ownerName) then
		if (_G[ownerName.."IconTexture"]) or (ownerName:match("SendMailAttachment(%d+)")) then
			return false;
		end
	end

	-- If we passed all checks, return true to show an icon
	return true;
end

--------------------------------------------------------------------------------------------------------
--                                       Tip LinkType Functions                                       --
--------------------------------------------------------------------------------------------------------


-- item
function LinkTypeFuncs:item(link,linkType,id)
	local _, _, itemRarity, itemLevel, _, _, _, itemStackCount, _, itemTexture, itemSellPrice = GetItemInfo(link);
	itemLevel = LibItemString:GetTrueItemLevel(link);

	-- Icon
	if (self.SetIconTextureAndText) and (not cfg.if_smartIcons or SmartIconEvaluation(self,linkType)) then
		local count = (itemStackCount and itemStackCount > 1 and (itemStackCount == 0x7FFFFFFF and "#" or itemStackCount) or "");
		self:SetIconTextureAndText(itemTexture,count);
	end

	-- Quality Border
	if (cfg.if_itemQualityBorder) then
		self:SetBackdropBorderColor(GetItemQualityColor(itemRarity or 0));
  end

  if itemSellPrice ~= nil then
    if itemSellPrice == 0 then
      -- do nothing
    else
      formattedValue = GetCoinTextureString(itemSellPrice);

      -- self:AddLine(format("Vendor Sell: %d",formattedValue),unpack(cfg.if_infoColor));
      self:AddLine("Vendor Sell: " .. formattedValue,unpack(cfg.if_infoColor));
    end
  end
end
