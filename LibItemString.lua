--[[----------------------------------------------------
	LibItemString - Easy Access to ItemString Properties
	----------------------------------------------------
	LibItemString:New(itemLink)
	* Returns an itemStringTable instance
	* Can easily be accessed using property field names
	* No need to remember which index a certain field has
	----------------------------------------------------
	Creating an ItemString Instance - Examples:
		is = LibItemString:New(itemLink);
		if (is.enchant ~= 0) then print("item is enchanted"); end
		itemID = is[1]; itemID = is.itemID;
		itemStringLabel:SetText(tostring(is));
	----------------------------------------------------
	LibItemString:GetFieldName(fieldindex)
	* Returns the name of the ItemString field
	----------------------------------------------------
	LibItemString:GetTrueItemLevel(itemLink)
	* Returns the true itemLevel, based on a tooltip scan
	----------------------------------------------------
	GetUpgradedItemLevelFromItemLink(itemLink)
	* Now obsolete - included for compatibility reason
	* Use LibItemString:GetTrueItemLevel(itemLink) instead
	----------------------------------------------------
	Changelog:
	## REV-01 (16.08.30) - Patch 7.0.3 ##
	- Replaces "GetUpgradedItemLevel.lua", but stays compatible
	## REV-02 (18.08.04) - 8.0/BfA ##
	- Added LIS:GetFieldName() to get the field name from index
	- Accessing the IS table using a negative index now works
--]]----------------------------------------------------

-- Abort if library has already loaded with the same or newer revision
local REVISION = 2;
if (type(LibItemString) == "table") and (REVISION <= LibItemString.REVISION) then
	return;
end

LibItemString = LibItemString or {};
local LIS = LibItemString;			-- local shortcut
LIS.REVISION = REVISION;
LIS.ScanTip = LIS.ScanTip or CreateFrame("GameTooltip","LibItemStringScanTip",nil,"GameTooltipTemplate");
LIS.ScanTip:SetOwner(UIParent,"ANCHOR_NONE");

-- this replaces REV-11 of "GetUpgradedItemLevel.lua"
GET_UPGRADED_ITEM_LEVEL_REV = 12;

--------------------------------------------------------------------------------------------------------
--                                      Constants / Data Tables                                       --
--------------------------------------------------------------------------------------------------------

-- The number of tooltip lines to scan for the level text
LIS.TOOLTIP_MAXLINE_LEVEL = 5;

-- Pattern to extract the actual itemLevel from the tooltip text line
LIS.ITEM_LEVEL_PATTERN = ITEM_LEVEL:gsub("%%d","(%%d+)");

-- Extraction pattern for the exact itemString, including all its properties
LIS.ITEMSTRING_PATTERN = "(item:[^|]+)";	-- replace with "(%w+:[^|]+)" to catch all hyperlinks

-- Index of the named itemString property
LIS.ITEMSTRING_PROPERTY_INDEX = {
	-- item --
	itemID					= 1,
	enchant					= 2,
	gemID1					= 3,
	gemID2					= 4,
	gemID3					= 5,
	gemID4					= 6,
	suffixID				= 7,
	uniqueID				= 8,
	linkLevel				= 9,
	specializationID		= 10,
	upgradeTypeID			= 11,
	instanceDifficultyID	= 12,
	numBonusIDs				= 13,
--	bonusID1				= 14,
--	bonusID2				= 15,
--	...
	upgradeValue			= -1,	-- negative value means the absolute index is relative to the last bonusID index
	unknown1				= -2,
	unknown2				= -3,
	unknown3				= -4,

--	relic1NumBonusIDs		= -10,
--	relic1BonusID1			= -11,
--	relic1BonusID2			= -12,
}

-- Table for adjustment of levels due to upgrade -- Source: http://www.wowinterface.com/forums/showthread.php?t=45388
LIS.UPGRADED_LEVEL_ADJUST = {
	[001] = 8, -- 1/1
};

-- Table for adjustment of levels due to Timewarped. These are fixed itemLevels, not upgrade amounts.
LIS.TIMEWARPED_LEVEL_ADJUST = {};

-- Table for adjustment of levels due to Timewarped Warforged. These are fixed itemLevels, not upgrade amounts.
LIS.TIMEWARPED_WARFORGED_LEVEL_ADJUST = {};

--------------------------------------------------------------------------------------------------------
--                                          Metatable Methods                                         --
--------------------------------------------------------------------------------------------------------

-- basic access; allow for LibItemString access, otherwise fall back to property name array index access
LIS.__index = function(tbl,k)
	if (LIS[k]) then
		return LIS[k];
	elseif (type(k) == "string") then
		-- reference by name
		local propIndex = LIS.ITEMSTRING_PROPERTY_INDEX[k];
		if (propIndex) then
			if (propIndex < 0) then
				propIndex = LIS.ITEMSTRING_PROPERTY_INDEX.numBonusIDs + tbl.numBonusIDs + abs(propIndex);
			end
			return tbl[propIndex] or 0;
		end
		-- bonusIDs
		local bonusIdIndex = tonumber(k:match("bonusID(%d+)"));
		if (bonusIdIndex) then
			local propIndex = LIS.ITEMSTRING_PROPERTY_INDEX.numBonusIDs;
			local numBonusIDs = tbl.numBonusIDs;
			return (numBonusIDs > 0) and (bonusIdIndex <= numBonusIDs) and tbl[propIndex + bonusIdIndex] or nil;
		end
	elseif (type(k) == "number") then
		if (k < 0) then
			local propIndex = LIS.ITEMSTRING_PROPERTY_INDEX.numBonusIDs + tbl.numBonusIDs + abs(k);
			return tbl[propIndex];
		end
	end
end

-- converts it back to an itemString using tostring()
LIS.__tostring = function(tbl)
	local itemLink = tbl.linkType;
	for index, value in ipairs(tbl) do
		itemLink = itemLink .. ":" .. (value == 0 and "" or tostring(value));
	end
	return itemLink;
end

--------------------------------------------------------------------------------------------------------
--                                             Functions                                              --
--------------------------------------------------------------------------------------------------------

-- Creates new itemString table instance
-- * itemLink			Example: item:128955:::-55:::::99:577::11:2:69:96:3
-- * itemStringTable	If you want to recycle the same table, pass it along here, otherwise a new table is constructed
function LIS:New(itemLink,itemStringTable)
	if (type(itemLink) == "string") then
		itemStringTable = setmetatable(itemStringTable or {},LIS);

		local itemString = itemLink:match(LIS.ITEMSTRING_PATTERN);
		itemStringTable:Parse(itemString);

		return itemStringTable;
	end
end

-- Parses the itemString properties into array entries -- To merge back, use tostring(itemStringTable)
function LIS:Parse(itemString)
	wipe(self);
	self.source = itemString;

	if (type(itemString) ~= "string") then
		return;
	end

	local index = 0;
	for value in self.source:gmatch("([^:]*):?") do
		index = (index + 1);
		if (index == 1) then
			self.linkType = value;		-- will normally just be "item", but we keep it in case we want to expand this lib later
		else
			self[#self + 1] = tonumber(value) or 0;
		end
	end
	self[#self] = nil;	-- removes the last invalid capure we get from matching the optional ":"
end

-- returns the name of the itemString field at the given index
function LIS:GetFieldName(fieldindex)
	local fieldIndices = self.ITEMSTRING_PROPERTY_INDEX;
	if (fieldindex > fieldIndices.numBonusIDs) then
		local bonusIndex = (fieldindex - fieldIndices.numBonusIDs);
		return format("bonusID%d",bonusIndex)
	end
	for name, index in next, fieldIndices do
		if (fieldindex == index) then
			return name;
		end
	end
	return UNKNOWN;
end

-- Analyses the itemString and checks for upgrades that affects itemLevel -- Only itemLevel 450 and above will have this
-- As new upgrades are added all the time, this function is rather unreliable, and its therefore not recommended to use
-- WARNING: Use the LibItemString:GetTrueItemLevel() function instead, which scans the tooltip for a 100% correct itemLevel
function LIS:GetUpgradedItemLevel()
	local _, _, _, itemLevel = GetItemInfo(self.source);
	if not (itemLevel) then
		return nil;
	end

	-- obtain the itemString upgrade and bonusValue
	local timewarp = self.bonusID1;
	local warforged = self.bonusID2;
	local upgradeValue = self.upgradeValue;

	-- Return the actual itemLevel based on the itemString properties
	if (itemLevel >= 450) and (LIS.UPGRADED_LEVEL_ADJUST[upgradeValue]) then
		return itemLevel + LIS.UPGRADED_LEVEL_ADJUST[upgradeValue];
	else
		return LIS.TIMEWARPED_WARFORGED_LEVEL_ADJUST[warforged] or LIS.TIMEWARPED_LEVEL_ADJUST[timewarp] or itemLevel;
	end
end

-- Scans the tooltip for the proper itemLevel as we cannot get it consistently any other way
-- No ItemString instance is needed to call this function, that is calling LibItemString:New()
function LIS:GetTooltipItemLevel(itemLink)
	LIS.ScanTip:ClearLines();
	LIS.ScanTip:SetHyperlink(itemLink);

	-- Line 1 is item name; Line 2 could simply be the itemLevel, or it could be the upgrade type such as "Mythic Warforged"
	for i = 2, min(LIS.ScanTip:NumLines(),LIS.TOOLTIP_MAXLINE_LEVEL) do
		local line = _G["LibItemStringScanTipTextLeft"..i]:GetText();
		local itemLevel = tonumber(line:match(LIS.ITEM_LEVEL_PATTERN));
		if (itemLevel) then
			return itemLevel;
		end
	end
end

-- GLOBAL function staying compatible with the old "GetUpgradedItemLevel.lua" unit
-- OBSOLETE: Use LibItemString:GetTrueItemLevel(itemLink) instead
function GetUpgradedItemLevelFromItemLink(itemLink)
	return LIS:GetTrueItemLevel(itemLink);
end