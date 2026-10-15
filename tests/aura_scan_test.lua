-- Exercise the actual restricted aura scanner with Blizzard API stubs.
local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")
local file = assert(io.open(T.repoRoot .. "/M33kAuras/BuffTrigger2.lua"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local getSubTable = assert(source:match("(local function GetSubTable.-)\nlocal function IsGroupTrigger"))
local scanStart = assert(source:find("local function ForEachRegisteredAura", 1, true))
local scanEnd = assert(source:find("---@class TooltipHelper", scanStart, true))
local scan = source:sub(scanStart, scanEnd - 1)
local restricted, calls, found = true, {}, {}
local ids, names = {}, {}
local env = setmetatable({
  scanFuncSpellId = {}, scanFuncSpellIdGroup = {},
  scanFuncName = {}, scanFuncNameGroup = {},
  C_Secrets = { ShouldAurasBeSecret = function() return restricted end },
  C_UnitAuras = {
    GetUnitAuraBySpellID = function(unit, id)
      calls[#calls + 1] = { unit = unit, key = id }
      return ids[id]
    end,
    GetAuraDataBySpellName = function(unit, name, filter)
      calls[#calls + 1] = { unit = unit, key = name, filter = filter }
      return names[name]
    end,
  },
  AuraUtil = { ForEachAura = function(...) calls = { ... }; return "enumerated" end },
}, { __index = _G })
local chunk = assert(loadstring(getSubTable .. scan .. "\nreturn SafeForEachAura"))
setfenv(chunk, env)
local forEach = chunk()
local function collect(aura) found[#found + 1] = aura end
local function reset()
  calls, found, ids, names = {}, {}, {}, {}
  for _, key in ipairs({ "scanFuncSpellId", "scanFuncSpellIdGroup", "scanFuncName", "scanFuncNameGroup" }) do
    env[key] = {}
  end
end
local function register(registry, unit, filter, key)
  env[registry][unit] = env[registry][unit] or {}
  env[registry][unit][filter] = env[registry][unit][filter] or {}
  env[registry][unit][filter][key] = true
end
local secretTiming = {}
local helpful = { auraInstanceID = 1, name = "Buff", spellId = 101, isHelpful = true, duration = secretTiming }
local harmful = { auraInstanceID = 2, name = "Debuff", spellId = 102, isHarmful = true }

T.section("Name-only restricted scans")
for _, registry in ipairs({ "scanFuncName", "scanFuncNameGroup" }) do
  for _, case in ipairs({ { "HELPFUL", helpful }, { "HARMFUL", harmful } }) do
    reset()
    local filter, aura = case[1], case[2]
    register(registry, "target", filter, aura.name)
    names[aura.name] = aura
    forEach("target", filter, nil, collect, true)
    T.expect(#found == 1 and found[1] == aura, registry .. " finds " .. filter .. " aura by name")
    T.expect(#calls == 1 and calls[1].unit == "target" and calls[1].filter == filter,
      "name lookup receives unit and aura filter")
  end
end

T.section("Overlapping registrations")
reset()
for _, registry in ipairs({ "scanFuncSpellId", "scanFuncSpellIdGroup" }) do
  register(registry, "player", "HELPFUL", 101)
end
for _, registry in ipairs({ "scanFuncName", "scanFuncNameGroup" }) do
  register(registry, "player", "HELPFUL", "Buff")
end
ids[101], names.Buff = helpful, helpful
forEach("player", "HELPFUL", nil, collect, true)
T.expect(#found == 1, "name, ID, individual and group matches deliver one instance once")
T.expect(found[1].duration == secretTiming, "timing values pass through untouched")
found = {}
forEach("player", "HELPFUL", nil, collect, true)
T.expect(#found == 1, "deduplication does not suppress later scans")
names.Buff = { auraInstanceID = 3, name = "Buff", spellId = 101, isHelpful = true }
found = {}
forEach("player", "HELPFUL", nil, collect, true)
T.expect(#found == 2, "different returned instances of the same spell are preserved")

T.section("Missing and unrelated auras")
reset()
register("scanFuncName", "player", "HELPFUL", "Missing")
register("scanFuncName", "target", "HELPFUL", "Buff")
register("scanFuncNameGroup", "player", "HARMFUL", "Debuff")
names.Buff, names.Debuff = helpful, harmful
forEach("player", "HELPFUL", nil, collect, true)
T.expect(#calls == 1 and #found == 0, "unavailable names and other units or filters produce no match")
register("scanFuncSpellId", "player", "HELPFUL", 102)
ids[102] = harmful
forEach("player", "HELPFUL", nil, collect, true)
T.expect(#found == 0, "ID lookup cannot deliver a harmful aura to a helpful scan")
reset()
forEach("player", "HELPFUL", nil, collect, true)
T.expect(#calls == 0 and #found == 0, "no selected names or IDs means no restricted lookup")

T.section("Unrestricted enumeration")
restricted = false
local result = forEach("target", "HARMFUL", 5, collect, false)
T.expect(result == "enumerated" and calls[1] == "target" and calls[2] == "HARMFUL"
  and calls[3] == 5 and calls[4] == collect and calls[5] == false,
  "normal enumeration retains its arguments and return value")

T.section("Arena specialization restrictions")
local appliesStart = assert(source:find("local function TriggerInfoApplies", 1, true))
local appliesEnd = assert(source:find("local function FormatAffectedUnaffected", appliesStart, true))
local appliesSource = source:sub(appliesStart, appliesEnd - 1) .. "\nreturn TriggerInfoApplies"
local secretSpec = newproxy(true)
local spec, arenaIndex, specCalls = 71, nil, 0
env.M33kAuras = { UnitIsPet = function() return false end }
env.issecretvalue = function(value) return rawequal(value, secretSpec) end
env.GetArenaOpponentSpec = function(index)
  arenaIndex, specCalls = index, specCalls + 1
  return spec
end
local applies = setfenv(assert(loadstring(appliesSource)), env)()
local info = {
  arenaSpec = setmetatable({ [71] = true }, {
    __index = function(_, key)
      assert(not rawequal(key, secretSpec), "secret specialization used as a table key")
    end,
  }),
}
T.expect(applies(info, "arena2") and arenaIndex == 2,
  "readable matching specializations use the arena index")
spec = 62
T.expect(not applies(info, "arena2"), "readable unselected specializations do not match")
spec = nil
T.expect(not applies(info, "arena2"), "unavailable specializations do not match")
spec = 0
T.expect(not applies(info, "arena2"), "unknown specializations do not match")
spec = secretSpec
T.expect(not applies(info, "arena2"), "secret specializations do not reach the selection table")
local before = specCalls
T.expect(applies(info, "target") and specCalls == before,
  "non-arena units do not query arena specializations")
T.expect(applies({}, "arena2") and specCalls == before,
  "unfiltered arena auras do not query secret specializations")
T.finish()
