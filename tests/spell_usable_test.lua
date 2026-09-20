-- Exercise the actual Spell Usable prototype and generic trigger compiler.
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
  local start = assert(source:find(first, 1, true))
  return source:sub(start, assert(source:find(last, start, true)) - 1)
end
local function load(source, env)
  return setfenv(assert(loadstring(source)), env)()
end
local secret = newproxy(true)
for _, op in ipairs({"__add", "__sub", "__mul", "__div", "__lt", "__le", "__eq", "__tostring"}) do
  getmetatable(secret)[op] = function() error("Inspected a secret value") end
end
local ready, usable, charges, maxCharges, count, range = true, true, 2, 3, 0, 1
local observedUsableId, observedRangeId, cooldownReads = nil, nil, 0
local env = setmetatable({
  L = setmetatable({}, {__index = function(_, key) return key end}),
  M33kAuras = {
    IsWrathOrCataOrMists = function() return false end,
    GetSpellCooldown = function() cooldownReads = cooldownReads + 1; return secret, secret, nil, 10, secret, true end,
    GetSpellCharges = function() return charges, maxCharges, count, 20, 30 end,
    IsSpellReady = function() return ready end,
    IsSpellInRange = function(id) observedRangeId = id; return range end,
  },
  Private = {ExecEnv = {
    GetEffectiveSpellId = function() return 200 end,
    GetSpellInfo = function() return "Override", nil, 100 end,
    IsUsableSpell = function(id) observedUsableId = id; return usable end,
  }},
  AddTargetConditionEvents = function(events) return events end,
  tinsert = table.insert, tconcat = table.concat,
  issecretvalue = function(value) return rawequal(value, secret) end,
  hasanysecretvalues = function(...)
    for i = 1, select("#", ...) do if rawequal(select(i, ...), secret) then return true end end
    return false
  end,
}, {__index = _G})
local prototype = load("return {" .. section(read("M33kAuras/Prototypes.lua"),
  '  ["Action Usable"] = {', '  ["Talent Known"] = {') .. "}", env)["Action Usable"]
local construct = load(section(read("M33kAuras/GenericTrigger.lua"),
  "function TestForTriState", "function Private.EndEvent") .. "\nreturn ConstructFunction", env)
local function trigger(options)
  options = options or {}
  options.spellName = 100
  local fn = load(construct(prototype, options), env)
  return function(state) return fn(state or {}, "SPELL_UPDATE_USABLE") end
end
T.section("Readiness, resources, and overrides")
local normal, inverse = trigger(), trigger({use_inverse = true})
local state = {}
T.expect(normal(state) and state.stacks == 2, "ready and usable spell displays readable charges")
T.expect(observedUsableId == 200, "usability checks the same effective spell as cooldown tracking")
T.expect(state.readyTime == 10 and state.chargeGainTime == 20 and state.chargeLostTime == 30,
  "retains timestamps without calculating cooldown timing")
ready = false
T.expect(not normal() and inverse(), "cooldown prevents normal activation and allows inverse")
ready = nil
T.expect(not normal() and inverse(), "unconfirmed readiness follows the not-ready default")
ready, usable = true, false
T.expect(not normal() and inverse(), "resource requirements still prevent activation when ready")
usable = true
T.section("Secret counts and numeric filters")
charges, maxCharges, count = secret, secret, secret
T.expect(normal(state) and rawequal(state.stacks, secret), "secret counts remain usable for display")
T.expect(not trigger({use_charges = true, charges = 1, charges_operator = ">="})(),
  "charge filters reject secret values")
T.expect(not trigger({use_spellCount = true, spellCount = 1, spellCount_operator = ">="})(),
  "spell count filters reject secret values")
maxCharges = 1
T.expect(normal(state) and rawequal(state.stacks, secret), "secret spell count displays for spells without multiple charges")
charges, maxCharges, count = 2, 3, 4
T.expect(trigger({use_charges = true, charges = 2, charges_operator = "=="})(), "readable charge filters still match")
T.expect(trigger({use_spellCount = true, spellCount = 4, spellCount_operator = "=="})(), "readable spell count filters still match")
charges, maxCharges, count = nil, nil, nil
T.expect(normal(state) and state.charges == 1, "spells without charges expose one when ready")
ready = false
T.expect(not normal() and inverse(), "spells without charges still follow readiness")
T.section("Ignoring cooldown and validating targets")
local ignore = trigger({use_ignoreSpellCooldown = true})
local reads = cooldownReads
T.expect(ignore() and cooldownReads == reads, "ignoring cooldown avoids cooldown and charge tracking reads")
usable = false
T.expect(not ignore(), "ignoring cooldown still checks resources")
usable, ready = true, true
local target = trigger({use_targetRequired = true})
range = 0
T.expect(target() and observedRangeId == 200, "out-of-range valid target is accepted for the effective spell")
range = false
T.expect(target(), "boolean out-of-range result still means a valid target")
range = nil
T.expect(not target(), "invalid target fails the target requirement")
range = secret
T.expect(target(), "target validity checks presence without inspecting a secret range result")
T.finish()
