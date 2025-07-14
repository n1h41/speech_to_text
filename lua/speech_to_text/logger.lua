local logger = {}

local logfile = io.open("debug.log", "a")

---Logger function to log messages to a file.
---@param message string
function logger.log(message)
	local timestamp = os.date("%Y-%m-%d %H:%M:%S")
	if logfile then
		logfile:write(string.format("[%s] %s\n", timestamp, tostring(message)))
		logfile:flush();
	end
end

return logger
