-- Restricted derived stats must not masquerade as real zero values.
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
local generic = readSource("M33kAuras/GenericTrigger.lua")
local init = readSource("M33kAuras/Init.lua")
local prototypeSource = "return {" .. section(prototypes,
  '  ["Character Stats"] = {', '  ["Conditions"] = {') .. "}"
local compilerSource = section(generic, "function TestForTriState", "function Private.EndEvent")
  .. "\nreturn ConstructFunction"
local conditionSource = section(readSource("M33kAuras/Conditions.lua"),
  "local function CreateTestForCondition", "local function CreateCheckCondition") .. "\nreturn CreateTestForCondition"
local helperSource = section(prototypes, "function M33kAuras.GetEffectiveAttackPower()", "local function talentSpecIdForTrigger")
  .. section(generic, "M33kAuras.GetCritChance = function()", "---@type fun(trigger: triggerData)")

local expected = {
  stamina = 40, criticalrating = 8, hitrating = 8, versatilitypercent = 7,
  movespeedpercent = 100, runspeedpercent = 200, defense = 105,
  blocktargetpercent = 3, armorpercent = 20, armortargetpercent = 20,
  criticalpercent = 15, hitpercent = 5, attackpower = 115, spellpower = 70,
  hastepercent = 6, meleehastepercent = 8, expertisebonus = 3,
  armorpenpercent = 250, spellpenpercent = 30, armorrating = 200,
  dodgepercent = 4, parrypercent = 5, blockpercent = 6, blockvalue = 30,
}
local rawStats = {
  strength = true, agility = true, intellect = true, spirit = true, mainstat = true,
  hastepercent = true, meleehastepercent = true, expertisebonus = true,
  armorpenpercent = true, spellpenpercent = true, armorrating = true,
  dodgepercent = true, parrypercent = true, blockpercent = true, blockvalue = true,
}
local foreverValues = {
  strength = 20, agility = 20, intellect = 20, spirit = 20, stamina = 20,
  hitpercent = 12, criticalpercent = 15, hastepercent = 17, meleehastepercent = 8,
  expertisebonus = 4, armorpenpercent = 250, spellpenpercent = 30,
  attackpower = 115, spellpower = 10, movespeedpercent = 100, runspeedpercent = 200,
  defense = 105, dodgepercent = 4, parrypercent = 5, blockpercent = 6, blockvalue = 30, armorrating = 200,
}

local function contains(list, value)
  for _, item in ipairs(list) do if item == value then return true end end
  return false
end

for _, flavor in ipairs({
  {"Forever", 10, 16001}, {"Midnight", 10, 120100}, {"Classic", 1, 11508},
  {"Wrath", 3, 30403}, {"Cata", 4, 40402}, {"Mists", 5, 50501},
}) do
  T.section(flavor[1] .. ": character stats")
  local forever = flavor[1] == "Forever"
  local restricted, zero = false, false
  -- This sentinel catches accidental arithmetic/comparisons; it does not emulate WoW taint.
  local secret = newproxy(true)
  local function forbidden() error("Attempted to calculate with a secret stat") end
  for _, name in ipairs({"__add", "__sub", "__mul", "__div", "__lt", "__le", "__eq", "__tostring"}) do
    getmetatable(secret)[name] = forbidden
  end
  local env = setmetatable({
    M33kAuras = {BuildInfo = flavor[3]}, Private = {ExecEnv = {
      GetSpecialization = function() return 1 end,
      GetSpecializationInfo = function() return nil, nil, nil, nil, nil, 1 end,
    }},
    L = setmetatable({}, {__index = function(_, key) return key end}),
    tinsert = table.insert, tconcat = table.concat, max = math.max, min = math.min,
    C_Secrets = {ShouldUnitStatsBeSecret = function() return restricted end},
    issecretvalue = function(value) return rawequal(value, secret) end,
    hasanysecretvalues = function(...)
      for i = 1, select("#", ...) do if rawequal(select(i, ...), secret) then return true end end
      return false
    end,
    PaperDollFrame_GetArmorReduction = function(value) return value / 10 end,
    PaperDollFrame_GetArmorReductionAgainstTarget = function(value) return value / 10 end,
  }, {__index = _G})
  for name, values in pairs({
    UnitStat = {10, 20, 2, -1}, GetUnitMaxHealthModifier = {2},
    GetCombatRating = {8}, GetCombatRatingBonus = {3}, GetVersatilityBonus = {4},
    GetUnitSpeed = {7, 14}, UnitDefense = {100, 5}, GetShieldBlock = {30}, UnitArmor = {100, 200},
    UnitEffectiveLevel = {60}, UnitLevel = {60},
    UnitAttackPower = {100, 20, -5}, GetRangedCritChance = {12}, GetCritChance = {10},
    GetHitModifier = {1}, GetRangedHitModifier = {9}, GetSpellHitModifier = {2},
    GetHaste = {6}, GetMeleeHaste = {8}, UnitSpellHaste = {12}, GetRangedHaste = {14, 3},
    GetExpertise = {2, 4, 3}, GetArmorPenetration = {250}, GetSpellPenetration = {30},
    UnitDefenseSkill = {100, 5}, GetDodgeChance = {4}, GetParryChance = {5}, GetBlockChance = {6},
  }) do
    env[name] = function()
      local result = {}
      for i, value in ipairs(values) do result[i] = restricted and secret or zero and 0 or value end
      return unpack(result)
    end
  end
  env.GetSpellCritChance = function(school)
    assert(forever and school == nil or not forever and school >= 2 and school <= 7)
    return restricted and secret or zero and 0 or 15
  end
  env.GetSpellBonusDamage = function(school)
    assert(school >= 2 and school <= 7)
    return restricted and secret or zero and 0 or school == 3 and 10 or school * 10
  end
  load("local flavor = " .. flavor[2] .. "\n"
    .. section(init, "function M33kAuras.IsClassicEra()", "---@param ... string"), env)
  load(helperSource, env)
  local prototype = load(prototypeSource, env)["Character Stats"]
  local construct, condition = load(compilerSource, env), load(conditionSource, env)
  local events = prototype.events()
  for _, event in ipairs({"SPELL_POWER_CHANGED", "SKILL_LINES_CHANGED"}) do
    T.expect(contains(events.events, event) == forever, "refreshes " .. event .. " only on Forever")
  end
  for _, event in ipairs({"UNIT_SPELL_HASTE", "UNIT_ATTACK_SPEED", "UNIT_DEFENSE"}) do
    T.expect(contains(events.unit_events.player, event) == forever, "refreshes player " .. event .. " only on Forever")
  end
  T.expect(contains(prototype.internal_events({}), "WA_UNIT_STATS_SECRET_STATE_UPDATE")
    == (forever or flavor[1] == "Midnight"), "listens for stat secrecy changes on supported flavors")
  local seen = {}
  for _, option in ipairs(prototype.args) do
    local name = option.name
    seen[name] = option
    if forever and option.type == "number" then
      T.expect((option.enable ~= false and not option.hidden) == (foreverValues[name] ~= nil),
        name .. ": follows the selected Forever stat catalogue")
    end
    local raw = rawStats[name]
    if forever then
      if name == "stamina" then raw = true end
      if name == "hastepercent" or name == "expertisebonus" then raw = false end
    end
    if (expected[name] or raw) and option.enable ~= false then
      local single = {args = {option}, init = prototype.init, statesParameter = prototype.statesParameter}
      local track = load(construct(single, {}), env)
      local below = load(construct(single, {["use_" .. name] = true, [name] = {1000}, [name .. "_operator"] = {"<"}}), env)
      local equalZero = load(construct(single, {["use_" .. name] = true, [name] = {0}, [name .. "_operator"] = {"=="}}), env)
      local check = condition({uid = "stats"}, {trigger = 1, variable = name, op = "<", value = 1000},
        {{[name] = {type = "number"}}}, {})
      local conditionBelow = load("return function(state) return " .. check .. " end", env)
      local state = {show = true}
      local value = forever and foreverValues[name] or expected[name] or 10
      restricted, zero = false, false
      T.expect(track(state, "UNIT_STATS") and state[name] == value, name .. ": computes its normal value")
      T.expect(below({}, "UNIT_STATS") and conditionBelow({state}), name .. ": matches an ordinary threshold")
      zero = true
      T.expect(track(state, "UNIT_STATS") and state[name] == 0 and equalZero({}, "UNIT_STATS")
        and conditionBelow({state}), name .. ": preserves real zero values")
      if flavor[1] == "Forever" or flavor[1] == "Midnight" then
        restricted, zero, state.changed = true, false, false
        T.expect(track(state, "UNIT_STATS") and state.changed
          and (raw and rawequal(state[name], secret) or not raw and state[name] == nil),
          name .. ": replaces the previous value without calculating with secrets")
        T.expect(not below({}, "UNIT_STATS") and not equalZero({}, "UNIT_STATS") and not conditionBelow({state}),
          name .. ": cannot match a threshold while restricted")
        restricted, state.changed = false, false
        T.expect(track(state, "UNIT_STATS") and state.changed and state[name] == value
          and conditionBelow({state}), name .. ": resumes after restrictions end")
      end
    end
  end
  if forever then
    for name in pairs(foreverValues) do T.expect(seen[name], "defines " .. name) end
  end
  if flavor[1] == "Forever" or flavor[1] == "Midnight" then
    for name, value in pairs({
      GetCritChance = 15, GetHitChance = forever and 12 or 5, GetEffectiveAttackPower = 115,
      GetEffectiveSpellPower = forever and 10 or 70, GetHaste = 17, GetDefense = 105,
    }) do
      restricted, zero = false, false
      T.expect(env.M33kAuras[name]() == value, name .. ": preserves the unrestricted result")
      restricted = true
      T.expect(env.M33kAuras[name]() == nil, name .. ": returns unavailable without secret arithmetic")
    end
  end
  if forever then
    restricted, zero = false, false
    env.UnitDefenseSkill = function() return 10, -30 end
    T.expect(env.M33kAuras.GetDefense() == 0, "clamps negative effective defense like the character panel")
  end
  if forever or flavor[1] == "Midnight" then
    restricted, zero = false, false
    local frame, queued, signals = {}, {}, 0
    local state = {}
    local track = load(construct({args = {seen.criticalpercent}, init = prototype.init, statesParameter = "one"}, {}), env)
    env.M33kAuras.IsLibsOK = function() return true end
    env.CreateFrame = function() return frame end
    frame.SetScript = function(_, _, handler) frame.OnEvent = handler end
    frame.RegisterEvent = function() end
    env.Enum = {AddOnRestrictionState = {Activating = 1}}
    env.C_Timer = {After = function(delay, callback) assert(delay == 0); queued[#queued + 1] = callback end}
    env.C_Secrets.ShouldAurasBeSecret = function() return false end
    env.C_Secrets.ShouldCooldownsBeSecret = function() return false end
    env.Private.callbacks = {Fire = function() end}
    env.Private.ScanEvents = function(event)
      if event == "WA_UNIT_STATS_SECRET_STATE_UPDATE" then
        signals = signals + 1
        track(state, event)
      end
    end
    setfenv(assert(loadstring(readSource("M33kAuras/Secrets.lua"))), env)("M33kAuras", env.Private)
    frame.OnEvent(frame, "PLAYER_ENTERING_WORLD")
    T.expect(signals == 1 and state.criticalpercent == 15, "initializes the stat secrecy state")
    frame.OnEvent(frame, "ADDON_RESTRICTION_STATE_CHANGED", 0, 1)
    T.expect(#queued == 1 and signals == 1, "waits for restrictions to apply after the Activating event")
    restricted = true
    queued[1]()
    T.expect(signals == 2 and state.criticalpercent == nil, "clears cached stats even when aura/cooldown secrecy did not change")
    frame.OnEvent(frame, "PLAYER_IN_COMBAT_CHANGED")
    T.expect(signals == 2, "does not refresh again when stat secrecy is unchanged")
    restricted = false
    frame.OnEvent(frame, "ADDON_RESTRICTION_STATE_CHANGED", 0, 0)
    T.expect(signals == 3 and state.criticalpercent == 15, "restores cached stats when restrictions end")
  end
end

T.finish()
