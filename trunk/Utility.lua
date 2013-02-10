-- ***************************************************************************************************************************************************
-- * Utility.lua                                                                                                                                     *
-- ***************************************************************************************************************************************************
-- * Defines helper functions                                                                                                                        *
-- ***************************************************************************************************************************************************
-- * 0.4.1 / 2012.07.10 / Baanano: Removed functionality not related to the LibPGC library                                                           *
-- * 0.4.0 / 2012.05.30 / Baanano: First version, splitted out of the old Init.lua                                                                   *
-- ***************************************************************************************************************************************************

local addonInfo, InternalInterface = ...
local addonID = addonInfo.identifier

local IUDetail = Inspect.Unit.Detail
local SChar = string.char
local TConcat = table.concat
local ipairs = ipairs
local setmetatable = setmetatable

InternalInterface.Utility = InternalInterface.Utility or {}

-- ***************************************************************************************************************************************************
-- * CopyTableSimple                                                                                                                                 *
-- ***************************************************************************************************************************************************
-- * Returns a shallow copy of a table, without its metatable                                                                                        *
-- ***************************************************************************************************************************************************
function InternalInterface.Utility.CopyTableSimple(sourceTable)
	local copy = {}
	for key, value in pairs(sourceTable) do 
		copy[key] = value 
	end
	return copy
end

-- ***************************************************************************************************************************************************
-- * CopyTableRecursive                                                                                                                              *
-- ***************************************************************************************************************************************************
-- * Returns a deep copy of a table, without its metatable                                                                                           *
-- ***************************************************************************************************************************************************
function InternalInterface.Utility.CopyTableRecursive(sourceTable)
	local copy = {}
	for key, value in pairs(sourceTable) do
		copy[key] = type(value) == "table" and InternalInterface.Utility.CopyTableRecursive(value) or value
	end
	return copy
end

-- ***************************************************************************************************************************************************
-- * GetPlayerName                                                                                                                                   *
-- ***************************************************************************************************************************************************
-- * Returns the name of the player, if known                                                                                                        *
-- ***************************************************************************************************************************************************
local playerName = nil
function InternalInterface.Utility.GetPlayerName()
	if not playerName then
		playerName = IUDetail("player")
		playerName = playerName and playerName.name or nil
	end
	return playerName
end

function InternalInterface.Utility.Converter(definitions)
	local lastOffset, fieldOffsets = 1, {}
	for _, definition in ipairs(definitions) do
	 	fieldOffsets[definition.field] =
	 	{
	 		from = lastOffset,
			length = definition.length,
	 	 	to = lastOffset + definition.length - 1,
	 	}
	 	lastOffset = lastOffset + definition.length
	end

	return function(value)
		value = value or ("\000"):rep(lastOffset - 1)
		
	 	return setmetatable({},
	 	{
	 	 	__index = function(tab, field)
	 	 	 	local fieldOffset = fieldOffsets[field]
	 	 		if not fieldOffset then return nil end
	 	 	 	
				local result = 0
	 	 	 	value:sub(fieldOffset.from, fieldOffset.to):gsub("(.)", function(c) result = result * 256 + c:byte() end)
	 	 	 	return result
	 	 	end,
			
	 	 	__newindex = function(tab, field, val)
	 	 	 	local fieldOffset = fieldOffsets[field]
	 	 	 	if not fieldOffset then return nil end
	 	 	 	
				local result = {}
	 	 	 	for index = fieldOffset.length, 1, -1 do
	 	 	 	 	result[index] = SChar(val % 256)
	 	 	 	 	val = bit.rshift(val, 8)
	 	 	 	end
	 	 	 	value = value:sub(1, fieldOffset.from - 1) .. TConcat(result) .. value:sub(fieldOffset.to + 1)
	 	 	end,
			
	 	 	__tostring = function()
				return value
			end,
	 	})
	end
end