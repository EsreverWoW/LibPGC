-- ***************************************************************************************************************************************************
-- * v1.lua                                                                                                                                          *
-- ***************************************************************************************************************************************************
-- * LibPGC DataModel v1                                                                                                                             *
-- ***************************************************************************************************************************************************
-- * 0.4.4 / 2013.01.01 / Baanano: First version                                                                                                     *
-- ***************************************************************************************************************************************************

local addonInfo, InternalInterface = ...
local addonID = addonInfo.identifier

local pairs = pairs
local type = type

local VERSION = 1
local DEFAULT_RARITY = 2
local DEFAULT_LASTSEEN = 0
local RARITIES_C2N = { "sellable", "common", "uncommon", "rare", "epic", "relic", "transcendant", "quest", }
local RARITIES_N2C = { sellable = 1, [""] = 2, common = 2, uncommon = 3, rare = 4, epic = 5, relic = 6, transcendant = 7, quest = 8, }
local MAX_DATA_AGE = 5 * 24 * 60 * 60

local function DataModelBuilder(rawData)
	-- If rawData is empty, create an empty model
	if rawData == nil then
		rawData = {}
	end

	-- Perform maintenance
	local purgeTime = Inspect.Time.Server() - MAX_DATA_AGE
	
	for itemType, itemData in pairs(rawData) do
		local hasAuctions = hasAuctions or (next(itemData.activeAuctions) and true or false)
		for auctionID, auctionData in pairs(itemData.expiredAuctions) do
			if auctionData.lastSeen < purgeTime then
				itemData.expiredAuctions[auctionID] = nil
			else
				hasAuctions = true
			end
		end
		if not hasAuctions then
			rawData[itemType] = nil
		end
	end
	
	-- Create the DataModel object
	local dataModel = {}
	
	-- Model	
	function dataModel:GetRawData()
		return rawData
	end
	
	function dataModel:GetVersion()
		return VERSION
	end
	
	-- Items
	function dataModel:CheckItemExists(itemType)
		return itemType and rawData[itemType] and true or false
	end
	
	function dataModel:RetrieveAllItems()
		local itemTypes = {}
		for itemType in pairs(rawData) do
			itemTypes[itemType] = true
		end
		return itemTypes
	end
	
	function dataModel:RetrieveItemData(itemType)
		local itemData = itemType and rawData[itemType] or nil
		if not itemData then return end
		
		return itemData.name,
		       itemData.icon,
			   itemData.category,
			   itemData.level,
			   {
				warrior = itemData.callings and itemData.callings.warrior and true or false,
				cleric = itemData.callings and itemData.callings.cleric and true or false,
				rogue = itemData.callings and itemData.callings.rogue and true or false,
				mage = itemData.callings and itemData.callings.mage and true or false,
			   },
			   RARITIES_N2C[itemData.rarity] or DEFAULT_RARITY,
			   itemData.lastSeen or DEFAULT_LASTSEEN
	end

	function dataModel:RetrieveItemName(itemType)
		return itemType and rawData[itemType] and rawData[itemType].name
	end
	
	function dataModel:RetrieveItemIcon(itemType)
		return itemType and rawData[itemType] and rawData[itemType].icon
	end
	
	function dataModel:RetrieveItemCategory(itemType)
		return itemType and rawData[itemType] and rawData[itemType].category
	end
	
	function dataModel:RetrieveItemRequiredLevel(itemType)
		return itemType and rawData[itemType] and rawData[itemType].level
	end
	
	function dataModel:RetrieveItemRequiredCallings(itemType)
		local itemData = itemType and rawData[itemType] or nil
		if not itemData then return end
		local callings = itemData.callings or {}
		return
		{
			warrior = callings.warrior and true or false,
			cleric = callings.cleric and true or false,
			rogue = callings.rogue and true or false,
			mage = callings.mage and true or false,
		}
	end
	
	function dataModel:RetrieveItemRarity(itemType)
		if not itemType or not rawData[itemType] then return nil end
		return RARITIES_N2C[rawData[itemType].rarity] or DEFAULT_RARITY
	end
	
	function dataModel:RetrieveItemLastSeen(itemType)
		if not itemType or not rawData[itemType] then return nil end
		return rawData[itemType].lastSeen or DEFAULT_LASTSEEN
	end
	
	function dataModel:StoreItem(itemType, name, icon, category, requiredLevel, requiredCallings, rarity, lastSeen)
		if not itemType or not name or not icon or not category or not requiredLevel or not requiredCallings or not rarity or not lastSeen then return false end
		if type(requiredCallings) ~= "table" or not RARITIES_C2N[rarity] then return false end
		
		rawData[itemType] = rawData[itemType] or { activeAuctions = {}, expiredAuctions = {}, }
		
		rawData[itemType].name = name
		rawData[itemType].icon = icon
		rawData[itemType].category = category
		rawData[itemType].level = requiredLevel
		rawData[itemType].callings =
		{
			warrior = requiredCallings.warrior and true or nil,
			cleric = requiredCallings.cleric and true or nil,
			rogue = requiredCallings.rogue and true or nil,
			mage = requiredCallings.mage and true or nil,
		}
		rawData[itemType].rarity = RARITIES_C2N[rarity]
		rawData[itemType].lastSeen = lastSeen
		
		return true
	end
	
	function dataModel:ModifyItemName(itemType, name)
		if not itemType or not name or not rawData[itemType] then return false end
		rawData[itemType].name = name
		return true
	end
	
	function dataModel:ModifyItemIcon(itemType, icon)
		if not itemType or not icon or not rawData[itemType] then return false end
		rawData[itemType].icon = icon
		return true
	end
	
	function dataModel:ModifyItemCategory(itemType, category)
		if not itemType or not category or not rawData[itemType] then return false end
		rawData[itemType].category = category
		return true
	end
	
	function dataModel:ModifyItemRequiredLevel(itemType, requiredLevel)
		if not itemType or not requiredLevel or not rawData[itemType] then return false end
		rawData[itemType].level = requiredLevel
		return true
	end
	
	function dataModel:ModifyItemRequiredCallings(itemType, requiredCallings)
		if not itemType or not requiredCallings or type(requiredCallings) ~= "table" or not rawData[itemType] then return false end
		rawData[itemType].callings =
		{
			warrior = requiredCallings.warrior and true or nil,
			cleric = requiredCallings.cleric and true or nil,
			rogue = requiredCallings.rogue and true or nil,
			mage = requiredCallings.mage and true or nil,
		}
		return true
	end
	
	function dataModel:ModifyItemRarity(itemType, rarity)
		if not itemType or not rarity or not RARITIES_C2N[rarity] or not rawData[itemType] then return false end
		rawData[itemType].rarity = RARITIES_C2N[rarity]
		return true
	end
	
	function dataModel:ModifyItemLastSeen(itemType, lastSeen)
		if not itemType or not lastSeen or not rawData[itemType] then return false end
		rawData[itemType].lastSeen = lastSeen
		return true
	end
	
	-- Auctions
	function dataModel:CheckAuctionExists(itemType, auctionID)
		return itemType and rawData[itemType] and (rawData[itemType].activeAuctions[auctionID] or rawData[itemType].expiredAuctions[auctionID]) and true or false
	end
	
	function dataModel:CheckAuctionActive(itemType, auctionID)
		return itemType and rawData[itemType] and rawData[itemType].activeAuctions[auctionID] and true or false
	end
	
	function dataModel:CheckAuctionExpired(itemType, auctionID)
		return itemType and rawData[itemType] and rawData[itemType].expiredAuctions[auctionID] and true or false
	end
	
	function dataModel:RetrieveAllAuctions(itemType)
		local itemData = itemType and rawData[itemType] or nil
		if not itemData then return nil end
		
		local auctions = {}
		for auctionID in pairs(itemData.activeAuctions) do
			auctions[auctionID] = true
		end
		for auctionID in pairs(itemData.expiredAuctions) do
			auctions[auctionID] = true
		end
		
		return auctions
	end
	
	function dataModel:RetrieveActiveAuctions(itemType)
		local itemData = itemType and rawData[itemType] or nil
		if not itemData then return nil end
		
		local auctions = {}
		for auctionID in pairs(itemData.activeAuctions) do
			auctions[auctionID] = true
		end
		
		return auctions
	end
	
	function dataModel:RetrieveExpiredAuctions(itemType)
		local itemData = itemType and rawData[itemType] or nil
		if not itemData then return nil end
		
		local auctions = {}
		for auctionID in pairs(itemData.expiredAuctions) do
			auctions[auctionID] = true
		end
		
		return auctions
	end
	
	function dataModel:RetrieveAuctionData(itemType, auctionID)
		local itemData = itemType and rawData[itemType] or nil
		if not itemData then return end
		
		local auctionData, active = itemData.activeAuctions[auctionID], true
		if not auctionData then
			auctionData, active = itemData.expiredAuctions[auctionID], false
		end
		if not auctionData then return end
		
		return auctionData.seller,
		       auctionData.bid,
			   auctionData.buy,
			   auctionData.ownBidded,
			   auctionData.firstSeen,
			   auctionData.lastSeen,
			   auctionData.minExpire,
			   auctionData.maxExpire,
			   auctionData.stack,
			   {
				own = auctionData.own and true or false,
				bidded = auctionData.bidded and true or false,
				beforeExpiration = auctionData.beforeExpiration and true or false,
				ownBought = auctionData.ownBought and true or false,
				cancelled = auctionData.cancelled and true or false,
			   },
			   active
	end
	
	function dataModel:RetrieveAuctionSeller(itemType, auctionID)
		local auctionData = itemType and rawData[itemType] and (rawData[itemType].activeAuctions[auctionID] or rawData[itemType].expiredAuctions[auctionID]) or nil
		return auctionData and auctionData.seller or nil
	end
	
	function dataModel:RetrieveAuctionBid(itemType, auctionID)
		local auctionData = itemType and rawData[itemType] and (rawData[itemType].activeAuctions[auctionID] or rawData[itemType].expiredAuctions[auctionID]) or nil
		return auctionData and auctionData.bid or nil
	end
	
	function dataModel:RetrieveAuctionBuy(itemType, auctionID)
		local auctionData = itemType and rawData[itemType] and (rawData[itemType].activeAuctions[auctionID] or rawData[itemType].expiredAuctions[auctionID]) or nil
		return auctionData and auctionData.buy or nil
	end
	
	function dataModel:RetrieveAuctionOwnBid(itemType, auctionID)
		local auctionData = itemType and rawData[itemType] and (rawData[itemType].activeAuctions[auctionID] or rawData[itemType].expiredAuctions[auctionID]) or nil
		return auctionData and auctionData.ownBidded or nil
	end
	
	function dataModel:RetrieveAuctionFirstSeen(itemType, auctionID)
		local auctionData = itemType and rawData[itemType] and (rawData[itemType].activeAuctions[auctionID] or rawData[itemType].expiredAuctions[auctionID]) or nil
		return auctionData and auctionData.firstSeen or nil
	end
	
	function dataModel:RetrieveAuctionLastSeen(itemType, auctionID)
		local auctionData = itemType and rawData[itemType] and (rawData[itemType].activeAuctions[auctionID] or rawData[itemType].expiredAuctions[auctionID]) or nil
		return auctionData and auctionData.lastSeen or nil
	end
	
	function dataModel:RetrieveAuctionMinExpire(itemType, auctionID)
		local auctionData = itemType and rawData[itemType] and (rawData[itemType].activeAuctions[auctionID] or rawData[itemType].expiredAuctions[auctionID]) or nil
		return auctionData and auctionData.minExpire or nil
	end
	
	function dataModel:RetrieveAuctionMaxExpire(itemType, auctionID)
		local auctionData = itemType and rawData[itemType] and (rawData[itemType].activeAuctions[auctionID] or rawData[itemType].expiredAuctions[auctionID]) or nil
		return auctionData and auctionData.maxExpire or nil
	end
	
	function dataModel:RetrieveAuctionStack(itemType, auctionID)
		local auctionData = itemType and rawData[itemType] and (rawData[itemType].activeAuctions[auctionID] or rawData[itemType].expiredAuctions[auctionID]) or nil
		return auctionData and auctionData.stack or nil
	end
	
	function dataModel:RetrieveAuctionFlags(itemType, auctionID)
		local auctionData = itemType and rawData[itemType] and (rawData[itemType].activeAuctions[auctionID] or rawData[itemType].expiredAuctions[auctionID]) or nil
		if not auctionData then return end
		return
		{
			own = auctionData.own and true or false,
			bidded = auctionData.bidded and true or false,
			beforeExpiration = auctionData.beforeExpiration and true or false,
			ownBought = auctionData.ownBought and true or false,
			cancelled = auctionData.cancelled and true or false,
	   }
	end

	function dataModel:StoreAuction(itemType, auctionID, active, seller, bid, buy, ownBid, firstSeen, lastSeen, minExpire, maxExpire, stack, flags)
		if not itemType or not auctionID or not seller or not bid or not buy or not ownBid or not firstSeen or not minExpire or not maxExpire or not stack then return false end
		if not flags or type(flags) ~= "table" then return false end
		local itemData = rawData[itemType]
		if not itemData then return false end
		
		local auctionData
		if active then
			itemData.activeAuctions[auctionID] = itemData.activeAuctions[auctionID] or {}
			auctionData = itemData.activeAuctions[auctionID]
		else
			if itemData.activeAuctions[auctionID] then
				itemData.activeAuctions[auctionID] = nil
			end
			itemData.expiredAuctions[auctionID] = itemData.expiredAuctions[auctionID] or {}
			auctionData = itemData.expiredAuctions[auctionID]
		end
		
		auctionData.seller = seller
		auctionData.bid = bid
		auctionData.buy = buy
		auctionData.ownBidded = ownBid
		auctionData.firstSeen = firstSeen
		auctionData.lastSeen = lastSeen
		auctionData.minExpire = minExpire
		auctionData.maxExpire = maxExpire
		auctionData.stack = stack
		auctionData.own = flags.own or nil
		auctionData.bidded = flags.bidded or nil
		auctionData.beforeExpiration = flags.beforeExpiration or nil
		auctionData.ownBought = flags.ownBought or nil
		auctionData.cancelled = flags.cancelled or nil

		return true		
	end
	
	function dataModel:ModifyAuctionSeller(itemType, auctionID, seller)
		if not itemType or not auctionID or not seller then return false end
		
		local auctionData = rawData[itemType] and (rawData[itemType].activeAuctions[auctionID] or rawData[itemType].expiredAuctions[auctionID]) or nil
		if not auctionData then return false end
		
		auctionData.seller = seller
		return true
	end
	
	function dataModel:ModifyAuctionBid(itemType, auctionID, bid)
		if not itemType or not auctionID or not bid then return false end
		
		local auctionData = rawData[itemType] and (rawData[itemType].activeAuctions[auctionID] or rawData[itemType].expiredAuctions[auctionID]) or nil
		if not auctionData then return false end
		
		auctionData.bid = bid
		return true
	end
	
	function dataModel:ModifyAuctionBuy(itemType, auctionID, buy)
		if not itemType or not auctionID or not buy then return false end
		
		local auctionData = rawData[itemType] and (rawData[itemType].activeAuctions[auctionID] or rawData[itemType].expiredAuctions[auctionID]) or nil
		if not auctionData then return false end
		
		auctionData.buy = buy
		return true
	end
	
	function dataModel:ModifyAuctionOwnBid(itemType, auctionID, ownBid)
		if not itemType or not auctionID or not ownBid then return false end
		
		local auctionData = rawData[itemType] and (rawData[itemType].activeAuctions[auctionID] or rawData[itemType].expiredAuctions[auctionID]) or nil
		if not auctionData then return false end
		
		auctionData.ownBidded = ownBid
		return true
	end
	
	function dataModel:ModifyAuctionFirstSeen(itemType, auctionID, firstSeen)
		if not itemType or not auctionID or not firstSeen then return false end
		
		local auctionData = rawData[itemType] and (rawData[itemType].activeAuctions[auctionID] or rawData[itemType].expiredAuctions[auctionID]) or nil
		if not auctionData then return false end
		
		auctionData.firstSeen = firstSeen
		return true
	end
	
	function dataModel:ModifyAuctionLastSeen(itemType, auctionID, lastSeen)
		if not itemType or not auctionID or not lastSeen then return false end
		
		local auctionData = rawData[itemType] and (rawData[itemType].activeAuctions[auctionID] or rawData[itemType].expiredAuctions[auctionID]) or nil
		if not auctionData then return false end
		
		auctionData.lastSeen = lastSeen
		return true
	end
	
	function dataModel:ModifyAuctionMinExpire(itemType, auctionID, minExpire)
		if not itemType or not auctionID or not minExpire then return false end
		
		local auctionData = rawData[itemType] and (rawData[itemType].activeAuctions[auctionID] or rawData[itemType].expiredAuctions[auctionID]) or nil
		if not auctionData then return false end
		
		auctionData.minExpire = minExpire
		return true
	end
	
	function dataModel:ModifyAuctionMaxExpire(itemType, auctionID, maxExpire)
		if not itemType or not auctionID or not maxExpire then return false end
		
		local auctionData = rawData[itemType] and (rawData[itemType].activeAuctions[auctionID] or rawData[itemType].expiredAuctions[auctionID]) or nil
		if not auctionData then return false end
		
		auctionData.maxExpire = maxExpire
		return true
	end
	
	function dataModel:ModifyAuctionStack(itemType, auctionID, stack)
		if not itemType or not auctionID or not stack then return false end
		
		local auctionData = rawData[itemType] and (rawData[itemType].activeAuctions[auctionID] or rawData[itemType].expiredAuctions[auctionID]) or nil
		if not auctionData then return false end
		
		auctionData.stack = stack
		return true
	end
	
	function dataModel:ModifyAuctionFlags(itemType, auctionID, flags)
		if not itemType or not auctionID or not flags or type(flags) ~= "table" then return false end
		
		local auctionData = rawData[itemType] and (rawData[itemType].activeAuctions[auctionID] or rawData[itemType].expiredAuctions[auctionID]) or nil
		if not auctionData then return false end
		
		auctionData.own = flags.own or nil
		auctionData.bidded = flags.bidded or nil
		auctionData.beforeExpiration = flags.beforeExpiration or nil
		auctionData.ownBought = flags.ownBought or nil
		auctionData.cancelled = flags.cancelled or nil
		
		return true
	end
	
	function dataModel:ExpireAuction(itemType, auctionID)
		if not itemType or not auctionID or not rawData[itemType] or not rawData[itemType].activeAuctions[auctionID] then return false end
		
		rawData[itemType].expiredAuctions[auctionID] = rawData[itemType].activeAuctions[auctionID]
		rawData[itemType].activeAuctions[auctionID] = nil
		
		return true
	end
	
	return dataModel
end

InternalInterface.Version.RegisterDataModel(VERSION, DataModelBuilder)
