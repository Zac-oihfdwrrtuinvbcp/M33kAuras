-- Exercise the talent cache and its login/event wiring with real addon code.
local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")

local function readSource(path)
  local file = assert(io.open(T.repoRoot .. "/" .. path))
  local source = file:read("*a"):gsub("\r\n", "\n")
  file:close()
  return source
end

-- These sections are embedded in large files with unrelated initialization.
-- Load their unchanged source in an isolated environment for each flavor.
local prototypes = readSource("M33kAuras/Prototypes.lua")
local start = assert(prototypes:find("table.sort(M33kAuras.classes_sorted)", 1, true))
local finish = assert(prototypes:find("function M33kAuras.CheckPvpTalentBySpellId", start, true))
local talentSource = prototypes:sub(start, finish - 1)
local generic = readSource("M33kAuras/GenericTrigger.lua")
local handleEventSource = assert(generic:match("(function HandleEvent%(.-)\n%-%- WORKAROUND"))

local function setup(flavor)
  local state = { configID = 1, timers = {}, loads = 0, scans = 0, metadataRefreshes = 0 }
  local definitions = { [101] = 1001, [102] = 1002, [103] = 1003, [104] = 1004, [105] = 1005 }
  local trees = {
    [1] = { 11, 12, 13, 14, 15, 16 },
    [2] = { 21, 22 },
  }
  local nodes = {
    [11] = { ID = 11, entryIDs = { 101, 102 }, activeRank = 1, activeEntry = { entryID = 101, rank = 1 } },
    [12] = { ID = 12, entryIDs = { 103 }, activeRank = 3 },
    [13] = { ID = 13, entryIDs = { 104 }, activeRank = 0 },
    [14] = { ID = 14, entryIDs = { 105 }, activeRank = 1, subTreeID = 7 },
    [15] = { ID = 15, entryIDs = { 106 }, activeRank = 1 }, -- no spell definition
    [16] = { ID = 0 }, -- unavailable node
    [21] = { ID = 21, entryIDs = { 101, 102 }, activeRank = 1, activeEntry = { entryID = 102, rank = 1 } },
    [22] = { ID = 22, entryIDs = { 103 }, activeRank = 0 },
  }
  local wa = {
    classes_sorted = {},
    IsRetail = function() return flavor == "Midnight" end,
    IsForever = function() return flavor == "Forever" end,
    IsClassicOrWrathOrCata = function() return flavor == "Classic" or flavor == "Wrath" or flavor == "Cata" end,
    IsMists = function() return flavor == "Mists" end,
    IsPaused = function() return false end,
  }
  local private = {
    frames = {},
    talentInfo = { [1482] = "old metadata" },
    StartProfileSystem = function() end,
    StopProfileSystem = function() end,
    ScanForLoads = function(_, event)
      if event == "WA_TALENT_UPDATE" then state.loads = state.loads + 1 end
    end,
    ScanEvents = function(event)
      if event == "WA_TALENT_UPDATE" then state.scans = state.scans + 1 end
    end,
    CheckCooldownReady = function() end,
    PreShowModels = function() end,
    ExecEnv = {
      GetSpecialization = function() return 1 end,
      GetSpecializationInfo = function() return 1482 end,
      GetSpellInfo = function(id) return "Spell " .. id, nil, id + 10000 end,
      GetTalentInfo = function() return "Legacy talent", nil, nil, nil, 1 end,
    },
  }
  private.GetTalentData = function(specID)
    assert(specID == 1482 and private.talentInfo[specID] == nil, "invalidate metadata before rebuilding")
    state.metadataRefreshes = state.metadataRefreshes + 1
    private.talentInfo[specID] = "new metadata"
  end
  local env = setmetatable({
    M33kAuras = wa,
    Private = private,
    MAX_NUM_TALENTS = 20,
    ceil = math.ceil,
    CreateFrame = function()
      local frame = { events = {} }
      function frame:RegisterEvent(event) self.events[event] = true end
      function frame:SetScript(script, callback) self[script] = callback end
      function frame:Fire(event)
        assert(self.events[event], "event must be registered: " .. event)
        self:OnEvent(event)
      end
      return frame
    end,
    C_ClassTalents = { GetActiveConfigID = function() return state.configID end },
    C_Traits = {
      GetConfigInfo = function(configID) return trees[configID] and { treeIDs = { configID } } end,
      GetTreeNodes = function(treeID) return trees[treeID] end,
      GetNodeInfo = function(_, nodeID) return nodes[nodeID] end,
      GetEntryInfo = function(_, entryID) return { definitionID = definitions[entryID] } end,
      GetDefinitionInfo = function(definitionID) return { spellID = definitionID } end,
      GetSubTreeInfo = function() return { isActive = false } end,
    },
    C_SpecializationInfo = { GetTalentInfo = function() return { selected = true } end },
    C_Timer = { After = function(_, callback) table.insert(state.timers, callback) end },
    timer = { ScheduleTimer = function(_, callback, delay)
      if delay == 0.8 then callback() end
    end },
  }, { __index = _G })
  setfenv(assert(loadstring(talentSource, "@talent cache in Prototypes.lua")), env)()
  setfenv(assert(loadstring(handleEventSource, "@HandleEvent in GenericTrigger.lua")), env)()
  return wa, private, state, env
end

for _, flavor in ipairs({ "Midnight", "Forever" }) do
  T.section(flavor .. ": selected talent cache")
  local wa, private, state, env = setup(flavor)
  local frame = private.frames["M33kAuras talentCheckFrame"]
  if T.expect(frame ~= nil, "registers the modern talent watcher") then
    frame:Fire("PLAYER_LOGIN")
    T.expect(wa.CheckTalentId(101) and not wa.CheckTalentId(102), "only the chosen entry of a choice node is selected")
    local name, icon, spellID, rank = wa.GetTalentById(103)
    T.expect(name == "Spell 1003" and icon == 11003 and spellID == 1003 and rank == 3,
      "retains spell metadata and multiple ranks")
    T.expect(not wa.CheckTalentId(104) and not wa.CheckTalentId(105), "unlearned and inactive subtree talents are not selected")
    T.expect(wa.GetTalentById(106) == nil and wa.GetTalentById(999) == nil, "ignores entries without spells and unknown talents")
    T.expect(state.loads == 1 and state.scans == 1, "refreshes load conditions and triggers after caching")

    state.configID = 2
    frame:Fire(flavor == "Forever" and "ACTIVE_TALENT_GROUP_CHANGED" or "PLAYER_SPECIALIZATION_CHANGED")
    T.expect(not wa.CheckTalentId(101) and wa.CheckTalentId(102), "switching configurations replaces the selected choice")
    T.expect(not wa.CheckTalentId(103) and wa.GetTalentById(104) == nil, "switching configurations removes old ranks and entries")
    if flavor == "Forever" then
      state.configID = 1
      frame:Fire("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
      T.expect(wa.CheckTalentId(101) and not wa.CheckTalentId(102), "handles the modern specialization event too")
    end

    frame:Fire("PLAYER_TALENT_UPDATE")
    if T.expect(#state.timers == 1, "a frame event schedules the delayed metadata refresh") then
      table.remove(state.timers, 1)()
      T.expect(state.metadataRefreshes == 1, "invalidates and rebuilds metadata after a talent update")
    end

    state.configID = nil
    frame:Fire("TRAIT_CONFIG_UPDATED")
    T.expect(wa.GetTalentById(101) == nil, "clears cached selections when there is no active configuration")
    state.configID = 99
    frame:Fire("TRAIT_CONFIG_CREATED")
    T.expect(wa.GetTalentById(101) == nil, "tolerates configuration data that is not ready")

    state.configID = 1
    local previousRefreshes = state.metadataRefreshes
    env.HandleEvent({}, "PLAYER_ENTERING_WORLD")
    T.expect(wa.CheckTalentId(101), "the delayed login scan recovers selections when talent data becomes available")
    if T.expect(#state.timers == 1, "the delayed login scan also schedules metadata refresh") then
      table.remove(state.timers, 1)()
      T.expect(state.metadataRefreshes == previousRefreshes + 1, "the delayed login scan rebuilds metadata")
    end
  end
end

for _, flavor in ipairs({ "Classic", "Wrath", "Cata", "Mists" }) do
  T.section(flavor .. ": legacy talent handling")
  local wa, private = setup(flavor)
  T.expect(private.frames["M33kAuras talentCheckFrame"] == nil, "does not register the modern watcher")
  T.expect(wa.CheckTalentByIndex(1, 4) == true and wa.CheckTalentByIndex(1, 5) == false,
    "retains the legacy talent and inverse checks")
end

T.finish()
