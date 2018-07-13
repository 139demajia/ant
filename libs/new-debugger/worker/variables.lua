local rdebug = require 'remotedebug'
local source = require 'new-debugger.worker.source'
local path = require 'new-debugger.path'

local varPool = {}

local VAR_LOCAL = 0xFFFF
local VAR_VARARG = 0xFFFE
local VAR_UPVALUE = 0xFFFD
local VAR_GLOBAL = 0xFFFC
local VAR_STANDARD = 0xFFFB

local standard = {}
for _, v in ipairs{
    "ipairs",
    "error",
    "utf8",
    "rawset",
    "tostring",
    "select",
    "tonumber",
    "_VERSION",
    "loadfile",
    "xpcall",
    "string",
    "rawlen",
    "ravitype",
    "print",
    "rawequal",
    "setmetatable",
    "require",
    "getmetatable",
    "next",
    "package",
    "coroutine",
    "io",
    "_G",
    "math",
    "collectgarbage",
    "os",
    "table",
    "ravi",
    "dofile",
    "pcall",
    "load",
    "module",
    "rawget",
    "debug",
    "assert",
    "type",
    "pairs",
    "bit32",
} do
    standard[v] = true
end

local function hasLocal(frameId)
    local i = 1
    while true do
        local name = rdebug.getlocal(frameId, i)
        if name == nil then
            return false
        end
        if name ~= '(*temporary)' then
            return true
        end
        i = i + 1
    end
end

local function hasVararg(frameId)
    return rdebug.getlocal(frameId, -1) ~= nil
end

local function hasUpvalue(frameId)
    local f = rdebug.getfunc(frameId)
    return rdebug.getupvalue(f, 1) ~= nil
end

local function hasGlobal()
    local gt = rdebug._G
    local key
    while true do
        key = rdebug.next(gt, key)
        local vkey = rdebug.value(key)
        if vkey == nil then
            return false
        end
        if not standard[vkey] then
            return true
        end
    end
end

local function hasStandard()
    return true
end

local function varCanExtand(type, subtype, value)
    if type == 'function' then
        return rdebug.value(rdebug.getupvalue(value, 1)) ~= nil
    elseif type == 'table' then
        if rdebug.value(rdebug.next(value, nil)) ~= nil then
            return true
        end
        if rdebug.value(rdebug.getmetatable(value)) ~= nil then
            return true
        end
        return false
    elseif type == 'userdata' then
        if rdebug.value(rdebug.getmetatable(value)) ~= nil then
            return true
        end
        if subtype == 'full' and rdebug.value(rdebug.getuservalue(value)) ~= nil then
            return true
        end
        return false
    end
    return false
end

local function varGetName(value)
    local type, subtype = rdebug.type(value)
    if type == 'string' then
        local str = rdebug.value(value)
        if #str < 32 then
            return str
        end
        return str:sub(1, 32) .. '...'
    elseif type == 'boolean' then
        if rdebug.value(value) then
            return 'true'
        else
            return 'false'
        end
    elseif type == 'nil' then
        return 'nil'
    elseif type == 'number' then
        if subtype == 'integer' then
            local rvalue = rdebug.value(value)
            if rvalue > 0 and rvalue < 1000 then
                return ('[%03d]'):format(rvalue)
            end
            return ('%d'):format(rvalue)
        else
            return ('%.4f'):format(rdebug.value(value))
        end
    elseif type == 'function' then
        --TODO
    elseif type == 'table' then
        --TODO
    elseif type == 'userdata' then
        --TODO
    end
    return tostring(rdebug.value(value))
end

local function varGetShortValue(value)
    local type, subtype = rdebug.type(value)
    if type == 'string' then
        local str = rdebug.value(value)
        if #str < 16 then
            return ("'%s'"):format(str)
        end
        return ("'%s...'"):format(str:sub(1, 16))
    elseif type == 'boolean' then
        if rdebug.value(value) then
            return 'true'
        else
            return 'false'
        end
    elseif type == 'nil' then
        return 'nil'
    elseif type == 'number' then
        if subtype == 'integer' then
            return ('%d'):format(rdebug.value(value))
        else
            return ('%f'):format(rdebug.value(value))
        end
    elseif type == 'function' then
        return 'func'
    elseif type == 'table' then
        if varCanExtand(type, subtype, value) then
            return "..."
        end
        return '{}'
    elseif type == 'userdata' then
        return 'userdata'
    end
    return type
end

local TABLE_VALUE_MAXLEN = 32
local function varGetTableValue(t)
    local str = ''
    local mark = {}
    local i = 1
    while true do
        local v = rdebug.index(t, i)
        if rdebug.value(v) == nil then
            break
        end
        if str == '' then
            str = varGetShortValue(v)
        else
            str = str .. "," .. varGetShortValue(v)
        end
        mark[i] = true
        if #str >= TABLE_VALUE_MAXLEN then
            return ("{%s...}"):format(str)
        end
    end

    local kvs = {}
    local key, value
    while true do
        key, value = rdebug.next(t, key)
        local vkey = rdebug.value(key)
        if vkey == nil then
            break
        end
        local _, subtype = rdebug.type(key)
        if subtype == 'integer' and mark[vkey] then
            goto continue
        end
        local kn = varGetName(key)
        kvs[#kvs + 1] = { kn, value }
        if #kvs >= 300 then
            break
        end
        ::continue::
    end
    table.sort(kvs, function(a, b) return a[1] < b[1] end)

    for _, kv in ipairs(kvs) do
        if str == '' then
            str = kv[1] .. '=' .. varGetShortValue(kv[2])
        else
            str = str .. ',' .. kv[1] .. '=' .. varGetShortValue(kv[2])
        end
        if #str >= TABLE_VALUE_MAXLEN then
            return ("{%s...}"):format(str)
        end
    end
    return ("{%s}"):format(str)
end

local function getLineStart(str, pos, n)
    for _ = 1, n - 1 do
        local f, _, nl1, nl2 = str:find('([\n\r])([\n\r]?)', pos)
        if not f then
            return
        end
        if nl1 == nl2 then
            pos = f + 1
        elseif nl2 == '' then
            pos = f + 1
        else
            pos = f + 2
        end
    end
    return pos
end

local function getLineEnd(str, pos, n)
    local pos = getLineStart(str, pos, n)
    if not pos then
        return
    end
    local pos = str:find('[\n\r]', pos)
    if not pos then
        return
    end
    return pos - 1
end

local function getFunctionCode(str, startLn, endLn)
    local startPos = getLineStart(str, 1, startLn)
    if not startPos then
        return str
    end
    local endPos = getLineEnd(str, startPos, endLn - startLn + 1)
    if not endPos then
        return str:sub(startPos)
    end
    return str:sub(startPos, endPos)
end

local function varGetValue(type, subtype, value)
    if type == 'string' then
        local str = rdebug.value(value)
        if #str < 256 then
            return ("'%s'"):format(str)
        end
        return ("'%s...'"):format(str:sub(1, 256))
    elseif type == 'boolean' then
        if rdebug.value(value) then
            return 'true'
        else
            return 'false'
        end
    elseif type == 'nil' then
        return 'nil'
    elseif type == 'number' then
        if subtype == 'integer' then
            return ('%d'):format(rdebug.value(value))
        else
            return ('%f'):format(rdebug.value(value))
        end
    elseif type == 'function' then
        if subtype == 'c' then
            return 'C function'
        end
        local info = rdebug.getinfo(value)
        if not info then
            return tostring(rdebug.value(value))
        end
        local src = source.create(info.source)
        if not source.valid(src) then
            return tostring(rdebug.value(value))
        end
        if src.path then
            return ("%s:%d"):format(source.clientPath(src.path), info.linedefined)
        end
        local code = source.getCode(src.ref)
        return getFunctionCode(code, info.linedefined, info.lastlinedefined)
    elseif type == 'table' then
        return varGetTableValue(value)
    elseif type == 'userdata' then
        local meta = rdebug.getmetatable(value)
        if rdebug.value(meta) ~= nil then
            local name = rdebug.index(meta, '__name')
            if rdebug.value(name) ~= nil then
                return 'userdata: ' .. tostring(rdebug.value(name))
            end
        end
        return 'userdata'
    end
    return tostring(rdebug.value(value))
end

local function varCreateReference(frameId, value, evaluateName)
    local type, subtype = rdebug.type(value)
    local text = varGetValue(type, subtype, value)
    if varCanExtand(type, subtype, value) then
        local pool = varPool[frameId]
        pool[#pool + 1] = { value, evaluateName }
        return text, type, (frameId << 16) | #pool
    end
    return text, type
end

local function varCreate(vars, frameId, varRef, name, value, evaluateName)
    local text, type, ref = varCreateReference(frameId, value, evaluateName)
    local var = {
        name = name,
        type = type,
        value = text,
        variablesReference = ref,
        evaluateName = evaluateName,
    }
    local maps = varRef[3]
    if maps[name] then
        vars[maps[name][3]] = var
        maps[name][1] = value
    else
        vars[#vars + 1] = var
        maps[name] = { value, evaluateName, #vars }
    end
end

local function varCreateInsert(vars, frameId, varRef, name, value, evaluateName)
    local text, type, ref = varCreateReference(frameId, value, evaluateName)
    local var = {
        name = name,
        type = type,
        value = text,
        variablesReference = ref,
        evaluateName = evaluateName,
    }
    local maps = varRef[3]
    if maps[name] then
        table.remove(vars, maps[name][3])
    end
    table.insert(vars, 1, var)
    maps[name] = { value, evaluateName }
end

local function getTabelKey(key)
    local type = rdebug.type(key)
    if type == 'string' then
        local str = rdebug.value(key)
        if str:match '^[_%a][_%w]*$' then
            return ('.%s'):format(str)
        end
        return ('[%q]'):format(str)
    elseif type == 'boolean' then
        return ('[%s]'):format(tostring(rdebug.value(key)))
    elseif type == 'number' then
        return ('[%s]'):format(tostring(rdebug.value(key)))
    end
end

local function extandTable(frameId, varRef)
    varRef[3] = {}
    local t = varRef[1]
    local evaluateName = varRef[2]
    local vars = {}
    local key, value
    while true do
        key, value = rdebug.next(t, key)
        if rdebug.value(key) == nil then
            break
        end
        varCreate(vars, frameId, varRef, varGetName(key), value, ('%s%s'):format(evaluateName, getTabelKey(key)))
    end
    table.sort(vars, function(a, b) return a.name < b.name end)

    local meta = rdebug.getmetatable(t)
    if rdebug.value(meta) ~= nil then
        varCreateInsert(vars, frameId, varRef, '[metatable]', meta, ('debug.getmetatable(%s)'):format(evaluateName))
    end
    return vars
end

local function extandFunction(frameId, varRef)
    varRef[3] = {}
    local f = varRef[1]
    local evaluateName = varRef[2]
    local vars = {}
    local i = 1
    while true do
        local name, value = rdebug.getupvalue(f, i)
        if name == nil then
            break
        end
        varCreate(vars, frameId, varRef, name, value, ('debug.getupvalue(%s,%d)'):format(evaluateName, i))
        i = i + 1
    end
    table.sort(vars, function(a, b) return a.name < b.name end)
    return vars
end

local function extandUserdata(frameId, varRef)
    varRef[3] = {}
    local u = varRef[1]
    local evaluateName = varRef[2]
    local vars = {}
    --TODO
    local uv = rdebug.getuservalue(u)
    if rdebug.value(uv) ~= nil then
        varCreateInsert(vars, frameId, varRef, '[uservalue]', uv, ('debug.getuservalue(%s)'):format(evaluateName))
    end
    local meta = rdebug.getmetatable(u)
    if rdebug.value(meta) ~= nil then
        varCreateInsert(vars, frameId, varRef, '[metatable]', meta, ('debug.getmetatable(%s)'):format(evaluateName))
    end
    return vars
end

local function extandValue(frameId, varRef)
    local type = rdebug.type(varRef[1])
    if type == 'table' then
        return extandTable(frameId, varRef)
    elseif type == 'function' then
        return extandFunction(frameId, varRef)
    elseif type == 'userdata' then
        return extandUserdata(frameId, varRef)
    end
    return {}
end

local function setValue(frameId, varRef, name, value)
    local maps = varRef[3]
    if not maps or not maps[name] then
        return nil, 'Failed set variable'
    end
    local rvalue = maps[name][1]
    local newvalue
    if value == 'nil' then
        newvalue = nil
    elseif value == 'false' then
        newvalue = false
    elseif value == 'true' then
        newvalue = true
    elseif value:sub(1,1) == "'" and value:sub(-1,-1) == "'" then
        newvalue = value:sub(2,-2)
    elseif value:sub(1,1) == '"' and value:sub(-1,-1) == '"' then
        newvalue = value:sub(2,-2)
    elseif tonumber(value) then
        newvalue = tonumber(value)
    else
        newvalue = value
    end
    if not rdebug.assign(rvalue, newvalue) then
        return nil, 'Failed set variable'
    end
    local text, type, ref = varCreateReference(frameId, rvalue, maps[name][2])
    return {
        value = text,
        type = type,
    }
end

local extand = {}
local set = {}
local children = {
    [VAR_LOCAL] = {},
    [VAR_VARARG] = {},
    [VAR_UPVALUE] = {},
    [VAR_GLOBAL] = {},
    [VAR_STANDARD] = {},
}

extand[VAR_LOCAL] = function(frameId)
    children[VAR_LOCAL][3] = {}
    local vars = {}
    local i = 1
    while true do
        local name, value = rdebug.getlocal(frameId, i)
        if name == nil then
            break
        end
        if name ~= '(*temporary)' then
            varCreate(vars, frameId, children[VAR_LOCAL], name, value, ('debug.getlocal(%d,%d,%q)'):format(frameId, i, name))
        end
        i = i + 1
    end
    table.sort(vars, function(a, b) return a.name < b.name end)
    return vars
end

extand[VAR_VARARG] = function(frameId)
    children[VAR_VARARG][3] = {}
    local vars = {}
    local i = -1
    while true do
        local name, value = rdebug.getlocal(frameId, i)
        if name == nil then
            break
        end
        varCreate(vars, frameId, children[VAR_VARARG], ('[%d]'):format(-i), value, ('debug.getlocal(%d,%d)'):format(frameId, -i))
        i = i - 1
    end
    table.sort(vars, function(a, b) return a.name < b.name end)
    return vars
end

extand[VAR_UPVALUE] = function(frameId)
    children[VAR_UPVALUE][3] = {}
    local vars = {}
    local i = 1
    local f = rdebug.getfunc(frameId)
    while true do
        local name, value = rdebug.getupvalue(f, i)
        if name == nil then
            break
        end
        varCreate(vars, frameId, children[VAR_UPVALUE], name, value, ('debug.getupvalue(%d,%d,%q)'):format(frameId, i, name))
        i = i + 1
    end
    table.sort(vars, function(a, b) return a.name < b.name end)
    return vars
end

extand[VAR_GLOBAL] = function(frameId)
    children[VAR_GLOBAL][3] = {}
    local vars = {}
    local gt = rdebug._G
    local key, value
    while true do
        key, value = rdebug.next(gt, key)
        if rdebug.value(key) == nil then
            break
        end
        local name = varGetName(key)
        if not standard[name] then
            varCreate(vars, frameId, children[VAR_GLOBAL], name, value, ('_G%s'):format(getTabelKey(key)))
        end
    end
    table.sort(vars, function(a, b) return a.name < b.name end)
    return vars
end

extand[VAR_STANDARD] = function(frameId)
    children[VAR_STANDARD][3] = {}
    local vars = {}
    local gt = rdebug._G
    local key, value
    while true do
        key, value = rdebug.next(gt, key)
        if rdebug.value(key) == nil then
            break
        end
        local name = varGetName(key)
        if standard[name] then
            varCreate(vars, frameId, children[VAR_STANDARD], name, value, ('_G%s'):format(getTabelKey(key)))
        end
    end
    table.sort(vars, function(a, b) return a.name < b.name end)
    return vars
end


set[VAR_LOCAL] = function(frameId, name, value)
    return setValue(frameId, children[VAR_LOCAL], name, value)
end

set[VAR_VARARG] = function(frameId, name, value)
    return setValue(frameId, children[VAR_VARARG], name, value)
end

set[VAR_UPVALUE] = function(frameId, name, value)
    return setValue(frameId, children[VAR_UPVALUE], name, value)
end

set[VAR_GLOBAL] = function(frameId, name, value)
    return setValue(frameId, children[VAR_GLOBAL], name, value)
end

set[VAR_STANDARD] = function(frameId, name, value)
    return setValue(frameId, children[VAR_STANDARD], name, value)
end

local m = {}

function m.scopes(frameId)
    local scopes = {}
    if hasLocal(frameId) then
        scopes[#scopes + 1] = {
            name = "Locals",
            variablesReference = (frameId << 16) | VAR_LOCAL,
            expensive = false,
        }
    end
    if hasVararg(frameId) then
        scopes[#scopes + 1] = {
            name = "Var Args",
            variablesReference = (frameId << 16) | VAR_VARARG,
            expensive = false,
        }
    end
    if hasUpvalue(frameId) then
        scopes[#scopes + 1] = {
            name = "Upvalues",
            variablesReference = (frameId << 16) | VAR_UPVALUE,
            expensive = false,
        }
    end
    if hasGlobal(frameId) then
        scopes[#scopes + 1] = {
            name = "Globals",
            variablesReference = (frameId << 16) | VAR_GLOBAL,
            expensive = true,
        }
    end
    if hasStandard(frameId) then
        scopes[#scopes + 1] = {
            name = "Standard",
            variablesReference = (frameId << 16) | VAR_STANDARD,
            expensive = true,
        }
    end
    if not varPool[frameId] then
        varPool[frameId] = {}
    end
    return scopes
end

function m.extand(frameId, valueId)
    if not varPool[frameId] then
        return nil, 'Error retrieving stack frame ' .. frameId
    end
    if extand[valueId] then
        return extand[valueId](frameId)
    end
    local varRef = varPool[frameId][valueId]
    if not varRef then
        return nil, 'Error variablesReference'
    end
    return extandValue(frameId, varRef)
end

function m.set(frameId, valueId, name, value)
    if not varPool[frameId] then
        return nil, 'Error retrieving stack frame ' .. frameId
    end
    if set[valueId] then
        return set[valueId](frameId, name, value)
    end
    local varRef = varPool[frameId][valueId]
    if not varRef then
        return nil, 'Error variablesReference'
    end
    return setValue(frameId, varRef, name, value)
end

function m.clean()
    varPool = {}
end

function m.createRef(frameId, value, evaluateName)
    if not varPool[frameId] then
        varPool[frameId] = {}
    end
    return varCreateReference(frameId, value, evaluateName)
end

return m
