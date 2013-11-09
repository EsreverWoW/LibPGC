-- ***************************************************************************************************************************************************
-- * Scanner.lua                                                                                                                                     *
-- ***************************************************************************************************************************************************
-- * 0.5.0 / 2013.09.29 / Baanano: Adapted to blTasks, added repost and fake expiration detection                                                    *
-- * 0.4.12/ 2013.09.17 / Baanano: Updated events to the new model                                                                                   *
-- * 0.4.4 / 2012.08.12 / Baanano: Fixed minor bug in Event.LibPGC.AuctionData                                                                       *
-- * 0.4.1 / 2012.07.10 / Baanano: Updated for LibPGC                                                                                                *
-- * 0.4.0 / 2012.05.31 / Baanano: Rewritten AHMonitoringService.lua                                                                                 *
-- ***************************************************************************************************************************************************

local addonDetail, addonData = ...
local addonID = addonDetail.identifier
local Internal, Public = addonData.Internal, addonData.Public

local LOCK_MODE =
{
	READ = 1,
	WRITE = 2,
}
local RARITIES_N2C = Internal.Constants.RarityToCode
local RARITIES_C2N = Internal.Constants.RarityFromCode

local dataModel = nil
local loading = true
local cachedAuctions = {}
local cachedItemTypes = {}
local alreadyMatched = {}
local pendingAuctions = {}
local pendingPosts = {}
local nativeIndexer = Internal.Indexer.Native()
local ownIndex = {}
local lock = {}

local ReadyEvent = Utility.Event.Create(addonID, "Ready")
local BeginEvent = Utility.Event.Create(addonID, "Scan.Begin")
local ProgressEvent = Utility.Event.Create(addonID, "Scan.Progress")
local EndEvent = Utility.Event.Create(addonID, "Scan.End")

-- TODO Extract
local function BinaryInsert(array, value, sortFunction)
	local first, final = 1, #array
	
	while first <= final do
		local mid = math.floor((first + final) / 2)
		if sortFunction(value, array[mid]) then
			final = mid - 1
		else
			first = mid + 1
		end
	end
	
	table.insert(array, first, value)
end

local function AcquireLock(task, mode)
	while lock[1] and not next(lock[1].tasks) do table.remove(lock, 1) end
	
	if mode == LOCK_MODE.READ then
		if loading then return false end
		
		if not lock[1] then
			lock[1] = { mode = LOCK_MODE.READ, tasks = blUtil.WeakReference.Key(), }
		end
		
		if lock[1].mode == LOCK_MODE.READ then
			lock[1].tasks[task] = true
			return true
		else
			return false
		end
	
	else
		for index = 1, #lock do
			if lock[index].mode == LOCK_MODE.WRITE and lock[index].tasks[task] then
				return not loading and index <= 1
			end
		end
		
		local index = #lock + 1
		lock[index] = { mode = LOCK_MODE.WRITE, tasks = blUtil.WeakReference.Key(), }
		lock[index].tasks[task] = true
		return not loading and index <= 1		
	end
end

local function FreeLock(task)
	for index = 1, #lock do
		lock[index].tasks[task] = nil
	end
end

local function TryMatchAuction(auctionID)
	if alreadyMatched[auctionID] then return end
	
	local itemType = cachedAuctions[auctionID]
	local pending = itemType and pendingPosts[itemType] or nil
	
	local bid = dataModel:RetrieveAuctionBid(itemType, auctionID)
	local buy = dataModel:RetrieveAuctionBuy(itemType, auctionID)
	
	if not pending or not bid then return end
	
	for index = 1, #pending do
		local pendingData = pending[index]
		
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

local function TryMatchPost(taskHandle, itemType, tim, timestamp, bid, buyout)
	-- Acquire lock
	while not AcquireLock(taskHandle, LOCK_MODE.WRITE) do taskHandle:Wait(blTasks.Wait.Timespan(1)) end

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
				break
			end
		end
	end
	
	FreeLock(taskHandle)

	pendingPosts[itemType] = pendingPosts[itemType] or {}
	pendingPosts[itemType][#pendingPosts[itemType] + 1] = { tim = tim, timestamp = timestamp, bid = bid, buy = buyout or 0 }
end

local function OnAuctionData(eventHandle, criteria, auctions)
	-- Timestamp when the data was received
	local auctionScanTime = Inspect.Time.Server()
	
	-- Expire timestamps
	local expireTimes =
	{ 
		short =		{ auctionScanTime, 			auctionScanTime + 7200 }, 
		medium =	{ auctionScanTime + 7200, 	auctionScanTime + 43200 }, 
		long =		{ auctionScanTime + 43200, 	auctionScanTime + 172800 },
	}
	
	-- Results
	local scanResults =
	{
		auctions =
		{
			count = { all = 0,  new = 0,  resurrected = 0,  reposted = 0,  updated = 0,  removed = 0,  beforeExpire = 0, },
			list =  { all = {}, new = {}, resurrected = {}, reposted = {}, updated = {}, removed = {}, beforeExpire = {}, }
		},
		itemTypes =
		{
			count = { all = 0,  new = 0,  updated = 0,  removed = 0,  modified = 0, },
			list =  { all = {}, new = {}, updated = {}, removed = {}, modified = {}, }
		},
	}
	local function UpdateResults(store, counter, value)
		if not scanResults[store].list[counter][value] then
			scanResults[store].list[counter][value] = true
			scanResults[store].count[counter] = scanResults[store].count[counter] + 1
		end
	end	
	
	-- Progress
	local progress = {}
	local function UpdateProgress(step, processed, total)
		if not progress.currentStep or step > progress.currentStep then
			if not progress.currentStep then
				progress.start = Inspect.Time.Real()
			end
			progress.currentStep = step
			progress.stepTotal = total
			progress.stepStart = Inspect.Time.Real()
		end
		progress.stepProcessed = processed
		progress.updated = true
	end
	local function ProgressReporter(taskHandle)
		BeginEvent(criteria)
		
		while true do
			if progress.updated then
				if progress.currentStep and progress.currentStep >= 5 then break end
				progress.updated = nil
				
				ProgressEvent(criteria, Inspect.Time.Real() - progress.start, math.floor(100 * (25 * (progress.currentStep - 1) + 25 * progress.stepProcessed / progress.stepTotal)) / 100)
			end
			taskHandle:Wait(blTasks.Wait.Frame())
		end
		
		EndEvent(criteria, Inspect.Time.Real() - progress.start, scanResults)
	end
	
	-- Player name
	local playerName = blUtil.Player.Name()
	
	-- Start task
	blTasks.Task.Create(
		function(taskHandle)
			local totalAuctions = 0
			local preprocessedAuctions = 0
			local auctionDetails = {}
			
			local reporterTask = blTasks.Task.Create(ProgressReporter):Start()
			
			-- 1. Collect auction data
			do
				-- 1.1. Count auctions
				for auctionID in pairs(auctions) do
					totalAuctions = totalAuctions + 1
				end
				
				-- 1.2. Stop now if there are no auctions
				if totalAuctions <= 0 then return end
				
				-- 1.3. Start step 1
				UpdateProgress(1, 0, totalAuctions)
				
				-- 1.4. Collect auction detail
				for auctionID in pairs(auctions) do
					taskHandle:BreathShort()
						
					-- 1.4.1. Get auction detail
					local ok, auctionDetail = pcall(Inspect.Auction.Detail, auctionID)
					if not ok or not auctionDetail then break end -- Error collecting auction data, the process will continue with the data collected so far.
					
					auctionDetails[auctionID] = auctionDetail
					preprocessedAuctions = preprocessedAuctions + 1
						
					-- 1.4.2. Update monitor
					UpdateProgress(1, preprocessedAuctions)
				end
			end
			
			-- 2. Acquire write lock
			while not AcquireLock(taskHandle, LOCK_MODE.WRITE) do taskHandle:Wait(blTasks.Wait.Timespan(1)) end
			
			-- 3. Process auction data
			do
				-- 3.1. Start step 2
				UpdateProgress(2, 0, preprocessedAuctions)
				
				-- 3.2. Process
				local processedAuctions = 0
				for auctionID, auctionDetail in pairs(auctionDetails) do
					taskHandle:Breath()
					
					-- 3.2.1. Get itemType
					local itemType = auctionDetail.itemType
						
					-- 3.2.2. If this is the first time the itemType has been seen on this session, update its data, as it could have changed
					if not cachedItemTypes[itemType] then
						-- 3.2.2.1. Get live itemType data
						local ok, itemDetail = pcall(Inspect.Item.Detail, itemType)
						if ok and itemDetail then
							local name = itemDetail.name
							local icon = itemDetail.icon
							local category = itemDetail.category or ""
							local level = itemDetail.requiredLevel or 1
							local callings = itemDetail.requiredCalling
							callings =
							{
								warrior = (not callings or callings:find("warrior")) and true or false,
								cleric = (not callings or callings:find("cleric")) and true or false,
								rogue = (not callings or callings:find("rogue")) and true or false,
								mage = (not callings or callings:find("mage")) and true or false,
							}
							local rarity = RARITIES_N2C[itemDetail.rarity or ""]

							-- 3.2.2.2. If the item isn't in the DB, add it
							if not dataModel:CheckItemExists(itemType) then
								dataModel:StoreItem(itemType, name, icon, category, level, callings, rarity, auctionScanTime)
							
							-- 3.2.2.3. Else, check if it the stored data needs to be updated
							else
								local storedName, storedIcon, storedCategory, storedLevel, storedCallings, storedRarity = dataModel:RetrieveItemData(itemType)
								if name ~= storedName or icon ~= storedIcon or category ~= storedCategory or level ~= storedLevel or callings.warrior ~= storedCallings.warrior or callings.cleric ~= storedCallings.cleric or callings.rogue ~= storedCallings.rogue or callings.mage ~= storedCallings.mage or rarity ~= storedRarity then
									
									-- 3.2.2.3.1. Update the index
									for auctionID in pairs(dataModel:RetrieveActiveAuctions(itemType)) do
										local price = dataModel:RetrieveAuctionBuy(itemType, auctionID)
										nativeIndexer.RemoveAuction(auctionID, storedCallings, storedRarity, storedLevel, storedCategory, storedName, price)
										nativeIndexer.AddAuction(itemType, auctionID, callings, rarity, level, category, name, price)
									end
									
									-- 3.2.2.3.2. Update the DB
									dataModel:StoreItem(itemType, name, icon, category, level, callings, rarity, auctionScanTime)
									
									-- 3.2.2.3.3. Add it to the results
									UpdateResults("itemTypes", "modified", value)
								end
							end
						
							-- 3.2.2.4. Add the itemtype to the cache so it isn't processed again during this session
							cachedItemTypes[itemType] = true							
						end
						
						taskHandle:Breath()
					end					
					
					if cachedItemTypes[itemType] then
						-- 3.2.3. Mark auction as seen this session
						cachedAuctions[auctionID] = itemType
					
						-- 3.2.4. Update results
						UpdateResults("itemTypes", "all", itemType)
						UpdateResults("auctions", "all", auctionID)
					
						-- 3.2.5. Check if this is a new auction
						if not dataModel:CheckAuctionExists(itemType, auctionID) then
							-- 3.2.5.1. Check if this is a repost
							local reposted = dataModel:CheckItemKnown(auctionDetail.item)
							
							-- 3.2.5.2. Store it in the DB
							dataModel:StoreAuction(itemType, auctionID, true,
								auctionDetail.seller, auctionDetail.item,
								auctionDetail.bid, auctionDetail.buyout or 0, auctionDetail.bidder and auctionDetail.bidder == playerName and auctionDetail.bid or 0,
								auctionScanTime, 0, expireTimes[auctionDetail.time][1], expireTimes[auctionDetail.time][2],
								auctionDetail.itemStack or 1,
								{
									own = auctionDetail.seller == playerName and true or false,
									bidded = auctionDetail.bidder and auctionDetail.bidder ~= "0" and true or false,
									beforeExpiration = false,
									ownBought = false,
									cancelled = false,
									reposted = reposted,
								})

							-- 3.2.5.3. Update results
							UpdateResults("itemTypes", "new", itemType)
							UpdateResults("auctions", "new", auctionID)
							if reposted then
								UpdateResults("auctions", "reposted", auctionID)
							end
							
							-- 3.2.5.4. Update indices
							local itemName, _, category, level, callings, rarity = dataModel:RetrieveItemData(itemType)
							nativeIndexer.AddAuction(itemType, auctionID, callings, rarity, level, category, itemName, auctionDetail.buyout or 0)
			
							if auctionDetail.seller == playerName then
								ownIndex[auctionID] = itemType
								TryMatchAuction(auctionID)
							end
						
						-- 3.2.6. Update the auction
						else
							local _, _, bid, _, _, _, _, minExpire, maxExpire, _, flags, active = dataModel:RetrieveAuctionData(itemType, auctionID)
							
							-- 3.2.6.1. Update the DB
							if not active then
								dataModel:ResurrectAuction(itemType, auctionID)
								dataModel:ModifyAuctionFirstUnseen(itemType, auctionID, 0)
							end

							if expireTimes[auctionDetail.time][1] > minExpire then
								dataModel:ModifyAuctionMinExpire(itemType, auctionID, expireTimes[auctionDetail.time][1])
							end
			
							if expireTimes[auctionDetail.time][2] < maxExpire then
								dataModel:ModifyAuctionMaxExpire(itemType, auctionID, expireTimes[auctionDetail.time][2])
							end
			
							if auctionDetail.bidder and auctionDetail.bidder == playerName then
								dataModel:ModifyAuctionOwnBid(itemType, auctionID, auctionDetail.bid)
							end
			
							flags.own = flags.own or auctionDetail.seller == playerName or false
							flags.bidded = flags.bidded or (auctionDetail.bidder and auctionDetail.bidder ~= "0") or false

							if auctionDetail.bid > bid then
								flags.bidded = true
								dataModel:ModifyAuctionBid(itemType, auctionID, auctionDetail.bid)
							end
			
							dataModel:ModifyAuctionFlags(itemType, auctionID, flags)
							
							-- 3.2.6.2. Update results
							if not active then
								UpdateResults("auctions", "resurrected", auctionID)
							end
							
							if auctionDetail.bid > bid then
								UpdateResults("itemTypes", "updated", itemType)
								UpdateResults("auctions", "updated", auctionID)
							end
							
			
							-- 3.2.6.3. Update indices
							if not active then
								local itemName, _, category, level, callings, rarity = dataModel:RetrieveItemData(itemType)
								nativeIndexer.AddAuction(itemType, auctionID, callings, rarity, level, category, itemName, auctionDetail.buyout or 0)
							end
							
							if flags.own then
								ownIndex[auctionID] = itemType
							end
						end
					end
					
					-- 3.2.7. Update progress
					processedAuctions = processedAuctions + 1
					UpdateProgress(2, processedAuctions)
				end
				
				-- 3.3. Update lastSeenon seen items
				for itemType in pairs(scanResults.itemTypes.list.all) do
					taskHandle:Breath()
					local lastSeen = dataModel:RetrieveItemLastSeen(itemType)
					if auctionScanTime > lastSeen then
						dataModel:ModifyItemLastSeen(itemType, auctionScanTime)
					end
				end
			end
			
			-- 4. Expire old auctions
			do
				local expiredCount = 0
				local expiredAuctions = {}
			
				-- 4.1. Regular search
				if criteria.type == "search" and (not criteria.index or (criteria.index == 0 and totalAuctions < 50)) then
					local matchingAuctions = nativeIndexer.Search(criteria.role, criteria.rarity and RARITIES_N2C[criteria.rarity], criteria.levelMin, criteria.levelMax, criteria.category, criteria.priceMin, criteria.priceMax, criteria.text)
					taskHandle:Breath()					
					for auctionID, itemType in pairs(matchingAuctions) do
						if not auctions[auctionID] then
							expiredCount = expiredCount + 1
							expiredAuctions[auctionID] = itemType
						end
					end
				
				-- 4.2. Mine search
				elseif criteria.type == "mine" then
					for auctionID, itemType in pairs(ownIndex) do
						if not auctions[auctionID] then
							local seller = dataModel:RetrieveAuctionSeller(itemType, auctionID)
							if seller == playerName then
								expiredCount = expiredCount + 1
								expiredAuctions[auctionID] = itemType
							end
						end
					end
				end
				
				-- 4.3. Update progress
				UpdateProgress(3, 0, expiredCount)
				
				-- 4.4. Expire them
				expiredCount = 0
				
				for auctionID, itemType in pairs(expiredAuctions) do
					taskHandle:Breath()
					
					-- 4.4.1. Update DB
					local minExpire = dataModel:RetrieveAuctionMinExpire(itemType, auctionID)
					local maxExpire = dataModel:RetrieveAuctionMaxExpire(itemType, auctionID)
					
					if auctionScanTime < minExpire then
						dataModel:ModifyAuctionFirstUnseen(itemType, auctionID, auctionScanTime)
						
						local flags = dataModel:RetrieveAuctionFlags(itemType, auctionID)
						flags.beforeExpiration = true
						dataModel:ModifyAuctionFlags(itemType, auctionID, flags)
					else
						dataModel:ModifyAuctionFirstUnseen(itemType, auctionID, math.min(auctionScanTime, maxExpire))
					end
					
					dataModel:ExpireAuction(itemType, auctionID)

					-- 4.4.2. Update results
					UpdateResults("itemTypes", "removed", itemType)
					UpdateResults("auctions", "removed", auctionID)
					
					if auctionScanTime < minExpire then
						UpdateResults("auctions", "beforeExpire", auctionID)
					end
					
					-- 4.4.3. Update indices
					local itemName, _, category, level, callings, rarity = dataModel:RetrieveItemData(itemType)
					local price = dataModel:RetrieveAuctionBuy(itemType, auctionID)
					nativeIndexer.RemoveAuction(auctionID, callings, rarity, level, category, itemName, price)

					ownIndex[auctionID] = nil
					
					-- 4.4.4. Update progress
					expiredCount = expiredCount + 1
					UpdateProgress(3, expiredCount)
				end
				
			end
			
			-- 5. Adjust expire times
			do
				if criteria.sort and criteria.sort == "time" and criteria.sortOrder then
					-- 5.1. Update progress
					UpdateProgress(4, 0, totalAuctions)
					
					-- 5.2. Select sort function
					local sortFunction = function(a, b) return auctions[b] < auctions[a] end
					if criteria.sortOrder == "descending" then
						sortFunction = function(a, b) return auctions[a] < auctions[b] end
					end
				
					-- 5.3. Sort the auctions from the first to the last to expire
					local knownAuctions = {}
					for auctionID in pairs(auctions) do
						taskHandle:Breath()
					
						if cachedAuctions[auctionID] then
							BinaryInsert(knownAuctions, auctionID, sortFunction)
						end
					end
					
					-- 5.4. Adjust expire times
					for index = 1, #knownAuctions do
						taskHandle:Breath()
						
						local prevID, thisID, nextID = knownAuctions[index - 1], knownAuctions[index], knownAuctions[index + 1]
						local thisMinExpire = dataModel:RetrieveAuctionMinExpire(cachedAuctions[thisID], thisID)
						local thisMaxExpire = dataModel:RetrieveAuctionMaxExpire(cachedAuctions[thisID], thisID)
						
						-- 5.4.1. Compare minExpire against previous
						if prevID then
							local prevMinExpire = dataModel:RetrieveAuctionMinExpire(cachedAuctions[prevID], prevID)
							if thisMinExpire < prevMinExpire then
								dataModel:ModifyAuctionMinExpire(cachedAuctions[thisID], thisID, prevMinExpire)
							end
						end
						
						-- 5.4.2. Compare maxExpire against next
						if nextID then
							local nextMaxExpire = dataModel:RetrieveAuctionMaxExpire(cachedAuctions[nextID], nextID)
							if thisMaxExpire > nextMaxExpire then
								dataModel:ModifyAuctionMaxExpire(cachedAuctions[thisID], thisID, nextMaxExpire)
							end
						end
						
						-- 5.4.3. Update progress
						UpdateProgress(4, index)
					end
				end
			end
			
			-- 6. Free write lock
			FreeLock(taskHandle)
			
			-- 7. Let the reporter announce the scan completion and terminate			
			UpdateProgress(5, 0, 0)
			taskHandle:Wait(blTasks.Wait.Children())
		end):Start():Abandon()
end
Command.Event.Attach(Event.Auction.Scan, OnAuctionData, addonID .. ".Scanner.OnAuctionData")

local function LoadAuctionTable(h, addon)
	if addon == addonID then
		local rawData = _G[addonID .. "AuctionTable"]

		blTasks.Task.Create(
			function(taskHandle)
				-- Load the data model
				dataModel = Internal.Version.LoadDataModel(rawData)
				taskHandle:Breath()
				
				-- Prepare the indices
				local allItemtypes = dataModel:RetrieveAllItems()
				taskHandle:Breath()
				
				for itemType in pairs(allItemtypes) do
					
					local activeAuctions = dataModel:RetrieveActiveAuctions(itemType)
					
					if activeAuctions and next(activeAuctions) then
						local name, _, category, level, callings, rarity = dataModel:RetrieveItemData(itemType)
						for auctionID in pairs(activeAuctions) do
							local buy = dataModel:RetrieveAuctionBuy(itemType, auctionID)
							local flags = dataModel:RetrieveAuctionFlags(itemType, auctionID)
							
							-- Native index
							nativeIndexer.AddAuction(itemType, auctionID, callings, rarity, level, category, name, buy)
							
							-- Own index
							if flags.own then
								ownIndex[auctionID] = itemType
							end
							
							taskHandle:BreathShort()
						end
					end
				end

				-- Deactivate the loading flag
				if dataModel then
					loading = nil
					ReadyEvent()
				end
			end):Start():Abandon()
	end
end
Command.Event.Attach(Event.Addon.SavedVariables.Load.End, LoadAuctionTable, addonID .. ".Scanner.LoadAuctionData")

local function SaveAuctionTable(h, addon)
	if addon == addonID and not loading then
		local rawData = dataModel:GetRawData()
		_G[addonID .. "AuctionTable"] = rawData
	end
end
Command.Event.Attach(Event.Addon.SavedVariables.Save.Begin, SaveAuctionTable, addonID .. ".Scanner.SaveAuctionData")

local function ProcessAuctionBuy(taskHandle, auctionID)
	-- Timestamps
	local auctionBuyTime = Inspect.Time.Server()
	local start = Inspect.Time.Real()
	
	-- Acquire read lock
	while not AcquireLock(taskHandle, LOCK_MODE.READ) do taskHandle:Wait(blTasks.Wait.Timespan(1)) end
	
	-- Get item/auction data
	local itemType = cachedAuctions[auctionID]
	local name, _, category, level, callings, rarity = dataModel:RetrieveItemData(itemType)
	local price = dataModel:RetrieveAuctionBuy(itemType, auctionID)
	
	-- Free lock
	FreeLock(taskHandle)
	
	if not name or not price then return end
	
	local criteria = { type = "playerbuy", auction = auctionID }
	BeginEvent(criteria)

	-- Acquire write lock
	while not AcquireLock(taskHandle, LOCK_MODE.WRITE) do taskHandle:Wait(blTasks.Wait.Timespan(1)) end

	-- Update auction DB
	dataModel:ModifyAuctionFirstUnseen(itemType, auctionID, auctionBuyTime)
	local flags = dataModel:RetrieveAuctionFlags(itemType, auctionID)
	flags.ownBought = true
	flags.beforeExpiration = true
	dataModel:ModifyAuctionFlags(itemType, auctionID, flags)
	dataModel:ExpireAuction(itemType, auctionID)

	-- Update indices
	nativeIndexer.RemoveAuction(auctionID, callings, rarity, level, category, name, price)
	ownIndex[auctionID] = nil

	-- Free lock
	FreeLock(taskHandle)
	
	-- Report results
	local scanResults =
	{
		auctions =
		{
			count = { all = 1,  new = 0,  resurrected = 0,  reposted = 0,  updated = 0,  removed = 1,  beforeExpire = 1, },
			list =  { all = { [auctionID] = true, }, new = {}, resurrected = {}, reposted = {}, updated = {}, removed = { [auctionID] = true, }, beforeExpire = { [auctionID] = true, }, }
		},
		itemTypes =
		{
			count = { all = 1,  new = 0,  updated = 0,  removed = 1,  modified = 0, },
			list =  { all = { [itemType] = true, }, new = {}, updated = {}, removed = { [itemType] = true, }, modified = {}, }
		},
	}
	EndEvent(criteria, Inspect.Time.Real() - start, scanResults)
end

local function ProcessAuctionBid(taskHandle, auctionID, amount)
	-- Timestamps
	local start = Inspect.Time.Real()

	-- Acquire read lock
	while not AcquireLock(taskHandle, LOCK_MODE.READ) do taskHandle:Wait(blTasks.Wait.Timespan(1)) end
	
	-- Get item/auction data
	local itemType = cachedAuctions[auctionID]
	local price = dataModel:RetrieveAuctionBuy(itemType, auctionID)
	
	-- Free lock
	FreeLock(taskHandle)
	
	if not price then return end

	-- Check if the bid is, instead, a buy
	if price > 0 and amount >= price then
		ProcessAuctionBuy(taskHandle, auctionID)
	else
		local criteria = { type = "playerbid", auction = auctionID, bid = amount }
		BeginEvent(criteria)
	
		-- Acquire write lock
		while not AcquireLock(taskHandle, LOCK_MODE.WRITE) do taskHandle:Wait(blTasks.Wait.Timespan(1)) end
		
		-- Update auction DB
		dataModel:ModifyAuctionBid(itemType, auctionID, amount)
		dataModel:ModifyAuctionOwnBid(itemType, auctionID, amount)
		local flags = dataModel:RetrieveAuctionFlags(itemType, auctionID)
		flags.bidded = true
		dataModel:ModifyAuctionFlags(itemType, auctionID, flags)
		
		-- Free lock
		FreeLock(taskHandle)
		
		-- Report results
		local scanResults =
		{
			auctions =
			{
				count = { all = 1,  new = 0,  resurrected = 0,  reposted = 0,  updated = 1,  removed = 0,  beforeExpire = 0, },
				list =  { all = { [auctionID] = true, }, new = {}, resurrected = {}, reposted = {}, updated = { [auctionID] = true, }, removed = {}, beforeExpire = {}, }
			},
			itemTypes =
			{
				count = { all = 1,  new = 0,  updated = 1,  removed = 0,  modified = 0, },
				list =  { all = { [itemType] = true, }, new = {}, updated = { [itemType] = true, }, removed = {}, modified = {}, }
			},
		}
		EndEvent(criteria, Inspect.Time.Real() - start, scanResults)
	end
end

local function ProcessAuctionCancel(taskHandle, auctionID)
	-- Timestamps
	local auctionBuyTime = Inspect.Time.Server()
	local start = Inspect.Time.Real()
	
	-- Acquire read lock
	while not AcquireLock(taskHandle, LOCK_MODE.READ) do taskHandle:Wait(blTasks.Wait.Timespan(1)) end
	
	-- Get item/auction data
	local itemType = cachedAuctions[auctionID]
	local name, _, category, level, callings, rarity = dataModel:RetrieveItemData(itemType)
	local price = dataModel:RetrieveAuctionBuy(itemType, auctionID)
	
	-- Free lock
	FreeLock(taskHandle)
	
	if not name or not price then return end

	local criteria = { type = "playercancel", auction = auctionID }
	BeginEvent(criteria)
	
	-- Acquire write lock
	while not AcquireLock(taskHandle, LOCK_MODE.WRITE) do taskHandle:Wait(blTasks.Wait.Timespan(1)) end

	-- Update auction DB
	dataModel:ModifyAuctionFirstUnseen(itemType, auctionID, auctionCancelTime)
	local flags = dataModel:RetrieveAuctionFlags(itemType, auctionID)
	flags.cancelled = true
	flags.beforeExpiration = true
	dataModel:ModifyAuctionFlags(itemType, auctionID, flags)
	dataModel:ExpireAuction(itemType, auctionID)

	-- Update indices
	nativeIndexer.RemoveAuction(auctionID, callings, rarity, level, category, name, price)
	ownIndex[auctionID] = nil	

	-- Free lock
	FreeLock(taskHandle)
	
	-- Report results
	local scanResults =
	{
		auctions =
		{
			count = { all = 1,  new = 0,  resurrected = 0,  reposted = 0,  updated = 0,  removed = 1,  beforeExpire = 1, },
			list =  { all = { [auctionID] = true, }, new = {}, resurrected = {}, reposted = {}, updated = {}, removed = { [auctionID] = true, }, beforeExpire = { [auctionID] = true, }, }
		},
		itemTypes =
		{
			count = { all = 1,  new = 0,  updated = 0,  removed = 1,  modified = 0, },
			list =  { all = { [itemType] = true, }, new = {}, updated = {}, removed = { [itemType] = true, }, modified = {}, }
		},
	}
	EndEvent(criteria, Inspect.Time.Real() - start, scanResults)
end

local function GetAuctionData(itemType, auctionID)
	-- Check itemType
	itemType = itemType or (auctionID and cachedAuctions[auctionID])
	if not itemType or not dataModel:CheckItemExists(itemType) then return nil end
	
	-- Get item/auction data
	local itemName, itemIcon, category, _, _, rarity = dataModel:RetrieveItemData(itemType)
	local seller, item, bid, buy, ownBidded, firstSeen, firstUnseen, minExpire, maxExpire, stacks, flags, active = dataModel:RetrieveAuctionData(itemType, auctionID)
	if not seller then return nil end
	
	return
	{
		active = active,
		item = item,
		itemType = itemType,
		itemName = itemName,
		itemIcon = itemIcon,
		itemRarity = RARITIES_C2N[rarity],
		itemCategory = category,
		stack = stacks,
		bidPrice = bid,
		buyoutPrice = buy,
		ownBidded = ownBidded,
		bidUnitPrice = bid / stacks,
		buyoutUnitPrice = buy / stacks,
		sellerName = seller,
		firstSeenTime = firstSeen,
		firstUnseenTime = firstUnseen,
		minExpireTime = minExpire,
		maxExpireTime = maxExpire,
		own = flags.own,
		bidded = flags.bidded,
		removedBeforeExpiration = flags.beforeExpiration,
		ownBought = flags.ownBought,
		cancelled = flags.cancelled,
		reposted = flags.reposted,
		cached = cachedAuctions[auctionID] and true or false,
	}
end

local function SearchAuctionsAsync(taskHandle, calling, rarity, levelMin, levelMax, category, priceMin, priceMax, name)
	-- Acquire read lock
	while not AcquireLock(taskHandle, LOCK_MODE.READ) do taskHandle:Wait(blTasks.Wait.Timespan(1)) end
	
	-- Get auction list
	local auctions = nativeIndexer.Search(calling, rarity and RARITIES_N2C[rarity] or nil, levelMin, levelMax, category, priceMin, priceMax, name)
	
	-- Collect auctionData
	for auctionID, itemType in pairs(auctions) do
		auctions[auctionID] = GetAuctionData(itemType, auctionID)
		taskHandle:Breath()
	end
	
	-- Free lock
	FreeLock(taskHandle)
	
	return auctions
end

local function AddAuctionsInInterval(itemType, source, destination, startTime, endTime)
	for auctionID in pairs(source) do
		local auctionData = GetAuctionData(itemType, auctionID)
		if auctionData and (auctionData.firstUnseenTime == 0 or auctionData.firstUnseenTime >= startTime) and auctionData.firstSeenTime <= endTime then
			destination[auctionID] = auctionData
		end
	end
end

local function GetAuctionDataAsync(taskHandle, item, startTime, endTime, excludeExpired)
	startTime = startTime or 0
	endTime = endTime or Inspect.Time.Server()

	-- Acquire read lock
	while not AcquireLock(taskHandle, LOCK_MODE.READ) do taskHandle:Wait(blTasks.Wait.Timespan(1)) end
	
	local auctions = {}
	
	if type(item) ~= "string" then
		for itemType in pairs(dataModel:RetrieveAllItems()) do
			if excludeExpired then
				AddAuctionsInInterval(itemType, dataModel:RetrieveActiveAuctions(itemType), auctions, startTime, endTime)
			else
				AddAuctionsInInterval(itemType, dataModel:RetrieveAllAuctions(itemType), auctions, startTime, endTime)
			end
			taskHandle:Breath()
		end
	else
		local itemType = nil
		if item:sub(1, 1) == "I" then
			itemType = item
		else
			local ok, itemDetail = pcall(Inspect.Item.Detail, item)
			itemType = ok and itemDetail and itemDetail.type or nil
		end
		
		if itemType and dataModel:CheckItemExists(itemType) then
			if excludeExpired then
				AddAuctionsInInterval(itemType, dataModel:RetrieveActiveAuctions(itemType), auctions, startTime, endTime)
			else
				AddAuctionsInInterval(itemType, dataModel:RetrieveAllAuctions(itemType), auctions, startTime, endTime)
			end
		end
	end
	
	-- Free lock
	FreeLock(taskHandle)
	
	return auctions
end

local function GetOwnAuctionDataAsync(taskHandle)
	-- Acquire read lock
	while not AcquireLock(taskHandle, LOCK_MODE.READ) do taskHandle:Wait(blTasks.Wait.Timespan(1)) end

	local auctions = {}
	for auctionID, itemType in pairs(ownIndex) do
		auctions[auctionID] = GetAuctionData(itemType, auctionID)
		taskHandle:Breath()
	end
	
	-- Free lock
	FreeLock(taskHandle)
	
	return auctions
end


function Public.Callback.Buy(auctionID)
	return function(failed)
		if failed then return end
		blTasks.Task.Create(function(taskHandle) ProcessAuctionBuy(taskHandle, auctionID) end, addonID):Start():Abandon()
	end
end

function Public.Callback.Bid(auctionID, amount)
	return function(failed)
		if failed then return end
		blTasks.Task.Create(function(taskHandle) ProcessAuctionBid(taskHandle, auctionID, amount) end, addonID):Start():Abandon()
	end
end

function Public.Callback.Post(itemType, duration, bid, buyout)
	local timestamp = Inspect.Time.Server()
	return function(failed)
		if failed then return end
		blTasks.Task.Create(function(taskHandle) TryMatchPost(taskHandle, itemType, duration, timestamp, bid, buyout or 0) end, addonID):Start():Abandon()
	end
end

function Public.Callback.Cancel(auctionID)
	return function(failed)
		if failed then return end
		blTasks.Task.Create(function(taskHandle) ProcessAuctionCancel(taskHandle, auctionID) end, addonID):Start():Abandon()
	end
end


function Public.Search.All(item, startTime, endTime)
	return blTasks.Task.Create(function(taskHandle) return GetAuctionDataAsync(taskHandle, item, startTime, endTime, false) end, addonID):Start()
end

function Public.Search.Active(item)
	return blTasks.Task.Create(function(taskHandle) return GetAuctionDataAsync(taskHandle, item, nil, nil, true) end, addonID):Start()
end

function Public.Search.Native(calling, rarity, levelMin, levelMax, category, priceMin, priceMax, name)
	return blTasks.Task.Create(function(taskHandle) return SearchAuctionsAsync(taskHandle, calling, rarity, levelMin, levelMax, category, priceMin, priceMax, name) end, addonID):Start()
end

function Public.Search.Own()
	return blTasks.Task.Create(GetOwnAuctionDataAsync, addonID):Start()
end

function Public.Item.LastTimeSeen(item)
	if not item or loading then return nil end

	local itemType = nil
	if item:sub(1, 1) == "I" then
		itemType = item
	else
		local ok, itemDetail = pcall(Inspect.Item.Detail, item)
		itemType = ok and itemDetail and itemDetail.type or nil
	end

	return dataModel:RetrieveItemLastSeen(itemType)
end

function Public.Auction.Cached(auctionID)
	return auctionID and cachedAuctions[auctionID] and true or false
end

function Public.Ready()
	return not loading
end

--[[ TODO Documentation
	.Callback.Buy
	.Callback.Bid
	.Callback.Post
	.Callback.Cancel
	
	.Search.All
	.Search.Active
	.Search.Native
	.Search.Own
	.Ready
	
	.Auction.Cached
	.Item.LastTimeSeen
	
	Event..Scan.Begin
	Event..Scan.Progress
	Event..Scan.end
	Event..Ready
]]