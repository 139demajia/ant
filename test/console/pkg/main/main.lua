local M = {}

function M.start(arg)
	dofile "/engine/ltask.lua" {
		bootstrap = {
			["logger"] = {},
			["main|startup"] = {
				args = arg,
				unique = false,
			}
		}
	}
end

return M