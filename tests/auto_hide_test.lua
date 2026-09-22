-- Exercise auto-hide scheduling when a state changes its progress type.
local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")
local file = assert(io.open(T.repoRoot .. "/M33kAuras/M33kAuras.lua"))
local source = file:read("*a")
file:close()
local first = assert(source:find("local function stopAutoHideTimer", 1, true))
local last = assert(source:find("local function ApplyStateToRegion", first, true))
local queued, updates, watched = {}, 0, 0
local env = setmetatable({
  timers = {},
  timer = {
    ScheduleTimerFixed = function(_, callback, delay)
      local handle = {callback = callback, delay = delay}
      queued[#queued + 1] = handle
      return handle
    end,
    CancelTimer = function(_, handle) handle.cancelled = true end,
  },
  GetTime = function() return 100 end,
  issecretvalue = function() return false end,
  Private = {
    watched_trigger_events = {aura = {[1] = true}},
    AddToWatchedTriggerDelay = function() watched = watched + 1 end,
    UpdatedTriggerState = function() updates = updates + 1 end,
  },
}, {__index = _G})
local update = setfenv(assert(loadstring(source:sub(first, last - 1)
  .. "\nreturn startStopTimers")), env)()
local function runDueTimers()
  for _, handle in ipairs(queued) do
    if not handle.cancelled and not handle.fired then
      handle.fired = true
      handle.callback()
    end
  end
end

T.section("Progress type transitions")
for _, progressType in ipairs({"durationObject", "static"}) do
  local state = {show = true, autoHide = true, progressType = "timed", duration = 20, expirationTime = 120}
  update("aura", progressType, 1, state)
  local original = queued[#queued]
  T.expect(original.delay == 20, "timed state schedules auto-hide")
  state.progressType = progressType
  state.durationObject = progressType == "durationObject" and newproxy() or nil
  local count = #queued
  update("aura", progressType, 1, state)
  T.expect(original.cancelled and #queued == count, progressType .. " cancels old auto-hide without scheduling another")
  runDueTimers()
  T.expect(state.show, progressType .. " stays shown after the old timer would fire")
  state.show = true
  state.progressType = "timed"
  update("aura", progressType, 1, state)
  T.expect(#queued == count + 1 and not queued[#queued].cancelled,
    "switching back to timed reschedules even with the same expiration")
  state.show = false
  update("aura", progressType, 1, state)
end

T.section("Boolean auto-hide only uses timed progress")
for _, progressType in ipairs({"durationObject", "static", "none"}) do
  local state = {show = true, autoHide = true, progressType = progressType, duration = 20}
  local count = #queued
  update("aura", progressType, 1, state)
  T.expect(#queued == count and state.expirationTime == nil,
    progressType .. " does not derive an expiration from leftover duration")
end

T.section("Existing timer behavior")
local timed = {show = true, autoHide = true, progressType = "timed", duration = 15}
update("aura", "timed", 1, timed)
T.expect(timed.expirationTime == 115 and queued[#queued].delay == 15,
  "timed progress retains duration-only fallback")
local handle = queued[#queued]
timed.paused = true
update("aura", "timed", 1, timed)
T.expect(handle.cancelled, "pausing timed progress cancels auto-hide")

local explicit = {show = true, autoHide = 130, progressType = "durationObject", expirationTime = 105, paused = true}
update("aura", "explicit", 1, explicit)
T.expect(queued[#queued].delay == 30, "explicit auto-hide timestamp works independently of progress type and pause")
updates, watched = 0, 0
runDueTimers()
T.expect(not explicit.show and explicit.changed and updates == 1 and watched == 1,
  "explicit timer hides the state and notifies watched triggers")

local other = {show = true, autoHide = true, progressType = "timed", expirationTime = 140}
update("aura", "other", 1, other)
handle = queued[#queued]
explicit.show, explicit.autoHide = true, true
update("aura", "explicit", 1, explicit)
T.expect(not handle.cancelled, "cancelling one clone's timer leaves other clones alone")
other.autoHide = false
update("aura", "other", 1, other)
T.expect(handle.cancelled, "disabling auto-hide still cancels a timed state's timer")
T.finish()
