if not M33kAuras.IsLibsOK() then return end
local _, OptionsPrivate = ...
local L = M33kAuras.L
local activeMenu

function OptionsPrivate.CloseDisplayButtonMenu()
  local menu = activeMenu
  activeMenu = nil
  if menu then menu:Close() end
end

local copyParts = {
  {"Everything", "all", "Paste Settings"},
  {"Display", "display", "Paste Display Settings"},
  {"Trigger", "trigger", "Paste Trigger Settings"},
  {"Conditions", "condition", "Paste Condition Settings"},
  {"Load", "load", "Paste Load Settings"},
  {"Actions", "action", "Paste Action Settings"},
  {"Animations", "animation", "Paste Animations Settings"},
  {"Author Options", "authorOptions", "Paste Author Options Settings"},
  {"Custom Configuration", "config", "Paste Custom Configuration"},
}

local function getSelection(uids)
  local ids = {}
  for _, uid in ipairs(uids) do
    local data = OptionsPrivate.Private.GetDataByUID(uid)
    -- Do not apply a batch action to only part of the original selection.
    if not data then return end
    ids[#ids + 1] = data.id
  end
  return ids
end

function OptionsPrivate.BuildDisplayButtonMenu(root, context)
  -- Menu modifiers share contextData; retain private action targets before dispatch.
  local uid, uids = context.auraUID, CopyTable(context.selectedUIDs)
  local data = OptionsPrivate.Private.GetDataByUID(uid)
  if not data then return end
  root:SetTag("M33KAURAS_DISPLAY_BUTTON_MENU", context)

  local function single(action)
    return function()
      OptionsPrivate.CloseDisplayButtonMenu()
      local current = OptionsPrivate.Private.GetDataByUID(uid)
      if current then action(OptionsPrivate.GetDisplayEntry(current.id), current) end
    end
  end
  local function batch(action)
    return function()
      OptionsPrivate.CloseDisplayButtonMenu()
      local ids = getSelection(uids)
      if ids then action(ids) end
    end
  end
  local deleteAction, deleteText
  if #uids > 1 then
    local ids = getSelection(uids)
    if not ids then return end
    local anyGroup, allSameParent, commonParent = false, true, nil
    for i, id in ipairs(ids) do
      local child = M33kAuras.GetData(id)
      anyGroup = anyGroup or child.controlledChildren ~= nil
      if i == 1 then commonParent = child.parent
      elseif child.parent ~= commonParent then allSameParent = false end
    end
    local parent = allSameParent and commonParent and M33kAuras.GetData(commonParent)
    local insideDynamicGroup = parent and parent.regionType == "dynamicgroup"
    root:CreateButton(L["Add to new Group"], batch(function(selected)
      OptionsPrivate.CreateGroupFromDisplayButtonSelection(selected, "group")
    end)):SetEnabled(not insideDynamicGroup)
    root:CreateButton(L["Add to new Dynamic Group"], batch(function(selected)
      OptionsPrivate.CreateGroupFromDisplayButtonSelection(selected, "dynamicgroup", true)
    end)):SetEnabled(not anyGroup and not insideDynamicGroup)
    root:CreateButton(L["Duplicate All"], batch(OptionsPrivate.DuplicateDisplayButtonSelection))
    deleteText, deleteAction = L["Delete all"], batch(OptionsPrivate.DeleteDisplayButtonSelection)
  else
    root:CreateButton(L["Rename"], single(function(entry) entry.callbacks.OnRenameClick() end))
    local copy = root:CreateButton(L["Copy settings..."])
    local function addCopy(label, part, pasteText)
      copy:CreateButton(L[label], single(function(_, current)
        OptionsPrivate.CopyDisplayButtonSettings(current, part, L[pasteText])
      end))
    end
    if data.controlledChildren then
      addCopy("Group", "display", "Paste Group Settings")
    else
      for _, part in ipairs(copyParts) do addCopy(unpack(part)) end
    end
    local pasteText = OptionsPrivate.GetDisplayButtonPasteText(data)
    if pasteText then
      root:CreateButton(pasteText, single(function(_, current)
        OptionsPrivate.PasteDisplayButtonSettings(current)
      end))
    end
    if not data.controlledChildren then
      local convert = root:CreateButton(L["Convert to..."])
      for regionType, region in pairs(OptionsPrivate.Private.regionOptions) do
        if regionType ~= "group" and regionType ~= "dynamicgroup" and regionType ~= data.regionType then
          convert:CreateButton(region.displayName, single(function(_, current)
            OptionsPrivate.ConvertDisplay(current, regionType)
          end))
        end
      end
    end
    root:CreateButton(L["Duplicate"], single(function(entry) entry.callbacks.OnDuplicateClick() end))
    root:CreateButton(L["Export..."], single(function(_, current) OptionsPrivate.ExportToString(current.id) end))
    root:CreateButton(L["Export debug table..."], single(function(_, current) OptionsPrivate.ExportToTable(current.id) end))
    deleteText = data.controlledChildren and L["Delete children and group"] or L["Delete"]
    deleteAction = single(function(entry, current)
      if current.controlledChildren then entry.callbacks.OnDeleteAllClick()
      else entry.callbacks.OnDeleteClick() end
    end)
  end
  root:CreateDivider():SetTag("M33KAURAS_DISPLAY_BUTTON_DELETE_SECTION")
  root:CreateButton(deleteText, deleteAction):SetTag("M33KAURAS_DISPLAY_BUTTON_DELETE")
  root:CreateDivider()
  root:CreateButton(L["Close"], OptionsPrivate.CloseDisplayButtonMenu):SetTag("M33KAURAS_DISPLAY_BUTTON_CLOSE")
end

function OptionsPrivate.OpenDisplayButtonMenu(entry)
  if not entry.row then return end
  OptionsPrivate.CloseDisplayButtonMenu()
  local multiple = OptionsPrivate.IsDisplayPicked(entry.data.id) and OptionsPrivate.IsPickedMultiple()
  if not multiple and not OptionsPrivate.IsDisplayPicked(entry.data.id) then
    M33kAuras.PickDisplay(entry.data.id, entry:IsGroup() and "group" or nil)
  end
  local context = {auraId = entry.data.id, auraUID = entry.uid, selectedIds = {}, selectedUIDs = {}}
  local selection = multiple and OptionsPrivate.tempGroup.controlledChildren or {entry.data.id}
  for _, id in ipairs(selection) do
    local data = M33kAuras.GetData(id)
    if data then
      context.selectedIds[#context.selectedIds + 1] = id
      context.selectedUIDs[#context.selectedUIDs + 1] = data.uid
    end
  end
  -- The list frame is stable; extensions never receive a pooled display button.
  local menu = MenuUtil.CreateContextMenu(OptionsPrivate.ScrollBox, function(_, root)
    OptionsPrivate.BuildDisplayButtonMenu(root, context)
  end)
  activeMenu = menu
  if menu then
    menu:SetClosedCallback(function() if activeMenu == menu then activeMenu = nil end end)
  end
end
