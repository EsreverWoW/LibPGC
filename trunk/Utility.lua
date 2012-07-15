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
