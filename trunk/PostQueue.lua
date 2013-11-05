-- ***************************************************************************************************************************************************
-- * PostQueue.lua                                                                                                                                   *
-- ***************************************************************************************************************************************************
-- * 0.5.0 / 2013.10.06 / Baanano: Adapted to blTasks, rewritten unjam code                                                                          *
-- * 0.4.12/ 2013.09.17 / Baanano: Updated events to the new model                                                                                   *
-- * 0.4.4 / 2012.11.01 / Baanano: Added auto unjam (best effort)                                                                                    *
-- * 0.4.1 / 2012.07.14 / Baanano: Updated for LibPGC                                                                                                *
-- * 0.4.0 / 2012.06.17 / Baanano: Rewritten AHPostingService.lua                                                                                    *
-- ***************************************************************************************************************************************************

local addonDetail, addonData = ...
local addonID = addonDetail.identifier
local Internal, Public = addonData.Internal, addonData.Public

 -- TODO Move to constants
local JAM_WAIT_SECONDS = 30
local QUEUE_STATUS =
{
	EMPTY = 1,
	PAUSED = 2,
	JAMMED = 3,
	NO_INTERACTION = 4,
	WAITING = 5,
	BUSY = 6,
}

local postingQueue = {}
local paused = false
local jammed = false
local waitingUpdate = false
local waitingPost = false
local ChangedEvent = Utility.Event.Create(addonID, "Queue.Changed")

local function QueueTask(taskHandle)
	while true do
		repeat
			ChangedEvent()
			
			-- Wait till all conditions are met
			while paused or jammed or waitingUpdate or waitingPost or #postingQueue <= 0 or not Inspect.Interaction("auction") or not Inspect.Queue.Status("global") do
				taskHandle:Wait(blTasks.Wait.Frame() * blTasks.Wait.Interaction("auction") * blTasks.Wait.Queue("global"))
			end
			
			ChangedEvent()

			-- Find what itemTypes to post
			local ordersByItemType = {}
			do
				local queueRemoved = false
				
				for index = #postingQueue, 1, -1 do
					local order = postingQueue[index]
					if order.amount <= 0 then
						table.remove(postingQueue, index)
						queueRemoved = true
					else
						ordersByItemType[order.itemType] = ordersByItemType[order.itemType] or {}
						ordersByItemType[order.itemType][index] = { amount = order.amount, direct = {}, split = {}, merge = {}, }
					end
				end
			end
		
			-- Match slots with orders
			local freeSlots = false
			for slotID, itemID in pairs(Inspect.Item.List(Utility.Item.Slot.Inventory())) do
				if type(itemID) == "boolean" then
					freeSlots = true
				else
					local itemDetail = Inspect.Item.Detail(itemID)
					if itemDetail and not itemDetail.bound and ordersByItemType[itemDetail.type] then
						local stacks = itemDetail.stack or 1
						
						for orderID, orderData in pairs(ordersByItemType[itemDetail.type]) do
							if stacks == orderData.amount then
								orderData.direct[#orderData.direct + 1] = itemDetail.id
							elseif stacks > orderData.amount then
								orderData.split[#orderData.split + 1] = slotID
							elseif stacks < orderData.amount then
								orderData.merge[#orderData.merge + 1] = slotID
							end
						end
					end
				end
			end
			
			-- Flatten orders
			local orders = {}
			for itemType, itemTypeOrders in pairs(ordersByItemType) do
				for orderID, orderData in pairs(itemTypeOrders) do
					orders[orderID] = orderData
				end
			end
			
			-- Search best matches
			local bogusID, directID, mergeID, splitID = nil, nil, nil, nil
			for orderID = #postingQueue, 1, -1 do
				local order = orders[orderID]
				
				if order then
					if #order.direct >= 1 then
						directID = orderID
					elseif #order.merge >= 2 then
						mergeID = orderID
					elseif #order.split >= 1 then
						splitID = orderID
					else
						bogusID = orderID
					end
				else
					bogusID = orderID
				end
			end
			
			-- Remove BogusID
			if bogusID then
				table.remove(postingQueue, bogusID)
				ChangedEvent()
				break
			end
			
			-- Post DirectID
			if directID then
				local order = orders[directID]
				local amount, item = order.amount, order.direct[1]

				local duration = postingQueue[directID].duration
				local bid = postingQueue[directID].unitBidPrice * amount
				local buy = postingQueue[directID].unitBuyoutPrice and postingQueue[directID].unitBuyoutPrice * amount or nil
					
				local cost = Utility.Auction.Cost(item, duration, bid, buy)
				local coinDetail = Inspect.Currency.Detail("coin")
				local money = coinDetail and coinDetail.stack or 0
					
				if money < cost then
					table.remove(postingQueue, directID)
					ChangedEvent()
					break
				end
					
				waitingUpdate = true
				waitingPost = true
					
				local postCallback = Public.Callback.Post(postingQueue[directID].itemType, duration, bid, buy)
				Command.Auction.Post(item, duration, bid, buy, function(...) waitingPost = false; postCallback(...); end)
					
				postingQueue[directID].amount = postingQueue[directID].amount - amount
				if postingQueue[directID].amount <= 0 then
					table.remove(postingQueue, directID)
				end
				
				ChangedEvent()
				break
			end

			-- Merge MergeID
			if mergeID then
				local order = orders[mergeID]
				local firstSlot, secondSlot = order.merge[1], order.merge[2]
				
				Command.Item.Move(firstSlot, secondSlot)
				waitingUpdate = true
				
				ChangedEvent()
				break
			end

			-- Split SplitID
			if splitID then
				if freeSlots then
					local order = orders[splitID]
					local slot, amount = order.split[1], order.amount
					Command.Item.Split(slot, amount)
					waitingUpdate = true
				else
					jammed = true
				end
				
				ChangedEvent()
				break
			end
			
		until true
		
		taskHandle:BreathLong()
	end
end
blTasks.Task.Create(QueueTask):Start():Abandon()

local function OnWaitingUnlock()
	waitingUpdate = false
	jammed = false
end
Command.Event.Attach(Event.Item.Slot, OnWaitingUnlock, addonID .. ".Post.OnItemSlot")
Command.Event.Attach(Event.Item.Update, OnWaitingUnlock, addonID .. ".Post.OnItemUpdate")


function Public.Queue.Post(item, stackSize, amount, unitBidPrice, unitBuyoutPrice, duration)
	if not item or not amount or not stackSize or not unitBidPrice or not duration then return false end
	
	amount, stackSize, unitBidPrice, duration = math.floor(amount), math.floor(stackSize), math.floor(unitBidPrice), math.floor(duration)
	if unitBuyoutPrice then unitBuyoutPrice = math.max(math.floor(unitBuyoutPrice), unitBidPrice) end
	if amount <= 0 or stackSize <= 0 or unitBidPrice <= 0 or (duration ~= 12 and duration ~= 24 and duration ~= 48) then return false end

	local itemType = nil
	if item:sub(1, 1) == "I" then
		itemType = item
	else
		local ok, itemDetail = pcall(Inspect.Item.Detail, item)
		itemType = ok and itemDetail and itemDetail.type or nil
	end
	if not itemType then return false end
	
	while amount > 0 do
		local stacks = amount < stackSize and amount or stackSize
		
		postingQueue[#postingQueue + 1] =
		{ 
			itemType = itemType,
			amount = stacks,
			unitBidPrice = unitBidPrice,
			unitBuyoutPrice = unitBuyoutPrice,
			duration = duration,
		}
		
		amount = amount - stacks
	end
	
	ChangedEvent()
	
	return true
end

function Public.Queue.CancelByIndex(index)
	if index < 0 or index > #postingQueue then return end
	table.remove(postingQueue, index)
	ChangedEvent()
end

function Public.Queue.CancelAll()
	postingQueue = {}
	ChangedEvent()
end

function Public.Queue.Detail()
	return blUtil.Copy.Deep(postingQueue)
end

function Public.Queue.Status()
	local status = QUEUE_STATUS.BUSY
	if paused then
		status = QUEUE_STATUS.PAUSED
	elseif #postingQueue <= 0 then
		status = QUEUE_STATUS.EMPTY
	elseif jammed then
		status = QUEUE_STATUS.JAMMED
	elseif not Inspect.Interaction("auction") then
		status = QUEUE_STATUS.NO_INTERACTION
	elseif waitingUpdate or waitingPost or not Inspect.Queue.Status("global") then
		status = QUEUE_STATUS.WAITING
	end
	
	return status, #postingQueue
end

function Public.Queue.Pause(pause)
	if pause == paused then return end
	paused = pause
	ChangedEvent()
end

--[[ TODO Documentation
	.Queue.Post
	.Queue.CancelByIndex
	.Queue.CancelAll
	.Queue.Detail
	.Queue.Status
	.Queue.Pause
	.Queue.QUEUE_STATUS

	Event..Queue.Changed
]]