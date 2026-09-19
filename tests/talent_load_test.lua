-- Check talent load expressions, class-tree metadata and picker coordinates.
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

local prototypes = readSource("M33kAuras/Prototypes.lua")
local helperStart = prototypes:find("local function talentSpecIdForLoad", 1, true)
  and "local function talentSpecIdForLoad" or "local function valuesForTalentFunction"
local loadHelpers = section(prototypes, helperStart, "Private.load_prototype =")
local talentArgs = section(prototypes, '    {\n      name = "talent",', '    {\n      name = "herotalent",')
local loadSource = loadHelpers .. "\nreturn { args = {\n" .. talentArgs .. "\n} }"
local compilerSource = section(readSource("M33kAuras/M33kAuras.lua"),
  "local function EvalBooleanArg", "function M33kAuras.GetActiveConditions") .. "\nreturn ConstructFunction"
local metadataSource = section(readSource("M33kAuras/Types_Retail.lua"),
  "local backgroundAlias", "M33kAuras.StopMotion =")
local widgetSource = "return {" .. section(readSource(
  "M33kAurasOptions/AceGUI-Widgets/AceGUIWidget-M33kAurasMiniTalent_TWW.lua"),
  "  SetList = function", "  SetDisabled = function") .. "}"

local function load(source, env)
  return setfenv(assert(loadstring(source)), env)()
end

local function environment(flavor)
  local legacy = flavor == "Classic" or flavor == "Wrath" or flavor == "Cata" or flavor == "Mists"
  local wa = {
    IsRetail = function() return flavor == "Midnight" end,
    IsForever = function() return flavor == "Forever" end,
    IsTWW = function() return flavor == "Midnight" end,
    IsClassicEra = function() return flavor == "Classic" end,
    IsWrathOrCata = function() return flavor == "Wrath" or flavor == "Cata" end,
    IsMists = function() return flavor == "Mists" end,
    IsWrathOrCataOrMists = function() return legacy and flavor ~= "Classic" end,
    IsClassicOrWrathOrCataOrMists = function() return legacy end,
    IsWrathOrCataOrMistsOrRetail = function() return flavor ~= "Classic" and flavor ~= "Forever" end,
    class_ids = { MAGE = 8, WARRIOR = 1 },
  }
  local selected = { [1001] = true, [1002] = false, [1003] = false }
  wa.CheckTalentId = function(id) return selected[id] end
  wa.CheckTalentByIndex = function(id, extra)
    if selected[id] == nil then return nil end
    return extra == 5 and not selected[id] or extra ~= 5 and selected[id]
  end
  local mageTalents = { { 1001 }, { 1002 }, { 1003 } }
  local warriorTalents = { { 2001 } }
  local private = {
    talentInfo = { MAGE = mageTalents },
    talent_types_specific = { MAGE = mageTalents },
    ExecEnv = { GetSpecializationInfoForClassID = function(classID, specIndex)
      assert(specIndex == 1, "Forever has one class tree")
      return classID == 8 and 1482 or 1491
    end },
    GetTalentData = function(specID)
      return (specID == 1482 or specID == 62) and mageTalents or warriorTalents
    end,
  }
  local env = setmetatable({
    M33kAuras = wa, Private = private, tinsert = table.insert,
    UnitClass = function() return "Mage", "MAGE" end,
    L = setmetatable({}, { __index = function(_, key) return key end }),
  }, { __index = _G })
  return env, selected, mageTalents, warriorTalents
end

for _, flavor in ipairs({ "Forever", "Midnight", "Classic", "Wrath", "Cata", "Mists" }) do
  T.section(flavor .. ": talent load conditions")
  local env, selected, mageTalents, warriorTalents = environment(flavor)
  local prototype = load(loadSource, env)
  local construct = load(compilerSource, env)
  local trigger = { use_class = true, class = { single = "MAGE" }, use_talent = false,
    talent = { multi = { [1001] = true, [1002] = false } } }
  if flavor == "Midnight" then
    trigger.use_class_and_spec, trigger.class_and_spec = true, { single = 62 }
  end
  local talent = prototype.args[1]
  T.expect(talent.enable(trigger) and not talent.hidden(trigger), "enables talents for the selected class or spec")
  T.expect(talent.values(trigger)() == mageTalents, "returns the selected class's talents")

  if flavor == "Forever" or flavor == "Midnight" then
    T.expect(talent.control == "M33kAurasMiniTalent" and talent.multiNoSingle and talent.multiTristate,
      "uses the picker with required and excluded selections")
    T.expect(talent.multiConvertKey(trigger, 2) == 1002 and talent.multiConvertKey(trigger, 99) == nil,
      "stores entry IDs instead of picker positions")
    T.expect(talent.enableTest(trigger, 1001) and not talent.enableTest(trigger, 9999),
      "validates entries against the displayed tree")
    local code, events = construct(prototype, trigger)
    local evaluate = load(code, env)
    T.expect(evaluate() and events.WA_TALENT_UPDATE, "loads when required talents are selected and excluded talents are absent")
    selected[1002] = true
    T.expect(not evaluate(), "an excluded talent blocks loading")
    selected[1002], selected[1001] = false, false
    T.expect(not evaluate(), "a missing required talent blocks loading")

    trigger.use_talent2, trigger.talent2 = false, { multi = { [1002] = true } }
    trigger.use_talent3, trigger.talent3 = false, { multi = { [1003] = true } }
    evaluate = load(construct(prototype, trigger), env)
    selected[1002] = true
    T.expect(evaluate(), "the second talent group provides an alternative")
    selected[1002], selected[1003] = false, true
    T.expect(evaluate(), "the third talent group provides an alternative")
    selected[1003] = false
    T.expect(not evaluate(), "loading fails when no talent group matches")

    trigger.talent.multi = { [9999] = true }
    trigger.use_talent2, trigger.use_talent3 = nil, nil
    T.expect(not load(construct(prototype, trigger), env)(), "unknown entry IDs cannot satisfy a talent group")

    local selector = flavor == "Forever" and "class" or "class_and_spec"
    trigger["use_" .. selector] = false
    trigger[selector] = { multi = flavor == "Forever" and { MAGE = true } or { [62] = true } }
    T.expect(talent.enable(trigger) and talent.values(trigger)() == mageTalents, "accepts a single class or spec in multiselect mode")
    trigger[selector].multi[flavor == "Forever" and "WARRIOR" or 71] = true
    T.expect(not talent.enable(trigger) and talent.hidden(trigger), "hides the picker when several trees are selected")
    trigger["use_" .. selector], trigger[selector] = true, { single = flavor == "Forever" and "WARRIOR" or 71 }
    T.expect(talent.values(trigger)() == warriorTalents, "can edit talents for a class other than the player's")
  else
    T.expect(talent.multiConvertKey == nil and talent.test:find("CheckTalentByIndex", 1, true),
      "preserves the legacy talent index path")
  end
end

for _, flavor in ipairs({ "Forever", "Midnight" }) do
  T.section(flavor .. ": talent tree metadata and layout")
  local env = environment(flavor)
  local specID = flavor == "Forever" and 1482 or 62
  local initializedLevel, previews = nil, 0
  local nodes = {}
  for i = 1, 3 do
    nodes[i] = { ID = i, entryIDs = { 1000 + i }, posX = 1400 + (i - 1) * 4000,
      posY = 2000, maxRanks = 5, visibleEdges = i == 1 and { { targetNode = 2 } } or {} }
  end
  env.Constants = { TraitConsts = { VIEW_TRAIT_CONFIG_ID = -1 } }
  env.GetMaxPlayerLevel = function() return 60 end
  env.GetNumClasses = function() return 8 end
  env.GetClassInfo = function(id) return "Mage", id == 8 and "MAGE" or "OTHER" end
  env.GetSpecializationInfoByID = function() return nil, nil, nil, nil, nil, "MAGE" end
  env.Private.ExecEnv.GetSpellName = function(id) return "Spell " .. id end
  env.C_ClassTalents = {
    InitializeViewLoadout = function(id, level)
      assert(id == specID)
      initializedLevel = level
      previews = previews + 1
    end,
    ViewLoadout = function(entries) assert(next(entries) == nil) end,
    GetHeroTalentSpecsForClassSpec = function()
      assert(flavor == "Midnight", "Forever has no hero talents")
      return {}
    end,
  }
  env.C_Traits = {
    GetConfigInfo = function() return { treeIDs = { 1 } } end,
    GetTreeNodes = function() return { 1, 2, 3 } end,
    GetNodeInfo = function(_, id) return nodes[id] end,
    GetEntryInfo = function(_, id) return { definitionID = id } end,
    GetDefinitionInfo = function(id) return { spellID = id + 10000 } end,
  }
  load(metadataSource, env)
  local talents, heroes, byNode = env.Private.GetTalentData(specID)
  T.expect(initializedLevel == (flavor == "Forever" and 60 or 70), "uses the appropriate preview level")
  T.expect(#talents == 3 and #heroes == 0 and byNode[1][1] == talents[1], "preserves all class-tree entries and node lookup")
  T.expect(talents[1][4][1] == 1002 and talents[1][5] == 5, "preserves tree connections and rank limits")
  T.expect(env.Private.GetTalentData(specID) == talents and previews == 1, "reuses cached metadata")
  T.expect(talents[999] == (flavor == "Forever" and "talent-background-mage" or "talents-background-mage-arcane"),
    "uses the flavor's talent background")
  if flavor == "Forever" then
    T.expect(talents[1000].offsetX == -11 and talents[1000].offsetY == -7, "uses Camelot's class pan offsets")
  end

  local function noop() end
  local widget = {
    frame = {}, saveSize = { fullWidth = 440 },
    buttonPool = { ReleaseAll = noop, Acquire = function()
      return { SetParent = noop, SetNormalTexture = noop, UpdateTexture = noop, ClearAllPoints = noop }
    end },
    linePool = { ReleaseAll = noop },
    background = { SetAtlas = noop, SetBlendMode = noop },
  }
  env.OptionsPrivate = { Private = env.Private }
  env.Private.ExecEnv.GetSpellInfo = function() return nil, nil, nil, nil, nil, nil, nil, 123 end
  env.TalentFrame_Update = noop
  load(widgetSource, env).SetList(widget, talents)
  T.expect(#widget.buttons == 3 and widget.talentIdToButton[1003] ~= nil, "lays out entries from all three talent groups")
  if flavor == "Forever" then
    local first, last = widget.talentIdToButton[1001], widget.talentIdToButton[1003]
    T.expect(last.posX - first.posX == 800 and first.posY == last.posY, "preserves the three groups' relative positions")
    T.expect(widget.scale == 440 / 1212 and widget.saveSize.fullHeight == 681 * widget.scale,
      "fits the Forever talent frame dimensions")
  else
    T.expect(widget.scale == 440 / 1612 and widget.saveSize.fullHeight == 856 * widget.scale * 1.3,
      "preserves the Midnight picker dimensions and zoom")
  end
end

T.finish()
