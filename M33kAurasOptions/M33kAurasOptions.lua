if not M33kAuras.IsLibsOK() then return end
---@type string
local AddonName = ...
---@class OptionsPrivate
local OptionsPrivate = select(2, ...)
WASYNC_OPTIONS_PRIVATE = OptionsPrivate

-- Lua APIs
local tinsert, tremove, wipe = table.insert, table.remove, wipe
local pairs, type = pairs, type
local error = error
local coroutine = coroutine
local _G = _G

-- WoW APIs
local InCombatLockdown = InCombatLockdown
local CreateFrame = CreateFrame

local AceGUI = LibStub("AceGUI-3.0")

---@class M33kAuras
local M33kAuras = M33kAuras
local L = M33kAuras.L
local ADDON_NAME = "M33kAurasOptions";

local displayEntries = OptionsPrivate.displayEntries;

local spellCache = M33kAuras.spellCache;
local savedVars = {};
OptionsPrivate.savedVars = savedVars;

OptionsPrivate.expanderAnchors = {}
OptionsPrivate.expanderButtons = {}

local collapsedOptions = {}
local collapsed = {} -- magic value

local tempGroup = {
  id = {"tempGroup"},
  regionType = "group",
  controlledChildren = {},
  load = {},
  triggers = {{}},
  config = {},
  authorOptions = {},
  anchorPoint = "CENTER",
  anchorFrameType = "SCREEN",
  xOffset = 0,
  yOffset = 0
};
OptionsPrivate.tempGroup = tempGroup;

-- Does not duplicate child auras.
function OptionsPrivate.DuplicateAura(data, newParent, massEdit, targetIndex)
  local base_id = data.id .. " "
  local num = 2

  -- if the old id ends with a number increment the number
  local matchName, matchNumber = string.match(data.id, "^(.-)(%d*)$")
  matchNumber = tonumber(matchNumber)
  if (matchName ~= "" and matchNumber ~= nil) then
    base_id = matchName
    num = matchNumber + 1
  end

  local new_id = base_id .. num
  while(M33kAuras.GetData(new_id)) do
    new_id = base_id .. num
    num = num + 1
  end

  local newData = CopyTable(data)
  newData.id = new_id
  newData.parent = nil
  newData.uid = M33kAuras.GenerateUniqueID()
  if newData.controlledChildren then
    newData.controlledChildren = {}
  end
  M33kAuras.Add(newData)
  M33kAuras.NewDisplayButton(newData, massEdit)
  if(newParent or data.parent) then
    local parentId = newParent or data.parent
    local parentData = M33kAuras.GetData(parentId)
    local index
    if targetIndex then
      index = targetIndex
    elseif newParent then
      index = #parentData.controlledChildren + 1
    else
      index = tIndexOf(parentData.controlledChildren, data.id) + 1
    end
    if(index) then
      tinsert(parentData.controlledChildren, index, newData.id)
      newData.parent = parentId
      M33kAuras.Add(newData)
      M33kAuras.Add(parentData)
      OptionsPrivate.Private.AddParents(parentData)

      for index, id in pairs(parentData.controlledChildren) do
        local childButton = OptionsPrivate.GetDisplayEntry(id)
        childButton:SetGroup(parentData.id, parentData.regionType == "dynamicgroup")
        childButton:SetGroupOrder(index, #parentData.controlledChildren)
      end

      if not massEdit then
        local button = OptionsPrivate.GetDisplayEntry(parentData.id)
        button.callbacks.UpdateExpandButton()
        button:UpdateParentWarning()
      end
      OptionsPrivate.ClearOptions(parentData.id)
    end
  end
  return newData
end

AceGUI:RegisterLayout("AbsoluteList", function(content, children)
  local yOffset = 0;
  for i = 1, #children do
    local child = children[i]

    local frame = child.frame;
    frame:ClearAllPoints();
    frame:Show();

    frame:SetPoint("LEFT", content);
    frame:SetPoint("RIGHT", content);
    frame:SetPoint("TOP", content, "TOP", 0, yOffset)

    if child.DoLayout then
      child:DoLayout()
    end

    yOffset = yOffset - ((frame.height or frame:GetHeight() or 0) + 2);
  end
  if(content.obj.LayoutFinished) then
    content.obj:LayoutFinished(nil, yOffset * -1);
  end
end);

function OptionsPrivate.MultipleDisplayTooltipDesc()
  local desc = {{L["Multiple Displays"], L["Temporary Group"]}};
  for index, id in pairs(tempGroup.controlledChildren) do
    desc[index + 1] = {" ", id};
  end
  desc[2][1] = L["Children:"]
  tinsert(desc, " ");
  tinsert(desc, {" ", "|cFF00FFFF"..L["Right-click for more options"]});
  tinsert(desc, {" ", "|cFF00FFFF"..L["Drag to move"]});
  return desc;
end

local frame;
local db;
local odb;
--- @type boolean?
local reopenAfterCombat = false;
local loadedFrame = CreateFrame("Frame");
loadedFrame:RegisterEvent("ADDON_LOADED");
loadedFrame:RegisterEvent("PLAYER_REGEN_ENABLED");
loadedFrame:RegisterEvent("PLAYER_REGEN_DISABLED");
loadedFrame:SetScript("OnEvent", function(self, event, addon)
  if (event == "ADDON_LOADED") then
    if(addon == ADDON_NAME) then
      db = M33kAurasSaved;
      M33kAurasOptionsSaved = M33kAurasOptionsSaved or {};

      odb = M33kAurasOptionsSaved;

      -- Remove icon and id cache (replaced with spellCache)
      if (odb.iconCache) then
        odb.iconCache = nil;
      end
      if (odb.idCache) then
        odb.idCache = nil;
      end
      odb.spellCache = odb.spellCache or {};
      spellCache.Load(odb);

      if odb.magnetAlign == nil then
        odb.magnetAlign = true
      end

      if db.import_disabled then
        db.import_disabled = nil
      end

      savedVars.db = db;
      savedVars.odb = odb;
    end
  elseif (event == "PLAYER_REGEN_DISABLED") then
    if(frame and frame:IsVisible()) then
      reopenAfterCombat = true;
      M33kAuras.HideOptions();
    end
  elseif (event == "PLAYER_REGEN_ENABLED") then
    if (reopenAfterCombat) then
      reopenAfterCombat = nil;
      M33kAuras.ShowOptions()
    end
  end
end);

local function addParents(hash, data)
  local parent = data.parent
  if parent then
    hash[parent] = true
    local parentData = M33kAuras.GetData(parent)
    if parentData then
      addParents(hash, parentData)
    end
  end
end

local function commonParent(controlledChildren)
  local allSame = true
  local parent = nil
  local targetIndex = math.huge
  for index, id in ipairs(controlledChildren) do
    local childData = M33kAuras.GetData(id);
    local childButton = OptionsPrivate.GetDisplayEntry(id)
    targetIndex = min(targetIndex, childButton:GetGroupOrder() or math.huge)

    -- nil is a real parent value (top level), not an uninitialized sentinel.
    if index == 1 then
      parent = childData.parent
    elseif childData.parent ~= parent then
      allSame = false
    end
  end
  if allSame then
    return parent, targetIndex
  end
end

function OptionsPrivate.CreateGroupFromDisplayButtonSelection(ids, regionType, resetChildPositions)
  local data = {
    id = OptionsPrivate.Private.FindUnusedId(ids[1].." Group"),
    regionType = regionType,
  };

  M33kAuras.DeepMixin(data, OptionsPrivate.Private.data_stub)
  data.internalVersion = M33kAuras.InternalVersion()
  OptionsPrivate.Private.validate(data, OptionsPrivate.Private.regionTypes[regionType].default);

  local parent, targetIndex = commonParent(ids)

  if (parent) then
    local parentData = M33kAuras.GetData(parent)
    tinsert(parentData.controlledChildren, targetIndex, data.id)
    data.parent = parent
    M33kAuras.Add(data);
    M33kAuras.Add(parentData);
    OptionsPrivate.Private.AddParents(parentData)
    M33kAuras.NewDisplayButton(data);
    M33kAuras.UpdateGroupOrders(parentData);
    OptionsPrivate.ClearOptions(parentData.id);

    local parentButton = OptionsPrivate.GetDisplayEntry(parent)
    parentButton.callbacks.UpdateExpandButton();
    parentButton:Expand();
    parentButton:ReloadTooltip();
    parentButton:UpdateParentWarning();
  else
    M33kAuras.Add(data);
    M33kAuras.NewDisplayButton(data);
  end

  for index, childId in pairs(ids) do
    local childData = M33kAuras.GetData(childId);
    local childButton = OptionsPrivate.GetDisplayEntry(childId)
    local oldParent = childData.parent
    local oldParentData = M33kAuras.GetData(oldParent)
    if (oldParent) then
      local oldIndex = childButton:GetGroupOrder()

      tremove(oldParentData.controlledChildren, oldIndex)
      M33kAuras.Add(oldParentData)
      OptionsPrivate.Private.AddParents(oldParentData)
      M33kAuras.UpdateGroupOrders(oldParentData);
      M33kAuras.ClearAndUpdateOptions(oldParent);
      local oldParentButton = OptionsPrivate.GetDisplayEntry(oldParent)
      oldParentButton.callbacks.UpdateExpandButton();
      oldParentButton:ReloadTooltip()
      oldParentButton:UpdateParentWarning()
    end

    tinsert(data.controlledChildren, childId);
    childData.parent = data.id;
    if resetChildPositions then
      childData.xOffset = 0;
        childData.yOffset = 0;
    end
    M33kAuras.Add(data);
    M33kAuras.Add(childData);
    OptionsPrivate.ClearOptions(childData.id)

    childButton:SetGroup(data.id, data.regionType == "dynamicgroup");
    childButton:SetGroupOrder(index, #data.controlledChildren);
  end

  local button = OptionsPrivate.GetDisplayEntry(data.id);
  button.callbacks.UpdateExpandButton();
  button:UpdateParentWarning()
  OptionsPrivate.SortDisplayButtons();
  button:Expand();

  if data.parent then
    OptionsPrivate.Private.AddParents(data)
  end
end

function OptionsPrivate.DuplicateDisplayButtonSelection(ids)
  local duplicated = {}
  for child in OptionsPrivate.Private.TraverseAllChildren({controlledChildren = ids}) do
    local data = OptionsPrivate.DuplicateAura(child)
    tinsert(duplicated, data.id)
  end
  OptionsPrivate.ClearPicks()
  frame:PickDisplayBatch(duplicated)
end

function OptionsPrivate.DeleteDisplayButtonSelection(ids)
  local toDelete, parents = {}, {}
  for child in OptionsPrivate.Private.TraverseAllChildren({controlledChildren = ids}) do
    tinsert(toDelete, child)
    addParents(parents, child)
  end
  OptionsPrivate.ConfirmDelete(toDelete, parents)
end

StaticPopupDialogs["M33kAuras_CONFIRM_DELETE"] = {
  text = "",
  button1 = L["Delete"],
  button2 = L["Cancel"],
  OnAccept = function(self)
    if self.data then
      OptionsPrivate.DeleteAuras(self.data.toDelete, self.data.parents)
    end
  end,
  OnCancel = function(self)
    self.data = nil
  end,
  showAlert = true,
  whileDead = true,
  preferredindex = 4,
}

function OptionsPrivate.IsWagoUpdateIgnored(auraId)
    local auraData = M33kAuras.GetData(auraId)
      if auraData then
        for child in OptionsPrivate.Private.TraverseAll(auraData) do
          if child.ignoreWagoUpdate then
            return true
          end
        end
      end
    return false
end

function OptionsPrivate.HasWagoUrl(auraId)
  local auraData = M33kAuras.GetData(auraId)
    if auraData then
      for child in OptionsPrivate.Private.TraverseAll(auraData) do
        if child.url and child.url ~= "" then
          return true
        end
      end
    end
  return false
end

function OptionsPrivate.ConfirmDelete(toDelete, parents)
  if toDelete then
    local warningForm = L["You are about to delete %d aura(s). |cFFFF0000This cannot be undone!|r Would you like to continue?"]
    StaticPopupDialogs["M33kAuras_CONFIRM_DELETE"].text = warningForm:format(#toDelete)
    StaticPopup_Show("M33kAuras_CONFIRM_DELETE", "", "", {toDelete = toDelete, parents = parents})
  end
end

local function AfterScanForLoads()
  if(frame) then
    if (frame:IsVisible()) then
      OptionsPrivate.RequestAuraListRefresh()
    else
      frame.needsSort = true;
    end
  end
end

local function OnAboutToDelete(event, uid, id, parentUid, parentId)
  OptionsPrivate.CloseDisplayButtonMenu()
  local data = OptionsPrivate.Private.GetDataByUID(uid)
  if(data.controlledChildren) then
    for index, childId in pairs(data.controlledChildren) do
      local childButton = displayEntries[childId];
      if(childButton) then
        childButton:SetGroup();
      end
      local childData = db.displays[childId];
      if(childData) then
        childData.parent = nil;
      end
    end
  end

  OptionsPrivate.Private.CollapseAllClones(id);
  OptionsPrivate.ClearOptions(id)

  frame:ClearPicks();

  if(displayEntries[id])then
    OptionsPrivate.auraListModel:Remove(uid)
    OptionsPrivate.RequestAuraListRefresh()
    displayEntries[id] = nil;
  end

  collapsedOptions[id] = nil
end

local function OnRename(event, uid, oldid, newid)
  OptionsPrivate.CloseDisplayButtonMenu()
  local data = OptionsPrivate.Private.GetDataByUID(uid)

  if not data then return end
  local entry = OptionsPrivate.auraListModel:Ensure(data)
  frame:OnRename(uid, oldid, newid)
  entry:SetData(data)
  OptionsPrivate.ClearOptions(oldid)

  OptionsPrivate.displayEntries[newid]:SetTitle(newid);

  collapsedOptions[newid] = collapsedOptions[oldid]
  collapsedOptions[oldid] = nil

  if(data.controlledChildren) then
    for _, childId in pairs(data.controlledChildren) do
      local child = OptionsPrivate.GetDisplayEntry(childId)
      if child then child:SetGroup(newid) end
    end
  end

  OptionsPrivate.StopGrouping()
  OptionsPrivate.SortDisplayButtons(nil, true)

  if not M33kAuras.IsImporting() then
    if OptionsPrivate.IsPickedMultiple() then frame:FillOptions() else M33kAuras.PickDisplay(newid) end
  end

  local parent = data.parent
  while parent do
    OptionsPrivate.ClearOptions(parent)
    local parentData = M33kAuras.GetData(parent)
    parent = parentData.parent
  end
end

local function OptionsFrame()
  if(frame) then
    return frame
  else
    return nil
  end
end

if not M33kAuras.ToggleOptions then
  ---@type fun(msg: string, Private: Private)
  function M33kAuras.ToggleOptions(msg, Private)
    if not Private then
      return
    end
    if not OptionsPrivate.Private then
      OptionsPrivate.Private = Private
      Private.OptionsFrame = OptionsFrame
      for _, fn in ipairs(OptionsPrivate.registerRegions) do
        fn()
      end
      OptionsPrivate.Private.callbacks:RegisterCallback("AuraWarningsUpdated", function(event, uid)
        local id = OptionsPrivate.Private.UIDtoID(uid)
        if displayEntries[id] then
          -- The button does not yet exists if a new aura is created
          displayEntries[id]:UpdateWarning()
        end
        local data = Private.GetDataByUID(uid)
        if data and data.parent then
          local button = OptionsPrivate.GetDisplayEntry(data.parent);
          if button then
            button:UpdateParentWarning()
          end
        end
      end)

      OptionsPrivate.Private.callbacks:RegisterCallback("ScanForLoads", AfterScanForLoads)
      OptionsPrivate.Private.callbacks:RegisterCallback("AboutToDelete", OnAboutToDelete)
      OptionsPrivate.Private.callbacks:RegisterCallback("Rename", OnRename)
      OptionsPrivate.Private.OpenUpdate = OptionsPrivate.OpenUpdate
    end

    if(frame and frame:IsVisible()) then
      M33kAuras.HideOptions();
    elseif (InCombatLockdown()) then
      M33kAuras.prettyPrint(L["Options will open after combat ends."])
      reopenAfterCombat = true;
    else
      M33kAuras.ShowOptions(msg);
    end
  end
end

function M33kAuras.HideOptions()
  if(frame) then
    frame:Hide()
  end
end

function M33kAuras.IsOptionsOpen()
  if(frame and frame:IsVisible()) then
    return true;
  else
    return false;
  end
end

local function LayoutDisplayButtons(msg)
  OptionsPrivate.SortDisplayButtons(msg)
  frame:SetLoadProgressVisible(false)
  local suspended
  OptionsPrivate.Private:Async({name = "AuraListPreviews"}, function()
    suspended = OptionsPrivate.Private.PauseAllDynamicGroups()
    local entries = {}
    for _, entry in pairs(displayEntries) do entries[#entries + 1] = entry end
    for _, entry in ipairs(entries) do
      if not M33kAuras.IsOptionsOpen() then break end
      if OptionsPrivate.auraListModel.byUID[entry.uid] == entry and OptionsPrivate.Private.loaded[entry.data.id] then
        entry:PriorityShow(1)
      end
      coroutine.yield()
    end
    OptionsPrivate.RefreshAuraPreviews()
  end):Finally(function()
    if suspended then OptionsPrivate.Private.ResumeAllDynamicGroups(suspended) end
  end)
end

local pendingDeletions = 0
function OptionsPrivate.DeleteAuras(auras, parents)
  -- Snapshot UIDs: names and data tables may change while deletion is queued.
  local uids, seen, parentUIDs = {}, {}, {}
  for _, data in ipairs(auras) do
    if not seen[data.uid] then
      seen[data.uid] = true
      uids[#uids + 1] = data.uid
    end
  end
  for id in pairs(parents or {}) do
    local data = M33kAuras.GetData(id)
    if data then parentUIDs[#parentUIDs + 1] = data.uid end
  end
  pendingDeletions = pendingDeletions + 1
  OptionsPrivate.massDelete = true
  local suspended
  local func1 = function()
    frame:SetLoadProgressVisible(true)
    local num = 0
    local total = #uids

    frame.loadProgress:SetText(L["Deleting auras: "]..num.."/"..total)

    suspended = OptionsPrivate.Private.PauseAllDynamicGroups()
    for _, uid in ipairs(uids) do
      local auraData = OptionsPrivate.Private.GetDataByUID(uid)
      if auraData then M33kAuras.Delete(auraData) end
      num = num +1
      frame.loadProgress:SetText(L["Deleting auras: "]..num.."/"..total)
      coroutine.yield()
    end
    for _, uid in ipairs(parentUIDs) do
      local parentData = OptionsPrivate.Private.GetDataByUID(uid)
      local parentButton = parentData and OptionsPrivate.GetDisplayEntry(parentData.id)
      if parentData and parentButton then
        M33kAuras.UpdateGroupOrders(parentData)
        if(#parentData.controlledChildren == 0) then
          parentButton:DisableExpand()
        else
          parentButton:EnableExpand()
        end
        parentButton:SetNormalTooltip()
        M33kAuras.Add(parentData)
        M33kAuras.ClearAndUpdateOptions(parentData.id)
        parentButton:UpdateParentWarning()
        frame.loadProgress:SetText(L["Finishing..."])
        coroutine.yield()
      end
    end
  end

  OptionsPrivate.Private:Async({name = "Deleting Auras"}, func1):Finally(function()
    pendingDeletions = pendingDeletions - 1
    OptionsPrivate.massDelete = pendingDeletions > 0 or nil
    if suspended then OptionsPrivate.Private.ResumeAllDynamicGroups(suspended) end
    if pendingDeletions == 0 then
      frame:SetLoadProgressVisible(false)
      OptionsPrivate.SortDisplayButtons(nil, true)
    end
  end)
end

function M33kAuras.ShowOptions(msg)
  local firstLoad = not(frame);
  OptionsPrivate.Private.Pause();
  OptionsPrivate.Private.SetFakeStates()

  M33kAuras.spellCache.Build()

  if (firstLoad) then
    frame = OptionsPrivate.CreateFrame();

    LayoutDisplayButtons(msg);
  end

  if (frame:GetWidth() > GetScreenWidth()) then
    frame:SetWidth(GetScreenWidth())
  end

  if (frame:GetHeight() > GetScreenHeight() - 50) then
    frame:SetHeight(GetScreenHeight() - 50)
  end


  if (frame.needsSort) then
    OptionsPrivate.SortDisplayButtons();
    frame.needsSort = nil;
  end

  frame:Show();

  if (OptionsPrivate.Private.mouseFrame) then
    OptionsPrivate.Private.mouseFrame:OptionsOpened();
  end

  if (OptionsPrivate.Private.personalRessourceDisplayFrame) then
    OptionsPrivate.Private.personalRessourceDisplayFrame:OptionsOpened();
  end

  if frame.moversizer then
    frame.moversizer:OptionsOpened()
  end

  if not(firstLoad) then
    -- Show what was last shown
    local suspended = OptionsPrivate.Private.PauseAllDynamicGroups()
    for id, button in pairs(displayEntries) do
      button:SyncVisibility()
    end
    OptionsPrivate.Private.ResumeAllDynamicGroups(suspended)
  end

  if (frame.pickedDisplay) then
    if (OptionsPrivate.IsPickedMultiple()) then
      local children = {}
      for k,v in pairs(tempGroup.controlledChildren) do
        children[k] = v
      end
      frame:PickDisplayBatch(children);
    else
      M33kAuras.PickDisplay(frame.pickedDisplay);
    end
  else
    frame:NewAura();
  end

  if (frame.window == "codereview") then
    local codereview = OptionsPrivate.CodeReview(frame, true)
    if codereview then
      codereview:Close();
    end
  end

  if firstLoad then
    frame:ShowTip()
  end

end

function OptionsPrivate.UpdateOptions()
  frame:UpdateOptions()
end

function M33kAuras.ClearAndUpdateOptions(id, clearChildren)
  frame:ClearAndUpdateOptions(id, clearChildren)
end

function OptionsPrivate.ClearOptions(id)
  frame:ClearOptions(id)
end

function M33kAuras.FillOptions()
  frame:FillOptions()
end

function OptionsPrivate.EnsureOptions(data, subOption)
  return frame:EnsureOptions(data, subOption)
end

function OptionsPrivate.GetPickedDisplay()
  return frame:GetPickedDisplay()
end

function OptionsPrivate.OpenTextEditor(...)
  OptionsPrivate.TextEditor(frame):Open(...);
end

function OptionsPrivate.ExportToString(id)
  OptionsPrivate.ImportExport(frame):Open("export", id);
end

function OptionsPrivate.ExportToTable(id)
  OptionsPrivate.ImportExport(frame):Open("table", id);
end

function OptionsPrivate.ImportFromString()
  OptionsPrivate.ImportExport(frame):Open("import");
end

function OptionsPrivate.OpenDebugLog(text)
  OptionsPrivate.DebugLog(frame):Open(text)
end

function OptionsPrivate.OpenUpdate(data, children, target, linkedAuras, sender, callbackFunc)
  return OptionsPrivate.UpdateFrame(frame):Open(data, children, target, linkedAuras, sender, callbackFunc)
end

function OptionsPrivate.ConvertDisplay(data, newType)
  local id = data.id;
  local visibility = displayEntries[id]:GetVisibility();
  displayEntries[id]:PriorityHide(2);

  if OptionsPrivate.Private.regions[id] and OptionsPrivate.Private.regions[id].region then
    OptionsPrivate.Private.regions[id].region:Collapse()
  end
  OptionsPrivate.Private.CollapseAllClones(id);

  OptionsPrivate.Private.Convert(data, newType);
  displayEntries[id]:Initialize();
  displayEntries[id]:PriorityShow(visibility);
  frame:ClearOptions(id)
  frame:FillOptions();
  M33kAuras.UpdateThumbnail(data);
  M33kAuras.SetMoverSizer(id)
  OptionsPrivate.ResetMoverSizer();
  OptionsPrivate.SortDisplayButtons()
end

function M33kAuras.NewDisplayButton(data, massEdit)
  OptionsPrivate.auraListModel:Ensure(data)
  OptionsPrivate.Private.ScanForLoads({[data.id] = true})
  if not massEdit then OptionsPrivate.RequestAuraListRefresh() end
end

function M33kAuras.UpdateGroupOrders(data)
  for _, id in ipairs(data.controlledChildren or {}) do
    local entry = OptionsPrivate.GetDisplayEntry(id)
    if entry then entry:Refresh() end
  end
  OptionsPrivate.RequestAuraListRefresh()
end

function OptionsPrivate.SortDisplayButtons(filter)
  if not frame then return end
  if OptionsPrivate.IsAuraListBusy() then
    frame.needsSort = true
    return
  end
  frame.needsSort = nil
  filter = filter or frame.filterInput:GetText()
  if frame.filterInput:GetText() ~= filter then
    frame.filterInput:SetText(filter)
    return
  end
  OptionsPrivate.RefreshAuraList(filter)
end

function OptionsPrivate.IsPickedMultiple()
  if(frame.pickedDisplay == tempGroup) then
    return true;
  else
    return false;
  end
end

function OptionsPrivate.IsDisplayPicked(id)
  if(frame.pickedDisplay == tempGroup) then
    for child in OptionsPrivate.Private.TraverseLeafs(tempGroup) do
      if(id == child.id) then
        return true;
      end
    end
    return false;
  else
    return frame.pickedDisplay == id;
  end
end

function M33kAuras.PickDisplay(id, tab, noHide)
  frame:PickDisplay(id, tab, noHide)
end

function OptionsPrivate.PickAndEditDisplay(id)
  frame:PickDisplay(id);
  displayEntries[id].callbacks.OnRenameClick();
end

function OptionsPrivate.ClearPick(id)
  frame:ClearPick(id);
end

function OptionsPrivate.ClearPicks()
  frame:ClearPicks();
end

function OptionsPrivate.PickDisplayMultiple(id)
  frame:PickDisplayMultiple(id);
end

function OptionsPrivate.PickDisplayMultipleShift(target)
  if not frame.pickedDisplay then M33kAuras.PickDisplay(target); return end
  local first = OptionsPrivate.IsPickedMultiple() and tempGroup.controlledChildren[#tempGroup.controlledChildren] or frame.pickedDisplay
  local firstData, targetData = M33kAuras.GetData(first), M33kAuras.GetData(target)
  if not firstData or not targetData or firstData.parent ~= targetData.parent or firstData.controlledChildren or targetData.controlledChildren then return end
  local visible = OptionsPrivate.auraListModel:VisibleEntries(function(entry) return entry:GetExpanded() end,
    function(section) return (section == "loaded" and frame.loadedButton or frame.unloadedButton):GetExpanded() end)
  local from, to
  for i, entry in ipairs(visible) do
    if entry.data.id == first then from = i end
    if entry.data.id == target then to = i end
  end
  if not from or not to then return end
  if from > to then from, to = to, from end
  local selection = {}
  for i = from, to do
    local data = visible[i].data
    if data.parent == firstData.parent and not data.controlledChildren then selection[#selection + 1] = data.id end
  end
  frame:PickDisplayBatch(selection)
end

function OptionsPrivate.AddDisplayButton(data)
  OptionsPrivate.auraListModel:Ensure(data)
  OptionsPrivate.RequestAuraListRefresh()
end

function OptionsPrivate.StartGrouping(data)
  if not data then
    return
  end

  if not OptionsPrivate.IsDisplayPicked(data.id) then
    M33kAuras.PickDisplay(data.id)
  end

  if (frame.pickedDisplay == tempGroup and #tempGroup.controlledChildren > 0) then
    local children = {};
    -- start grouping for selected buttons
    for index, childId in ipairs(tempGroup.controlledChildren) do
      local button = OptionsPrivate.GetDisplayEntry(childId);
      button:StartGrouping(tempGroup.controlledChildren, true);
      children[childId] = true;
    end
    -- set grouping for non selected buttons
    for _, button in pairs(displayEntries) do
      if not children[button.data.id] then
        button:StartGrouping(tempGroup.controlledChildren, false);
      end
    end
  else
    local children = {};
    for child in OptionsPrivate.Private.TraverseAllChildren(data) do
      children[child.id] = true
    end

    for id, button in pairs(displayEntries) do
      button:StartGrouping({data.id},
                           data.id == id,
                           data.regionType == "dynamicgroup" or data.regionType == "group",
                           children[id]);
    end
  end
end

function OptionsPrivate.StopGrouping(data)
  for id, button in pairs(displayEntries) do
    button:StopGrouping();
  end
end

function OptionsPrivate.Ungroup(data)
  if not OptionsPrivate.IsDisplayPicked(data.id) then
    M33kAuras.PickDisplay(data.id)
  end

  if (frame.pickedDisplay == tempGroup and #tempGroup.controlledChildren > 0) then
    for index, childId in ipairs(tempGroup.controlledChildren) do
      local button = OptionsPrivate.GetDisplayEntry(childId);
      button:Ungroup(data);
    end
  else
    local button = OptionsPrivate.GetDisplayEntry(data.id);
    button:Ungroup(data);
  end
  M33kAuras.FillOptions()
end

function OptionsPrivate.DragReset()
  OptionsPrivate.EndAuraDrag()
  -- A released drop owns its snapshot until the scheduler completes or cancels it.
  if OptionsPrivate.movingAuras then return end
  for _, button in pairs(displayEntries) do
    button:DragReset();
  end
end

local function CompareButtonOrder(a, b)
  if (a.data.parent == b.data.parent) then
    if (a.data.parent) then
      return a:GetGroupOrder() < b:GetGroupOrder()
    else
      return a.data.id < b.data.id
    end
  end

  -- Different parents, so find common parent by first
  -- going up a's hierarchy

  local parents = {}

  local aNode = a.data.id
  local lastAParent = aNode

  while(aNode) do
    local parent = M33kAuras.GetData(aNode).parent
    if (parent) then
      parents[parent] = aNode
      lastAParent = parent
    end
    aNode = parent
  end

  local bNode = b.data.id
  local lastBParent = bNode

  while(bNode) do
    local parent = M33kAuras.GetData(bNode).parent
    if parent then
      if (parents[parent]) then
        -- We have found the common parent, the last node in the chain is
        -- Compare the previous nodes GroupOrder
        local aButton = OptionsPrivate.GetDisplayEntry(parents[parent])
        local bButton = OptionsPrivate.GetDisplayEntry(bNode)
        return aButton:GetGroupOrder() < bButton:GetGroupOrder()
      end
      lastBParent = parent
    end
    bNode = parent
  end

  -- If we are here there was no common parent
  local aButton = OptionsPrivate.GetDisplayEntry(lastAParent)
  local bButton = OptionsPrivate.GetDisplayEntry(lastBParent)

  return aButton.data.id < bButton.data.id
end

local function CompareButtonOrderReverse(a, b)
  return CompareButtonOrder(b, a)
end

function OptionsPrivate.Drop(mainAura, target, action, area)
  if OptionsPrivate.movingAuras then return end
  OptionsPrivate.EndAuraDrag()
  OptionsPrivate.CloseDisplayButtonMenu()
  M33kAuras_DropDownMenu:Hide()
  if not target or not action then OptionsPrivate.DragReset(); return end

  local mode = OptionsPrivate.IsPickedMultiple() and "MULTI" or mainAura.controlledChildren and "GROUP" or "SINGLE"
  local entries = {}
  for _, entry in pairs(displayEntries) do
    if entry:IsDragging() then entries[#entries + 1] = entry end
  end
  if #entries == 0 then OptionsPrivate.DragReset(); return end
  if mode == "MULTI" then
    table.sort(entries, area == "BEFORE" and CompareButtonOrder or CompareButtonOrderReverse)
  end
  local function isCurrent(entry)
    local data = M33kAuras.GetData(entry.data.id)
    return data and data.uid == entry.uid
  end

  -- Reserve the operation before Async starts; OnHide and duplicate mouse events
  -- must not change the selected sources between scheduler slices.
  OptionsPrivate.movingAuras = true
  frame:SetLoadProgressVisible(true)
  local completed
  OptionsPrivate.Private:Async({name = "Dropping Auras"}, function()
    for index, entry in ipairs(entries) do
      if not isCurrent(target) then break end
      if isCurrent(entry) then entry:Drop(mode, mainAura, target, action) end
      frame.loadProgress:SetText(L["Moving auras: "] .. index .. "/" .. #entries)
      coroutine.yield()
    end
    completed = true
  end):Finally(function()
    OptionsPrivate.movingAuras = nil
    frame:SetLoadProgressVisible(false)
    OptionsPrivate.DragReset()
    OptionsPrivate.SortDisplayButtons(nil, true)
    if completed then M33kAuras.FillOptions() end
  end)
end

function OptionsPrivate.StartDrag(mainAura)
  if OptionsPrivate.movingAuras or M33kAuras.IsImporting() then return end
  OptionsPrivate.CloseDisplayButtonMenu()
  M33kAuras_DropDownMenu:Hide()

  if (frame.pickedDisplay == tempGroup and #tempGroup.controlledChildren > 0) then
    -- Multi selection
    local children = {};
    local size = #tempGroup.controlledChildren;
    -- set dragging for selected buttons in reverse for ordering

    for child in OptionsPrivate.Private.TraverseAllChildren(tempGroup) do
      local button = OptionsPrivate.GetDisplayEntry(child.id);
      button:DragStart("MULTI", true, mainAura, size)
      children[child.id] = true
    end
    -- set dragging for non selected buttons
    for id, button in pairs(displayEntries) do
      if not children[button.data.id] then
        button:DragStart("MULTI", false, mainAura);
      end
    end
  else
    if mainAura.controlledChildren then
      -- Group aura
      local mode = "GROUP"
      local children = {};
      for child in OptionsPrivate.Private.TraverseAll(mainAura) do
        local button = OptionsPrivate.GetDisplayEntry(child.id);
        button:DragStart(mode, true, mainAura)
        children[child.id] = true
      end
      -- set dragging for non selected buttons
      for _, button in pairs(displayEntries) do
        if not children[button.data.id] then
          button:DragStart(mode, false, mainAura);
        end
      end
    else
      for id, button in pairs(displayEntries) do
        button:DragStart("SINGLE", id == mainAura.id, mainAura);
      end
    end
  end
end

function OptionsPrivate.DropIndicator()
  local indicator = frame.dropIndicator
  if not indicator then
    ---@class Frame
    indicator = CreateFrame("Frame", "M33kAuras_DropIndicator")
    indicator:SetHeight(4)
    indicator:SetFrameStrata("FULLSCREEN")

    local groupTexture = indicator:CreateTexture(nil, "ARTWORK")
    groupTexture:SetBlendMode("ADD")
    groupTexture:SetTexture("Interface\\AddOns\\M33kAuras\\Media\\Textures\\Square_FullWhite")

    local lineTexture = indicator:CreateTexture(nil, "ARTWORK")
    lineTexture:SetBlendMode("ADD")
    lineTexture:SetAllPoints(indicator)
    lineTexture:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight")

    indicator.lineTexture = lineTexture
    indicator.groupTexture = groupTexture
    frame.dropIndicator = indicator
    indicator:Hide()

    function indicator:ShowAction(target, action)
      if not target.row then self:Hide(); return end
      self:Show()
      self:ClearAllPoints()
      if action == "GROUP" then
        self.groupTexture:ClearAllPoints()
        self.groupTexture:SetVertexColor(0.4, 0.7, 1, 0.7)
        self.groupTexture:Show()
        self.groupTexture:SetPoint("TOPLEFT", target.row.icon, "TOPRIGHT", 2, -1)
        self.groupTexture:SetPoint("BOTTOMRIGHT", target.row.frame, "BOTTOMRIGHT", 0, 1)
      else
        self.groupTexture:Hide()
      end

      -- Position line texture, if needed
      if action == "BEFORE" then
        self.lineTexture:Show()
        self:SetPoint("BOTTOMLEFT", target.row.frame, "TOPLEFT", 0, -1)
        self:SetPoint("BOTTOMRIGHT", target.row.frame, "TOPRIGHT", 0, -1)
        self:SetHeight(4)
      elseif action == "AFTER" then
        self.lineTexture:Show()
        self:SetPoint("TOPLEFT", target.row.frame, "BOTTOMLEFT", 0, 1)
        self:SetPoint("TOPRIGHT", target.row.frame, "BOTTOMRIGHT", 0, 1)
        self:SetHeight(4)
      else
        self.lineTexture:Hide()
      end
    end

  end
  return indicator
end

function M33kAuras.UpdateThumbnail(data)
  if type(data) == "string" then data = M33kAuras.GetData(data) end
  if not data then return end
  local id = data.id
  local button = displayEntries[id]
  if (not button) then
    return
  end
  button:UpdateThumbnail()
end

function OptionsPrivate.OpenTexturePicker(baseObject, paths, properties, textures, SetTextureFunc, adjustSize)
   OptionsPrivate.TexturePicker(frame):Open(baseObject, paths, properties, textures, SetTextureFunc, adjustSize)
end

function OptionsPrivate.OpenIconPicker(baseObject, paths, groupIcon)
  OptionsPrivate.IconPicker(frame):Open(baseObject, paths, groupIcon)
end

function OptionsPrivate.OpenModelPicker(baseObject, path)
  if not(C_AddOns.IsAddOnLoaded("M33kAurasModelPaths")) then
    local loaded, reason = C_AddOns.LoadAddOn("M33kAurasModelPaths");
    if not(loaded) then
      reason = string.lower("|cffff2020" .. _G["ADDON_" .. reason] .. "|r.")
      M33kAuras.prettyPrint(string.format(L["ModelPaths could not be loaded, the addon is %s"], reason));
      M33kAuras.ModelPaths = {};
    end
    OptionsPrivate.ModelPicker(frame).modelTree:SetTree(M33kAuras.ModelPaths)
  end
  OptionsPrivate.ModelPicker(frame):Open(baseObject, path);
end

function OptionsPrivate.OpenCodeReview(data)
  OptionsPrivate.CodeReview(frame):Open(data);
end

function OptionsPrivate.OpenTriggerTemplate(data, targetId)
  if not(C_AddOns.IsAddOnLoaded("M33kAurasTemplates")) then
    local loaded, reason = C_AddOns.LoadAddOn("M33kAurasTemplates");
    if not(loaded) then
      reason = string.lower("|cffff2020" .. _G["ADDON_" .. reason] .. "|r.")
      M33kAuras.prettyPrint(string.format(L["Templates could not be loaded, the addon is %s"], reason));
      return;
    end
    frame.newView = M33kAuras.CreateTemplateView(OptionsPrivate.Private, frame);
  end
  -- This is called multiple times if a group is selected
  if frame.window ~= "newView" then
    frame.newView:Open(data, targetId);
  end
end

OptionsPrivate.currentDynamicTextInput = false;

local BaseDynamicTextCodes = {
  trigger = {
    {type = "mini", name = "p", desc = L["Progress - The remaining time of a timer, or a non-timer value"]},
    {type = "mini", name = "t", desc = L["Total - The maximum duration of a timer, or a maximum non-timer value"]},
    {type = "mini", name = "n", desc = L["Name - The name of the display (usually an aura name), or the display's ID if there is no dynamic name"]},
    {type = "mini", name = "i", desc = L["Icon - The icon associated with the display"]},
    {type = "mini", name = "s", desc = L["Stacks - The number of stacks of an aura (usually)"]},
  },
  global = {
    {type = "mini", name = "c", desc = L["Custom - Allows you to define a custom Lua function that returns a list of string values. %c1 will be replaced by the first value returned, %c2 by the second, etc."]},
    {type = "mini", name = "%", desc = L["% - To show a percent sign"]},
  }
}

function OptionsPrivate.UpdateTextReplacements(frame, data)
  frame.scrollList:ReleaseChildren()

  local props = OptionsPrivate.Private.GetAdditionalProperties(data)
  local sortedProps = {}

  -- Add global header and markers
  table.insert(sortedProps, {type = "header", triggerNum = 0, name = "Global Properties"})
  for index, icon in ipairs(ICON_LIST) do
    table.insert(sortedProps, {type = "marker", triggerNum = 0, name = "{rt"..index.."}", desc = icon..":0|t", widthFraction = #ICON_LIST})
  end

  -- Add base dynamic text codes
  local globalProps = {}
  tAppendAll(globalProps, CopyTable(BaseDynamicTextCodes.trigger))
  tAppendAll(globalProps, CopyTable(BaseDynamicTextCodes.global))
  for _, prop in ipairs(globalProps) do
    prop.widthFraction = #globalProps
    prop.triggerNum = 0
    table.insert(sortedProps, prop)
  end

  -- Process each trigger's properties
  for triggerNum, triggerProps in pairs(props) do
    if next(triggerProps) then
      -- Create a temporary table for this trigger's properties
      local tempProps = {}

      -- Add the properties to the temporary table
      for name, data in pairs(triggerProps) do
        table.insert(tempProps, {triggerNum = triggerNum, name = name, desc = data.display})
      end

      -- Sort the temporary table by name
      table.sort(tempProps, function(a, b)
        return a.name < b.name
      end)

      -- Add a header for the trigger
      table.insert(sortedProps, {type = "header", triggerNum = triggerNum, name = OptionsPrivate.GetTriggerTitle(data, triggerNum)})

      -- Add the base properties for the trigger
      for _, v in ipairs(BaseDynamicTextCodes.trigger) do
        local prop = CopyTable(v)
        prop.widthFraction = #BaseDynamicTextCodes.trigger
        prop.triggerNum = triggerNum
        table.insert(sortedProps, prop)
      end

      -- Add the sorted properties to the sortedProps table
      for _, prop in ipairs(tempProps) do
        table.insert(sortedProps, prop)
      end
    end
  end

  -- Create a modified M33kAurasSnippetButton for each property and add it to ScrollList
  local lastType, miniGroup
  for i, prop in ipairs(sortedProps) do
    if prop.type == "header" then
      local heading = AceGUI:Create("Heading")
      heading:SetText(prop.name)
      heading:SetRelativeWidth(1)
      heading.label:SetFontObject(GameFontNormalSmall2)
      frame.scrollList:AddChild(heading)
    else
      if ((prop.type == "mini" or prop.type == "marker") and prop.type ~= lastType)
      then
        miniGroup = AceGUI:Create("SimpleGroup")
        miniGroup:SetLayout("Flow")
        miniGroup:SetAutoAdjustHeight(true)
        miniGroup:SetRelativeWidth(1)
        frame.scrollList:AddChild(miniGroup)
      end
      local button = AceGUI:Create("M33kAurasSnippetButton")
      local propIndex = prop.triggerNum > 0 and ("%s"):format(prop.triggerNum) or ""
      local propPrefix = prop.triggerNum > 0 and ("%%%s."):format(propIndex) or "%"
      if prop.type == "marker" then
        button:SetTitle(prop.desc)
      else
        button:SetTitle(string.format("|cFFFFCC00%s|r%s", propPrefix, prop.name))
      end
      if prop.type == "mini" or prop.type == "marker" then
        button:SetRelativeWidth((1/prop.widthFraction) - 1e-10)
      else
        button:SetRelativeWidth(1)
      end
      button.title:SetFontObject(GameFontNormal)
      button.frame:SetHeight(28)
      button:SetDynamicTextStyle()

      -- Set Tooltip
      if prop.type ~= "marker" then
        button.frame:SetScript("OnEnter", function(frame)
          local tooltip = GameTooltip
          tooltip:SetWidth(300)
          tooltip:SetOwner(frame, "ANCHOR_RIGHT")
          tooltip:ClearLines()
          tooltip:AddLine(("%s%s"):format(propPrefix, prop.name))
          tooltip:AddLine(prop.desc, 1, 1, 1, true)
          if prop.name ~= "c" and prop.name ~= "%" then
            tooltip:AddLine("\n")
            tooltip:AddLine(
              prop.triggerNum > 0
              and L["The trigger number is optional. When no trigger number is specified, the trigger selected via dynamic information will be used."]
              or L["By default this shows the information from the trigger selected via dynamic information. The information from a specific trigger can be shown via e.g. %2.p."],
              0.8, 0.8, 0.8,
              true)
          end
          tooltip:Show()
          frame.obj:Fire("OnEnter")
        end)
      else
        button.frame:SetScript("OnEnter", nil)
      end

      -- Insert dynamic text property on click
      button:SetCallback("OnClick", function()
        local insertProp
        if prop.type == "marker" then
          insertProp = prop.name
        else
          if IsShiftKeyDown() then
            insertProp = prop.name == "%" and "%%" or ("%%{%s}"):format(prop.name)
            if prop.triggerNum > 0 then
              insertProp = string.format("%%{%d.%s}", propIndex, prop.name)
            end
          else
            insertProp = prop.name == "%" and "%%" or ("%%%s"):format(prop.name)
            if prop.triggerNum > 0 then
              insertProp = string.format("%%%d.%s", propIndex, prop.name)
            end
          end
        end

        OptionsPrivate.currentDynamicTextInput.editbox:Insert(insertProp)
        OptionsPrivate.currentDynamicTextInput.editbox:SetFocus()
      end)

      if prop.type == "mini" or prop.type == "marker" then
        miniGroup:AddChild(button)
      else
        frame.scrollList:AddChild(button)
      end
    end
    lastType = prop.type
  end
end

function OptionsPrivate.ResetMoverSizer()
  if(frame and frame.mover and frame.moversizer and frame.mover.moving.region and frame.mover.moving.data) then
    frame.moversizer:SetToRegion(frame.mover.moving.region, frame.mover.moving.data);
  end
end

function M33kAuras.SetMoverSizer(id)
  OptionsPrivate.Private.EnsureRegion(id)
  if OptionsPrivate.Private.regions[id].region.toShow then
    frame.moversizer:SetToRegion(OptionsPrivate.Private.regions[id].region, db.displays[id])
  else
    if OptionsPrivate.Private.clones[id] then
      local _, clone = next(OptionsPrivate.Private.clones[id])
      if clone then
        frame.moversizer:SetToRegion(clone, db.displays[id])
      end
    end
  end
end

function M33kAuras.GetMoverSizerId()
  return frame.moversizer:GetCurrentId()
end

local function AddDefaultSubRegions(data)
  data.subRegions = data.subRegions or {}
  for type, subRegionData in pairs(OptionsPrivate.Private.subRegionTypes) do
    if subRegionData.addDefaultsForNewAura then
      subRegionData.addDefaultsForNewAura(data)
    end
  end
end

function M33kAuras.NewAura(sourceData, regionType, targetId)
  local function ensure(t, k, v)
    return t and k and v and t[k] == v
  end
  local new_id = OptionsPrivate.Private.FindUnusedId("New")
  local data = {id = new_id, regionType = regionType, uid = M33kAuras.GenerateUniqueID()}
  M33kAuras.DeepMixin(data, OptionsPrivate.Private.data_stub);
  if (sourceData) then
    M33kAuras.DeepMixin(data, sourceData);
  end
  data.internalVersion = M33kAuras.InternalVersion();
  OptionsPrivate.Private.validate(data, OptionsPrivate.Private.regionTypes[regionType].default);

  AddDefaultSubRegions(data)

  if targetId then
    local target = OptionsPrivate.GetDisplayEntry(targetId);
    local group
    if (target) then
      if (target:IsGroup()) then
        group = target;
      else
        group = OptionsPrivate.GetDisplayEntry(target.data.parent);
      end
      if (group) then
        -- Sanity check so that we don't create a group/dynamic group in a group
        if (regionType == "group" or regionType == "dynamicgroup") and group.data.regionType == "dynamicgroup" then
          return
        end

        local children = group.data.controlledChildren;
        local index = target:GetGroupOrder();
        if (ensure(children, index, target.data.id)) then
          -- account for insert position
          index = index + 1;
          tinsert(children, index, data.id);
        else
          -- move source into group as the first child
          tinsert(children, 1, data.id);
        end
        data.parent = group.data.id;
        M33kAuras.Add(data);
        M33kAuras.Add(group.data);
        OptionsPrivate.Private.AddParents(group.data)
        M33kAuras.NewDisplayButton(data);
        M33kAuras.UpdateGroupOrders(group.data);
        OptionsPrivate.ClearOptions(group.data.id);
        group.callbacks.UpdateExpandButton();
        group:UpdateParentWarning();
        group:Expand();
        group:ReloadTooltip();
        OptionsPrivate.PickAndEditDisplay(data.id);
      else
        -- move source into the top-level list
        M33kAuras.Add(data);
        M33kAuras.NewDisplayButton(data);
        OptionsPrivate.PickAndEditDisplay(data.id);
      end
    else
      error(string.format("Calling 'M33kAuras.NewAura' with invalid groupId %s. Reload your UI to fix the display list.", targetId))
    end
  else
    -- move source into the top-level list
    M33kAuras.Add(data);
    M33kAuras.NewDisplayButton(data);
    OptionsPrivate.PickAndEditDisplay(data.id);
  end
end


function OptionsPrivate.ResetCollapsed(id, namespace)
  if id then
    if namespace and collapsedOptions[id] then
      collapsedOptions[id][namespace] = nil
    else
      collapsedOptions[id] = nil
    end
  end
end

function OptionsPrivate.IsCollapsed(id, namespace, path, default)
  local tmp = collapsedOptions[id]
  if tmp == nil then return default end

  tmp = tmp[namespace]
  if tmp == nil then return default end

  if type(path) ~= "table" then
    tmp = tmp[path]
  else
    for _, key in ipairs(path) do
      tmp = tmp[key]
      if tmp == nil or tmp[collapsed] then
        break
      end
    end
  end
  if tmp == nil or tmp[collapsed] == nil then
    return default
  else
    return tmp[collapsed]
  end
end

function OptionsPrivate.SetCollapsed(id, namespace, path, v)
  collapsedOptions[id] = collapsedOptions[id] or {}
  collapsedOptions[id][namespace] = collapsedOptions[id][namespace] or {}
  if type(path) ~= "table" then
    collapsedOptions[id][namespace][path] = collapsedOptions[id][namespace][path] or {}
    collapsedOptions[id][namespace][path][collapsed] = v
  else
    local tmp = collapsedOptions[id][namespace] or {}
    for _, key in ipairs(path) do
      tmp[key] = tmp[key] or {}
      tmp = tmp[key]
    end
    tmp[collapsed] = v
  end
end

function OptionsPrivate.MoveCollapseDataUp(id, namespace, path)
  collapsedOptions[id] = collapsedOptions[id] or {}
  collapsedOptions[id][namespace] = collapsedOptions[id][namespace] or {}
  if type(path) ~= "table" then
    collapsedOptions[id][namespace][path], collapsedOptions[id][namespace][path - 1]
      = collapsedOptions[id][namespace][path - 1], collapsedOptions[id][namespace][path]
  else
    local tmp = collapsedOptions[id][namespace]
    local lastKey = tremove(path)
    for _, key in ipairs(path) do
      tmp[key] = tmp[key] or {}
      tmp = tmp[key]
    end
    tmp[lastKey], tmp[lastKey - 1] = tmp[lastKey - 1], tmp[lastKey]
  end
end

function OptionsPrivate.MoveCollapseDataDown(id, namespace, path)
  collapsedOptions[id] = collapsedOptions[id] or {}
  collapsedOptions[id][namespace] = collapsedOptions[id][namespace] or {}
  if type(path) ~= "table" then
    collapsedOptions[id][namespace][path], collapsedOptions[id][namespace][path + 1]
      = collapsedOptions[id][namespace][path + 1], collapsedOptions[id][namespace][path]
  else
    local tmp = collapsedOptions[id][namespace]
    local lastKey = tremove(path)
    for _, key in ipairs(path) do
      tmp[key] = tmp[key] or {}
      tmp = tmp[key]
    end
    tmp[lastKey], tmp[lastKey + 1] = tmp[lastKey + 1], tmp[lastKey]
  end
end

function OptionsPrivate.RemoveCollapsed(id, namespace, path)
  local data = collapsedOptions[id] and collapsedOptions[id][namespace]
  if not data then
    return
  end
  local index
  local maxIndex = 0
  if type(path) ~= "table" then
    index = path
  else
    index = path[#path]
    for i = 1, #path - 1 do
      data = data[path[i]]
      if not data then
        return
      end
    end
  end
  for k in pairs(data) do
    if k ~= collapsed then
      maxIndex = max(maxIndex, k)
    end
  end
  while index <= maxIndex do
    data[index] = data[index + 1]
    index = index + 1
  end
end

function OptionsPrivate.InsertCollapsed(id, namespace, path, value)
  local data = collapsedOptions[id] and collapsedOptions[id][namespace]
  if not data then
    return
  end
  local insertPoint
  local maxIndex
  if type(path) ~= "table" then
    insertPoint = path
  else
    insertPoint = path[#path]
    for i = 1, #path - 1 do
      data = data[path[i]]
      if not data then
        return
      end
    end
  end
  for k in pairs(data) do
    if k ~= collapsed and k >= insertPoint then
      if not maxIndex or k > maxIndex then
        maxIndex = k
      end
    end
  end
  if maxIndex then -- may be nil if insertPoint is greater than the max of anything else
    for i = maxIndex, insertPoint, -1 do
      data[i + 1] = data[i]
    end
  end
  data[insertPoint] = {[collapsed] = value}
end

function OptionsPrivate.DuplicateCollapseData(id, namespace, path)
  collapsedOptions[id] = collapsedOptions[id] or {}
  collapsedOptions[id][namespace] = collapsedOptions[id][namespace] or {}
  if type(path) ~= "table" then
    if (collapsedOptions[id][namespace][path]) then
      tinsert(collapsedOptions[id][namespace], path + 1, CopyTable(collapsedOptions[id][namespace][path]))
    end
  else
    local tmp = collapsedOptions[id][namespace]
    local lastKey = tremove(path)
    for _, key in ipairs(path) do
      tmp[key] = tmp[key] or {}
      tmp = tmp[key]
    end

    if (tmp[lastKey]) then
      tinsert(tmp, lastKey + 1, CopyTable(tmp[lastKey]))
    end
  end
end

function OptionsPrivate.AddTextFormatOption(input, withHeader, get, addOption, hidden, setHidden,
                                            withoutColor, index, total)
  local headerOption
  if withHeader and (not index or index == 1) then
    headerOption =  {
      type = "execute",
      control = "M33kAurasExpandSmall",
      name = L["|cffffcc00Format Options|r"],
      width = M33kAuras.doubleWidth,
      func = function(info, button)
        setHidden(not hidden())
      end,
      image = function()
        return hidden() and "collapsed" or "expanded"
      end,
      imageWidth = 15,
      imageHeight = 15,
      arg = {
        expanderName = tostring(addOption)
      }
    }
    addOption("header", headerOption)
  else
    hidden = false
  end


  local seenSymbols = {}

  local parseFn = function(symbol)
    if not seenSymbols[symbol] then
      local _, sym = string.match(symbol, "(.+)%.(.+)")
      sym = sym or symbol

      if sym == "i" then
        -- No special options for these
      else
        addOption(symbol .. "desc", {
          type = "description",
          name = L["Format for %s"]:format("%" .. symbol),
          width = M33kAuras.normalWidth,
          hidden = hidden
        })
        addOption(symbol .. "_format", {
          type = "select",
          name = L["Format"],
          width = M33kAuras.normalWidth,
          values = OptionsPrivate.Private.format_types_display,
          hidden = hidden,
          reloadOptions = true
        })

        local selectedFormat = get(symbol .. "_format")
        if (OptionsPrivate.Private.format_types[selectedFormat]) then
          OptionsPrivate.Private.format_types[selectedFormat].AddOptions(symbol, hidden, addOption, get, withoutColor)
        end
        seenSymbols[symbol] = true
      end
    end
  end

  if type(input) == "table" then
    for _, txt in ipairs(input) do
      OptionsPrivate.Private.ParseTextStr(txt, parseFn)
    end
  else
    OptionsPrivate.Private.ParseTextStr(input, parseFn)
  end

  if withHeader and (not index or index == total) then
    addOption("header_anchor",
    {
      type = "description",
      name = "",
      control = "M33kAurasExpandAnchor",
      arg = {
        expanderName = tostring(addOption)
      }
    }

  )
  end

  if not next(seenSymbols) and headerOption and not index then
    headerOption.hidden = true
  end

  return next(seenSymbols) ~= nil
end
