-- ***************************************************************************************************************************************************
-- * Scanner.lua                                                                                                                                     *
-- ***************************************************************************************************************************************************
-- * Processes auction scans and stores them in the auction DB                                                                                       *
-- ***************************************************************************************************************************************************
-- * 0.4.4 / 2012.08.12 / Baanano: Fixed minor bug in Event.LibPGC.AuctionData                                                                       *
-- * 0.4.1 / 2012.07.10 / Baanano: Updated for LibPGC                                                                                                *
-- * 0.4.0 / 2012.05.31 / Baanano: Rewritten AHMonitoringService.lua                                                                                 *
-- ***************************************************************************************************************************************************

local addonInfo, InternalInterface = ...
local addonID = addonInfo.identifier

_G[addonID] = _G[addonID] or {}
local PublicInterface = _G[addonID]

local PAGESIZE = 1000
local ITEM, ACTIVE, EXPIRED = 1, 2, 3

local CreateTask = LibScheduler.CreateTask
local GetPlayerName = InternalInterface.Utility.GetPlayerName
local IInteraction = Inspect.Interaction
local IADetail = Inspect.Auction.Detail
local IIDetail = Inspect.Item.Detail
local MFloor = math.floor
local MMax = math.max
local MMin = math.min
local Release = LibScheduler.Release
local Time = Inspect.Time.Server
local TInsert = table.insert
local TRemove = table.remove
local TSort = table.sort
local ipairs = ipairs
local next = next
local pairs = pairs
local pcall = pcall
local tonumber = tonumber

local dataModel = nil
local loadComplete = false

local cachedAuctions = {}
local cachedItemTypes = {}

local alreadyMatched = {}
local pendingAuctions = {}
local pendingPosts = {}

local nativeIndexer = InternalInterface.Indexers.BuildNativeIndexer()
local ownIndex = {}

local lastTask = nil

local AuctionDataEvent = Utility.Event.Create(addonID, "AuctionData")

local RARITIES_C2N = { "sellable", "common", "uncommon", "rare", "epic", "relic", "transcendant", "quest", }
local RARITIES_N2C = { sellable = 1, [""] = 2, common = 2, uncommon = 3, rare = 4, epic = 5, relic = 6, transcendant = 7, quest = 8, }

local function TryMatchAuction(auctionID)
	if alreadyMatched[auctionID] then return end
	
	local itemType = cachedAuctions[auctionID]
	local pending = itemType and pendingPosts[itemType] or nil
	
	local bid = dataModel:RetrieveAuctionBid(itemType, auctionID)
	local buy = dataModel:RetrieveAuctionBuy(itemType, auctionID)
	
	if not pending or not bid then return end
	
	for index, pendingData in ipairs(pending) do
		if not pendingData.matched and pendingData.bid == bid and pendingData.buy == buy then
			local firstSeen = dataModel:RetrieveAuctionFirstSeen(itemType, auctionID)
			
			dataModel:ModifyAuctionMinExpire(itemType, auctionID, pendingData.timestamp + pendingData.tim * 3600)
			dataModel:ModifyAuctionMaxExpire(itemType, auctionID, firstSeen + pendingData.tim * 3600)
			
			pendingPosts[itemType][index].matched = true
			alreadyMatched[auctionID] = true
			return
		end
	end
	
	pendingAuctions[itemType] = pendingAuctions[itemType] or {}
	pendingAuctions[itemType][auctionID] = true
end

local function TryMatchPost(itemType, tim, timestamp, bid, buyout)
	local auctions = pendingAuctions[itemType] or {}
	for auctionID in pairs(auctions) do
		if not alreadyMatched[auctionID] then
			local auctionBid = dataModel:RetrieveAuctionBid(itemType, auctionID)
			local auctionBuy = dataModel:RetrieveAuctionBuy(itemType, auctionID)
			
			if bid == auctionBid and (buyout or 0) == auctionBuy then
				local firstSeen = dataModel:RetrieveAuctionFirstSeen(itemType, auctionID)
				
				dataModel:ModifyAuctionMinExpire(itemType, auctionID, timestamp + tim * 3600)
				dataModel:ModifyAuctionMaxExpire(itemType, auctionID, firstSeen + tim * 3600)
				
				pendingAuctions[itemType][auctionID] = nil
				alreadyMatched[auctionID] = true
				return
			end
		end
	end

	pendingPosts[itemType] = pendingPosts[itemType] or {}
	TInsert(pendingPosts[itemType], { tim = tim, timestamp = timestamp, bid = bid, buy = buyout or 0 })
end

local function OnAuctionData(criteria, auctions)
	local auctionScanTime = Time()
	local expireTimes = 
	{ 
		short =		{ auctionScanTime, 			auctionScanTime + 7200 }, 
		medium =	{ auctionScanTime + 7200, 	auctionScanTime + 43200 }, 
		long =		{ auctionScanTime + 43200, 	auctionScanTime + 172800 },
	}

	local totalAuctions, newAuctions, updatedAuctions, removedAuctions, beforeExpireAuctions = {}, {}, {}, {}, {}
	local totalItemTypes, newItemTypes, updatedItemTypes, removedItemTypes, modifiedItemTypes = {}, {}, {}, {}, {}
	
	local playerName = GetPlayerName()
	
	local function ProcessItemType(itemType)
		totalItemTypes[itemType] = true
		if cachedItemTypes[itemType] then return end
		
		local itemDetail = IIDetail(itemType)

		local name, icon, rarity, level = itemDetail.name, itemDetail.icon, RARITIES_N2C[itemDetail.rarity or ""], itemDetail.requiredLevel or 1
		local category, callings = itemDetail.category or "", itemDetail.requiredCalling
		callings =
		{
			warrior = (not callings or callings:find("warrior")) and true or false,
			cleric = (not callings or callings:find("cleric")) and true or false,
			rogue = (not callings or callings:find("rogue")) and true or false,
			mage = (not callings or callings:find("mage")) and true or false,
		}
		
		if not dataModel:CheckItemExists(itemType) then
			dataModel:StoreItem(itemType, name, icon, category, level, callings, rarity, auctionScanTime)
		else
			local storedName, storedIcon, storedCategory, storedLevel, storedCallings, storedRarity = dataModel:RetrieveItemData(itemType)
			if name ~= storedName or icon ~= storedIcon or category ~= storedCategory or level ~= storedLevel or callings.warrior ~= storedCallings.warrior or callings.cleric ~= storedCallings.cleric or callings.rogue ~= storedCallings.rogue or callings.mage ~= storedCallings.mage or rarity ~= storedRarity then
				for auctionID in pairs(dataModel:RetrieveActiveAuctions(itemType)) do
					local price = dataModel:RetrieveAuctionBuy(itemType, auctionID)
					
					nativeIndexer:RemoveAuction(auctionID, storedCallings, storedRarity, storedLevel, storedCategory, storedName, price)
					nativeIndexer:AddAuction(itemType, auctionID, callings, rarity, level, category, name, price)
				end
				
				dataModel:StoreItem(itemType, name, icon, category, level, callings, rarity, auctionScanTime)
				modifiedItemTypes[itemType] = true
			else
				dataModel:ModifyItemLastSeen(itemType, auctionScanTime)
			end
		end
		
		cachedItemTypes[itemType] = true
	end
	
	local function ProcessAuction(auctionID, auctionDetail)
		local itemType = auctionDetail.itemType
		
		ProcessItemType(itemType)
		cachedAuctions[auctionID] = itemType
		
		TInsert(totalAuctions, auctionID)
		
		if not dataModel:CheckAuctionActive(itemType, auctionID) then
			dataModel:StoreAuction(itemType, auctionID, true, auctionDetail.seller,
			                       auctionDetail.bid, auctionDetail.buyout or 0, auctionDetail.bidder and auctionDetail.bidder == playerName and auctionDetail.bid or 0,
							       auctionScanTime, auctionScanTime, expireTimes[auctionDetail.time][1], expireTimes[auctionDetail.time][2],
							       auctionDetail.itemStack or 1,
								   {
									own = auctionDetail.seller == playerName and true or false,
									bidded = auctionDetail.bidder and auctionDetail.bidder ~= "0" and true or false,
									beforeExpiration = false,
									ownBought = false,
									cancelled = false,
								   })

			TInsert(newAuctions, auctionID)
			newItemTypes[itemType] = true
			
			local itemName, _, category, level, callings, rarity = dataModel:RetrieveItemData(itemType)
			nativeIndexer:AddAuction(itemType, auctionID, callings, rarity, level, category, itemName, auctionDetail.buyout or 0)
			
			if auctionDetail.seller == playerName then
				ownIndex[auctionID] = itemType
				TryMatchAuction(auctionID)
			end
		else
			dataModel:ModifyAuctionLastSeen(itemType, auctionID, auctionScanTime)

			local minExpire = dataModel:RetrieveAuctionMinExpire(itemType, auctionID)
			if expireTimes[auctionDetail.time][1] > minExpire then
				dataModel:ModifyAuctionMinExpire(itemType, auctionID, expireTimes[auctionDetail.time][1])
			end
			
			local maxExpire = dataModel:RetrieveAuctionMaxExpire(itemType, auctionID)
			if expireTimes[auctionDetail.time][2] < maxExpire then
				dataModel:ModifyAuctionMaxExpire(itemType, auctionID, expireTimes[auctionDetail.time][2])
			end
			
			if auctionDetail.bidder and auctionDetail.bidder == playerName then
				dataModel:ModifyAuctionOwnBid(itemType, auctionID, auctionDetail.bid)
			end
			
			local flags = dataModel:RetrieveAuctionFlags(itemType, auctionID)
			flags.own = flags.own or auctionDetail.seller == playerName or false
			flags.bidded = flags.bidded or (auctionDetail.bidder and auctionDetail.bidder ~= "0") or false

			local bid = dataModel:RetrieveAuctionBid(itemType, auctionID)
			if auctionDetail.bid > bid then
				flags.bidded = true
				TInsert(updatedAuctions, auctionID)
				updatedItemTypes[itemType] = true
				dataModel:ModifyAuctionBid(itemType, auctionID, auctionDetail.bid)
			end
			
			dataModel:ModifyAuctionFlags(itemType, auctionID, flags)
			
			if flags.own then ownIndex[auctionID] = itemType end
		end
	end
	
	local function ProcessAuctions()
		local preprocessingSuccessful = true
		
		for auctionID in pairs(auctions) do
			local ok, auctionDetail = pcall(IADetail, auctionID)
			if not ok or not auctionDetail then
				preprocessingSuccessful = false 
				break 
			end
			ProcessAuction(auctionID, auctionDetail)
			Release()
		end

		if criteria.type == "search" then
			local auctionCount = 0
			if not preprocessingSuccessful then
				for auctionID in pairs(auctions) do auctionCount = auctionCount + 1  end
			else
				auctionCount = #totalAuctions
			end
			
			if not criteria.index or (criteria.index == 0 and auctionCount < 50) then
				local matchingAuctions = nativeIndexer:Search(criteria.role, criteria.rarity and RARITIES_N2C[criteria.rarity], criteria.levelMin, criteria.levelMax, criteria.category, criteria.priceMin, criteria.priceMax, criteria.text)
				for auctionID, itemType in pairs(matchingAuctions) do
					if not auctions[auctionID] then
						TInsert(removedAuctions, auctionID)
						removedItemTypes[itemType] = true
					
						local minExpire = dataModel:RetrieveAuctionMinExpire(itemType, auctionID)
						if auctionScanTime < minExpire then
							local flags = dataModel:RetrieveAuctionFlags(itemType, auctionID)
							flags.beforeExpiration = true
							dataModel:ModifyAuctionFlags(itemType, auctionID, flags)
							
							TInsert(beforeExpireAuctions, auctionID)
						end
						
						local itemName, _, category, level, callings, rarity = dataModel:RetrieveItemData(itemType)
						local price = dataModel:RetrieveAuctionBuy(itemType, auctionID)
						nativeIndexer:RemoveAuction(auctionID, callings, rarity, level, category, itemName, price)
						ownIndex[auctionID] = nil
						
						dataModel:ExpireAuction(itemType, auctionID)
					end
					Release()
				end
			end
		elseif criteria.type == "mine" then
			for auctionID, itemType in pairs(ownIndex) do
				if not auctions[auctionID] then
					local seller = dataModel:RetrieveAuctionSeller(itemType, auctionID)
					if seller == playerName then
						TInsert(removedAuctions, auctionID)
						removedItemTypes[itemType] = true
						
						local minExpire = dataModel:RetrieveAuctionMinExpire(itemType, auctionID)
						if auctionScanTime < minExpire then
							local flags = dataModel:RetrieveAuctionFlags(itemType, auctionID)
							flags.beforeExpiration = true
							dataModel:ModifyAuctionFlags(itemType, auctionID, flags)
							
							TInsert(beforeExpireAuctions, auctionID)						
						end
						
						local itemName, _, category, level, callings, rarity = dataModel:RetrieveItemData(itemType)
						local price = dataModel:RetrieveAuctionBuy(itemType, auctionID)
						nativeIndexer:RemoveAuction(auctionID, callings, rarity, level, category, itemName, price)
						ownIndex[auctionID] = nil
						
						dataModel:ExpireAuction(itemType, auctionID)						
					end
				end
				Release()
			end
		end

		if criteria.sort and criteria.sort == "time" and criteria.sortOrder then
			local knownAuctions = {}
			if preprocessingSuccessful then
				knownAuctions = totalAuctions
			else
				for auctionID in pairs(auctions) do
					if cachedAuctions[auctionID] then
						TInsert(knownAuctions, auctionID)
						Release()
					end
				end
			end
			
			local sortFunction = nil
			if criteria.sortOrder == "descending" then
				sortFunction = function(a, b) return auctions[a] < auctions[b] end
			else
				sortFunction = function(a, b) return auctions[b] < auctions[a] end
			end
			
			local knownAuctionsPages = {}
			for index, auctionID in ipairs(knownAuctions) do
				local page = MFloor(index / PAGESIZE) + 1
				knownAuctionsPages[page] = knownAuctionsPages[page] or {}
				TInsert(knownAuctionsPages[page], auctionID)
				Release()
			end
			
			for _, page in pairs(knownAuctionsPages) do
				TSort(page, sortFunction)
				Release()
			end
			
			knownAuctions = {}
			repeat
				local minPageIndex = nil
				
				for pageIndex, page in pairs(knownAuctionsPages) do
					if #page > 0 then
						if not minPageIndex or sortFunction(page[1], knownAuctionsPages[minPageIndex][1]) then
							minPageIndex = pageIndex
						end
					end
				end
				
				if minPageIndex then
					TInsert(knownAuctions, knownAuctionsPages[minPageIndex][1])
					TRemove(knownAuctionsPages[minPageIndex], 1)
				end
				
				Release()
			until not minPageIndex
			
			for index = 2, #knownAuctions, 1 do
				local auctionID = knownAuctions[index]
				local prevAuctionID = knownAuctions[index - 1]
				
				local minExpire = dataModel:RetrieveAuctionMinExpire(cachedAuctions[auctionID], auctionID)
				local previousMinExpire = dataModel:RetrieveAuctionMinExpire(cachedAuctions[prevAuctionID], prevAuctionID)
				
				if minExpire < previousMinExpire then
					dataModel:ModifyAuctionMinExpire(cachedAuctions[auctionID], auctionID, previousMinExpire)
				end
				Release()
			end
			
			for index = #knownAuctions - 1, 1, -1 do
				local auctionID = knownAuctions[index]
				local nextAuctionID = knownAuctions[index + 1]

				local maxExpire = dataModel:RetrieveAuctionMaxExpire(cachedAuctions[auctionID], auctionID)
				local nextMaxExpire = dataModel:RetrieveAuctionMaxExpire(cachedAuctions[nextAuctionID], nextAuctionID)
				
				if maxExpire > nextMaxExpire then
					dataModel:ModifyAuctionMaxExpire(cachedAuctions[auctionID], auctionID, nextMaxExpire)
				end
				Release()
			end
		end		
	end
	
	local function ProcessCompleted()
		AuctionDataEvent(criteria.type, totalAuctions, newAuctions, updatedAuctions, removedAuctions, beforeExpireAuctions, totalItemTypes, newItemTypes, updatedItemTypes, removedItemTypes, modifiedItemTypes)
	end
	
	lastTask = CreateTask(ProcessAuctions, ProcessCompleted, nil, lastTask) or lastTask
end
TInsert(Event.Auction.Scan, { OnAuctionData, addonID, addonID .. ".Scanner.OnAuctionData" })

local function LoadAuctionTable(addonId)
	if addonId == addonID then
		local rawData = _G[addonID .. "AuctionTable"]

		lastTask = CreateTask(
		function()
			--print("LibPGC: Loading auction database...")
		
			dataModel = InternalInterface.Version.LoadDataModel(rawData)
			Release()
			
			--print("LibPGC: Indexing active auctions...")
			
			for itemType in pairs(dataModel:RetrieveAllItems()) do
				local activeAuctions = dataModel:RetrieveActiveAuctions(itemType)
				if activeAuctions and next(activeAuctions) then
					local name, _, category, level, callings, rarity = dataModel:RetrieveItemData(itemType)
					for auctionID in pairs(activeAuctions) do
						local price = dataModel:RetrieveAuctionBuy(itemType, auctionID)
						local flags = dataModel:RetrieveAuctionFlags(itemType, auctionID)
						
						nativeIndexer:AddAuction(itemType, auctionID, callings, rarity, level, category, name, price)
						if flags.own then ownIndex[auctionID] = itemType end
						Release()
					end
				end
				Release()
			end
			
			loadComplete = dataModel and true
			
			--print("LibPGC: Ready!")
		end, nil, nil, lastTask) or lastTask
	end
end
TInsert(Event.Addon.SavedVariables.Load.End, {LoadAuctionTable, addonID, addonID .. ".Scanner.LoadAuctionData"})

local function SaveAuctionTable(addonId)
	if addonId == addonID and loadComplete then
		local rawData = dataModel:GetRawData()
		_G[addonID .. "AuctionTable"] = rawData
	end
end
TInsert(Event.Addon.SavedVariables.Save.Begin, {SaveAuctionTable, addonID, addonID .. ".Scanner.SaveAuctionData"})

local function ProcessAuctionBuy(auctionID)
	local itemType = cachedAuctions[auctionID]

	local name, _, category, level, callings, rarity = dataModel:RetrieveItemData(itemType)
	local price = dataModel:RetrieveAuctionBuy(itemType, auctionID)
	if not name or not price then return end
	
	nativeIndexer:RemoveAuction(auctionID, callings, rarity, level, category, name, price)
	ownIndex[auctionID] = nil
	
	local flags = dataModel:RetrieveAuctionFlags(itemType, auctionID)
	flags.ownBought = true
	flags.beforeExpiration = true
	dataModel:ModifyAuctionFlags(itemType, auctionID, flags)
	
	dataModel:ExpireAuction(itemType, auctionID)
	
	AuctionDataEvent("playerbuy", {auctionID}, {}, {}, {auctionID}, {auctionID}, {[itemType] = true}, {}, {}, {[itemType] = true}, {})
end

local function ProcessAuctionBid(auctionID, amount)
	local itemType = cachedAuctions[auctionID]
	
	local price = dataModel:RetrieveAuctionBuy(itemType, auctionID)
	if not price then return end

	if price > 0 and amount >= price then
		ProcessAuctionBuy(auctionID)
	else
		dataModel:ModifyAuctionBid(itemType, auctionID, amount)
		dataModel:ModifyAuctionOwnBid(itemType, auctionID, amount)
	
		local flags = dataModel:RetrieveAuctionFlags(itemType, auctionID)
		flags.bidded = true
		dataModel:ModifyAuctionFlags(itemType, auctionID, flags)
		
		AuctionDataEvent("playerbid", {auctionID}, {}, {auctionID}, {}, {}, {[itemType] = true}, {}, {[itemType] = true}, {}, {})
	end
end

local function ProcessAuctionCancel(auctionID)
	local itemType = cachedAuctions[auctionID]
	
	local name, _, category, level, callings, rarity = dataModel:RetrieveItemData(itemType)
	local price = dataModel:RetrieveAuctionBuy(itemType, auctionID)
	if not name or not price then return end
	
	nativeIndexer:RemoveAuction(auctionID, callings, rarity, level, category, name, price)
	ownIndex[auctionID] = nil

	local flags = dataModel:RetrieveAuctionFlags(itemType, auctionID)
	flags.cancelled = true
	flags.beforeExpiration = true
	dataModel:ModifyAuctionFlags(itemType, auctionID, flags)
	
	dataModel:ExpireAuction(itemType, auctionID)
	
	AuctionDataEvent("playercancel", {auctionID}, {}, {}, {auctionID}, {auctionID}, {[itemType] = true}, {}, {}, {[itemType] = true}, {})
end

local function GetAuctionData(itemType, auctionID)
	if not loadComplete then return nil end

	itemType = itemType or (auctionID and cachedAuctions[auctionID])
	if not itemType or not dataModel:CheckItemExists(itemType) then return nil end
	
	local itemName = dataModel:RetrieveItemName(itemType)
	local itemIcon = dataModel:RetrieveItemIcon(itemType)
	local rarity = dataModel:RetrieveItemRarity(itemType)

	local seller, bid, buy, ownBidded, firstSeen, lastSeen, minExpire, maxExpire, stacks, flags, active = dataModel:RetrieveAuctionData(itemType, auctionID)
	if not seller then return nil end
	
	return
	{
		active = active,
		itemType = itemType,
		itemName = itemName,
		itemIcon = itemIcon,
		itemRarity = RARITIES_C2N[rarity],
		stack = stacks,
		bidPrice = bid,
		buyoutPrice = buy ~= 0 and buy or nil,
		ownBidded = ownBidded,
		bidUnitPrice = bid / stacks,
		buyoutUnitPrice = buy ~= 0 and (buy / stacks) or nil,
		sellerName = seller,
		firstSeenTime = firstSeen,
		lastSeenTime = lastSeen,
		minExpireTime = minExpire,
		maxExpireTime = maxExpire,
		own = flags.own,
		bidded = flags.bidded,
		removedBeforeExpiration = flags.beforeExpiration,
		ownBought = flags.ownBought,
		cancelled = flags.cancelled,
	}
end

local function SearchAuctionsAsync(calling, rarity, levelMin, levelMax, category, priceMin, priceMax, name)
	local auctions = nativeIndexer:Search(calling, rarity and RARITIES_N2C[rarity] or nil, levelMin, levelMax, category, priceMin, priceMax, name)
	for auctionID, itemType in pairs(auctions) do
		auctions[auctionID] = GetAuctionData(itemType, auctionID)
		Release()
	end
	return auctions
end

local function GetAuctionDataAsync(item, startTime, endTime, excludeExpired)
	local auctions = {}
	
	startTime = startTime or 0
	endTime = endTime or Time()
	
	if not item then
		for itemType in pairs(dataModel:RetrieveAllItems()) do
			for auctionID in pairs(dataModel:RetrieveActiveAuctions(itemType)) do
				local auctionData = GetAuctionData(itemType, auctionID)
				if auctionData and auctionData.lastSeenTime >= startTime and auctionData.firstSeenTime <= endTime then
					auctions[auctionID] = auctionData
				end
				Release()
			end
			
			if not excludeExpired then
				for auctionID in pairs(dataModel:RetrieveExpiredAuctions(itemType)) do
					local auctionData = GetAuctionData(itemType, auctionID)
					if auctionData and auctionData.lastSeenTime >= startTime and auctionData.firstSeenTime <= endTime then
						auctions[auctionID] = auctionData
					end
					Release()
				end
			end
		end
	else
		local itemType = nil
		if item:sub(1, 1) == "I" then
			itemType = item
		else
			local ok, itemDetail = pcall(IIDetail, item)
			itemType = ok and itemDetail and itemDetail.type or nil
		end
		
		if not dataModel:CheckItemExists(itemType) then return {} end
		
		for auctionID in pairs(dataModel:RetrieveActiveAuctions(itemType)) do
			local auctionData = GetAuctionData(itemType, auctionID)
			if auctionData and auctionData.lastSeenTime >= startTime and auctionData.firstSeenTime <= endTime then
				auctions[auctionID] = auctionData
			end
			Release()
		end
		
		if not excludeExpired then
			for auctionID in pairs(dataModel:RetrieveExpiredAuctions(itemType)) do
				local auctionData = GetAuctionData(itemType, auctionID)
				if auctionData and auctionData.lastSeenTime >= startTime and auctionData.firstSeenTime <= endTime then
					auctions[auctionID] = auctionData
				end
				Release()
			end
		end
	end
	
	return auctions
end

local function GetOwnAuctionDataAsync()
	local auctions = {}
	for auctionID, itemType in pairs(ownIndex) do
		auctions[auctionID] = GetAuctionData(itemType, auctionID)
		Release()
	end
	return auctions
end



function PublicInterface.GetAuctionBuyCallback(auctionID)
	return function(failed)
		if failed then return end
		lastTask = CreateTask(function() ProcessAuctionBuy(auctionID) end, nil, nil, lastTask) or lastTask
	end
end

function PublicInterface.GetAuctionBidCallback(auctionID, amount)
	return function(failed)
		if failed then return end
		lastTask = CreateTask(function() ProcessAuctionBid(auctionID, amount) end, nil, nil, lastTask) or lastTask
	end
end

function PublicInterface.GetAuctionPostCallback(itemType, duration, bid, buyout)
	local timestamp = Time()
	return function(failed)
		if not failed then
			lastTask = CreateTask(function() TryMatchPost(itemType, duration, timestamp, bid, buyout or 0) end, nil, nil, lastTask) or lastTask
		end
	end
end

function PublicInterface.GetAuctionCancelCallback(auctionID)
	return function(failed)
		if failed then return end
		lastTask = CreateTask(function() ProcessAuctionCancel(auctionID) end, nil, nil, lastTask) or lastTask
	end
end

PublicInterface.GetAuctionData = GetAuctionData

function PublicInterface.SearchAuctions(callback, calling, rarity, levelMin, levelMax, category, priceMin, priceMax, name)
	if type(callback) ~= "function" then return end
	lastTask = CreateTask(function() return SearchAuctionsAsync(calling, rarity, levelMin, levelMax, category, priceMin, priceMax, name) end, callback, nil, lastTask) or lastTask
end

function PublicInterface.GetAllAuctionData(callback, item, startTime, endTime)
	if type(callback) ~= "function" then return end
	lastTask = CreateTask(function() return GetAuctionDataAsync(item, startTime, endTime, false) end, callback, nil, lastTask) or lastTask
end

function PublicInterface.GetActiveAuctionData(callback, item)
	if type(callback) ~= "function" then return end
	lastTask = CreateTask(function() return GetAuctionDataAsync(item, nil, nil, true) end, callback, nil, lastTask) or lastTask
end

function PublicInterface.GetOwnAuctionData(callback)
	if type(callback) ~= "function" then return end
	lastTask = CreateTask(GetOwnAuctionDataAsync, callback, nil, lastTask) or lastTask
end	

function PublicInterface.GetAuctionCached(auctionID)
	return cachedAuctions[auctionID] and true or false -- TODO Consider moving this to GetAuctionData
end

function PublicInterface.GetLastTimeSeen(item)
	if not item or not loadComplete then return nil end

	local itemType = nil
	if item:sub(1, 1) == "I" then
		itemType = item
	else
		local ok, itemDetail = pcall(IIDetail, item)
		itemType = ok and itemDetail and itemDetail.type or nil
	end

	return dataModel:RetrieveItemLastSeen(itemType)
end	

function PublicInterface.GetLastTask()
	return lastTask
end
