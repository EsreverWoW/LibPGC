-- ***************************************************************************************************************************************************
-- * v4.lua                                                                                                                                          *
-- ***************************************************************************************************************************************************
-- * 0.4.4 / 2013.09.29 / Baanano: First version                                                                                                     *
-- ***************************************************************************************************************************************************

local addonDetail, addonData = ...
local addonID = addonDetail.identifier
local Internal, Public = addonData.Internal, addonData.Public

local VERSION = 4
local MAX_DATA_AGE = 30 * 24 * 60 * 60

local CheckFlag = function(value, flag) return bit.band(value, flag) == flag end
local Converter = Internal.Utility.Converter

local ItemTypeConverter = Converter({
	{ field = "name",         length = 4, },
	{ field = "icon",         length = 4, },
	{ field = "category",     length = 2, },
	{ field = "level",        length = 1, },
	{ field = "callings",     length = 1, },
	{ field = "rarity",       length = 1, },
	{ field = "lastSeen",     length = 4, },
})

local AuctionConverter = Converter({
	{ field = "seller",       length = 3, },
	{ field = "item",         length = 3, },
	{ field = "bid",          length = 5, },
	{ field = "buy",          length = 5, },
	{ field = "ownbid",       length = 5, },
	{ field = "firstSeen",    length = 4, },
	{ field = "firstUnseen",  length = 4, },
	{ field = "minExpire",    length = 4, },
	{ field = "maxExpire",    length = 4, },
	{ field = "stacks",       length = 2, },
	{ field = "flags",        length = 1, },
})

local function DataModelBuilder(rawData)
	local IT_ITEMDATA, IT_AUCTIONS = 1, 2
	local ITC_WARRIOR, ITC_CLERIC, ITC_ROGUE, ITC_MAGE = 8, 4, 2, 1
	local AF_OWN, AF_BIDDED, AF_BEFOREEXPIRATION, AF_OWNBOUGHT, AF_CANCELLED, AF_REPOSTED = 128, 64, 32, 16, 8, 4
	
	local contextHandle = blTasks.Task.Current()

	-- If rawData is empty, create an empty model
	if rawData == nil then
		rawData =
		{
			itemTypes = {},
			auctions = {},
			auctionSellers = {},
			auctionItems = {},
			itemNames = {},
			itemIcons = {},
			itemCategories = {},
			version = VERSION,
		}
	end
	
	-- Check if the raw data is in the proper format
	if type(rawData) ~= "table" or rawData.version ~= VERSION then
		error("Wrong data format")
	end
	
	-- Create the DataModel object
	local dataModel = {}
	
	-- Create the reverse lookups
	local reverseSellers = {}
	for index = 1, #rawData.auctionSellers do
		reverseSellers[rawData.auctionSellers[index]] = index
		contextHandle:BreathShort()
	end
	
	local reverseItems = {}
	for index = 1, #rawData.auctionItems do
		reverseItems[rawData.auctionItems[index]] = index
		contextHandle:BreathShort()
	end
	
	local reverseNames = {}
	for index = 1, #rawData.itemNames do
		reverseNames[rawData.itemNames[index]] = index
		contextHandle:BreathShort()
	end
	
	local reverseIcons = {}
	for index = 1, #rawData.itemIcons do
		reverseIcons[rawData.itemIcons[index]] = index
		contextHandle:BreathShort()
	end
	
	local reverseCategories = {}
	for index = 1, #rawData.itemCategories do
		reverseCategories[rawData.itemCategories[index]] = index
		contextHandle:BreathShort()
	end
	
	-- Perform maintenance
	local purgeTime = Inspect.Time.Server() - MAX_DATA_AGE
	
	for auctionID, auctionData in pairs(rawData.auctions) do
		local auctionInfo = AuctionConverter(auctionData)
		if auctionInfo.firstUnseen > 0 and auctionInfo.firstUnseen < purgeTime and not CheckFlag(auctionInfo.flags, AF_OWN) and not CheckFlag(auctionInfo.flags, AF_OWNBOUGHT) then
			rawData.auctions[auctionID] = nil
		end
		
		contextHandle:BreathShort()
	end
	
	for itemType, itemData in pairs(rawData.itemTypes) do
		for auctionID in pairs(itemData[IT_AUCTIONS]) do
			if not rawData.auctions[auctionID] then
				itemData[IT_AUCTIONS][auctionID] = nil
			end
		end
		
		if not next(itemData[IT_AUCTIONS]) then
			rawData.itemTypes[itemType] = nil
		end
		
		contextHandle:BreathShort()
	end
	
	
	-- Model	
	function dataModel:GetRawData()
		return rawData
	end
	
	function dataModel:GetVersion()
		return VERSION
	end
	
	
	-- Items
	function dataModel:CheckItemExists(itemType)
		return itemType and rawData.itemTypes[itemType] and true or false
	end
	
	function dataModel:RetrieveAllItems()
		local itemTypes = {}
		for itemType in pairs(rawData.itemTypes) do
			itemTypes[itemType] = true
		end
		return itemTypes
	end
	
	function dataModel:RetrieveItemData(itemType)
		local itemData = itemType and rawData.itemTypes[itemType] and rawData.itemTypes[itemType][IT_ITEMDATA] or nil
		if not itemData then return end
		
		itemData = ItemTypeConverter(itemData)
		local callings = itemData.callings
		
		return 	rawData.itemNames[itemData.name],
				rawData.itemIcons[itemData.icon],
				rawData.itemCategories[itemData.category],
				itemData.level,
				{
					warrior = CheckFlag(callings, ITC_WARRIOR),
					cleric = CheckFlag(callings, ITC_CLERIC),
					rogue = CheckFlag(callings, ITC_ROGUE),
					mage = CheckFlag(callings, ITC_MAGE),
				},
				itemData.rarity,
				itemData.lastSeen
	end

	function dataModel:RetrieveItemName(itemType)
		local itemData = itemType and rawData.itemTypes[itemType] and rawData.itemTypes[itemType][IT_ITEMDATA] or nil
		if not itemData then return end
		return rawData.itemNames[ItemTypeConverter(itemData).name]
	end
	
	function dataModel:RetrieveItemIcon(itemType)
		local itemData = itemType and rawData.itemTypes[itemType] and rawData.itemTypes[itemType][IT_ITEMDATA] or nil
		if not itemData then return end
		return rawData.itemIcons[ItemTypeConverter(itemData).icon]
	end
	
	function dataModel:RetrieveItemCategory(itemType)
		local itemData = itemType and rawData.itemTypes[itemType] and rawData.itemTypes[itemType][IT_ITEMDATA] or nil
		if not itemData then return end
		return rawData.itemCategories[ItemTypeConverter(itemData).category]
	end
	
	function dataModel:RetrieveItemRequiredLevel(itemType)
		local itemData = itemType and rawData.itemTypes[itemType] and rawData.itemTypes[itemType][IT_ITEMDATA] or nil
		if not itemData then return end
		return ItemTypeConverter(itemData).level
	end
	
	function dataModel:RetrieveItemRequiredCallings(itemType)
		local itemData = itemType and rawData.itemTypes[itemType] and rawData.itemTypes[itemType][IT_ITEMDATA] or nil
		if not itemData then return end
		local callings = ItemTypeConverter(itemData).callings
		return
		{
			warrior = CheckFlag(callings, ITC_WARRIOR),
			cleric = CheckFlag(callings, ITC_CLERIC),
			rogue = CheckFlag(callings, ITC_ROGUE),
			mage = CheckFlag(callings, ITC_MAGE),
		}
	end
	
	function dataModel:RetrieveItemRarity(itemType)
		local itemData = itemType and rawData.itemTypes[itemType] and rawData.itemTypes[itemType][IT_ITEMDATA] or nil
		if not itemData then return end
		return ItemTypeConverter(itemData).rarity
	end
	
	function dataModel:RetrieveItemLastSeen(itemType)
		local itemData = itemType and rawData.itemTypes[itemType] and rawData.itemTypes[itemType][IT_ITEMDATA] or nil
		if not itemData then return end
		return ItemTypeConverter(itemData).lastSeen
	end
	
	function dataModel:StoreItem(itemType, name, icon, category, requiredLevel, requiredCallings, rarity, lastSeen)
		if not itemType then return false end
		if not name or not icon or not category or not requiredLevel or type(requiredCallings) ~= "table" or not rarity or not lastSeen then return false end
		
		rawData.itemTypes[itemType] = rawData.itemTypes[itemType] or { "", {}, }
		
		local nameID = reverseNames[name]
		if not nameID then
			nameID = #rawData.itemNames + 1
			rawData.itemNames[nameID] = name
			reverseNames[name] = nameID
		end
		
		local iconID = reverseIcons[icon]
		if not iconID then
			iconID = #rawData.itemIcons + 1
			rawData.itemIcons[iconID] = icon
			reverseIcons[icon] = iconID
		end
		
		local categoryID = reverseCategories[category]
		if not categoryID then
			categoryID = #rawData.itemCategories + 1
			rawData.itemCategories[categoryID] = category
			reverseCategories[category] = categoryID
		end
		
		local itemData = ItemTypeConverter()
		itemData.name = nameID
		itemData.icon = iconID
		itemData.category = categoryID
		itemData.level = requiredLevel
		itemData.callings = (requiredCallings.warrior and ITC_WARRIOR or 0) +
		                    (requiredCallings.cleric and ITC_CLERIC or 0) +
		                    (requiredCallings.rogue and ITC_ROGUE or 0) +
		                    (requiredCallings.mage and ITC_MAGE or 0)
		itemData.rarity = rarity
		itemData.lastSeen = lastSeen
		
		rawData.itemTypes[itemType][IT_ITEMDATA] = tostring(itemData)
		
		return true
	end
	
	function dataModel:ModifyItemName(itemType, name)
		if not itemType or not rawData.itemTypes[itemType] then return false end
		if not name then return false end
		
		local nameID = reverseNames[name]
		if not nameID then
			nameID = #rawData.itemNames + 1
			rawData.itemNames[nameID] = name
			reverseNames[name] = nameID
		end
		
		local itemData = ItemTypeConverter(rawData.itemTypes[itemType][IT_ITEMDATA])
		itemData.name = nameID
		rawData.itemTypes[itemType][IT_ITEMDATA] = tostring(itemData)
		
		return true
	end
	
	function dataModel:ModifyItemIcon(itemType, icon)
		if not itemType or not rawData.itemTypes[itemType] then return false end
		if not icon then return false end
		
		local iconID = reverseIcons[icon]
		if not iconID then
			iconID = #rawData.itemIcons + 1
			rawData.itemIcons[iconID] = icon
			reverseIcons[icon] = iconID
		end
		
		local itemData = ItemTypeConverter(rawData.itemTypes[itemType][IT_ITEMDATA])
		itemData.icon = iconID
		rawData.itemTypes[itemType][IT_ITEMDATA] = tostring(itemData)

		return true
	end
	
	function dataModel:ModifyItemCategory(itemType, category)
		if not itemType or not rawData.itemTypes[itemType] then return false end
		if not category then return false end
		
		local categoryID = reverseCategories[category]
		if not categoryID then
			categoryID = #rawData.itemCategories + 1
			rawData.itemCategories[categoryID] = category
			reverseCategories[category] = categoryID
		end
		
		local itemData = ItemTypeConverter(rawData.itemTypes[itemType][IT_ITEMDATA])
		itemData.category = categoryID
		rawData.itemTypes[itemType][IT_ITEMDATA] = tostring(itemData)

		return true
	end
	
	function dataModel:ModifyItemRequiredLevel(itemType, requiredLevel)
		if not itemType or not rawData.itemTypes[itemType] then return false end
		if not requiredLevel then return false end
		
		local itemData = ItemTypeConverter(rawData.itemTypes[itemType][IT_ITEMDATA])
		itemData.level = requiredLevel
		rawData.itemTypes[itemType][IT_ITEMDATA] = tostring(itemData)

		return true
	end
	
	function dataModel:ModifyItemRequiredCallings(itemType, requiredCallings)
		if not itemType or not rawData.itemTypes[itemType] then return false end
		if type(requiredCallings) ~= "table" then return false end

		local itemData = ItemTypeConverter(rawData.itemTypes[itemType][IT_ITEMDATA])
		itemData.callings = (requiredCallings.warrior and ITC_WARRIOR or 0) +
		                    (requiredCallings.cleric and ITC_CLERIC or 0) +
		                    (requiredCallings.rogue and ITC_ROGUE or 0) +
		                    (requiredCallings.mage and ITC_MAGE or 0)
		rawData.itemTypes[itemType][IT_ITEMDATA] = tostring(itemData)

		return true
	end
	
	function dataModel:ModifyItemRarity(itemType, rarity)
		if not itemType or not rawData.itemTypes[itemType] then return false end
		if not rarity then return false end
		
		local itemData = ItemTypeConverter(rawData.itemTypes[itemType][IT_ITEMDATA])
		itemData.rarity = rarity
		rawData.itemTypes[itemType][IT_ITEMDATA] = tostring(itemData)

		return true
	end
	
	function dataModel:ModifyItemLastSeen(itemType, lastSeen)
		if not itemType or not rawData.itemTypes[itemType] then return false end
		if not lastSeen then return false end
		
		local itemData = ItemTypeConverter(rawData.itemTypes[itemType][IT_ITEMDATA])
		itemData.lastSeen = lastSeen
		rawData.itemTypes[itemType][IT_ITEMDATA] = tostring(itemData)

		return true
	end
	
	-- Auctions
	function dataModel:CheckAuctionExists(itemType, auctionID)
		return rawData.auctions[auctionID] ~= nil
	end
	
	function dataModel:CheckAuctionActive(itemType, auctionID)
		return itemType and rawData.itemTypes[itemType] and rawData.itemTypes[itemType][IT_AUCTIONS][auctionID] == true
	end
	
	function dataModel:CheckAuctionExpired(itemType, auctionID)
		return itemType and rawData.itemTypes[itemType] and rawData.itemTypes[itemType][IT_AUCTIONS][auctionID] == false
	end
	
	function dataModel:RetrieveAllAuctions(itemType)
		if not itemType or not rawData.itemTypes[itemType] then return nil end
		
		local auctions = {}
		for auctionID in pairs(rawData.itemTypes[itemType][IT_AUCTIONS]) do
			auctions[auctionID] = true
		end
		
		return auctions
	end
	
	function dataModel:RetrieveActiveAuctions(itemType)
		if not itemType or not rawData.itemTypes[itemType] then return nil end
		
		local auctions = {}
		for auctionID, active in pairs(rawData.itemTypes[itemType][IT_AUCTIONS]) do
			if active then
				auctions[auctionID] = true
			end
		end
		
		return auctions
	end
	
	function dataModel:RetrieveExpiredAuctions(itemType)
		if not itemType or not rawData.itemTypes[itemType] then return nil end
		
		local auctions = {}
		for auctionID, active in pairs(rawData.itemTypes[itemType][IT_AUCTIONS]) do
			if not active then
				auctions[auctionID] = true
			end
		end
		
		return auctions
	end
	
	function dataModel:RetrieveAuctionData(itemType, auctionID)
		if not itemType or not rawData.itemTypes[itemType] then return nil end
		
		local active = rawData.itemTypes[itemType][IT_AUCTIONS][auctionID]
		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		local flags = auctionData.flags
		
		return rawData.auctionSellers[auctionData.seller], rawData.auctionItems[auctionData.item],
				auctionData.bid, auctionData.buy, auctionData.ownbid,
				auctionData.firstSeen, auctionData.firstUnseen, auctionData.minExpire, auctionData.maxExpire,
				auctionData.stacks,
				{
					own = CheckFlag(flags, AF_OWN),
					bidded = CheckFlag(flags, AF_BIDDED),
					beforeExpiration = CheckFlag(flags, AF_BEFOREEXPIRATION),
					ownBought = CheckFlag(flags, AF_OWNBOUGHT),
					cancelled = CheckFlag(flags, AF_CANCELLED),
					reposted = CheckFlag(flags, AF_REPOSTED),
				},
			   active
	end
	
	function dataModel:RetrieveAuctionSeller(itemType, auctionID)
		if not itemType or not rawData.itemTypes[itemType] then return end
		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		return rawData.auctionSellers[auctionData.seller]
	end
	
	function dataModel:RetrieveAuctionItem(itemType, auctionID)
		if not itemType or not rawData.itemTypes[itemType] then return end
		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		return rawData.auctionItems[auctionData.item]
	end
	
	function dataModel:RetrieveAuctionBid(itemType, auctionID)
		if not itemType or not rawData.itemTypes[itemType] then return end
		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		return auctionData.bid
	end
	
	function dataModel:RetrieveAuctionBuy(itemType, auctionID)
		if not itemType or not rawData.itemTypes[itemType] then return end
		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		return auctionData.buy
	end
	
	function dataModel:RetrieveAuctionOwnBid(itemType, auctionID)
		if not itemType or not rawData.itemTypes[itemType] then return end
		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		return auctionData.ownbid
	end
	
	function dataModel:RetrieveAuctionFirstSeen(itemType, auctionID)
		if not itemType or not rawData.itemTypes[itemType] then return end
		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		return auctionData.firstSeen
	end
	
	function dataModel:RetrieveAuctionFirstUnseen(itemType, auctionID)
		if not itemType or not rawData.itemTypes[itemType] then return end
		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		return auctionData.firstUnseen
	end
	
	function dataModel:RetrieveAuctionMinExpire(itemType, auctionID)
		if not itemType or not rawData.itemTypes[itemType] then return end
		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		return auctionData.minExpire
	end
	
	function dataModel:RetrieveAuctionMaxExpire(itemType, auctionID)
		if not itemType or not rawData.itemTypes[itemType] then return end
		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		return auctionData.maxExpire
	end
	
	function dataModel:RetrieveAuctionStack(itemType, auctionID)
		if not itemType or not rawData.itemTypes[itemType] then return end
		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		return auctionData.stacks
	end
	
	function dataModel:RetrieveAuctionFlags(itemType, auctionID)
		if not itemType or not rawData.itemTypes[itemType] then return end
		local flags = AuctionConverter(rawData.auctions[auctionID]).flags
		return
		{
			own = CheckFlag(flags, AF_OWN),
			bidded = CheckFlag(flags, AF_BIDDED),
			beforeExpiration = CheckFlag(flags, AF_BEFOREEXPIRATION),
			ownBought = CheckFlag(flags, AF_OWNBOUGHT),
			cancelled = CheckFlag(flags, AF_CANCELLED),
			reposted = CheckFlag(flags, AF_REPOSTED),
		}
	end

	function dataModel:StoreAuction(itemType, auctionID, active, seller, item, bid, buy, ownBid, firstSeen, firstUnseen, minExpire, maxExpire, stack, flags)
		if not itemType or not rawData.itemTypes[itemType] or not auctionID then return false end
		if not seller or not bid or not buy or not item or not ownBid or not firstSeen or not firstUnseen or not minExpire or not maxExpire or not stack or type(flags) ~= "table" then return false end

		local sellerID = reverseSellers[seller]
		if not sellerID then
			sellerID = #rawData.auctionSellers + 1
			rawData.auctionSellers[sellerID] = seller
			reverseSellers[seller] = sellerID
		end
		
		local itemID = reverseItems[item]
		if not itemID then
			itemID = #rawData.auctionItems + 1
			rawData.auctionItems[itemID] = item
			reverseItems[item] = itemID
		end
		
		local auctionData = AuctionConverter()
		
		auctionData.seller = sellerID
		auctionData.item = itemID
		auctionData.bid = bid
		auctionData.buy = buy
		auctionData.ownbid = ownBid
		auctionData.firstSeen = firstSeen
		auctionData.firstUnseen = firstUnseen
		auctionData.minExpire = minExpire
		auctionData.maxExpire = maxExpire
		auctionData.stacks = stack
		auctionData.flags = (flags.own and AF_OWN or 0) +
		                    (flags.bidded and AF_BIDDED or 0) +
		                    (flags.beforeExpiration and AF_BEFOREEXPIRATION or 0) +
		                    (flags.ownBought and AF_OWNBOUGHT or 0) +
		                    (flags.cancelled and AF_CANCELLED or 0) +
		                    (flags.reposted and AF_REPOSTED or 0)
		
		rawData.auctions[auctionID] = tostring(auctionData)
		rawData.itemTypes[itemType][IT_AUCTIONS][auctionID] = active and true or false

		return true		
	end
	
	function dataModel:ModifyAuctionSeller(itemType, auctionID, seller)
		if not itemType or not rawData.itemTypes[itemType] or not auctionID then return false end
		if not seller then return false end

		local sellerID = reverseSellers[seller]
		if not sellerID then
			sellerID = #rawData.auctionSellers + 1
			rawData.auctionSellers[sellerID] = seller
			reverseSellers[seller] = sellerID
		end
		
		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		auctionData.seller = sellerID
		rawData.auctions[auctionID] = tostring(auctionData)

		return true
	end
	
	function dataModel:ModifyAuctionItem(itemType, auctionID, item)
		if not itemType or not rawData.itemTypes[itemType] or not auctionID then return false end
		if not item then return false end

		local itemID = reverseItems[item]
		if not itemID then
			itemID = #rawData.auctionItems + 1
			rawData.auctionItems[itemID] = item
			reverseItems[item] = itemID
		end
		
		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		auctionData.item = itemID
		rawData.auctions[auctionID] = tostring(auctionData)

		return true
	end
	
	function dataModel:ModifyAuctionBid(itemType, auctionID, bid)
		if not itemType or not rawData.itemTypes[itemType] or not auctionID then return false end
		if not bid then return false end

		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		auctionData.bid = bid
		rawData.auctions[auctionID] = tostring(auctionData)

		return true
	end
	
	function dataModel:ModifyAuctionBuy(itemType, auctionID, buy)
		if not itemType or not rawData.itemTypes[itemType] or not auctionID then return false end
		if not buy then return false end

		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		auctionData.buy = buy
		rawData.auctions[auctionID] = tostring(auctionData)

		return true
	end
	
	function dataModel:ModifyAuctionOwnBid(itemType, auctionID, ownBid)
		if not itemType or not rawData.itemTypes[itemType] or not auctionID then return false end
		if not ownBid then return false end

		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		auctionData.ownbid = ownBid
		rawData.auctions[auctionID] = tostring(auctionData)

		return true
	end
	
	function dataModel:ModifyAuctionFirstSeen(itemType, auctionID, firstSeen)
		if not itemType or not rawData.itemTypes[itemType] or not auctionID then return false end
		if not firstSeen then return false end

		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		auctionData.firstSeen = firstSeen
		rawData.auctions[auctionID] = tostring(auctionData)

		return true
	end
	
	function dataModel:ModifyAuctionFirstUnseen(itemType, auctionID, firstUnseen)
		if not itemType or not rawData.itemTypes[itemType] or not auctionID then return false end
		if not firstUnseen then return false end

		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		auctionData.firstUnseen = firstUnseen
		rawData.auctions[auctionID] = tostring(auctionData)

		return true
	end
	
	function dataModel:ModifyAuctionMinExpire(itemType, auctionID, minExpire)
		if not itemType or not rawData.itemTypes[itemType] or not auctionID then return false end
		if not minExpire then return false end

		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		auctionData.minExpire = minExpire
		rawData.auctions[auctionID] = tostring(auctionData)

		return true
	end
	
	function dataModel:ModifyAuctionMaxExpire(itemType, auctionID, maxExpire)
		if not itemType or not rawData.itemTypes[itemType] or not auctionID then return false end
		if not maxExpire then return false end

		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		auctionData.maxExpire = maxExpire
		rawData.auctions[auctionID] = tostring(auctionData)

		return true
	end
	
	function dataModel:ModifyAuctionStack(itemType, auctionID, stack)
		if not itemType or not rawData.itemTypes[itemType] or not auctionID then return false end
		if not stack then return false end

		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		auctionData.stacks = stack
		rawData.auctions[auctionID] = tostring(auctionData)

		return true
	end
	
	function dataModel:ModifyAuctionFlags(itemType, auctionID, flags)
		if not itemType or not rawData.itemTypes[itemType] or not auctionID then return false end
		if type(flags) ~= "table" then return false end

		local auctionData = AuctionConverter(rawData.auctions[auctionID])
		auctionData.flags = (flags.own and AF_OWN or 0) +
		                    (flags.bidded and AF_BIDDED or 0) +
		                    (flags.beforeExpiration and AF_BEFOREEXPIRATION or 0) +
		                    (flags.ownBought and AF_OWNBOUGHT or 0) +
		                    (flags.cancelled and AF_CANCELLED or 0) +
		                    (flags.reposted and AF_REPOSTED or 0)
		rawData.auctions[auctionID] = tostring(auctionData)		

		return true
	end
	
	function dataModel:ExpireAuction(itemType, auctionID)
		if not itemType or not rawData.itemTypes[itemType] or not auctionID then return false end
		
		rawData.itemTypes[itemType][IT_AUCTIONS][auctionID] = false
		
		return true
	end
	
	function dataModel:ResurrectAuction(itemType, auctionID)
		if not itemType or not rawData.itemTypes[itemType] or not auctionID then return false end
		
		rawData.itemTypes[itemType][IT_AUCTIONS][auctionID] = true
		
		return true
	end
	
	return dataModel
end

Internal.Version.RegisterDataModel(VERSION, DataModelBuilder)
