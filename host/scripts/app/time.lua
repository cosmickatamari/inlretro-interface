
-- create the module's table
local time = {}

-- import required modules
local inl_ui = require "scripts.app.inl_ui"

-- file constants & variables
local tstart


-- local functions
local function start()
	tstart = os.clock()
end

local function format_total_time_sec(sec)
	if sec == nil or sec <= 0 then
		return nil
	end
	if sec <= 60 then
		return string.format("%.2f seconds", sec)
	end
	local mins = math.floor(sec / 60)
	local rem = sec - mins * 60
	return string.format("%.2f seconds (%d min, %.2f seconds)", sec, mins, rem)
end

--send the number of KBytes flashed so it can report KBps
local function report(sizeKB)
	local elapsed = os.clock() - tstart
	local uc = inl_ui.use_ansi()
	local kbps = string.format("%.2f", (sizeKB / elapsed))
	local time_str = format_total_time_sec(elapsed) or ""
	if uc then
		inl_ui.print_kv("Total time", time_str, true)
		inl_ui.print_kv("Average speed", kbps .. " KBps", true)
	else
		print("total time:", time_str, ", average speed:", kbps, "KBps")
	end
end

local function sleep(n)  -- seconds
	local t0 = os.clock()
	while os.clock() - t0 <= n do end
end

-- global variables so other modules can use them


-- call functions desired to run when script is called/imported


-- functions other modules are able to call
time.start = start
time.report = report
time.sleep = sleep

-- return the module's table
return time
