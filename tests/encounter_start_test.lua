-- Exercise encounter delivery through the real load handler, options close and trigger scanner.
local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")

local function read(path)
  local file = assert(io.open(T.repoRoot .. "/" .. path))
  local source = file:read("*a"):gsub("\r\n", "\n")
  file:close()
  return source
end
local function section(source, first, last)
  local from = assert(source:find(first, 1, true))
  return source:sub(from, assert(source:find(last, from, true)) - 1)
end
local function load(source, env)
  return setfenv(assert(loadstring(source)), env)()
end
local function noop() end
local function no() return false end
local function yes() return true end
local function wipe(t)
  for key in pairs(t) do t[key] = nil end
  return t
end
local core = read("M33kAuras/M33kAuras.lua")
local generic = read("M33kAuras/GenericTrigger.lua")
local options = read("M33kAurasOptions/M33kAurasOptions.lua")
local optionsFrame = read("M33kAurasOptions/OptionsFrames/OptionsFrame.lua")

local function fixture(namespacedAPI)
  local f = {frames = {}, calls = {}, ends = {}, errors = {}, timers = {},
    combat = false, encounter = false, resumes = 0, opens = 0}
  local function frame()
    local result = {events = {}, scripts = {}, visible = false}
    function result:RegisterEvent(event) self.events[event] = true end
    result.RegisterUnitEvent = result.RegisterEvent
    function result:SetScript(name, fn) self.scripts[name] = fn end
    function result:IsVisible() return self.visible end
    function result:Hide()
      local wasVisible = self.visible
      self.visible = false
      if wasVisible and self.scripts.OnHide then self.scripts.OnHide() end
    end
    f.frames[#f.frames + 1] = result
    return result
  end
  local private = {
    frames = {}, regions = {}, clones = {}, callbacks = {Fire = noop},
    ExecEnv = {GroupType = function() return "solo" end},
    StartProfileSystem = noop, StopProfileSystem = noop,
    StartProfileAura = noop, StopProfileAura = noop,
    ActivateAuraEnvironment = noop, UpdatedTriggerState = noop,
    EnsureRegion = noop, TraverseParents = function() return noop end,
    IsOptionsProcessingPaused = no, FinishLoadUnload = noop,
    PauseAllDynamicGroups = noop, ResumeAllDynamicGroups = noop,
    ClearFakeStates = noop, UnloadAllConditions = noop,
    CancelAllDelayedTriggers = noop, CancelDelayedTrigger = noop, UnregisterAllEveryFrameUpdate = noop,
    UnregisterEveryFrameUpdate = noop,
    GetErrorHandlerId = function() return function(err) f.errors[#f.errors + 1] = err end end,
  }
  local data, states = {}, {}
  local addon = {
    IsLoginFinished = yes, IsRetail = no, IsForever = no, IsSecretStateActive = no,
    IsClassicOrWrathOrCataOrMists = no, IsClassicEra = no, IsWrathClassic = no,
    IsWrathOrCataOrMistsOrRetail = no, IsCataOrMistsOrRetail = no, IsMistsOrRetail = no,
    GetData = function(id) return data[id] end,
    GetTriggerStateForTrigger = function(id)
      states[id] = states[id] or setmetatable({}, {__index = {SetChanged = noop, IsChanged = no}})
      return states[id]
    end,
  }
  local all = {Always = true, Combat = true, Encounter = true, Unloaded = true}
  local env = setmetatable({
    M33kAuras = addon, Private = private, GenericTrigger = {GetDelay = function() return 0 end},
    OptionsPrivate = {Private = private, DragReset = noop},
    L = setmetatable({}, {__index = function(_, key) return key end}),
    CreateFrame = frame, wipe = wipe, tinsert = table.insert, issecrettable = no,
    paused = false, loaded = {}, runtimeActiveDisplays = {},
    triggerState = {}, timers = {}, clones = {}, watched_trigger_events = {}, nameplateExists = {},
    events = {}, loaded_events = {}, loaded_unit_events = {}, loaded_auras = {},
    loadEvents = {SCAN_ALL = all, ENCOUNTER_START = {Encounter = true}, ENCOUNTER_END = {Encounter = true},
      PLAYER_REGEN_DISABLED = {Combat = true}, PLAYER_REGEN_ENABLED = {Combat = true}},
    loadFuncs = {Always = yes, Combat = function(_, combat) return combat end,
      Encounter = function(_, _, _, encounter) return encounter end, Unloaded = no},
    loadFuncsForOptions = {},
    C_Timer = {NewTicker = noop, After = function(_, fn) f.timers[#f.timers + 1] = fn end},
    C_Map = {GetBestMapForUnit = noop},
    InCombatLockdown = function() return f.combat end,
    IsEncounterInProgress = function() return f.encounter end,
    UnitName = noop, GetRealmName = noop, GetRealZoneText = noop, GetGuildInfo = noop,
    GetMinimapZoneText = noop, UnitRace = noop, UnitFactionGroup = noop, UnitClass = noop,
    UnitAffectingCombat = function() return f.combat end,
    UnitIsDeadOrGhost = no, UnitIsGroupLeader = no, UnitIsGroupAssistant = no, IsMounted = no,
    GetNumGroupMembers = function() return 1 end,
    GetInstanceTypeAndSize = function() return "raid", "normal", "raid", 100, 14 end,
    CreateEncounterTable = function(id) addon.CurrentEncounter = {id = id, zone_id = 100} end,
    DestroyEncounterTable = function() addon.CurrentEncounter = nil end,
    -- WoW's xpcall forwards arguments to the callback.
    xpcall = function(fn, handler, ...)
      local args, n = {...}, select("#", ...)
      return xpcall(function() return fn(unpack(args, 1, n)) end, handler)
    end,
  }, {__index = _G})
  if namespacedAPI then
    env.C_InstanceEncounter = {IsEncounterInProgress = env.IsEncounterInProgress}
    env.IsEncounterInProgress = function() error("legacy encounter API should not be used") end
  end
  addon.IsPaused = function() return env.paused end
  addon.ShowOptions = function()
    f.opens = f.opens + 1
    f.options.visible, env.paused = true, true
  end
  env.loadFrame = load(section(core, 'local loadFrame = CreateFrame("Frame");',
    'if M33kAuras.IsRetail() then\n  loadFrame:RegisterEvent("PLAYER_TALENT_UPDATE")')
    .. "\nreturn loadFrame", env)
  env.unitLoadFrame = frame()
  for _, event in ipairs({"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED"}) do
    env.loadFrame:RegisterEvent(event)
  end
  env.RunTriggerFunc = load(section(generic, "local function ignoreErrorHandler()", "---ScanEvents may receive")
    .. "\nreturn RunTriggerFunc", env)
  env.getGameEventFromComposedEvent = load(section(generic, "local function getGameEventFromComposedEvent", "local scannerFrame")
    .. "\nreturn getGameEventFromComposedEvent", env)
  load(section(generic, "function Private.ScanEvents(event,", "function M33kAuras.ScanEvents("), env)
  load(section(generic, "function Private.ScanEventsInternal(", "function M33kAuras.ScanEventsInternal("), env)
  load(section(generic, "function GenericTrigger.ScanWithFakeEvent(", "function HandleEvent("), env)
  load(section(generic, "function HandleEvent(", "-- WORKAROUND https://github.com/Stanzilla"), env)
  load(section(generic, "function GenericTrigger.UnloadAll()", "function GenericTrigger.Delete(")
    .. section(generic, "function LoadEvent(", "function GenericTrigger.FinishLoadUnload()"), env)
  env.triggerSystems = {env.GenericTrigger}
  env.scanForLoadsImpl = load(section(core, "local toLoad = {}", 'local loadFrame = CreateFrame("Frame")')
    .. "\nreturn scanForLoadsImpl", env)
  load(section(core, "local function UnloadAll()", "function Private.LoadDisplays("), env)
  private.LoadDisplays = env.GenericTrigger.LoadDisplays
  private.UnloadDisplays = env.GenericTrigger.UnloadDisplays
  local resume = private.Resume
  private.Resume = function()
    f.resumes = f.resumes + 1
    resume()
  end
  load(section(core, "function Private.RegisterLoadEvents()", "local function HasCustomEnvironmentLifecycle("), env)
  private.RegisterLoadEvents()
  local setOptionsFrame = load(section(options, "-- WoW APIs", "local AceGUI =")
    .. section(options, "local frame;", "local function addParents(")
    .. section(options, "function M33kAuras.HideOptions(", "local function LayoutDisplayButtons(")
    .. "\nreturn function(value) frame = value end", env)
  f.options = frame()
  setOptionsFrame(f.options)
  env.frame = f.options
  load(section(optionsFrame, '  frame:SetScript("OnHide",', "  local width, height"), env)
  for id in pairs(all) do
    data[id] = {id = id}
    local function record(event, ...)
      if event == "ENCOUNTER_START" then
        f.calls[#f.calls + 1] = {id = id, args = {...}, n = select("#", ...),
          open = addon.IsOptionsOpen(), paused = addon.IsPaused(), encounter = addon.CurrentEncounter.id}
      elseif event == "ENCOUNTER_END" then
        f.ends[#f.ends + 1] = {id = id, open = addon.IsOptionsOpen(), paused = addon.IsPaused()}
      end
      return false
    end
    env.events[id] = {{events = {"ENCOUNTER_START", "ENCOUNTER_END"}, triggerFunc = record}}
    if id == "Encounter" then
      env.events[id][1].statesParameter = "full"
      env.events[id][1].force_events = "STATUS"
      env.events[id][1].triggerFunc = function(_, ...) return record(...) end
    end
  end
  private.ScanForLoads()
  function f:emit(event, ...)
    if event == "ENCOUNTER_START" then self.encounter = true end
    if event == "ENCOUNTER_END" then self.encounter = false end
    -- Snapshot recipients so registering during delivery cannot receive this event.
    local recipients = {}
    for _, candidate in ipairs(self.frames) do
      if candidate.events[event] then recipients[#recipients + 1] = candidate end
    end
    for index = 1, #recipients do
      local recipient = recipients[self.reverseEvents and (#recipients - index + 1) or index]
      recipient.scripts.OnEvent(recipient, event, ...)
    end
  end
  function f:flush()
    local pending = self.timers
    self.timers = {}
    for _, fn in ipairs(pending) do fn() end
  end
  function f:check(expected)
    local counts = {}
    for _, call in ipairs(self.calls) do
      counts[call.id] = (counts[call.id] or 0) + 1
      T.expect(not call.open and not call.paused, call.id .. " runs with options closed and execution resumed")
      T.expect(call.encounter == 42 and call.n == 5 and call.args[1] == 42 and call.args[2] == "Boss"
        and call.args[3] == 14 and call.args[4] == 20 and call.args[5] == nil,
        call.id .. " receives the current encounter and the complete original payload")
    end
    for id in pairs(all) do
      T.expect((counts[id] or 0) == (expected[id] and 1 or 0), id .. " receives the expected number of start events")
    end
    T.expect(#self.errors == 0, "custom triggers do not raise errors")
  end
  f.addon, f.env = addon, env
  return f
end

for _, combatFirst in ipairs({false, true}) do
  T.section(combatFirst and "Combat closes options before encounter start" or "Encounter starts with options open")
  local f = fixture()
  f.addon.ShowOptions()
  f.combat = true
  if combatFirst then f:emit("PLAYER_REGEN_DISABLED") end
  f:emit("ENCOUNTER_START", 42, "Boss", 14, 20, nil)
  f:check({Always = true, Combat = true, Encounter = true})
  T.expect(f.resumes == 1, "options resume execution once")
  T.expect(f.env.Private.frames["M33kAuras Generic Trigger Frame"].events.ENCOUNTER_START
    and not f.env.loadFrame.events.ENCOUNTER_START,
    "one native handler prepares the encounter and delivers it through the normal scanner")
  f:emit("PLAYER_REGEN_DISABLED")
  T.expect(f.resumes == 1, "later combat notification does not resume a second time")
  f.combat = false
  f:emit("ENCOUNTER_END", 42)
  f:emit("PLAYER_REGEN_ENABLED")
  f:flush()
  T.expect(f.addon.IsOptionsOpen() and f.opens == 2, "options reopen after combat")
end

T.section("Encounter starts before the player enters combat")
local f = fixture()
f.addon.ShowOptions()
f:emit("ENCOUNTER_START", 42, "Boss", 14, 20, nil)
f:check({Always = true, Encounter = true})

T.section("Options were never loaded")
f = fixture()
f.combat = true
f:emit("PLAYER_REGEN_DISABLED")
f.addon.IsOptionsOpen = no
f.addon.HideOptions = nil
f:emit("ENCOUNTER_START", 42, "Boss", 14, 20, nil)
f:check({Always = true, Combat = true, Encounter = true})
T.expect(f.resumes == 0, "normal encounter start does not resume the addon")
f:emit("ENCOUNTER_END", 42)
f.calls = {}
f:emit("ENCOUNTER_START", 42, "Boss", 14, 20, nil)
f:check({Always = true, Combat = true, Encounter = true})

T.section("Manual pause without options")
f = fixture()
f.env.paused, f.combat = true, true
f:emit("ENCOUNTER_START", 42, "Boss", 14, 20, nil)
f:check({})
T.expect(f.addon.IsPaused() and f.resumes == 0, "encounter start respects a manual pause")

for _, namespacedAPI in ipairs({false, true}) do
  T.section((namespacedAPI and "Namespaced" or "Legacy") .. " API: reopen after both combat and encounter end")
  f = fixture(namespacedAPI)
  f.addon.ShowOptions()
  f.combat = true
  f:emit("ENCOUNTER_START", 42, "Boss", 14, 20, nil)
  f.combat = false
  f:emit("PLAYER_REGEN_ENABLED")
  T.expect(not f.addon.IsOptionsOpen() and f.opens == 1,
    "dropping combat during an encounter leaves options closed")
  local encounter = f.addon.CurrentEncounter
  f.addon.CurrentEncounter = nil
  f:emit("PLAYER_REGEN_ENABLED")
  T.expect(not f.addon.IsOptionsOpen(), "the game encounter query also guards against an absent encounter cache")
  f.addon.CurrentEncounter = encounter
  f:emit("ENCOUNTER_END", 42)
  T.expect(not f.addon.IsOptionsOpen(), "encounter end finishes dispatching before options reopen")
  f:flush()
  T.expect(f.addon.IsOptionsOpen() and f.opens == 2, "encounter end reopens options after an earlier combat drop")
  f:emit("PLAYER_REGEN_ENABLED")
  f:emit("ENCOUNTER_END", 42)
  f:flush()
  T.expect(f.opens == 2, "later end notifications do not reopen options again")

  f = fixture(namespacedAPI)
  f.addon.ShowOptions()
  f.combat = true
  f:emit("ENCOUNTER_START", 42, "Boss", 14, 20, nil)
  f:emit("ENCOUNTER_END", 42)
  f:flush()
  T.expect(not f.addon.IsOptionsOpen(), "an encounter ending while combat continues leaves options closed")
  f.combat = false
  f:emit("PLAYER_REGEN_ENABLED")
  T.expect(f.addon.IsOptionsOpen() and f.opens == 2, "combat ending after the encounter reopens options")

  f = fixture(namespacedAPI)
  f.reverseEvents = true
  f.addon.ShowOptions()
  f:emit("ENCOUNTER_START", 42, "Boss", 14, 20, nil)
  f:emit("ENCOUNTER_END", 42)
  local endReceived = false
  for _, call in ipairs(f.ends) do
    if call.id == "Always" then
      endReceived = not call.open and not call.paused
    end
  end
  T.expect(endReceived, "custom triggers receive encounter end even when options handle it first")
  T.expect(not f.addon.IsOptionsOpen(), "options remain closed until all encounter-end handlers finish")
  f:flush()
  T.expect(f.addon.IsOptionsOpen() and f.opens == 2, "encounters without player combat also restore options")

  f = fixture(namespacedAPI)
  f.addon.ShowOptions()
  f:emit("ENCOUNTER_START", 42, "Boss", 14, 20, nil)
  f:emit("ENCOUNTER_END", 42)
  f:emit("ENCOUNTER_START", 43, "Next Boss", 14, 20, nil)
  f:flush()
  T.expect(not f.addon.IsOptionsOpen(), "a new encounter cancels reopening from the previous encounter end")
  f:emit("ENCOUNTER_END", 43)
  f:flush()
  T.expect(f.addon.IsOptionsOpen() and f.opens == 2, "the pending reopen survives until the new encounter ends")

  f = fixture(namespacedAPI)
  f.addon.ShowOptions()
  f:emit("ENCOUNTER_START", 42, "Boss", 14, 20, nil)
  f:emit("ENCOUNTER_END", 42)
  f.combat = true
  f:emit("PLAYER_REGEN_DISABLED")
  f:flush()
  T.expect(not f.addon.IsOptionsOpen(), "combat restarting before the deferred reopen keeps options closed")
  f.combat = false
  f:emit("PLAYER_REGEN_ENABLED")
  T.expect(f.addon.IsOptionsOpen() and f.opens == 2, "options reopen when that later combat ends")

  f = fixture(namespacedAPI)
  f.addon.ShowOptions()
  f.combat = true
  f:emit("PLAYER_REGEN_DISABLED")
  f.combat = false
  f:emit("PLAYER_REGEN_ENABLED")
  T.expect(f.addon.IsOptionsOpen() and f.opens == 2, "ordinary combat still restores options without an encounter")

  f = fixture(namespacedAPI)
  f:emit("ENCOUNTER_START", 42, "Boss", 14, 20, nil)
  f:emit("ENCOUNTER_END", 42)
  f:emit("PLAYER_REGEN_ENABLED")
  f:flush()
  T.expect(not f.addon.IsOptionsOpen() and f.opens == 0, "end events do not open options without a pending request")
end

T.finish()
