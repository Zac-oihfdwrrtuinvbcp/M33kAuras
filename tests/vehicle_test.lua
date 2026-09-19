-- Compile the real vehicle load/trigger options and inspect their event wiring.
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

local core = readSource("M33kAuras/M33kAuras.lua")
local prototypes = readSource("M33kAuras/Prototypes.lua")
local loadSource = "return { args = {" .. section(prototypes,
  '    {\n      name = "vehicle",', '    {\n      name = "dragonriding",') .. "} }"
local conditionSource = section(prototypes, '  ["Conditions"] = {', '  ["Spell Known"] = {')
local eventSource = "return {" .. section(conditionSource, "    events = function", "    internal_events =") .. "}"
local triggerSource = "return { args = {" .. section(conditionSource,
  '      {\n        name = "vehicle",', '      {\n        name = "resting",') .. "} }"
local queryContext = section(core, "  local mounted = IsMounted()", "  if M33kAuras.IsCataOrMistsOrRetail() then")
local queryStart = assert(queryContext:find("  if M33kAuras.IsClassicEra()", 1, true))
local querySource = "return function()\nlocal vehicle, vehicleUi = false, false\n"
  .. queryContext:sub(queryStart)
  .. "\nreturn vehicle, vehicleUi end"
local loadCompiler = section(core, "local function EvalBooleanArg", "function M33kAuras.GetActiveConditions")
  .. "\nreturn ConstructFunction"
local triggerCompiler = section(readSource("M33kAuras/GenericTrigger.lua"), "function TestForTriState", "function Private.EndEvent")
  .. "\nreturn ConstructFunction"
local globalEvents = section(core, 'if M33kAuras.IsRetail() then\n  loadFrame:RegisterEvent("PLAYER_TALENT_UPDATE")',
  'loadFrame:RegisterEvent("GROUP_ROSTER_UPDATE")')
local unitEvents = section(core, 'unitLoadFrame:RegisterUnitEvent("UNIT_FLAGS"', 'function Private.RegisterLoadEvents()')

local function contains(list, needle)
  for _, value in ipairs(list) do if value == needle then return true end end
  return false
end

for _, flavor in ipairs({ "Forever", "Midnight", "Classic", "Wrath", "Cata", "Mists" }) do
  T.section(flavor .. ": taxi, vehicle and vehicle UI")
  local classic, forever = flavor == "Classic", flavor == "Forever"
  local taxiOnly = classic or forever
  local values, registrations, apiCalls = {}, {}, 0
  local frame = {
    RegisterEvent = function(_, event) registrations[event] = true end,
    RegisterUnitEvent = function(_, event, unit)
      assert(unit == "player")
      registrations[event] = true
    end,
  }
  local env = setmetatable({
    M33kAuras = {
      IsForever = function() return forever end,
      IsRetail = function() return flavor == "Midnight" end,
      IsClassicEra = function() return classic end,
      IsWrathOrCataOrMistsOrRetail = function() return not classic and not forever end,
      IsWrathOrCataOrMists = function() return flavor == "Wrath" or flavor == "Cata" or flavor == "Mists" end,
      IsMists = function() return flavor == "Mists" end,
    },
    Private = {}, L = setmetatable({}, { __index = function(_, key) return key end }),
    tinsert = table.insert, tconcat = table.concat,
    issecretvalue = function() return false end,
    loadFrame = frame, unitLoadFrame = frame,
    UnitOnTaxi = function(unit) assert(unit == "player"); return values.taxi end,
  }, { __index = _G })
  for name, key in pairs({ UnitInVehicle = "vehicle", UnitHasVehicleUI = "ui",
    HasOverrideActionBar = "override", HasVehicleActionBar = "bar" }) do
    env[name] = function()
      assert(not taxiOnly, "Taxi-only flavors must not query vehicle APIs")
      apiCalls = apiCalls + 1
      return values[key]
    end
  end
  load(globalEvents .. unitEvents, env)
  local query = load(querySource, env)
  local loadPrototype = load(loadSource, env)
  local triggerPrototype = load(triggerSource, env)
  local constructLoad = load(loadCompiler, env)
  local constructTrigger = load(triggerCompiler, env)
  local loadVehicle = load(constructLoad(loadPrototype, { use_vehicle = true }), env)
  local loadNoVehicle = load(constructLoad(loadPrototype, { use_vehicle = false }), env)
  local loadUI = load(constructLoad(loadPrototype, { use_vehicleUi = true }), env)
  local loadNoUI = load(constructLoad(loadPrototype, { use_vehicleUi = false }), env)
  local triggerVehicle = load(constructTrigger(triggerPrototype, { use_vehicle = true }), env)
  local triggerNoVehicle = load(constructTrigger(triggerPrototype, { use_vehicle = false }), env)
  local triggerEvents = load(eventSource, env).events({ use_vehicle = true })
  T.expect(loadPrototype.args[1].display == (taxiOnly and "On Taxi" or "In Vehicle")
    and triggerPrototype.args[1].display == (taxiOnly and "On Taxi" or "In Vehicle"), "load and trigger labels agree")
  T.expect(loadPrototype.args[2].enable == not taxiOnly and loadPrototype.args[2].hidden == taxiOnly
    and (loadPrototype.args[2].init == "arg") == not taxiOnly,
    "exposes vehicle UI on supported flavors only")
  T.expect(registrations.UNIT_FLAGS and (registrations.UNIT_ENTERED_VEHICLE == true) == not classic
    and (registrations.UNIT_EXITED_VEHICLE == true) == not classic, "registers load events for taxi and vehicle transitions")
  T.expect((registrations.VEHICLE_UPDATE == true) == not classic
    and (registrations.UPDATE_VEHICLE_ACTIONBAR == true) == not taxiOnly
    and (registrations.UPDATE_OVERRIDE_ACTIONBAR == true) == not taxiOnly, "registers vehicle updates appropriate to the flavor")
  for _, event in ipairs(loadPrototype.args[1].events) do
    T.expect(registrations[event], "registers " .. event .. " for the load condition")
  end
  T.expect((registrations.PLAYER_FLAGS_CHANGED == true) == (not classic and not forever), "preserves unrelated legacy event guards")
  T.expect(contains(triggerEvents.unit_events.player, "UNIT_FLAGS") == (classic or forever)
    and contains(triggerEvents.unit_events.player, "UNIT_ENTERED_VEHICLE") == not classic
    and contains(triggerEvents.unit_events.player, "UNIT_EXITED_VEHICLE") == not classic,
    "refreshes Conditions for the flavor's taxi and vehicle events")
  T.expect(contains(triggerEvents.events, "PLAYER_ENTERING_WORLD"), "reevaluates Conditions after entering the world")
  T.expect(contains(triggerEvents.events, "VEHICLE_UPDATE") == forever, "refreshes Forever taxi status on vehicle updates")

  for _, case in ipairs({ { "on foot" }, { "taxi", taxi = true }, { "vehicle", vehicle = true },
    { "vehicle UI", vehicle = true, ui = true }, { "override bar", override = true },
    { "vehicle action bar", bar = true }, { "taxi with UI", taxi = true, ui = true } }) do
    values = case
    local vehicle, ui = query()
    local expectedVehicle = case.taxi or (not taxiOnly and case.vehicle) or false
    local expectedUI = not taxiOnly and (case.ui or case.override or case.bar) or false
    local expectedTrigger = (taxiOnly and case.taxi) or (not taxiOnly and case.vehicle) or false
    T.expect(not not vehicle == expectedVehicle and not not ui == expectedUI, case[1] .. ": queries the right state")
    T.expect(not not loadVehicle("UNIT_FLAGS", vehicle, ui) == expectedVehicle
      and not not loadNoVehicle("UNIT_FLAGS", vehicle, ui) == not expectedVehicle, case[1] .. ": loads and unloads correctly")
    if not taxiOnly then
      T.expect(not not loadUI("VEHICLE_UPDATE", vehicle, ui) == expectedUI
        and not not loadNoUI("VEHICLE_UPDATE", vehicle, ui) == not expectedUI, case[1] .. ": evaluates vehicle UI tri-state loads")
    end
    T.expect(not not triggerVehicle("CONDITIONS_CHECK") == expectedTrigger
      and not not triggerNoVehicle("CONDITIONS_CHECK") == not expectedTrigger, case[1] .. ": evaluates the Conditions tri-state")
  end
  if taxiOnly then T.expect(apiCalls == 0, "never queries vehicle APIs on taxi-only flavors") end
end

T.finish()
