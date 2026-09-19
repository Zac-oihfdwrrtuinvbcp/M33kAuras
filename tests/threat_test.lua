-- Threat filters must use readable fields independently of restricted fields.
local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")

local function readSource(path)
  local file = assert(io.open(T.repoRoot .. "/" .. path))
  local source = file:read("*a"):gsub("\r\n", "\n")
  file:close()
  return source
end

local function section(source, first, last)
  local from = assert(source:find(first, 1, true))
  local to = assert(source:find(last, from, true))
  return source:sub(from, to - 1)
end

local function load(source, env)
  return setfenv(assert(loadstring(source)), env)()
end

local prototypes = readSource("M33kAuras/Prototypes.lua")
local compiler = section(readSource("M33kAuras/GenericTrigger.lua"),
  "function TestForTriState", "function Private.EndEvent") .. "\nreturn ConstructFunction"
local conditionCompiler = section(readSource("M33kAuras/Conditions.lua"),
  "local function CreateTestForCondition", "local function CreateCheckCondition") .. "\nreturn CreateTestForCondition"
local prototypeSource = section(prototypes, "local unitHelperFunctions = {", "Private.event_categories = {")
  .. "\nreturn {" .. section(prototypes, '  ["Threat Situation"] = {', '  ["Crowd Controlled"] = {') .. "}"

T.section("Threat filters and conditions")
-- Hostile sentinels catch secret arithmetic. They do not emulate WoW taint.
local secret = newproxy(true)
local function forbidden() error("Calculated with secret threat") end
for _, name in ipairs({"__add", "__sub", "__mul", "__div", "__lt", "__le", "__eq", "__tostring"}) do
  getmetatable(secret)[name] = forbidden
end
local values, generalStatus, unitMatches, apiError
local function reset()
  values = {true, 3, 50, 60, 100}
  generalStatus, unitMatches, apiError = 3, true, false
end
reset()
local env = setmetatable({
  M33kAuras = {UnitExistsFixed = function() return true end},
  Private = {ExecEnv = {UnitName = function() return "Target" end,
    ParseStringCheck = function() return {Check = function() return true end} end}},
  L = setmetatable({}, {__index = function(_, key) return key end}),
  tinsert = table.insert, tconcat = table.concat,
  strsplit = function() return "" end,
  UnitGUID = function() return nil end,
  UnitIsUnit = function() return unitMatches end,
  UnitThreatSituation = function() return generalStatus end,
  UnitDetailedThreatSituation = function()
    if apiError then error("Unit unavailable") end
    return unpack(values, 1, 5)
  end,
  issecretvalue = function(value) return rawequal(value, secret) end,
  hasanysecretvalues = function(...)
    for i = 1, select("#", ...) do if rawequal(select(i, ...), secret) then return true end end
    return false
  end,
}, {__index = _G})
load("local UnitDetailedThreatSituation = UnitDetailedThreatSituation\n" .. section(prototypes,
  "function M33kAuras.UnitDetailedThreatSituation", "M33kAuras.UnitCastingInfo ="), env)
local prototype = load(prototypeSource, env)["Threat Situation"]
local construct = load(compiler, env)
local function trigger(options)
  options = options or {}
  options.unit = options.unit or "target"
  local fn = load(construct(prototype, options), env)
  return function(state) return fn(state or {}, "UNIT_THREAT_LIST_UPDATE", options.unit) end
end
local track, status = trigger(), trigger({use_status = true, status = 3})
local aggro, noAggro = trigger({use_aggro = true}), trigger({use_aggro = false})
local state = {show = true}
T.expect(track(state) and state.total == 200 and state.value == 100, "computes normal threat progress")
T.expect(status() and aggro() and not noAggro(), "matches readable status and aggro")
values[1], values[2] = false, 1
T.expect(not aggro() and noAggro(), "preserves a real false aggro value")
values[3], values[4], values[5] = 0, 0, 0
T.expect(track(state) and state.total == 0 and state.value == 0, "preserves zero threat without division by zero")
values = {}
T.expect(not track(), "does not show when the API returns no threat")
apiError = true
T.expect(not track(), "does not show when the detailed API fails")
reset()
local general = trigger({unit = "none"})
T.expect(general(state) and state.aggro and state.total == 100, "supports general player threat")
generalStatus = 1
T.expect(general(state) and state.aggro == false, "derives non-tanking general threat")
local metadata = {{}}
for _, option in ipairs(prototype.args) do
  if option.conditionType then metadata[1][option.name] = {type = option.conditionType} end
end
local createCondition = load(conditionCompiler, env)
local function condition(name, value, op)
  local code = createCondition({uid = "threat"},
    {trigger = 1, variable = name, value = value, op = op or "=="}, metadata, {})
  return load("return function(state) return " .. code .. " end", env)
end
local aggroCondition, noAggroCondition = condition("aggro", 1), condition("aggro", 0)
for index, name in ipairs({"aggro", "status", "threatpct", "rawthreatpct", "threatvalue"}) do
  reset()
  state = {show = true}
  assert(track(state))
  state.changed = false
  values[index] = secret
  T.expect(track(state) and state.changed and rawequal(state[name], secret), name .. ": replaces cached data without secret arithmetic")
  T.expect((state.total == nil) == (index == 3 or index == 5), name .. ": only suppresses dependent calculations")
  T.expect(not condition(name, name == "aggro" and 1 or 3)({state}), name .. ": cannot satisfy a condition")
  if index == 1 then
    T.expect(not aggro() and not noAggro(), "secret aggro cannot pass either filter polarity")
    T.expect(not aggroCondition({state}) and not noAggroCondition({state}), "secret aggro cannot pass either condition polarity")
    T.expect(status(), "readable status works with secret aggro")
  elseif index == 2 then
    T.expect(not status() and aggro(), "secret status fails its filter while readable aggro works")
  else
    local below = trigger({["use_" .. name] = true, [name] = {1000}, [name .. "_operator"] = {"<"}})
    local zero = trigger({["use_" .. name] = true, [name] = {0}, [name .. "_operator"] = {"=="}})
    T.expect(not below() and not zero(), name .. ": cannot satisfy numeric filters")
    T.expect(status() and aggro(), name .. ": leaves readable status and aggro usable")
  end
  for _, other in ipairs({"threatpct", "rawthreatpct", "threatvalue"}) do
    if other ~= name then
      local readable = trigger({["use_" .. other] = true, [other] = {0}, [other .. "_operator"] = {">"}})
      T.expect(readable() and condition(other, 0, ">")({state}), name .. ": leaves " .. other .. " filters usable")
    end
  end
  reset()
  T.expect(track(state) and state.total == 200 and state.aggro == true, name .. ": resumes with readable data")
end
reset()
values = {secret, secret, secret, secret, secret}
T.expect(track(state) and state.total == nil, "unfiltered trigger tolerates all threat fields being secret")
generalStatus = secret
T.expect(general(state) and rawequal(state.status, secret) and state.aggro == nil,
  "general threat preserves secret status without deriving aggro")
T.expect(not trigger({unit = "none", use_aggro = true})()
  and not trigger({unit = "none", use_aggro = false})(), "unknown general aggro cannot pass either filter")
T.expect(not trigger({unit = "none", use_status = true, status = 3})(), "secret general status cannot pass its filter")
T.expect(not aggroCondition({state}) and not noAggroCondition({state}), "unknown general aggro cannot pass either condition")
reset()
unitMatches = secret
T.expect(not trigger({use_specific_unit = true})(), "secret unit comparison cannot pass the specific-unit filter")
T.expect(track(), "unfiltered unit still works when a unit comparison would be secret")

T.finish()
