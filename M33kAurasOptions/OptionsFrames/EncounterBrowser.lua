if not M33kAuras.IsLibsOK() then return end
local _, OptionsPrivate = ...
local L = M33kAuras.L

local entries, instances, instanceOrder, instanceTypes
local lastMap, lastQuery, matches

local headerType = "Dropdown-Item-M33kAurasEncounterHeader"
local function RegisterHeader(AceGUI)
  if AceGUI:GetWidgetVersion(headerType) then return end
  -- Use a separate widget pool so styling cannot leak into other dropdowns.
  AceGUI:RegisterWidgetType(headerType, function()
    local ItemBase = LibStub("AceGUI-3.0-DropDown-ItemBase"):GetItemBase()
    local item = ItemBase.Create(headerType)
    item.text:SetFontObject(GameFontNormal)
    item.text:ClearAllPoints()
    item.text:SetPoint("TOPLEFT", item.frame, "TOPLEFT", 8, 0)
    item.text:SetPoint("BOTTOMRIGHT", item.frame, "BOTTOMRIGHT", -8, 0)
    local background = item.frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(1, 0.82, 0, 0.12)
    local divider = item.frame:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("BOTTOMLEFT", item.frame, "BOTTOMLEFT", 4, 0)
    divider:SetPoint("BOTTOMRIGHT", item.frame, "BOTTOMRIGHT", -4, 0)
    divider:SetColorTexture(1, 0.82, 0, 0.5)
    item.SetDisabled = function(self, disabled)
      ItemBase.SetDisabled(self, disabled)
      self.useHighlight = false
      self.text:SetTextColor(1, 0.82, 0)
    end
    item:SetDisabled(false)
    AceGUI:RegisterAsWidget(item)
    return item
  end, 1)
end

local function Initialize()
  if entries then return end
  entries, instances, instanceOrder, instanceTypes = {}, {[0] = L["All Instances"]}, {}, {}
  for mapId, instance in pairs(OptionsPrivate.Private.GetForeverEncounters()) do
    instances[mapId] = instance.name
    instanceTypes[mapId] = instance.instanceType
    instanceOrder[#instanceOrder + 1] = mapId
    -- Group alternate IDs only for browsing; the catalog keeps one entry per ID.
    local byName = {}
    for index, encounter in ipairs(instance.encounters) do
      local id, name = encounter[1], encounter[2]
      local entry = byName[name]
      if entry then
        entry.ids = entry.ids .. ", " .. id
      else
        entry = {
          name = name, instance = instance.name, mapId = mapId,
          instanceType = instance.instanceType,
          ids = tostring(id), order = index,
        }
        byName[name] = entry
        entries[#entries + 1] = entry
      end
    end
  end
  for _, entry in ipairs(entries) do
    entry.search = (entry.name .. " " .. entry.instance .. " " .. entry.ids):lower()
  end
  table.sort(instanceOrder, function(a, b)
    if instanceTypes[a] ~= instanceTypes[b] then return instanceTypes[a] == "raid" end
    return instances[a] < instances[b]
  end)
  table.insert(instanceOrder, 1, 0)
  table.sort(entries, function(a, b)
    if a.instanceType ~= b.instanceType then return a.instanceType == "raid" end
    if a.instance ~= b.instance then return a.instance < b.instance end
    if a.mapId ~= b.mapId then return a.mapId < b.mapId end
    return a.order < b.order
  end)
end

function OptionsPrivate.GetEncounterBrowserEntries(mapId, query)
  Initialize()
  mapId = mapId or 0
  query = (query or ""):lower():match("^%s*(.-)%s*$")
  if mapId == 0 and query == "" then return entries end
  if lastMap == mapId and lastQuery == query then return matches end
  lastMap, lastQuery, matches = mapId, query, {}
  local words = {}
  for word in query:gmatch("%S+") do words[#words + 1] = word end
  for _, entry in ipairs(entries) do
    if mapId == 0 or entry.mapId == mapId then
      local match = true
      for _, word in ipairs(words) do
        if not entry.search:find(word, 1, true) then
          match = false
          break
        end
      end
      if match then matches[#matches + 1] = entry end
    end
  end
  return matches
end

local list, closeWindow
local function GetList(parent)
  if not list then
    list = CreateFrame("Frame", nil, parent)
    list.scrollBox = CreateFrame("Frame", nil, list, "WowScrollBoxList")
    list.scrollBox:SetPoint("TOPLEFT", 0, -2)
    list.scrollBox:SetPoint("BOTTOMRIGHT", -24, 2)
    list.scrollBar = CreateFrame("EventFrame", nil, list, "MinimalScrollBar")
    list.scrollBar:SetPoint("TOPRIGHT", -2, -16)
    list.scrollBar:SetPoint("BOTTOMRIGHT", -2, 16)
    list.empty = list:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    list.empty:SetPoint("CENTER")
    list.empty:SetText(L["No encounters match your search."])

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(52)
    view:SetElementInitializer("Button", function(row, entry)
      if not row.name then
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.name:SetPoint("TOPLEFT", 8, -7)
        row.name:SetPoint("RIGHT", -200, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.instance = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.instance:SetPoint("TOPLEFT", 8, -28)
        row.instance:SetPoint("RIGHT", -200, 0)
        row.instance:SetJustifyH("LEFT")
        row.instance:SetWordWrap(false)
        row.ids = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.ids:SetPoint("RIGHT", -102, 0)
        row.ids:SetWidth(100)
        row.ids:SetJustifyH("RIGHT")
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.selection = row:CreateTexture(nil, "BACKGROUND")
        row.selection:SetAllPoints()
        row.selection:SetColorTexture(1, 0.82, 0, 0.12)
        row.copyButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.copyButton:SetSize(90, 24)
        row.copyButton:SetPoint("RIGHT", -4, 0)
        row.copyButton:SetText(L["Copy IDs"])
        local function Select()
          if row.entry and list.onSelect then list.onSelect(row.entry) end
        end
        row:SetScript("OnClick", Select)
        row.copyButton:SetScript("OnClick", Select)
        row:SetScript("OnEnter", function()
          if not row.entry then return end
          GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
          GameTooltip:SetText(row.entry.name)
          GameTooltip:AddLine(row.entry.instance, 1, 1, 1)
          GameTooltip:AddLine(L["Encounter ID(s)"] .. ": " .. row.entry.ids, 1, 1, 1)
          GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
          if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
        end)
      end
      row.entry = entry
      row.name:SetText(entry.name)
      row.instance:SetText(entry.instance)
      row.ids:SetText(entry.ids)
      row.selection:SetShown(entry == list.selected)
    end)
    view:SetElementResetter(function(row)
      if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
      row.entry = nil
      row.selection:Hide()
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(list.scrollBox, list.scrollBar, view)
  end
  list:SetParent(parent)
  list:ClearAllPoints()
  list:SetAllPoints()
  list:Show()
  return list
end

function OptionsPrivate.OpenEncounterBrowser()
  if not M33kAuras.IsForever() then return end
  if closeWindow then closeWindow() end
  Initialize()
  local AceGUI = LibStub("AceGUI-3.0")
  RegisterHeader(AceGUI)
  local window = AceGUI:Create("Frame")
  window:SetTitle(L["Browse Encounters"])
  window:SetWidth(720)
  window:SetHeight(660)
  window:EnableResize(false)
  window:SetLayout("Flow")

  local search = AceGUI:Create("EditBox")
  search:SetLabel(L["Search by encounter, instance, or ID"])
  search:SetFullWidth(true)
  search:DisableButton(true)
  window:AddChild(search)
  local filter = AceGUI:Create("Dropdown")
  filter:SetLabel(L["Instance"])
  filter:SetFullWidth(true)
  filter:SetList({[0] = instances[0]}, {0})
  local previousType
  for _, mapId in ipairs(instanceOrder) do
    if mapId ~= 0 then
      local instanceType = instanceTypes[mapId]
      if instanceType ~= previousType then
        filter:AddItem(instanceType, instanceType == "raid" and L["Raids"] or L["Dungeons"], headerType)
        previousType = instanceType
      end
      filter:AddItem(mapId, instances[mapId])
    end
  end
  -- AceGUI's default handler calls SetValue on headers as well as toggle items.
  -- Keep header rows nonselectable and update checks only on instance items.
  filter.pullout:SetCallback("OnOpen", function(pullout)
    local selected = filter:GetValue()
    for _, item in pullout:IterateItems() do
      if item.SetValue then
        item:SetValue(item.userdata.value == selected)
      end
    end
    filter.open = true
    filter:Fire("OnOpened")
  end)
  filter:SetValue(0)
  window:AddChild(filter)
  local results = AceGUI:Create("SimpleGroup")
  results:SetFullWidth(true)
  results:SetAutoAdjustHeight(false)
  results:SetHeight(430)
  window:AddChild(results)
  local rows = GetList(results.content)
  local copy = AceGUI:Create("EditBox")
  copy:SetLabel(L["Selected encounter IDs (press Ctrl+C to copy)"])
  copy:SetFullWidth(true)
  copy:DisableButton(true)
  window:AddChild(copy)
  local selectedIDs = ""
  copy:SetCallback("OnTextChanged", function(_, _, text)
    if text ~= selectedIDs then copy:SetText(selectedIDs) end
  end)
  rows.onSelect = function(entry)
    rows.selected = entry
    rows.scrollBox:ForEachFrame(function(row)
      row.selection:SetShown(row.entry == entry)
    end)
    selectedIDs = entry.ids
    copy:SetText(selectedIDs)
    copy:SetFocus()
    copy:HighlightText()
  end

  local closed = false
  local copyEscape = copy.editbox:GetScript("OnEscapePressed")
  local searchEscape = search.editbox:GetScript("OnEscapePressed")
  local function Close()
    if closed then return end
    closed = true
    rows.onSelect, rows.selected = nil, nil
    rows.scrollBox:RemoveDataProvider()
    rows:Hide()
    rows:SetParent(UIParent)
    copy.editbox:SetScript("OnEscapePressed", copyEscape)
    search.editbox:SetScript("OnEscapePressed", searchEscape)
    closeWindow = nil
    AceGUI:Release(window)
  end
  closeWindow = Close
  window:SetCallback("OnClose", Close)
  copy.editbox:SetScript("OnEscapePressed", Close)
  search.editbox:SetScript("OnEscapePressed", Close)
  local displayed
  local function Refresh()
    local found = OptionsPrivate.GetEncounterBrowserEntries(filter:GetValue(), search:GetText())
    if displayed ~= found then
      rows.selected = nil
      selectedIDs = ""
      copy:SetText("")
      rows.scrollBox:SetDataProvider(CreateDataProvider(found), false)
      displayed = found
    end
    rows.empty:SetShown(#found == 0)
    window:SetStatusText(L["%d matching encounters"]:format(#found))
  end
  search:SetCallback("OnTextChanged", Refresh)
  filter:SetCallback("OnValueChanged", Refresh)
  Refresh()
  search:SetFocus()
end
