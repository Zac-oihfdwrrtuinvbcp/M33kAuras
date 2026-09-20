-- Test the actual browser against a visible-row ScrollBox boundary model.
local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")
-- Use AceGUI's real open handler by default so unsupported header items cannot
-- silently pass through an oversimplified dropdown stub.
local dropdownFile = assert(io.open(T.repoRoot .. "/M33kAurasOptions/Libs/AceGUI-3.0/widgets/AceGUIWidget-DropDown.lua"))
local dropdownSource = dropdownFile:read("*a")
dropdownFile:close()
local openStart = assert(dropdownSource:find("local function OnPulloutOpen", 1, true))
local openEnd = assert(dropdownSource:find("local function OnPulloutClose", openStart, true))
local defaultPulloutOpen = assert(loadstring(dropdownSource:sub(openStart, openEnd - 1) .. "\nreturn OnPulloutOpen"))()
local f = {widgets = {}}
local gui = {}
local widgetVersions = {}
function gui:GetWidgetVersion(kind) return widgetVersions[kind] end
function gui:RegisterWidgetType(kind, constructor, version) widgetVersions[kind] = version end
function gui:Create(kind)
  local w = { kind = kind, children = {}, callbacks = {}, text = "", frame = {}, content = {} }
  if kind == "Frame" then f.window = w end
  if kind == "Dropdown" then
    w.pullout = {userdata = {obj = w}, items = {}, callbacks = {OnOpen = defaultPulloutOpen}}
    function w.pullout:SetCallback(event, fn) self.callbacks[event] = fn end
    function w.pullout:IterateItems() return ipairs(self.items) end
    function w.pullout:Open() self.callbacks.OnOpen(self) end
  end
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
  function w:Fire(event, ...) if self.callbacks[event] then self.callbacks[event](self, event, ...) end end
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
  function w:SetList(values, order)
    self.values, self.order = values, {}
    self.pullout.items = {}
    for _, value in ipairs(order) do self:AddItem(value, values[value]) end
  end
  function w:AddItem(value, text, itemType)
    self.values[value] = text
    self.order[#self.order + 1] = value
    self.itemTypes = self.itemTypes or {}
    self.itemTypes[value] = itemType
    local item = {userdata = {value = value}}
    if not itemType then
      function item:SetValue(checked) self.checked = checked end
    end
    self.pullout.items[#self.pullout.items + 1] = item
  end
  function w:SetValue(value) self.value = value end
  function w:GetValue() return self.value end
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
  function frame:SetWidth(value) self.width = value end
  function frame:SetColorTexture(...) self.color = {...} end
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
  function scrollBox:ForEachFrame(fn)
    for i = 1, math.min(10, self.provider and #self.provider - self.offset or 0) do fn(self.pool[i]) end
  end
  function scrollBox:RemoveDataProvider()
    self.provider = nil
    self:ScrollToOffset(0)
  end
end

local core, options = {}, {}
options.Private = core
local env = setmetatable({
  M33kAuras = {
    IsLibsOK = function() return true end, IsForever = function() return true end,
    L = setmetatable({}, {__index = function(_, key) return key end}),
  },
  LibStub = function() return gui end, CreateFrame = createFrame, UIParent = {},
  CreateDataProvider = function(rows) return rows end,
  CreateScrollBoxListLinearView = function()
    return {
      SetElementExtent = function(self, value) self.extent = value end,
      SetElementInitializer = function(self, _, fn) self.initializer = fn end,
      SetElementResetter = function(self, fn) self.resetter = fn end,
    }
  end,
  ScrollUtil = {InitScrollBoxListWithScrollBar = initScrollBox},
  GameTooltip = {
    SetOwner = function(self, owner) self.owner = owner end,
    SetText = function(self, text) self.text = text end,
    AddLine = function() end,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
    IsOwned = function(self, owner) return self.owner == owner end,
  },
}, {__index = _G})
setfenv(assert(loadfile(T.repoRoot .. "/M33kAuras/Encounters_Forever.lua")), env)("M33kAuras", core)
local catalog = core.BuildForeverEncounterLists()
core.GetForeverEncounters = function() return catalog end
setfenv(assert(loadfile(T.repoRoot .. "/M33kAurasOptions/OptionsFrames/EncounterBrowser.lua")), env)("Options", options)

T.section("Search and filtering")
local all = options.GetEncounterBrowserEntries()
T.expect(#all > 250, "all encounters are available without paging")
local found = options.GetEncounterBrowserEntries(0, "  MOLTEN ragnaros  ")
T.expect(#found == 1 and found[1].ids == "672", "search combines case-insensitive boss and instance words")
T.expect(options.GetEncounterBrowserEntries(0, "molten ragnaros") == found, "repeated searches reuse their results")
found = options.GetEncounterBrowserEntries(48, "2916")
T.expect(#found == 1 and found[1].name == "Ghamoo-ra" and found[1].ids == "2761, 2916",
  "search finds alternate IDs while preserving the full set for copying")
T.expect(#options.GetEncounterBrowserEntries(409, "2916") == 0, "instance filter combines with search")
T.expect(#options.GetEncounterBrowserEntries(0, "[%") == 0, "search treats Lua pattern characters literally")
T.expect(#options.GetEncounterBrowserEntries(409, "") == 10, "instance filter shows its full encounter list")

T.section("Rows, copying, and lifecycle")
options.OpenEncounterBrowser()
local window = f.window
local search, filter, copy = window.children[1], window.children[2], window.children[4]
local scroll = f.scrollBox
T.expect(#scroll.provider == #all and #scroll.pool == 10, "all data is loaded with only visible rows created")
T.expect(filter.order[1] == 0 and filter.values[2959], "instance selector includes All and Forever's new dungeons")
T.expect(filter.order[2] == "raid" and filter.itemTypes.raid == "Dropdown-Item-M33kAurasEncounterHeader"
  and filter.itemTypes.party == "Dropdown-Item-M33kAurasEncounterHeader", "dropdown distinguishes raids and dungeons with dedicated nonselectable headers")
local reachedDungeons, raidCount, dungeonCount = false, 0, 0
for _, mapId in ipairs(filter.order) do
  if mapId == "party" then reachedDungeons = true end
  if type(mapId) == "number" and mapId ~= 0 then
    assert(catalog[mapId].instanceType == (reachedDungeons and "party" or "raid"), "wrong instance group")
    if reachedDungeons then dungeonCount = dungeonCount + 1 else raidCount = raidCount + 1 end
  end
end
T.expect(raidCount == 9 and dungeonCount == 23, "all nine raid/world-boss maps precede all 23 dungeon maps")
reachedDungeons = false
for _, entry in ipairs(all) do
  if entry.instanceType == "party" then reachedDungeons = true end
  assert(not reachedDungeons or entry.instanceType == "party", "raid result follows a dungeon")
end
T.expect(true, "encounter results also place raids before dungeons")
local opened = 0
filter:SetCallback("OnOpened", function() opened = opened + 1 end)
local function checkSelection(expected)
  filter:SetValue(expected)
  filter.pullout:Open()
  local checked = 0
  for _, item in filter.pullout:IterateItems() do
    if item.checked then
      checked = checked + 1
      assert(item.userdata.value == expected, "wrong instance has a checkmark")
    end
  end
  return checked == 1
end
T.expect(checkSelection(0), "opening the grouped dropdown checks only All Instances")
T.expect(checkSelection(409), "reopening checks the chosen raid and clears the previous check")
T.expect(checkSelection(2959), "check state updates for a dungeon after both headers")
T.expect(checkSelection(0), "returning to All Instances clears the dungeon check")
T.expect(filter.open and opened == 4, "preserves AceGUI's open state and OnOpened callback")
local firstRow = scroll.pool[1]
local row = firstRow
row.scripts.OnClick()
T.expect(copy.text == row.entry.ids and copy.highlighted and f.focus == copy,
  "row selection highlights the encounter IDs for Ctrl+C")
T.expect(row.selection.shown, "selected row has a persistent highlight")
copy:SetText("edited")
T.expect(copy.text == row.entry.ids, "copy field cannot silently replace the selected IDs")
row.scripts.OnEnter()
T.expect(env.GameTooltip.shown and env.GameTooltip.text == row.entry.name, "tooltip shows the full encounter name")
scroll:ScrollToOffset(20)
T.expect(scroll.pool[1] == firstRow and #scroll.pool == 10, "scrolling reuses existing row frames")
T.expect(not env.GameTooltip.shown and not row.selection.shown, "recycling clears the old tooltip and highlight")
row.copyButton.scripts.OnClick()
T.expect(copy.text == row.entry.ids, "recycled Copy button uses its current encounter")
search:SetText("Ghamoo-ra")
T.expect(scroll.offset == 0 and #scroll.provider == 1 and copy.text == "", "search resets scroll and clears stale copied IDs")
row.copyButton.scripts.OnClick()
T.expect(copy.text == "2761, 2916", "copies all IDs for an encounter together")
filter:SetValue(409)
filter.callbacks.OnValueChanged()
T.expect(#scroll.provider == 0 and copy.text == "", "filter changes clear selection when there are no matches")
T.expect(scroll.parent.empty.shown, "empty results have an explanatory message")
search:SetText("")
T.expect(#scroll.provider == 10 and not scroll.parent.empty.shown, "clearing search retains the instance filter")
row.scripts.OnEnter()
copy.editbox.scripts.OnEscapePressed()
T.expect(window.released and scroll.provider == nil and not env.GameTooltip.shown, "Escape releases the popup and clears row state")
T.expect(copy.editbox.scripts.OnEscapePressed == "original", "restores handlers before returning widgets to AceGUI")
options.OpenEncounterBrowser()
T.expect(f.scrollBox == scroll and scroll.pool[1] == firstRow, "reopening reuses the list and its frame pool")
T.expect(#scroll.provider == #all and f.window.children[4].text == "", "reopening starts with all encounters and no stale selection")
local previous = f.window
options.OpenEncounterBrowser()
T.expect(previous.released and not f.window.released, "opening again replaces the popup without duplicate windows")
f.window.callbacks.OnClose()
T.finish()
