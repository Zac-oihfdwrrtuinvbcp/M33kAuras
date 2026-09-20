local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")
local function read(path)
  local file = assert(io.open(T.repoRoot .. "/" .. path))
  local source = file:read("*a"):gsub("\r\n", "\n")
  file:close()
  return source
end
local types = read("M33kAuras/Types_Retail.lua")
types = types:sub(1, assert(types:find("local backgroundAlias", 1, true)) - 1)
local generated = read("M33kAuras/Encounters_Forever.lua")
local optionsSource = read("M33kAurasOptions/LoadOptions.lua")
optionsSource = optionsSource:sub(assert(optionsSource:find("local function AddEncounterReference", 1, true)),
  assert(optionsSource:find("function OptionsPrivate.GetLoadOptions", 1, true)) - 1)
local L = setmetatable({}, {__index = function(_, key) return key end})
for _, forever in ipairs({true, false}) do
  T.section(forever and "Forever encounter reference" or "Midnight journal reference")
  local private, opened, journalCalls, tier = {}, 0, 0, 3
  local env = setmetatable({
    M33kAuras = {
      newFeatureString = "",
      L = L, IsLibsOK = function() return true end, IsForever = function() return forever end,
    },
    OptionsPrivate = {Private = private, OpenEncounterBrowser = function() opened = opened + 1 end}, L = L,
    EJ_GetCurrentTier = function() journalCalls = journalCalls + 1; return tier end,
    EJ_GetNumTiers = function() return 4 end,
    EJ_SelectTier = function(value) tier = value end,
    EJ_GetTierInfo = function() return "Current expansion" end,
    EJ_GetInstanceByIndex = function(index, raid) if index == 1 and raid then return 100 end end,
    EJ_SelectInstance = function() end,
    EJ_GetInstanceInfo = function() return "Retail Raid", nil, nil, nil, nil, nil, 200 end,
    EJ_GetEncounterInfoByIndex = function(index)
      if index == 1 then return "Retail Boss", nil, nil, nil, nil, nil, 300 end
    end,
    C_Map = {GetMapGroupID = function() return nil end},
  }, {__index = _G})
  local function load(source) return setfenv(assert(loadstring(source)), env)("M33kAuras", private) end
  load(generated)
  load(types)
  private.InitializeEncounterAndZoneLists()
  local addOptions = load(optionsSource .. "\nreturn AddEncounterReference")
  local data = {id = "test", load = {encounterid = "672", use_encounterid = true}}
  local options = {encounterid = {order = 10, hidden = false}, enabledBossModID = {order = 12, hidden = true}}
  addOptions(options, data)
  if forever then
    T.expect(journalCalls == 0, "Forever initializes without calling the Encounter Journal")
    local instances = private.GetForeverEncounters()
    local count = 0
    for _ in pairs(instances) do count = count + 1 end
    T.expect(count == 32, "lists the reviewed 32 instance maps")
    T.expect(instances[2959] and instances[2998] and instances[2999] and instances[3065],
      "includes all four new dungeons from the Forever LFG catalog")
    T.expect(not instances[13] and not instances[2856] and not instances[3002],
      "omits test, SoD-only, and unlisted new maps")
    local ids = {}
    local encounterCount = 0
    for _, instance in pairs(instances) do
      for _, encounter in ipairs(instance.encounters) do
        local id, name = encounter[1], encounter[2]
        assert(type(id) == "number" and type(name) == "string" and #encounter == 2)
        assert(not ids[id], "Encounter IDs must be unique")
        ids[id] = name
        encounterCount = encounterCount + 1
      end
    end
    T.expect(encounterCount == 282, "catalog exposes all IDs as individual {id, localizedName} entries")
    T.expect(ids[672] == "Ragnaros", "uses DungeonEncounter IDs")
    T.expect(not ids[3018], "omits the extra SoD Molten Core encounter")
    T.expect(ids[2761] == "Ghamoo-ra" and ids[2916] == "Ghamoo-ra",
      "retains multiple normal-difficulty IDs")
    T.expect(not ids[2697], "excludes SoD dungeon variants")
    T.expect(private.GetForeverEncounters() == instances, "reuses initialized reference data")
    T.expect(private.get_zoneId_list() == "", "does not confuse instance map IDs with zone IDs")
    options.encounterReference.func()
    T.expect(opened == 1, "reference button opens the encounter browser")
    T.expect(options.encounterReferenceList == nil, "does not embed a long reference in the load panel")
    T.expect(data.load.encounterid == "672" and data.load.encounterReference == nil,
      "browsing never changes aura load conditions")
    T.expect(not options.encounterReference.hidden(), "reference is visible with the Encounter ID field")
    options.encounterid.hidden = true
    T.expect(options.encounterReference.hidden(), "reference hides when both related fields are hidden")
    options.enabledBossModID.hidden = function() return false end
    T.expect(not options.encounterReference.hidden(), "reference also works with only the boss-mod field")
  else
    T.expect(private.BuildForeverEncounterLists == nil, "Midnight skips the generated Forever data")
    T.expect(private.get_encounters_list():find("Retail Boss: 300", 1, true), "Midnight still uses journal encounters")
    T.expect(private.get_zoneId_list():find("Retail Raid: 200", 1, true), "Midnight still builds its zone list")
    T.expect(tier == 3, "restores the selected journal tier")
    T.expect(options.encounterReference == nil, "Midnight options are unchanged")
  end
end
local toc = read("M33kAuras/M33kAuras.toc")
T.expect(toc:find("Encounters_Forever.lua", 1, true) < toc:find("Types_Retail.lua", 1, true),
  "generated reference loads before its consumer")
T.finish()
