-- Exercise the generated Totem trigger with readable and restricted slots.
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
local slots, numSlots, now, scheduled = {}, 6, 100, {}
local queriedSlots = {}
local empty = {false, "", 0, 0, 0, 1, 0}
local active = {true, "Searing Totem", 90, 30, 50, 1, 200}
local durationObject = newproxy(true)
getmetatable(durationObject).__index = function() error("Unwrapped duration object") end
active.durationObject = durationObject
local restricted = {secret, secret, secret, secret, secret, secret, secret}
restricted.durationObject = durationObject
local restrictedEmpty = {secret, secret, secret, secret, secret, secret, secret}
local env = setmetatable({
  L = setmetatable({}, {__index = function(_, key) return key end}),
  M33kAuras = {
    IsRetail = function() return false end,
    IsForever = function() return true end,
  },
  Private = {ExecEnv = {
    GetSpellName = function() return "Searing Totem" end,
    GetSpellIcon = function() return 50 end,
    ScheduleScan = function(time, event) scheduled = {time, event} end,
  }},
  FindSpellOverrideByID = function(id) return id == 100 and 200 or id end,
  GetTotemInfo = function(slot) return unpack(slots[slot] or empty, 1, 7) end,
  GetTotemDuration = function(slot)
    queriedSlots[#queriedSlots + 1] = slot
    return (slots[slot] or empty).durationObject
  end,
  issecretvalue = function(value) return rawequal(value, secret) end,
  GetNumTotemSlots = function() return numSlots end,
  GetTime = function() return now end,

}, {__index = _G})
load(section(read("M33kAuras/GenericTrigger.lua"),
  "function Private.ExecEnv.CheckTotemName", "-- Queueable Spells"), env)
local prototype = load("return {" .. section(read("M33kAuras/Prototypes.lua"),
  '  ["Totem"] = {', '  ["Item Count"] = {') .. "}", env)["Totem"]
local function trigger(options)
  return load(prototype.triggerFunction(options or {}), env)
end
local function shown(states, id) return states[id or ""] and states[id or ""].show == true end
local selected = {use_totemType = true, totemType = 1}
local normal, inverse, clones = trigger(selected), trigger({use_inverse = true}), trigger({use_clones = true})
T.section("Readable slots and secret transitions")
slots[1] = active
local states = {}
normal(states, "PLAYER_ENTERING_WORLD")
T.expect(shown(states) and states[""].expirationTime == 120 and states[""].duration == 30,
  "selected slot shows readable timing")
T.expect(states[""].name == "Searing Totem" and states[""].icon == 50 and states[""].spellId == 200,
  "stores readable name, icon, and spell ID")
slots[1] = restricted
T.expect(normal(states, "PLAYER_TOTEM_UPDATE", 2) == false and shown(states),
  "unrelated slot events leave a selected slot alone")
normal(states, "WA_SECRET_STATE_UPDATE")
T.expect(shown(states) and states[""].changed and states[""].expirationTime == nil
  and states[""].duration == nil and states[""].modRate == nil
  and states[""].progressType == "durationObject" and states[""].durationObject == durationObject,
  "secret totem displays its duration object without keeping readable timing")
T.expect(rawequal(states[""].name, secret) and rawequal(states[""].icon, secret),
  "secret names and icons are passed through for display")
normal({}, "PLAYER_ENTERING_WORLD")
T.expect(true, "fully secret slot is safe on first evaluation")
slots[1] = active
normal(states, "WA_SECRET_STATE_UPDATE")
T.expect(shown(states) and states[""].progressType == "timed" and states[""].durationObject == nil
  and states[""].expirationTime == 120, "readable timing replaces the duration object after restrictions end")
slots[1] = empty
normal(states, "PLAYER_TOTEM_UPDATE", 1)
T.expect(not shown(states), "empty slot hides its display")
slots[1] = {}
normal(states, "PLAYER_ENTERING_WORLD")
T.expect(not shown(states), "missing slot information is safe")
T.expect(rawget(env, "active") == nil, "does not leak active into the execution environment")

T.section("Inverse requires known absence")
states, slots = {}, {}
inverse(states, "PLAYER_ENTERING_WORLD")
T.expect(shown(states) and states[""].progressType == "static", "inverse displays when all slots are empty")
slots[1] = restricted
inverse(states, "WA_SECRET_STATE_UPDATE")
T.expect(not shown(states), "duration object establishes presence despite secret info")
slots[6] = active
inverse(states, "PLAYER_TOTEM_UPDATE", 6)
T.expect(not shown(states), "present secret slot prevents inverse")
slots[1] = empty
inverse(states, "PLAYER_TOTEM_UPDATE", 1)
T.expect(not shown(states), "inverse checks slots beyond the old five-slot limit")
local selectedInverse = trigger({use_totemType = true, totemType = 1, use_inverse = true})
selectedInverse(states, "PLAYER_ENTERING_WORLD")
T.expect(shown(states), "selected inverse ignores other slots")
slots[1] = restricted
selectedInverse(states, "WA_SECRET_STATE_UPDATE")
T.expect(not shown(states), "selected inverse rejects a present secret totem")

T.section("Duration object determines presence")
slots, states = {[1] = restrictedEmpty}, {}
normal(states, "PLAYER_ENTERING_WORLD")
T.expect(not shown(states), "nil duration object hides a slot even when every info field is secret")
selectedInverse(states, "PLAYER_ENTERING_WORLD")
T.expect(shown(states), "inverse matches an empty secret slot")
inverse(states, "PLAYER_ENTERING_WORLD")
T.expect(shown(states), "all-slot inverse matches when duration objects confirm every slot is empty")
slots[1] = restricted
normal(states, "PLAYER_ENTERING_WORLD")
slots[1] = restrictedEmpty
normal(states, "PLAYER_TOTEM_UPDATE", 1)
T.expect(not shown(states) and states[""].durationObject == nil, "removed secret totem clears its previous duration object")
local zeroTiming = {true, "Searing Totem", 0, 0, 50, 1, 200, durationObject = durationObject}
slots[1] = zeroTiming
normal(states, "PLAYER_ENTERING_WORLD")
T.expect(shown(states), "presence follows the duration object rather than a zero start time")

T.section("Clones and first match")
states, slots = {}, {[1] = active, [6] = active}
clones(states, "PLAYER_ENTERING_WORLD")
T.expect(shown(states, "1") and shown(states, "6"), "clones cover every exposed slot")
slots[1] = restricted
clones(states, "WA_SECRET_STATE_UPDATE")
T.expect(shown(states, "1") and shown(states, "6") and states["1"].durationObject == durationObject,
  "secret and readable clones both display")
local single = trigger()
local singleStates = {}
single(singleStates, "PLAYER_ENTERING_WORLD")
T.expect(shown(singleStates) and singleStates[""].durationObject == durationObject,
  "single display accepts the first present totem even when its details are secret")
local filteredStates = {}
trigger({use_totemName = true, totemName = "Searing Totem"})(filteredStates, "PLAYER_ENTERING_WORLD")
T.expect(shown(filteredStates) and filteredStates[""].expirationTime == 120,
  "name filter continues past a secret slot to a readable match")
numSlots = 5
clones(states, "PLAYER_ENTERING_WORLD")
T.expect(not shown(states, "6"), "removed slot no longer leaves a stale clone")
single(singleStates, "PLAYER_ENTERING_WORLD")
T.expect(shown(singleStates), "single display remains when only a present secret slot remains")
numSlots = 6

T.section("Slot-specific updates")
states, slots = {}, {[1] = active, [6] = restricted}
clones(states, "PLAYER_ENTERING_WORLD")
states["1"].changed, states["6"].changed = false, false
slots[1], queriedSlots = restricted, {}
clones(states, "PLAYER_TOTEM_UPDATE", 1)
T.expect(#queriedSlots == 1 and queriedSlots[1] == 1,
  "clone event queries only its slot")
T.expect(states["1"].changed and states["1"].durationObject == durationObject
  and states["1"].expirationTime == nil, "updated clone clears old readable timing")
T.expect(shown(states, "6") and not states["6"].changed and states["6"].durationObject == durationObject,
  "unrelated clone keeps its visibility, timing, and changed flag")
slots[1] = empty
clones(states, "PLAYER_TOTEM_UPDATE", 1)
T.expect(not shown(states, "1") and states["1"].durationObject == nil and shown(states, "6"),
  "removing one clone leaves other clones visible")
slots[2] = active
clones(states, "PLAYER_TOTEM_UPDATE", 2)
T.expect(shown(states, "2") and shown(states, "6"), "slot event creates a new clone")
local filteredClones = trigger({use_clones = true, use_totemName = true, totemName = "Searing Totem"})
states, slots = {}, {[1] = active, [2] = active}
filteredClones(states, "PLAYER_ENTERING_WORLD")
slots[1] = restricted
filteredClones(states, "PLAYER_TOTEM_UPDATE", 1)
T.expect(not shown(states, "1") and shown(states, "2"), "newly secret filter hides only the affected clone")
singleStates, slots = {}, {[1] = active, [6] = restricted}
single(singleStates, "PLAYER_ENTERING_WORLD")
slots[1] = empty
single(singleStates, "PLAYER_TOTEM_UPDATE", 1)
T.expect(shown(singleStates) and singleStates[""].durationObject == durationObject,
  "removing first match selects another slot")
slots[1] = active
single(singleStates, "PLAYER_TOTEM_UPDATE", 1)
T.expect(singleStates[""].expirationTime == 120 and singleStates[""].durationObject == nil,
  "new earlier match takes priority")
slots[1] = empty
inverse(states, "PLAYER_TOTEM_UPDATE", 1)
T.expect(not shown(states), "all-slot inverse still considers other occupied slots")

T.section("Readable filters and restricted values")
local filters = {
  {use_totemName = true, totemName = "Searing Totem"},
  {use_totemNamePattern = true, totemNamePattern = "Searing", totemNamePattern_operator = "find('%s')"},
  {use_icon = true, icon = 50, icon_operator = "=="},
  {use_totemSpellId = true, totemSpellId = 100},
}
for _, options in ipairs(filters) do
  slots, states = {[1] = active}, {}
  local fn = trigger(options)
  fn(states, "PLAYER_ENTERING_WORLD")
  T.expect(shown(states), "readable " .. next(options) .. " filter matches on Forever")
  slots[1] = restricted
  fn(states, "WA_SECRET_STATE_UPDATE")
  T.expect(not shown(states), "filter hides when totem becomes secret")
  options.use_inverse = true
  fn = trigger(options)
  fn(states, "PLAYER_ENTERING_WORLD")
  T.expect(not shown(states), "inverse filter cannot match secret information")
end
slots, states = {[1] = active}, {}
trigger({use_totemSpellId = true, totemSpellId = 100, use_ignoreoverride = true})(states, "PLAYER_ENTERING_WORLD")
T.expect(not shown(states), "Ignore Spell Override requires the exact ID")
trigger({use_totemName = true, totemName = "Other", use_inverse = true})(states, "PLAYER_ENTERING_WORLD")
T.expect(shown(states), "readable nonmatching totem allows inverse")
T.section("Inverse clears previous secret progress")
slots, states = {[1] = restricted}, {}
normal(states, "PLAYER_ENTERING_WORLD")
slots[1] = active
trigger({use_totemName = true, totemName = "Other", use_inverse = true})(states, "PLAYER_ENTERING_WORLD")
T.expect(shown(states) and states[""].durationObject == nil and states[""].progressType == "static",
  "readable name mismatch permits inverse and clears old secret progress")

T.section("Remaining time and option availability")
slots, states = {[1] = active}, {}
local remaining = trigger({use_remaining = true, remaining = 10, remaining_operator = "<"})
remaining(states, "PLAYER_ENTERING_WORLD")
T.expect(not shown(states) and scheduled[1] == 110 and scheduled[2] == "COOLDOWN_REMAINING_CHECK",
  "remaining-time filter schedules its threshold")
now = 111
remaining(states, "COOLDOWN_REMAINING_CHECK")
T.expect(shown(states), "scheduled scan activates the remaining-time match")
slots[1] = restricted
remaining(states, "WA_SECRET_STATE_UPDATE")
T.expect(not shown(states), "remaining-time display hides when timing becomes secret")
for _, option in ipairs(prototype.args) do
  if option.name == "totemSpellId" then T.expect(option.enable, "Forever exposes the Spell ID option") end
  if option.name == "ignoreoverride" then
    T.expect(option.enable({use_totemSpellId = true}), "Forever exposes Ignore Spell Override")
  end
end
local listensForRestrictions = false
for _, event in ipairs(prototype.internal_events) do
  if event == "WA_SECRET_STATE_UPDATE" then listensForRestrictions = true end
end
T.expect(listensForRestrictions, "reevaluates on secrecy changes beyond combat events")
T.finish()
