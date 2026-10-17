-- The tests: `luajit tests/run.lua` from the game's folder, no LÖVE needed.
-- Each tests/*_test.lua returns a list of { name, function }; a function
-- passes by not raising. `luajit tests/run.lua game` runs only the files
-- whose name has "game" in it.

package.path = "./?.lua;" .. package.path
require "tests.love"

local only = arg[1]
local files = {}
for name in io.popen("ls tests"):lines() do
    if name:match("_test%.lua$") and (not only or name:find(only, 1, true)) then files[#files + 1] = name end
end
table.sort(files)

local passed, failed = 0, 0
for _, file in ipairs(files) do
    local tests = dofile("tests/" .. file)
    for _, t in ipairs(tests) do
        local ok, err = xpcall(t[2], debug.traceback)
        if ok then
            passed = passed + 1
        else
            failed = failed + 1
            print(("FAIL %s: %s\n%s\n"):format(file, t[1], err))
        end
    end
end
print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
