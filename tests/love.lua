-- Just enough of LÖVE for the rules to run under plain LuaJIT: its random
-- generator, the very same numbers (xorshift64* seeded through a Wang hash,
-- as LÖVE 11 does it), a save directory in memory, a clock, and an OS (for
-- the screen's state, src/ui/state.lua, which the toolbar reads).

local ffi = require "ffi"
local bit = require "bit"

local function wang(key)
    key = bit.bnot(key) + bit.lshift(key, 21)
    key = bit.bxor(key, bit.rshift(key, 24))
    key = (key + bit.lshift(key, 3)) + bit.lshift(key, 8)
    key = bit.bxor(key, bit.rshift(key, 14))
    key = (key + bit.lshift(key, 2)) + bit.lshift(key, 4)
    key = bit.bxor(key, bit.rshift(key, 28))
    return key + bit.lshift(key, 31)
end

local function newRandomGenerator(seed)
    local s = ffi.new("uint64_t", seed or 0)
    repeat s = wang(s) until s ~= 0ULL
    local g = {}
    function g:random(l, u)
        s = bit.bxor(s, bit.rshift(s, 12))
        s = bit.bxor(s, bit.lshift(s, 25))
        s = bit.bxor(s, bit.rshift(s, 27))
        local r = tonumber(bit.rshift(s * 2685821657736338717ULL, 12)) / 2 ^ 52
        if l == nil then return r end
        if u == nil then return math.floor(r * l) + 1 end
        return math.floor(r * (u - l + 1)) + l
    end
    -- As LÖVE keeps it: a string, to set it back to later.
    function g:getState() return tostring(s) end
    function g:setState(state) s = ffi.new("uint64_t", assert(loadstring("return " .. state))()) end
    function g:typeOf(name) return name == "RandomGenerator" end
    return g
end

local dice = newRandomGenerator(0)

-- The save directory: file name to contents.
local files = {}

love = {
    math = {
        newRandomGenerator = newRandomGenerator,
        random = function(...) return dice:random(...) end,
    },
    filesystem = {
        getInfo = function(name) return files[name] and { type = "file", size = #files[name] } or nil end,
        read = function(name) return files[name] end,
        write = function(name, data) files[name] = data; return true end,
        remove = function(name) local had = files[name] ~= nil; files[name] = nil; return had end,
    },
    timer = { getTime = os.clock },
    system = { getOS = function() return "Linux" end },
}

-- For the tests: the save directory itself, and emptying it.
return {
    files = files,
    clearFiles = function() for k in pairs(files) do files[k] = nil end end,
}
