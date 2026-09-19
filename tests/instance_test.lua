-- Exercise instance classification and filters through the real compilers.
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
local types = readSource("M33kAuras/Types.lua")
local init = readSource("M33kAuras/Init.lua")
local loadSource = "return {args = {" .. section(prototypes,
  '    {\n      name = "size",', '    {\n      name = "affixes",') .. "}}"
local locationSource = "return {statesParameter = 'one', args = {" .. section(prototypes,
  '      {\n        name = "instanceSize",', '    },\n    automaticrequired = true,\n    progressType = "none"') .. "}}"
local encounterSource = "return {" .. section(prototypes,
  '  ["Encounter Events"] = {', '  ["Evoker Essence"] = {') .. "}"
local loadCompiler = section(core, "local function EvalBooleanArg", "function M33kAuras.GetActiveConditions")
  .. "\nreturn ConstructFunction"
local triggerCompiler = section(readSource("M33kAuras/GenericTrigger.lua"),
  "function TestForTriState", "function Private.EndEvent") .. "\nreturn ConstructFunction"

for _, flavor in ipairs({
  {"Forever", 10, 16001}, {"Midnight", 10, 120100}, {"Classic", 1, 11508},
  {"Wrath", 3, 30403}, {"Cata", 4, 40402}, {"Mists", 5, 50501},
}) do
  T.section(flavor[1] .. ": instances")
  local forever = flavor[1] == "Forever"
  local hidden = forever or flavor[1] == "Classic"
  local instance, catalogCalls = {}, 0
  local env = setmetatable({
    M33kAuras = {BuildInfo = flavor[3]}, Private = {},
    L = setmetatable({}, {__index = function(_, key) return key end}),
    tinsert = table.insert, tconcat = table.concat,
    issecretvalue = function() return false end,
    hasanysecretvalues = function() return false end,
    IsInInstance = function() return instance.kind ~= "none", instance.kind end,
    GetInstanceInfo = function()
      return "Instance", instance.kind, instance.id, "Difficulty", instance.capacity, 0, false, 123
    end,
    GetDifficultyInfo = function(id)
      catalogCalls = catalogCalls + 1
      if id == 1 then return "Normal", "party" end
    end,
    C_PvP = {IsRatedArena = function() return false end, IsRatedBattleground = function() return false end},
  }, {__index = _G})
  load("local flavor = " .. flavor[2] .. "\n"
    .. section(init, "function M33kAuras.IsClassicEra()", "---@param ... string"), env)
  load(section(types, "Private.difficulty_info = {", "Private.glow_types"), env)
  load(section(types, "Private.instance_difficulty_types = {}", "Private.TocToExpansion"), env)
  T.expect((catalogCalls == 0) == hidden, "skips the difficulty catalog only where both selectors are hidden")
  local classify = load(section(core, "local foreverRaidSizes = {", "local toLoad = {}")
    .. "\nreturn GetInstanceTypeAndSize", env)
  for _, case in ipairs({
    {"none", 0, 0, "none", "none"}, {"party", 1, 5, "party", "party"},
    {"raid", 243, 10, "ten", "raid"}, {"raid", 242, 20, "twenty", "raid"},
    {"raid", 999, 25, "twentyfive", "raid"}, {"raid", 999, 40, "fortyman", "raid"},
    {"raid", 3, 20, "twenty", "ten"}, {"raid", 9, 40, "fortyman", "fortyman"},
    {"raid", 186, 0, "fortyman", "fortyman"}, {"raid", 186, nil, "fortyman", "fortyman"},
    {"raid", 999, 30, "raid", "raid"}, {"arena", 1, 5, "arena", "arena"},
    {"pvp", 1, 40, "pvp", "pvp"},
  }) do
    instance = {kind = case[1], id = case[2], capacity = case[3]}
    local size, _, _, _, raw = classify()
    local expectedRaw = (case[1] == "arena" or case[1] == "pvp") and 0 or case[2]
    T.expect(size == (forever and case[4] or case[5]) and raw == expectedRaw,
      ("classifies %s / difficulty %d / capacity %s"):format(case[1], case[2], tostring(case[3])))
  end

  local loadPrototype, location = load(loadSource, env), load(locationSource, env)
  for _, prototype in ipairs({loadPrototype, location}) do
    T.expect(not prototype.args[1].hidden and prototype.args[1].enable ~= false, "keeps Instance Size Type available")
    for i = 2, 3 do
      T.expect(prototype.args[i].hidden == hidden and prototype.args[i].enable == not hidden,
        "exposes " .. prototype.args[i].display .. " only on the intended flavors")
    end
  end
  local constructLoad, constructTrigger = load(loadCompiler, env), load(triggerCompiler, env)
  local loadFilter = load(constructLoad(loadPrototype, {
    use_size = true, size = {single = "ten"},
    use_difficulty = true, difficulty = {single = "heroic"},
    use_instance_type = true, instance_type = {single = 5},
  }), env)
  T.expect(loadFilter("ZONE_CHANGED", "ten", "normal", 3) == hidden,
    "ignores hidden imported difficulty load checks")
  T.expect(loadFilter("ZONE_CHANGED", "ten", "heroic", 5)
    and not loadFilter("ZONE_CHANGED", "twenty", "heroic", 5), "still filters loads by instance size")

  instance = {kind = "raid", id = 3, capacity = 10}
  local locationFilter = load(constructTrigger(location, {
    use_instanceSize = true, instanceSize = {single = "ten"},
    use_instanceDifficulty = true, instanceDifficulty = {single = "heroic"},
    use_instanceType = true, instanceType = {single = 5},
  }), env)
  T.expect(locationFilter({}, "ZONE_CHANGED") == hidden, "ignores hidden imported Location difficulty checks")
  local locationSize = load(constructTrigger(location, {use_instanceSize = true, instanceSize = {single = "ten"}}), env)
  local state = {}
  T.expect(locationSize(state, "ZONE_CHANGED") and state.instanceSize == "ten", "stores the Location size")
  instance = {kind = "raid", id = 9, capacity = 40}
  T.expect(not locationSize({}, "ZONE_CHANGED"), "rejects a different Location size")

  local encounter = load(encounterSource, env)["Encounter Events"]
  local difficultyArg = encounter.args[4]
  T.expect(difficultyArg.hidden == forever and (difficultyArg.conditionType == nil) == forever,
    "hides the encounter difficulty selector and condition only on Forever")
  local counter = {GetNext = function() return 1 end}
  local finish = load(constructTrigger(encounter, {eventtype = "ENCOUNTER_END", use_success = true}), env)
  state = {}
  T.expect(finish(state, counter, "ENCOUNTER_END", 123, "Boss", 243, 10, 1)
    and state.encounterId == 123 and state.difficulty == 243 and state.success == 1,
    "keeps encounter arguments aligned through the success flag")
  T.expect(not finish({}, counter, "ENCOUNTER_END", 123, "Boss", 243, 10, 0), "rejects an unsuccessful encounter")
  local start = load(constructTrigger(encounter, {eventtype = "ENCOUNTER_START"}), env)
  state = {}
  T.expect(start(state, counter, "ENCOUNTER_START", 123, "Boss", 243, 10) and state.difficulty == 243,
    "preserves the raw difficulty on encounter start")
  local selectedDifficulty = load(constructTrigger(encounter, {
    eventtype = "ENCOUNTER_END", use_difficulty = true, difficulty = "heroic",
  }), env)
  T.expect(selectedDifficulty({}, counter, "ENCOUNTER_END", 123, "Boss", 9, 40, 1) == forever,
    "ignores hidden imported encounter difficulty checks only on Forever")
end

T.finish()
