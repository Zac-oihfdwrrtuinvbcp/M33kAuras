-- Verify ruleset precedence, compiled loads and migration from the old Hardcore check.
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
local init = readSource("M33kAuras/Init.lua")
local loadArgs = "return { args = {" .. section(prototypes,
  '    {\n      name = "combat",', '    {\n      name = "class_and_spec",') .. "} }"
local querySource = "return function()\n" .. section(core, "  local ruleset\n", "  local pvp = false")
  .. "\nreturn ruleset end"
local compilerSource = section(core, "local function EvalBooleanArg", "function M33kAuras.GetActiveConditions")
  .. "\nreturn ConstructFunction"
local callSource = section(core, "      if M33kAuras.IsForever() then\n        shouldBeLoaded", "      -- end")
local registrationSource = section(core, 'if M33kAuras.IsForever() then\n  loadFrame:RegisterEvent("VEHICLE_UPDATE")',
  "if M33kAuras.IsWrathOrCataOrMists() then")
local version = assert(tonumber(core:match("local internalVersion = (%d+)")))

for _, flavor in ipairs({"Forever", "Midnight"}) do
  T.section(flavor .. ": game mode loads")
  local forever = flavor == "Forever"
  local active, calls, registrations = {}, {}, {}
  local env = setmetatable({
    M33kAuras = {BuildInfo = forever and 16001 or 120100, IsLibsOK = function() return true end,
      InternalVersion = function() return version end},
    Private = {}, L = setmetatable({}, {__index = function(_, key) return key end}),
    Enum = {GameRule = {HardcoreRuleset = "Hardcore", RPRuleset = "RP", PvPRuleset = "PvP"}},
    C_GameRules = {IsGameRuleActive = function(rule)
      assert(rule == "Hardcore" or rule == "RP" or rule == "PvP")
      calls[#calls + 1] = rule
      return active[rule] or false
    end},
    tinsert = table.insert, tconcat = table.concat, max = math.max,
    issecretvalue = function() return false end,
    loadFrame = {RegisterEvent = function(_, event) registrations[event] = true end},
  }, {__index = _G})
  load("local flavor = 10\n" .. section(init, "function M33kAuras.IsClassicEra()", "---@param ... string"), env)
  load(registrationSource, env)
  local query = load(querySource, env)
  local prototype = load(loadArgs, env)
  local option
  for _, arg in ipairs(prototype.args) do
    if arg.name == "ruleset" then option = arg end
    T.expect(arg.name ~= "hardcore" and arg.name ~= "engraving", "omits the old Hardcore and Season of Discovery options")
  end
  assert(option, "ruleset option is missing")
  T.expect(option.type == "multiselect" and option.display == "Game Mode", "uses the standard multiselect")
  T.expect(option.enable == forever and option.hidden == not forever and (option.init == "arg") == forever,
    "exposes game mode only on Forever")
  for _, key in ipairs({"Hardcore", "RP", "PvP", "PvE"}) do
    T.expect(option.values[key] == key, "provides " .. key)
  end
  T.expect(not registrations.GAME_RULES_CHANGED, "does not register in-session ruleset updates")
  local construct = load(compilerSource, env)
  local function evaluate(selection, ruleset)
    local source, events = construct(prototype, selection)
    env.loadFunc = load(source, env)
    env.loadOpt = load(construct(prototype, selection, true), env)
    env.ruleset, env.class = ruleset, "MAGE"
    load(callSource, env)
    return not not env.shouldBeLoaded, not not env.couldBeLoaded, events
  end
  local single = {use_ruleset = true, ruleset = {single = "Hardcore"}, use_class = true, class = {single = "MAGE"}}
  local multiple = {use_ruleset = false, ruleset = {multi = {PvE = true, RP = true}},
    use_class = true, class = {single = "MAGE"}}
  for _, case in ipairs({
    {expected = "PvE"}, {Hardcore = true, expected = "Hardcore"},
    {RP = true, expected = "RP"}, {PvP = true, expected = "PvP"},
    {RP = true, PvP = true, expected = "RP"}, {Hardcore = true, PvP = true, expected = "Hardcore"},
    {Hardcore = true, RP = true, expected = "Hardcore"},
    {Hardcore = true, RP = true, PvP = true, expected = "Hardcore"},
  }) do
    active, calls = case, {}
    local ruleset = query()
    T.expect(ruleset == (forever and case.expected or nil), "resolves ruleset precedence to " .. case.expected)
    local expectedCalls = not forever and "" or case.Hardcore and "Hardcore"
      or case.RP and "Hardcore,RP" or "Hardcore,RP,PvP"
    T.expect(table.concat(calls, ",") == expectedCalls, "queries rules in priority order only on Forever")
    local loaded, available, events = evaluate(single, ruleset)
    local expected = not forever or case.expected == "Hardcore"
    T.expect(loaded == expected and available == expected, "single selection also filters the options load check")
    T.expect(not events.GAME_RULES_CHANGED, "compiled loads do not subscribe to ruleset updates")
    loaded, available = evaluate(multiple, ruleset)
    expected = not forever or case.expected == "PvE" or case.expected == "RP"
    T.expect(loaded == expected and available == expected, "multiple selection matches any selected mode")
    T.expect(evaluate({}, ruleset), "unused selector does not restrict loading")
  end
  if forever then
    T.expect(not evaluate({use_ruleset = false, ruleset = {multi = {}}}, "PvE"), "empty multiselect matches no mode")
    T.expect(not evaluate({use_ruleset = true, ruleset = {single = "PvE"},
      use_class = true, class = {single = "WARRIOR"}}, "PvE"), "class still filters correctly after the new argument")
  end

  T.section(flavor .. ": old Hardcore modernization")
  setfenv(assert(loadfile(T.repoRoot .. "/M33kAuras/Modernize.lua")), env)("M33kAuras", env.Private)
  for _, choice in ipairs({true, false}) do
    local data = {internalVersion = 89, load = {use_hardcore = choice, use_combat = true}}
    env.Private.Modernize(data)
    T.expect(data.internalVersion == version and data.load.use_hardcore == nil and data.load.hardcore == nil,
      "upgrades the version and removes the old Hardcore field")
    T.expect(data.load.use_combat == true, "preserves unrelated load settings")
    T.expect(data.load.use_ruleset == choice, "maps checked Hardcore to single and unchecked Hardcore to multiple")
    for _, mode in ipairs({"Hardcore", "RP", "PvP", "PvE"}) do
      env.inCombat = true
      local loaded, available = evaluate(data.load, mode)
      local expected = not forever or ((mode == "Hardcore") == choice)
      T.expect(loaded == expected and available == expected, "preserves the old check's behavior in " .. mode)
    end
    local ruleset = data.load.ruleset
    env.Private.Modernize(data)
    T.expect(data.load.ruleset == ruleset, "does not repeat migration")
  end
  local unused = {internalVersion = 89, load = {hardcore = true}}
  env.Private.Modernize(unused)
  T.expect(unused.load.use_ruleset == nil and unused.load.ruleset == nil, "unused Hardcore does not add a restriction")
  for _, setting in ipairs({true, false, "disabled"}) do
    local ruleset = {single = "RP", multi = {RP = true}}
    local data = {internalVersion = 89, load = {use_hardcore = true, ruleset = ruleset}}
    if setting ~= "disabled" then data.load.use_ruleset = setting end
    local expectedSetting = data.load.use_ruleset
    env.Private.Modernize(data)
    T.expect(data.load.ruleset == ruleset
      and data.load.use_ruleset == expectedSetting,
      "preserves an existing ruleset selection, including disabled selections")
  end
  local group = {internalVersion = 89, controlledChildren = {"child"}}
  env.Private.Modernize(group)
  T.expect(group.load == nil and group.internalVersion == version, "handles groups without load data")
end

T.finish()
