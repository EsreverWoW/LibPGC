-- ***************************************************************************************************************************************************
-- * Scheduler.lua                                                                                                                                   *
-- ***************************************************************************************************************************************************
-- * Coordinates execution of long tasks, so they don't trigger the Evil Watchdog                                                                    *
-- ***************************************************************************************************************************************************
-- * 0.4.1 / 2012.07.10 / Baanano: Adapted to the new incarnation of the Watchdog                                                                    *
-- * 0.4.0 / 2012.05.30 / Baanano: First version                                                                                                     *
-- ***************************************************************************************************************************************************

local addonInfo, InternalInterface = ...
local addonID = addonInfo.identifier

local WATCHDOG_LIMIT = 0.03

local CCreate = coroutine.create
local CResume = coroutine.resume
local CStatus = coroutine.status
local ISWatchdog = Inspect.System.Watchdog
local TInsert = table.insert 
local TRemove = table.remove

local queue = {}

local function RunTask(taskCoroutine)
	local run, result = false, nil
	while CStatus(taskCoroutine) ~= "dead" and ISWatchdog() > WATCHDOG_LIMIT do
		local ok
		ok, result = CResume(taskCoroutine)
		if not ok then error(result) end
		run = true
	end
	return run, result
end

local function RunScheduler()
	while #queue > 0 do
		local nextTask = queue[1]

		local ok, run, result = pcall(RunTask, nextTask.coroutine)
		
		if not ok then
			TRemove(queue, 1)
			error(run)
		end
		
		if not run then break end

		if CStatus(nextTask.coroutine) == "dead" then
			TRemove(queue, 1)
			if type(nextTask.callback) == "function" then
				nextTask.callback(result)
			end
		end
	end
end
TInsert(Event.System.Update.Begin, { RunScheduler, addonID, addonID .. ".Scheduler" })

InternalInterface.Scheduler = InternalInterface.Scheduler or {}

-- ***************************************************************************************************************************************************
-- * QueueTask                                                                                                                                       *
-- ***************************************************************************************************************************************************
-- * Enqueues a task for async execution                                                                                                             *
-- ***************************************************************************************************************************************************
function InternalInterface.Scheduler.QueueTask(task, callback)
	if type(task) ~= "function" then return false end
	
	local queuedTask = { coroutine = CCreate(task), callback = callback }
	
	TInsert(queue, queuedTask)
	
	return true
end
