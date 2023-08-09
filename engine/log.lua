local ltask = require "ltask"
local LOG
if not debug.getregistry().LTASK_ID then
    --TODO
    function LOG(...)
        io.write(...)
        io.write "\n"
    end
else
    function LOG(...)
        ltask.pushlog(ltask.pack(...))
    end
end

local modes = {
    'debug',
    'info',
    'warn',
    'error'
}
local color = {
    debug = nil,
    info = nil,
    warn = "\x1b[33m",
    error = "\x1b[31m",
}
local levels = {}

local function round(x, increment)
    increment = increment or 1
    x = x / increment
    return (x > 0 and math.floor(x + 0.5) or math.ceil(x - 0.5)) * increment
end

local function packstring(...)
    local t = {}
    for i = 1, select('#', ...) do
        local x = select(i, ...)
        if math.type(x) == 'float' then
            x = round(x, 0.01)
        end
        t[#t + 1] = tostring(x)
    end
    return table.concat(t, '\t')
end

local m = {}
m.level = __ANT_RUNTIME__ and 'debug' or 'info'
m.skip = nil
for i, name in ipairs(modes) do
    levels[name] = i
    m[name] = function(...)
        if i < levels[m.level] then
            return
        end
        local info = debug.getinfo(m.skip or 2, 'Sl')
        m.skip = nil
        local text = ('[%-5s](%s:%d) %s'):format(name:upper(), info.short_src, info.currentline, packstring(...))
        if not __ANT_RUNTIME__ and color[name] then
            text = color[name]..text.."\x1b[0m"
        end
        LOG(text)
    end
end

---@diagnostic disable-next-line: lowercase-global
log = m
print = log.info

return m
