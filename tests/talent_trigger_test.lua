-- Compile the real Talent Known prototype and refresh it through the talent cache.
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

local source = readSource("M33kAuras/Prototypes.lua")
local helperSource = source:find("local function talentSpecIdForTrigger", 1, true)
  and section(source, "local function talentSpecIdForTrigger", "local function talentSpecIdForLoad") or ""
local prototypeSource = helperSource .. "\nreturn {" .. section(source,
  '  ["Talent Known"] = {', '  ["PvP Talent Selected"] = {') .. "}"
local cacheSource = section(source, "table.sort(M33kAuras.classes_sorted)", "function M33kAuras.CheckPvpTalentBySpellId")
local compilerSource = section(readSource("M33kAuras/GenericTrigger.lua"),
  "function TestForTriState", "function Private.EndEvent") .. "\nreturn ConstructFunction"

local function load(code, env)
  return setfenv(assert(loadstring(code)), env)()
end

local function setup(flavor)
  local modern = flavor == "Midnight" or flavor == "Forever"
  local state = { ranks = { [1001] = 3, [1002] = 0, [3001] = 1 }, configID = 1, class = "MAGE", spec = 1 }
  local talents, heroes = { { 1001 }, { 1002 } }, { { 3001 } }
  local wa = {
    classes_sorted = {}, class_ids = { MAGE = 8, WARRIOR = 1 },
    IsRetail = function() return flavor == "Midnight" end,
    IsForever = function() return flavor == "Forever" end,
    IsTWW = function() return flavor == "Midnight" end,
    IsClassicEra = function() return flavor == "Classic" end,
    IsClassicOrWrathOrCata = function() return not modern and flavor ~= "Mists" end,
    IsWrathOrCataOrMists = function() return not modern and flavor ~= "Classic" end,
    IsMists = function() return flavor == "Mists" end,
    IsMistsOrRetail = function() return flavor == "Mists" or flavor == "Midnight" end,
  }
  local function specForClass(classID, spec)
    assert(classID == 8 or classID == 1)
    assert(spec == 1, "requests the expected class tree or specialization")
    return classID == 8 and (flavor == "Forever" and 1482 or 62) or 71
  end
  local private = {
    frames = {}, talentInfo = { MAGE = talents }, talent_types_specific = { MAGE = talents },
    StartProfileSystem = function() end, StopProfileSystem = function() end,
    ScanForLoads = function() end,
    ExecEnv = {
      GetSpecializationInfoForClassID = specForClass,
      GetSpecialization = function() return state.spec end,
      GetSpellInfo = function(id) return "Spell " .. id, nil, id + 10000 end,
      GetTalentInfo = function()
        assert(not modern, "modern talents must not use the Classic talent API")
        return "Legacy talent", 42, nil, nil, 1
      end,
    },
    GetTalentData = function(id) return id == 71 and { { 2001 } } or talents, heroes end,
  }
  private.ScanEvents = function(event)
    if state.evaluate and event == "WA_TALENT_UPDATE" then
      state.scans = (state.scans or 0) + 1
      state.active = state.evaluate(state.triggerState, event)
    end
  end
  local env = setmetatable({
    M33kAuras = wa, Private = private, ceil = math.ceil, MAX_NUM_TALENTS = 20,
    L = setmetatable({}, { __index = function(_, key) return key end }),
    tinsert = table.insert, tconcat = table.concat,
    issecretvalue = function() return false end, hasanysecretvalues = function() return false end,
    UnitClass = function() return "Mage", state.class end,
    GetNumClasses = function() return 8 end,
    GetClassInfo = function(id) return "Class", id == 8 and "MAGE" or "WARRIOR" end,
    GetSpecializationInfoForClassID = specForClass,
    CreateFrame = function()
      local frame = { events = {} }
      function frame:RegisterEvent(event) self.events[event] = true end
      function frame:SetScript(script, callback) self[script] = callback end
      function frame:Fire(event)
        assert(self.events[event], "cache must watch " .. event)
        self:OnEvent(event)
      end
      return frame
    end,
    C_Timer = { After = function() end },
    C_ClassTalents = { GetActiveConfigID = function() return state.configID end },
    C_Traits = {
      GetConfigInfo = function() return { treeIDs = { 1 } } end,
      GetTreeNodes = function() return { 1001, 1002, 3001 } end,
      GetNodeInfo = function(_, id) return { ID = id, entryIDs = { id }, activeRank = state.ranks[id] } end,
      GetEntryInfo = function(_, id) return { definitionID = id } end,
      GetDefinitionInfo = function(id) return { spellID = id + 1000 } end,
    },
    C_SpecializationInfo = { GetTalentInfo = function() return { selected = true, name = "Mists talent", icon = 42 } end },
  }, { __index = _G })
  load(cacheSource, env)
  local prototype = load(prototypeSource, env)["Talent Known"]
  local args = {}
  for _, arg in ipairs(prototype.args) do args[arg.name] = arg end
  local construct = load(compilerSource, env)
  local function compile(trigger)
    state.triggerState = {}
    state.evaluate = load(construct(prototype, trigger), env)
    return function() return state.evaluate(state.triggerState, "STATUS") end
  end
  return prototype, args, state, compile, private.frames["M33kAuras talentCheckFrame"]
end

for _, flavor in ipairs({ "Forever", "Midnight" }) do
  T.section(flavor .. ": Talent Known")
  local prototype, args, state, compile, frame = setup(flavor)
  local trigger = { use_class = true, class = "MAGE", use_talent = false, talent = { multi = { [1001] = true } } }
  if flavor == "Midnight" then trigger.use_spec, trigger.spec = true, 1 end
  T.expect(args.class.enable and not args.class.hidden and args.talent.enable(trigger), "enables the class and talent controls")
  T.expect(not args.spec.enable(trigger) == (flavor == "Forever"), "Forever needs only a class; Midnight still requires a spec")
  T.expect(args.herotalent.enable(trigger) == (flavor == "Midnight"), "hero talents remain Midnight-only")
  T.expect(args.inverse.enable == false and args.inverse.hidden, "uses per-talent exclusions instead of the legacy inverse toggle")
  T.expect(args.talent.control == "M33kAurasMiniTalent" and args.talent.multiNoSingle and args.talent.multiTristate,
    "uses the modern multiselect picker")
  T.expect(args.talent.values(trigger)[1][1] == 1001 and args.talent.multiConvertKey(trigger, 2) == 1002,
    "maps picker positions to talent entry IDs")
  T.expect(prototype.internal_events[1] == "WA_TALENT_UPDATE" and prototype.force_events == "TRAIT_CONFIG_UPDATED",
    "subscribes to cache updates and supports an initial evaluation")

  local evaluate = compile(trigger)
  T.expect(not evaluate(), "stays inactive before the cache is available")
  frame:Fire("PLAYER_LOGIN")
  T.expect(state.active and state.scans == 1, "a cache update activates the generated trigger")
  T.expect(state.triggerState.name == "Spell 2001" and state.triggerState.icon == 12001 and state.triggerState.stacks == 3,
    "stores the selected talent's name, icon and rank")

  trigger.use_stacks, trigger.stacks_operator, trigger.stacks = true, ">=", "4"
  evaluate = compile(trigger)
  T.expect(not evaluate(), "honors a rank threshold")
  state.ranks[1001] = 4
  frame:Fire("TRAIT_CONFIG_UPDATED")
  T.expect(state.active and state.triggerState.stacks == 4, "refreshes rank conditions after talent changes")
  state.ranks[1001] = 0
  frame:Fire(flavor == "Forever" and "ACTIVE_TALENT_GROUP_CHANGED" or "PLAYER_SPECIALIZATION_CHANGED")
  T.expect(not state.active, "switching talents deactivates an unmet requirement")

  trigger.use_stacks = nil
  trigger.talent.multi = { [1001] = false, [1002] = true }
  T.expect(not args.stacks.enable(trigger), "does not expose a single rank for multiple selections")
  evaluate = compile(trigger)
  T.expect(not evaluate(), "requires every selected condition")
  state.ranks[1002] = 1
  frame:Fire("TRAIT_CONFIG_UPDATED")
  T.expect(state.active, "combines required and excluded talents")
  state.ranks[1001] = 1
  frame:Fire("TRAIT_CONFIG_UPDATED")
  T.expect(not state.active, "an excluded selected talent prevents activation")

  trigger.talent.multi = { [9999] = true }
  T.expect(not compile(trigger)(), "unknown required talent IDs remain inactive")
  trigger.talent.multi = { [9999] = false }
  T.expect(not compile(trigger)(), "unknown excluded talent IDs also remain inactive")
  trigger.talent.multi = {}
  T.expect(not compile(trigger)(), "an empty selection remains inactive")
  trigger.talent.multi = { [1001] = true }
  state.configID = nil
  evaluate = compile(trigger)
  frame:Fire("TRAIT_CONFIG_UPDATED")
  T.expect(not state.active, "losing the active configuration clears an active trigger")
  state.configID = 1
  frame:Fire("TRAIT_CONFIG_CREATED")
  T.expect(state.active, "configuration availability restores the trigger")

  state.class = "WARRIOR"
  T.expect(not evaluate(), "enforces the selected player class")
  state.class = "MAGE"
  if flavor == "Midnight" then
    state.spec = 2
    T.expect(not evaluate(), "still enforces the Midnight specialization")
    state.spec = 1
    trigger.use_herotalent, trigger.herotalent = false, { multi = { [3001] = true } }
    T.expect(compile(trigger)(), "preserves hero talent evaluation")
    trigger.use_herotalent = nil
  end
  trigger.use_talent, trigger.talent = true, { single = 1001 }
  T.expect(compile(trigger)(), "saved single selections also use the modern cache")
  trigger.talent.single = 9999
  T.expect(not compile(trigger)(), "an unknown saved single selection remains inactive")
end

for _, flavor in ipairs({ "Classic", "Wrath", "Cata", "Mists" }) do
  T.section(flavor .. ": legacy Talent Known")
  local prototype, args, _, compile = setup(flavor)
  T.expect(not args.class.enable and prototype.internal_events == nil, "retains legacy controls and event wiring")
  local trigger = flavor == "Mists" and { use_talent = false, talent = { multi = { [1] = true } } }
    or { use_talent = true, talent = { single = 1 } }
  T.expect(compile(trigger)(), "still evaluates the legacy talent API")
  if flavor ~= "Mists" then
    trigger.use_inverse = true
    T.expect(not compile(trigger)(), "preserves the legacy inverse toggle")
  end
end

T.finish()
