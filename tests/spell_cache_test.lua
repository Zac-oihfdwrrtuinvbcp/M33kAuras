local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")

local function setup(testBuild, forever)
  local f = { threads = {}, widgets = {}, timers = {}, queries = {}, build = "100", locale = "enUS" }
  f.spells = {
    [1] = { name = "Buff", icon = 100, aura = 0 },
    [2] = { name = "Gear Buff", icon = 136243, aura = 0 },
    [3] = { name = "No Icon", cooldown = 0 },
    [4] = { name = "Shared", icon = 100, cast = 0, cooldown = 0 },
    [5] = { name = "Shared", icon = 100, aura = 0 },
    [6] = { name = "Always", icon = 100, aura = 1, cooldown = 1, cast = 1 },
    [7] = { name = "Contextual", icon = 100 },
  }
  local api = {}
  for kind, method in pairs({ aura = "GetSpellAuraSecrecy", cooldown = "GetSpellCooldownSecrecy", cast = "GetSpellCastSecrecy" }) do
    api[method] = function(id)
      assert(f.spells[id], "only valid named spells should be classified")
      f.queries[kind] = (f.queries[kind] or 0) + 1
      return f.spells[id][kind] or 2
    end
  end
  local gui = {}
  function gui:Create(kind)
    local w = { kind = kind, children = {}, callbacks = {}, text = "", frame = {}, content = {} }
    if kind == "Frame" then f.window = w end
    local function editbox()
      return {
        scripts = { OnEscapePressed = "original" },
        SetScript = function(self, name, fn) self.scripts[name] = fn end,
        GetScript = function(self, name) return self.scripts[name] end,
      }
    end
    w.editBox, w.editbox = editbox(), editbox()
    function w:SetText(text)
      if self.text == text then return end
      self.text = text
      if self.callbacks.OnTextChanged then self.callbacks.OnTextChanged(self, "OnTextChanged", text) end
    end
    function w:GetText() return self.text end
    function w:SetCallback(event, fn) self.callbacks[event] = fn end
    function w:SetStatusText(text) self.status = text end
    function w:SetTitle(text) self.title = text end
    function w:AddChild(child) self.children[#self.children + 1] = child end
    function w:ReleaseChildren()
      for _, child in ipairs(self.children) do gui:Release(child) end
      self.children = {}
    end
    function w:SetImage(image) self.image = image end
    function w:SetImageSize(width, height) self.imageWidth, self.imageHeight = width, height end
    function w:SetDisabled(disabled) self.disabled = disabled end
    function w:SetFocus() f.focus = self end
    function w:HighlightText() self.highlighted = true end
    function w:SetScroll(value) self.scroll = value end
    for _, method in ipairs({ "SetWidth", "SetHeight", "EnableResize", "SetLayout", "SetFullWidth", "SetLabel", "DisableButton", "SetRelativeWidth", "SetJustifyH", "PauseLayout", "ResumeLayout", "DoLayout", "SetFontObject", "SetAutoAdjustHeight" }) do
      w[method] = function() end
    end
    f.widgets[#f.widgets + 1] = w
    return w
  end
  function gui:Release(w)
    assert(not w.released, "widget must only be released once")
    w.released = true
    if w.callbacks.OnClose then w.callbacks.OnClose() end
    w:ReleaseChildren()
  end
  local function createFrame(kind, _, parent, template)
    local frame = { kind = kind, parent = parent, template = template, scripts = {} }
    function frame:SetScript(event, fn) self.scripts[event] = fn end
    function frame:SetParent(value) self.parent = value end
    function frame:SetText(value) self.text = value end
    function frame:SetTexture(value) self.texture = value end
    function frame:SetSize(width, height) self.width, self.height = width, height end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:SetShown(value) self.shown = value end
    function frame:CreateTexture() return createFrame("Texture", nil, self) end
    function frame:CreateFontString() return createFrame("FontString", nil, self) end
    for _, method in ipairs({ "SetPoint", "ClearAllPoints", "SetAllPoints", "SetJustifyH", "SetWordWrap", "SetHighlightTexture" }) do
      frame[method] = function() end
    end
    return frame
  end
  -- Model Blizzard's visible-range callbacks at the integration boundary.
  -- The addon must supply all data and safely reinitialize the same pooled rows.
  local function initScrollBox(scrollBox, _, view)
    f.scrollBox = scrollBox
    scrollBox.pool = {}
    scrollBox.offset = 0
    scrollBox.providerChanges = 0
    function scrollBox:ScrollToOffset(offset)
      self.offset = offset
      for _, row in ipairs(self.pool) do view.resetter(row) end
      for i = 1, math.min(10, self.provider and #self.provider - offset or 0) do
        local row = self.pool[i] or createFrame("Button", nil, self)
        self.pool[i] = row
        view.initializer(row, self.provider[offset + i])
      end
    end
    function scrollBox:SetDataProvider(provider, retainScrollPosition)
      self.provider = provider
      self.providerChanges = self.providerChanges + 1
      self:ScrollToOffset(retainScrollPosition and self.offset or 0)
    end
    function scrollBox:RemoveDataProvider()
      self.provider = nil
      self:ScrollToOffset(0)
    end
  end
  local wa = {
    IsLibsOK = function() return true end,
    IsForever = function() return forever ~= false end,
    IsClassicEra = function() return false end,
    IsCataClassic = function() return false end,
    IsMists = function() return false end,
    IsRetail = function() return forever == false end,
    IsCataOrMistsOrRetail = function() return false end,
    versionString = "test",
    L = setmetatable({}, { __index = function(_, key) return key end }),
  }
  local private = { Private = {
    ExecEnv = {
      GetSpellName = function(id) return f.spells[id] and f.spells[id].name end,
      GetSpellIcon = function(id) return f.spells[id] and f.spells[id].icon end,
    },
    Threads = { Add = function(_, _, co) f.threads[#f.threads + 1] = co end },
  } }
  local env = setmetatable({
    M33kAuras = wa,
    C_Secrets = api,
    Enum = { SecrecyLevel = { NeverSecret = 0 } },
    IsTestBuild = function() return testBuild end,
    GetBuildInfo = function() return "test", f.build end,
    GetLocale = function() return f.locale end,
    wipe = function(t) for k in pairs(t) do t[k] = nil end end,
    LibStub = function() return gui end,
    CreateFrame = createFrame,
    UIParent = {},
    CreateScrollBoxListLinearView = function()
      return {
        SetElementExtent = function(self, value) self.extent = value end,
        SetElementInitializer = function(self, _, fn) self.initializer = fn end,
        SetElementResetter = function(self, fn) self.resetter = fn end,
      }
    end,
    CreateDataProvider = function(entries) return entries end,
    ScrollUtil = { InitScrollBoxListWithScrollBar = initScrollBox },
    GameTooltip = {
      SetOwner = function(self, owner) self.owner = owner end,
      SetSpellByID = function(self, id) self.spellId = id end,
      Show = function(self) self.shown = true end,
      Hide = function(self) self.shown = false end,
      IsOwned = function(self, owner) return self.owner == owner end,
    },
    C_Timer = { NewTicker = function(_, fn)
      local timer = { callback = fn, Cancel = function(self) self.cancelled = true end }
      f.timers[#f.timers + 1] = timer
      return timer
    end },
  }, { __index = _G })
  setfenv(assert(loadfile(T.repoRoot .. "/M33kAurasOptions/Cache.lua")), env)("M33kAurasOptions", private)
  f.cache, f.options, f.data, f.env, f.wa = wa.spellCache, private, { spellCache = {} }, env, wa
  f.cache.Load(f.data)
  function f:finish()
    local co = self.threads[#self.threads]
    while coroutine.status(co) ~= "dead" do
      local ok, err = coroutine.resume(co)
      assert(ok, err)
    end
  end
  return f
end

T.section("Classify spells during the real background scan")
local f = setup(true)
T.expect(f.data.needsRebuild, "old caches require secrecy data")
f.cache.Build()
f.cache.Build()
T.expect(#f.threads == 1 and f.data.rebuilding, "Forever test builds scan once even if requested twice")
local _, _, complete = f.cache.GetNeverSecretSpells("aura")
T.expect(not complete, "an unfinished scan is not presented as complete")
f:finish()
local auras, count, ready = f.cache.GetNeverSecretSpells("aura")
T.expect(ready and count == 3 and auras[1].id == 1 and auras[2].id == 2 and auras[3].id == 5,
  "includes never-secret auras, including gear-icon spells, in ID order")
local cooldowns, cooldownCount = f.cache.GetNeverSecretSpells("cooldown")
T.expect(cooldownCount == 2 and cooldowns[1].id == 3 and cooldowns[2].id == 4,
  "includes cooldown classifications even without an icon")
local casts, castCount = f.cache.GetNeverSecretSpells("cast")
T.expect(castCount == 1 and casts[1].id == 4, "casts have a separate classification")
T.expect(f.queries.aura == 7 and f.queries.cooldown == 7 and f.queries.cast == 7,
  "only valid named spells are queried, with no runtime secrecy checks")
T.expect(not f.data.spellCache["Gear Buff"] and not f.data.spellCache["No Icon"],
  "reference lists do not change icon-picker exclusions")
local matches = f.cache.GetNeverSecretSpells("aura", "  bUfF  ")
T.expect(#matches == 2, "name search ignores case and surrounding spaces")
matches = f.cache.GetNeverSecretSpells("aura", "5")
T.expect(#matches == 1 and matches[1].id == 5, "search finds spell IDs")
matches = f.cache.GetNeverSecretSpells("aura", "[.*")
T.expect(#matches == 0, "search text is literal, not a Lua pattern")
matches, count = f.cache.GetNeverSecretSpells("aura", "")
T.expect(#matches == 3 and count == 3, "returns all matches without a page limit")
T.expect(f.cache.GetNeverSecretSpells("aura", "  ") == matches, "equivalent searches reuse the filtered array")
f.cache.Build()
T.expect(#f.threads == 1, "completed cache is not scanned again")

T.section("Static classifications and normal cache invalidation")
local originalEntries = f.cache.GetNeverSecretSpells("aura")
f.spells[8] = { name = "New Spell", icon = 100, aura = 0 }
f.cache.AddIcon("New Spell", 8, 100)
T.expect(f.cache.GetNeverSecretSpells("aura") == originalEntries,
  "adding an icon does not invalidate static secrecy data")
f.spells[1].aura = 2
f.cache.AddIcon("Buff", 1, 100)
T.expect(f.data.neverSecretSpells.aura[1] == "Buff" and not f.data.neverSecretSpells.aura[8],
  "secrecy metadata stays unchanged until the normal cache rebuild")
T.expect(f.queries.aura == 7 and f.queries.cooldown == 7 and f.queries.cast == 7,
  "icon additions and browser searches make no extra secrecy queries")
-- Meet the existing spell-name cache size check when exercising reuse.
for i = 1, 39000 do f.data.spellCache["Cached " .. i] = {} end
f.cache.Load(f.data)
_, count, complete = f.cache.GetNeverSecretSpells("aura")
T.expect(complete and count == 3 and not f.data.needsRebuild, "saved classifications are reused on the same build")
f.build = "101"
f.cache.Load(f.data)
_, count, complete = f.cache.GetNeverSecretSpells("aura")
T.expect(count == 0 and not complete and f.data.needsRebuild, "a new game build clears stale classifications")
f.cache.Build()
f:finish()
local rebuilt = f.cache.GetNeverSecretSpells("aura")
T.expect(rebuilt ~= originalEntries and not f.data.neverSecretSpells.aura[1]
  and f.data.neverSecretSpells.aura[8] == "New Spell", "normal rebuild refreshes classifications and browser data")
f.data.rebuilding = true
f.data.neverSecretSpells.aura[99] = "Partial"
f.cache.Load(f.data)
_, count, complete = f.cache.GetNeverSecretSpells("aura")
T.expect(count == 0 and not complete and not f.data.rebuilding, "interrupted saved scans restart without stale entries")

T.section("Virtual list search, row reuse, and lifecycle")
f = setup(false)
f.options.OpenSpellSecrecyList("aura")
local window = f.window
local search, results, copy = unpack(window.children, 2, 4)
local scrollBox = f.scrollBox
local list = scrollBox.parent
T.expect(window.title == "Never-secret auras" and window.status == "Building spell list...",
  "popup labels its category and pending scan")
T.expect(#f.timers == 1 and list.empty.shown, "empty popup refreshes while scanning")
-- Populate enough data to require recycling long before the end of the list.
for id = 1000, 3999 do
  f.spells[id] = { name = "Reference Spell " .. id, icon = id, aura = 0 }
end
local pendingEntries = scrollBox.provider
for i = 1, 3999 do assert(coroutine.resume(f.threads[1])) end
f.timers[1].callback()
T.expect(scrollBox.provider == pendingEntries and #scrollBox.pool == 0,
  "partial scans do not allocate browser rows or rebuild the data provider")
local partial = f.cache.GetNeverSecretSpells("aura", "Buff")
T.expect(partial == pendingEntries, "searching an incomplete scan reuses the empty result")
f:finish()
f.timers[1].callback()
T.expect(f.timers[1].cancelled, "completion publishes the list and stops polling")
T.expect(#scrollBox.provider == 3003 and #scrollBox.pool == 10,
  "one data provider contains all matches while only the visible rows are initialized")
local firstSpell = scrollBox.pool[1]
local originalIcon, originalCopyButton = firstSpell.icon, firstSpell.copyButton
T.expect(firstSpell.icon.texture == 100 and firstSpell.icon.width == 32 and firstSpell.icon.height == 32,
  "spell rows show readable icons")
firstSpell.scripts.OnEnter()
T.expect(f.env.GameTooltip.spellId == 1 and f.env.GameTooltip.shown, "hovering a row opens the spell tooltip")
firstSpell.scripts.OnLeave()
T.expect(not f.env.GameTooltip.shown, "leaving a row hides its tooltip")
firstSpell.copyButton.scripts.OnClick()
T.expect(copy.text == "1" and copy.highlighted and f.focus == copy, "Copy ID selects the spell ID ready for Ctrl+C")
copy:SetText("accidental edit")
T.expect(copy.text == "1", "copy field rejects accidental edits")
local getEntries = f.cache.GetNeverSecretSpells
f.cache.GetNeverSecretSpells = function() error("scrolling must not query or filter the cache") end
firstSpell.scripts.OnEnter()
scrollBox:ScrollToOffset(2993)
T.expect(#scrollBox.pool == 10 and scrollBox.pool[1] == firstSpell
  and firstSpell.icon == originalIcon and firstSpell.copyButton == originalCopyButton,
  "scrolling to the end reuses the same rows, icons, and buttons")
T.expect(not f.env.GameTooltip.shown, "recycling a row clears its old tooltip")
T.expect(firstSpell.entry.id == 3990 and firstSpell.icon.texture == 3990
  and firstSpell.name.text:find("Reference Spell 3990", 1, true), "recycled rows show the current spell")
firstSpell.scripts.OnEnter()
T.expect(f.env.GameTooltip.spellId == 3990, "recycled tooltip callback reads the current spell")
scrollBox.pool[10].copyButton.scripts.OnClick()
T.expect(copy.text == "3999", "the final spell is reachable and copies its own ID")
f.cache.GetNeverSecretSpells = getEntries
local providerChanges = scrollBox.providerChanges
f.timers[1].callback()
T.expect(scrollBox.providerChanges == providerChanges and scrollBox.offset == 2993,
  "unchanged background refreshes preserve the provider and scroll position")
search:SetText("Gear")
T.expect(#scrollBox.provider == 1 and scrollBox.offset == 0 and firstSpell.entry.id == 2,
  "typing filters all entries and resets scroll to the first match")
search:SetText("no such spell")
T.expect(#scrollBox.provider == 0 and list.empty.shown and list.empty.text == "No spells match your search.",
  "empty searches have a clear message")
T.expect(firstSpell.entry == nil, "released rows discard their spell references")
search:SetText("3999")
T.expect(#scrollBox.provider == 1 and firstSpell.entry.id == 3999 and not list.empty.shown,
  "search reaches entries beyond the initial viewport")
firstSpell.scripts.OnEnter()
f.options.OpenSpellSecrecyList("cooldown")
T.expect(window.released and f.window.title == "Never-secret cooldowns", "opening another category releases the old popup")
T.expect(not f.env.GameTooltip.shown, "closing a browser hides its spell tooltip")
T.expect(search.editbox.scripts.OnEscapePressed == "original" and copy.editbox.scripts.OnEscapePressed == "original",
  "pooled edit boxes regain their original Escape handlers")
T.expect(f.scrollBox == scrollBox and scrollBox.pool[1] == firstSpell and #scrollBox.pool == 10,
  "reopening the browser reuses its ScrollBox and frame pool")
T.expect(firstSpell.icon.texture == 134400, "spells without icons use a fallback icon")
firstSpell.copyButton.scripts.OnClick()
T.expect(f.window.children[4].text == "3", "reused Copy ID callback targets the new popup")
f.window.children[2].editbox.scripts.OnEscapePressed()
T.expect(f.window.released and not list.shown and not list.onCopy and not scrollBox.provider,
  "Escape closes the popup and clears its data and callback")
f = setup(false)
f.options.OpenSpellSecrecyList("cast")
f.window.callbacks.OnClose()
T.expect(f.timers[1].cancelled, "closing an unfinished list cancels its timer")

T.section("Trigger reference buttons")
f = setup(false)
local builder, opened
f.wa.RegisterTriggerSystemOptions = function(_, fn) builder = fn end
f.wa.GetTriggerCategoryFor = function() return "combatlog" end
f.env.Mixin = function(target, values) for k, v in pairs(values) do target[k] = v end end
f.options.commonOptions = { AddCommonTriggerOptions = function() end }
f.options.AddTriggerMetaFunctions = function() end
f.options.Private.SortOrderForValues = function() return {} end
f.options.Private.category_event_prototype = { spell = { Test = true } }
f.options.Private.event_prototypes = {}
f.options.OpenSpellSecrecyList = function(kind) opened = kind end
f.options.ConstructOptions = function(prototype)
  local name = prototype.cast and "description_secretFiltersDescription" or "description_secretValuesDescription"
  return { [name] = { order = 12 }, unrelated = { order = 13 } }
end
setfenv(assert(loadfile(T.repoRoot .. "/M33kAurasOptions/GenericTrigger.lua")), f.env)("M33kAurasOptions", f.options)
for _, event in ipairs({ "Cast", "Cooldown Progress (Spell)", "Cooldown Ready (Spell)", "Charges Changed", "Action Usable", "Power" }) do
  f.options.Private.event_prototypes[event] = { cast = event == "Cast" }
  local options = builder({ id = "test", triggers = { { trigger = { type = "spell", event = event } } } }, 1)
  local _, args = next(options)
  local button = args.neverSecretSpells
  if event == "Power" then
    T.expect(not button, "unrelated triggers do not receive a spell reference button")
  else
    T.expect(button and button.order > 12 and button.order < 13, event .. " places its button after secrecy help")
    button.func()
    T.expect(opened == (event == "Cast" and "cast" or "cooldown"), event .. " opens the appropriate category")
  end
end

T.section("Disabled test-build scans")
f = setup(true, false)
f.cache.Build()
T.expect(#f.threads == 0 and not f.data.rebuilding, "existing Retail test-build scan restriction remains intact")
T.finish()
