-- Assertions for the tests, each saying what was wrong.
local C = {}

function C.eq(got, want, what)
    if got ~= want then
        error(("%s: got %s, want %s"):format(what or "value", tostring(got), tostring(want)), 2)
    end
end

function C.yes(v, what)
    if not v then error((what or "expected true") .. ": got " .. tostring(v), 2) end
end

function C.no(v, what)
    if v then error((what or "expected false") .. ": got " .. tostring(v), 2) end
end

-- Two lists of ids, the same in the same order.
function C.list(got, want, what)
    C.eq(table.concat(got, " "), table.concat(want, " "), what)
end

return C
