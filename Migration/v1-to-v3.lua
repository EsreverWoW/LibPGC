-- ***************************************************************************************************************************************************
-- * Migration.lua                                                                                                                                   *
-- ***************************************************************************************************************************************************
-- * Handles migration between datamodels                                                                                                            *
-- ***************************************************************************************************************************************************
-- * 0.4.4 / 2012.12.19 / Baanano: First version                                                                                                     *
-- ***************************************************************************************************************************************************

local addonInfo, InternalInterface = ...
local addonID = addonInfo.identifier

local Release = LibScheduler.Release
local error = error
local pairs = pairs
local print = print

local ORIGINAL_VERSION = 1
local TARGET_VERSION = 3

local function Migration(oldModel)
	print("Migrating " .. addonID .. " saved data from v" .. ORIGINAL_VERSION .. " to v" .. TARGET_VERSION .. "...")
	
	local itemCount = 0
	local auctionCount = 0
	
	local newModel = InternalInterface.Version.GetDataModelBuilder(TARGET_VERSION)
	if not newModel then
		error("Couldn't find a target data model builder")
	end
	newModel = newModel()

	for itemType in pairs(oldModel:RetrieveAllItems()) do
		local name, icon, category, requiredLevel, requiredCallings, rarity, lastSeen = oldModel:RetrieveItemData(itemType)
		if not newModel:StoreItem(itemType, name, icon, category, requiredLevel, requiredCallings, rarity, lastSeen) then
			error("Couldn't migrate item")
		end
		
		Release()
		
		for auctionID in pairs(oldModel:RetrieveAllAuctions(itemType)) do
			local seller, bid, buy, ownBid, firstSeen, lastSeen, remaining, stack, flags, active = oldModel:RetrieveAuctionData(itemType, auctionID)
			if not newModel:StoreAuction(itemType, auctionID, active, seller, bid, buy, ownBid, firstSeen, lastSeen, remaining, stack, flags) then
				error("Couldn't migrate auction")
			end
			auctionCount = auctionCount + 1
			Release()
		end
		
		itemCount = itemCount + 1
	end

	print(addonID .. " saved data has been successfully migrated to v" .. TARGET_VERSION .. ": " .. itemCount .. " item(s), " .. auctionCount .. " auction(s).")
	
	return newModel, TARGET_VERSION
end

InternalInterface.Version.RegisterMigrationProcedure(ORIGINAL_VERSION, Migration)
