-- Exercise PvP flags through the real load and Conditions compilers.
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

local function contains(list, value)
  for _, item in ipairs(list) do if item == value then return true end end
  return false
end

local core = readSource("M33kAuras/M33kAuras.lua")
local prototypes = readSource("M33kAuras/Prototypes.lua")
local init = readSource("M33kAuras/Init.lua")
local loadArgs = "return { args = {" .. section(prototypes,
  '    {\n      name = "combat",', '    {\n      name = "addonRestrictionsActive",') .. "} }"
local conditions = section(prototypes, '  ["Conditions"] = {', '  ["Spell Known"] = {')
local triggerArgs = "return { args = {" .. section(conditions,
  '      {\n        name = "pvpflagged",', '      {\n        name = "alive",') .. "} }"
local eventSource = "return {" .. section(conditions, "    events = function", "    force_events =") .. "}"
local loadCompiler = section(core, "local function EvalBooleanArg", "function M33kAuras.GetActiveConditions")
  .. "\nreturn ConstructFunction"
local triggerCompiler = section(readSource("M33kAuras/GenericTrigger.lua"),
  "function TestForTriState", "function Private.EndEvent") .. "\nreturn ConstructFunction"
local querySource = "return function()\n" .. section(core, "  local pvp = false", "  local addonRestrictionsActive")
  .. "\nreturn pvp end"
local callSource = section(core, "      if M33kAuras.IsForever() then\n        shouldBeLoaded", "      -- end")
local registrationSource = section(core, 'unitLoadFrame:RegisterUnitEvent("UNIT_FLAGS"', "function Private.RegisterLoadEvents()")

for _, flavor in ipairs({
  {"Forever", 10, 16001}, {"Midnight", 10, 120100}, {"Classic", 1, 11508},
  {"Wrath", 3, 30403}, {"Cata", 4, 40402}, {"Mists", 5, 50501},
}) do
  T.section(flavor[1] .. ": PvP flags")
  local forever, wrath, retail = flavor[1] == "Forever", flavor[1] == "Wrath", flavor[1] == "Midnight"
  local values, registrations, apiCalls = {}, {}, 0
  local env = setmetatable({
    M33kAuras = {BuildInfo = flavor[3]}, Private = {},
    L = setmetatable({}, {__index = function(_, key) return key end}),
    tinsert = table.insert, tconcat = table.concat,
    issecretvalue = function() return false end,
    unitLoadFrame = {RegisterUnitEvent = function(_, event, unit)
      assert(unit == "player")
      registrations[event] = true
    end},
    UnitIsPVP = function(unit) assert(unit == "player"); apiCalls = apiCalls + 1; return values.pvp end,
    UnitIsPVPFreeForAll = function(unit) assert(unit == "player"); apiCalls = apiCalls + 1; return values.ffa end,
  }, {__index = _G})
  load("local flavor = " .. flavor[2] .. "\n"
    .. section(init, "function M33kAuras.IsClassicEra()", "---@param ... string"), env)
  load(registrationSource, env)
  local query = load(querySource, env)
  local loadPrototype, triggerPrototype = load(loadArgs, env), load(triggerArgs, env)
  local pvpArg
  for _, option in ipairs(loadPrototype.args) do
    if option.name == "pvpmode" then pvpArg = option end
  end
  T.expect(pvpArg.enable == (forever or wrath) and pvpArg.hidden == not (forever or wrath)
    and (pvpArg.init == "arg") == (forever or wrath), "exposes the load option only on intended flavors")
  T.expect(pvpArg.display == (forever and "PvP Flagged" or "PvP Mode Active"), "labels the player's flag correctly")
  T.expect(triggerPrototype.args[1].enable == (forever or wrath or retail)
    and triggerPrototype.args[1].hidden == not (forever or wrath or retail), "preserves Conditions availability on other flavors")
  local constructLoad, constructTrigger = load(loadCompiler, env), load(triggerCompiler, env)
  local positive = load(constructLoad({args = {pvpArg}}, {use_pvpmode = true}), env)
  local negative = load(constructLoad({args = {pvpArg}}, {use_pvpmode = false}), env)
  local triggerPositive = load(constructTrigger(triggerPrototype, {use_pvpflagged = true}), env)
  local triggerNegative = load(constructTrigger(triggerPrototype, {use_pvpflagged = false}), env)
  local queryCalls = apiCalls
  query()
  T.expect((apiCalls > queryCalls) == (forever or wrath), "queries player PvP only on intended load paths")
  local eventsPrototype = load(eventSource, env)
  for _, choice in ipairs({true, false}) do
    local events = eventsPrototype.events({use_pvpflagged = choice})
    T.expect(contains(events.events, "PLAYER_FLAGS_CHANGED"), "watches both positive and negative flag conditions")
    T.expect(contains(events.unit_events.player, "UNIT_FACTION") == forever
      and contains(events.unit_events.player, "UNIT_FLAGS") == forever
      and contains(events.events, "ZONE_CHANGED") == forever, "refreshes Forever flag and faction changes")
    T.expect(contains(eventsPrototype.internal_events({use_pvpflagged = choice}), "WA_DELAYED_PLAYER_ENTERING_WORLD"),
      "refreshes the initial flag after entering the world")
  end
  T.expect(#eventsPrototype.events({}).unit_events.player == 0, "does not add unit listeners without a selected condition")
  if forever then
    for _, event in ipairs(pvpArg.events) do
      T.expect(event == "ZONE_CHANGED" or registrations[event], "registers " .. event .. " for loads")
    end
  end
  for _, case in ipairs({
    {pvp = false, ffa = false}, {pvp = true, ffa = false},
    {pvp = false, ffa = true}, {pvp = true, ffa = true},
  }) do
    values = case
    local flagged = case.pvp or case.ffa
    local value = query()
    if forever or wrath then
      T.expect(value == flagged and not not positive("UNIT_FACTION", value) == flagged
        and not not negative("UNIT_FACTION", value) == not flagged, "evaluates both PvP load states, including free-for-all")
    end
    if forever or wrath or retail then
      local expected = forever and flagged or case.pvp
      T.expect(not not triggerPositive("CONDITIONS_CHECK") == expected
        and not not triggerNegative("CONDITIONS_CHECK") == not expected, "evaluates both Conditions states with flavor-specific semantics")
    end
    if forever or retail then
      for _, choice in ipairs({true, false}) do
        local selection = {use_pvpmode = choice, use_mounted = true, use_vehicle = false}
        env.loadFunc = load(constructLoad(loadPrototype, selection), env)
        env.loadOpt = env.loadFunc
        env.pvp, env.mounted, env.vehicle = value, true, false
        load(callSource, env)
        local expected = not forever or flagged == choice
        T.expect(not not env.shouldBeLoaded == expected and not not env.couldBeLoaded == expected,
          "passes the real load and options arguments without shifting mounted or taxi checks")
      end
    end
  end
end

T.finish()
