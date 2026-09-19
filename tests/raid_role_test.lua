-- Exercise raid assignments through the real load compiler and aura filter.
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
local core = readSource("M33kAuras/M33kAuras.lua")
local buffs = readSource("M33kAuras/BuffTrigger2.lua")
local helper = section(prototypes, "if M33kAuras.IsClassicOrWrathOrCataOrMists() or M33kAuras.IsForever() then",
  "local function")
local loadArg = section(prototypes, '    {\n      name = "raid_role",', '    {\n      name = "ingroup",')
local compiler = section(core, "local function EvalBooleanArg", "function M33kAuras.GetActiveConditions")
  .. "\nreturn ConstructFunction"
local assignment = section(core, "  local mounted = IsMounted()", "  vehicle =")
-- End before the legacy vehicle branches when testing committed source.
assignment = assignment:match("^(.-)\n  if M33kAuras.IsClassicEra%(%) then") or assignment
local applies = section(buffs, "local function TriggerInfoApplies", "local function FormatAffectedUnaffected")
  .. "\nreturn TriggerInfoApplies"
local effective = assert(buffs:match("local effectiveRaidRole = ([^\n]+)"))
local handler = section(buffs, "local function EventHandler", "\nif M33kAuras.IsCataOrMistsOrRetail() then")
  .. "\nreturn EventHandler"
local registration = section(buffs, 'Buff2Frame:RegisterEvent("UNIT_AURA")', "-- For UNIT_IN_RANGE_UPDATE")

for _, flavor in ipairs({ "Forever", "Midnight", "Classic", "Wrath", "Cata", "Mists" }) do
  T.section(flavor .. ": raid assignments")
  local legacy = flavor ~= "Forever" and flavor ~= "Midnight"
  local roster = { [1] = "MAINTANK", [2] = "MAINASSIST", [3] = false }
  local units = { player = 1, raid1 = 1, raid2 = 2, raid3 = 3 }
  local wa = {
    IsForever = function() return flavor == "Forever" end,
    IsRetail = function() return flavor == "Midnight" end,
    IsClassicEra = function() return flavor == "Classic" end,
    IsWrathClassic = function() return flavor == "Wrath" end,
    IsClassicOrWrathOrCataOrMists = function() return legacy end,
    IsClassicOrCataOrMists = function() return legacy and flavor ~= "Wrath" end,
    IsWrathOrCataOrMistsOrRetail = function() return flavor ~= "Classic" and flavor ~= "Forever" end,
    UnitIsPet = function(unit) return unit == "raidpet1" end,
    petUnitToUnit = { raidpet1 = "raid1" },
  }
  local env = setmetatable({
    M33kAuras = wa, Private = {}, tinsert = table.insert,
    L = setmetatable({}, { __index = function(_, key) return key end }),
    issecretvalue = function() return false end,
    UnitInRaid = function(unit) return units[unit] end,
    GetRaidRosterInfo = function(id)
      return "Player", nil, nil, nil, nil, nil, nil, nil, nil, roster[id] or nil
    end,
    IsMounted = function() return false end,
    UnitGroupRolesAssigned = function() return "NONE" end,
    GetTalentGroupRole = function() return "NONE" end,
    GetActiveTalentGroup = function() return 1 end,
  }, { __index = _G })
  load(helper, env)
  local prototype = load("return { args = {" .. loadArg .. "} }", env)
  local raidArg = prototype.args[1]
  local enabled = flavor ~= "Midnight"
  T.expect(raidArg.enable == enabled and raidArg.hidden == not enabled,
    "exposes load conditions on the expected flavors")

  if enabled then
    T.expect(wa.UnitRaidRole("raid1") == "MAINTANK" and wa.UnitRaidRole("raid2") == "MAINASSIST",
      "reads main tank and main assist assignments")
    T.expect(wa.UnitRaidRole("raid3") == "NONE" and wa.UnitRaidRole("party1") == nil,
      "distinguishes unassigned raid members from units outside the raid")
    local construct = load(compiler, env)
    local evaluate, events = construct(prototype, { use_raid_role = true, raid_role = { single = "MAINTANK" } })
    evaluate = load(evaluate, env)
    local getPlayerAssignment = load("return function() local raidRole, role = false, false\n"
      .. assignment .. "\nreturn raidRole end", env)
    T.expect(evaluate("test", getPlayerAssignment()), "loads for the player's selected raid assignment")
    roster[1] = "MAINASSIST"
    T.expect(not evaluate("test", getPlayerAssignment()), "unloads when the assignment changes")
    units.player = nil
    T.expect(not evaluate("test", getPlayerAssignment()), "unloads when the player leaves the raid")
    T.expect(events.PLAYER_ROLES_ASSIGNED, "refreshes loads on assignment changes")
    if flavor == "Forever" then
      T.expect(events.GROUP_ROSTER_UPDATE, "refreshes Forever loads when raid membership changes")
    end
    evaluate = load(construct(prototype, { use_raid_role = false,
      raid_role = { multi = { MAINTANK = true, NONE = true } } }), env)
    T.expect(evaluate("test", "MAINTANK") and evaluate("test", "NONE") and not evaluate("test", "MAINASSIST"),
      "supports selecting multiple raid assignments")
    roster[1] = "MAINTANK"
  end

  for _, name in ipairs({ "Unit Characteristics", "Power", "Alternate Power", "Cast" }) do
    local triggerSource = section(prototypes, '  ["' .. name .. '"] = {', '\n  ["')
    local roleArg = section(triggerSource, '      {\n        name = "raid_role",', '      -- {')
    local role = load("return {" .. roleArg .. "}", env)[1]
    local expected = flavor == "Forever" or (legacy and (name == "Unit Characteristics" or flavor ~= "Wrath"))
    T.expect(role.enable({ unit = "raid" }) == expected and not role.enable({ unit = "target" }),
      name .. " exposes raid filtering on the expected flavors and units")
    if name == "Cast" then
      T.expect(not role.enable({ unit = "raid", use_inverse = true }), "inverse casts omit raid filtering")
    end
  end

  local trigger = { unit = "raid", useRaidRole = true, raid_role = { MAINTANK = true } }
  env.trigger, env.groupTrigger = trigger, true
  local info = { raidRole = load("return " .. effective, env) }
  T.expect((info.raidRole ~= nil) == enabled, "applies configured aura filters on the expected flavors")
  if enabled then
    local filter = load(applies, env)
    T.expect(filter(info, "raid1") and filter(info, "raidpet1") and not filter(info, "raid2"),
      "filters raid members and their pets by the owner's assignment")
    roster[1] = "MAINASSIST"
    T.expect(not filter(info, "raid1"), "rejects a member after its assignment changes")
    info.raidRole = { NONE = true }
    T.expect(filter(info, "raid3") and not filter(info, "party1"), "Other matches unassigned raid members")
  end

  if flavor == "Forever" or flavor == "Midnight" then
    local checked, registered = {}, {}
    local function noop() end
    env.Private = { player_target_events = {}, StartProfileSystem = noop, StopProfileSystem = noop }
    env.Buff2Frame = { RegisterEvent = function(_, event) registered[event] = true end, SetScript = noop }
    env.GetTime, env.DeactivateScanFuncs, env.ScanGroupUnit, env.ScanGroupRoleScanFunc = noop, noop, noop, noop
    -- The addon iterator returns a unit as its first value.
    env.GetAllUnits = function()
      local i, all = 0, { "raid1", "raid2", "raidpet1" }
      return function() i = i + 1; return all[i] end
    end
    env.UnitExistsFixed = function() return true end
    env.RecheckActiveForUnitType = function(_, unit) checked[unit] = true end
    env.matchDataChanged = {}
    load(registration, env)
    T.expect((registered.PLAYER_ROLES_ASSIGNED == true) == (flavor == "Forever"),
      "registers the additional aura assignment event only for Forever")
    if flavor == "Forever" then
      load(handler, env)(nil, "PLAYER_ROLES_ASSIGNED")
      T.expect(checked.raid1 and checked.raid2 and checked.raidpet1,
        "rechecks aura membership for players and pets on assignment changes")
    end
  end
end

T.finish()
