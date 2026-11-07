-- Test runner: lua run.lua [addon-dir]
-- Loads the WoW stubs, then core.lua + goals.lua, then runs the test files.
-- UI (ui.lua), broker.lua and slash.lua need the real game client and are not covered.

local ADDON = arg[1] or "../"
if ADDON:sub(-1) ~= "/" then ADDON = ADDON .. "/" end

local stubs = dofile("wow_stubs.lua")

local total, failed = 0, 0
function test(name, fn)
    total = total + 1
    local ok, err = pcall(fn)
    if ok then
        print("  ok - " .. name)
    else
        failed = failed + 1
        print("  FAIL - " .. name .. ": " .. tostring(err))
    end
end

function assertEq(a, b, msg)
    if a ~= b then
        error((msg or "mismatch:") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2)
    end
end

dofile("test_core.lua")(stubs, ADDON)
dofile("test_goals.lua")(stubs, ADDON)
dofile("test_ui.lua")(stubs, ADDON)

print(string.format("\n%d tests, %d failed", total, failed))
os.exit(failed > 0 and 1 or 0)
