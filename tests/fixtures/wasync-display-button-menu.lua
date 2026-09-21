-- WASync integration fixture; AddonDB, module and MRT are supplied by the test.
local WA = AddonDB.WeakAuras
local displayButtonMenuHandle = Menu.ModifyMenu("M33KAURAS_DISPLAY_BUTTON_MENU", function(_, root, context)
  if #context.selectedUIDs ~= 1 then return end
  local insertionIndex
  for index, entry in root:EnumerateElementDescriptions() do
    if entry:GetTag() == "M33KAURAS_DISPLAY_BUTTON_DELETE_SECTION" then
      insertionIndex = index
      break
    end
  end
  if not insertionIndex then return end
  root:Insert(MenuUtil.CreateDivider(), insertionIndex)
  insertionIndex = insertionIndex + 1
  local id = context.auraId
  local function insert(text, callback)
    local entry = MenuUtil.CreateButton(text, callback)
    root:Insert(entry, insertionIndex)
    insertionIndex = insertionIndex + 1
    return entry
  end
  insert("|cFF8855FFWASync|r Send...", function()
    Menu.GetManager():CloseMenus()
    module:ExternalExportWA(id)
  end)
  insert("|cFF8855FFWASync|r Check Version", function()
    Menu.GetManager():CloseMenus()
    MRT.Options:Open()
    MRT.Options:OpenByModuleName("WAChecker")
    module.options.filterEdit:SetText("")
    module.options.filterEdit:SetText(id)
    module:GetWAVer(id)
  end)
  if not (AddonDB.RGAPI and AddonDB.RGAPI:IsCustomSender("player")) then return end
  insert("|cFF8855FFWASync|r Get AutoImport String", function()
    Menu.GetManager():CloseMenus()
    local task = AddonDB:Async(function()
      local data = WA.GetData(id)
      if not data then return end
      local encoded = module.DisplayToString(data, true)
      return string.format("id = %q,\n\t\t\texrtLastSync = %s,\n\t\t\tdataStr = [[%s]]",
        id, data.exrtLastSync or 0, encoded)
    end)
    AddonDB:QuickCopy(task, "|cFF8855FFWASync|r AutoImport String")
  end)
  local players = insert("|cFF8855FFWASync|r Custom options...")
  for unit in AddonDB:IterateGroupMembers() do
    local fullName = AddonDB:GetFullName(unit)
    local player = players:CreateButton(AddonDB.RGAPI:ClassColorName(unit))
    local function action(text, callback)
      player:CreateButton(text, function()
        Menu.GetManager():CloseMenus()
        callback(id, fullName)
      end)
    end
    action("Request WA", function(auraId, target) module:RequestWA(auraId, target) end)
    action("Set Load Never (|cff00ff00false|r)", function(auraId, target) module:SendSetLoadNever(auraId, target, false) end)
    action("Set Load Never (|cffff0000true|r)", function(auraId, target) module:SendSetLoadNever(auraId, target, true) end)
    action("Archive and Delete", function(auraId, target) module:SendDeleteWA(auraId, target) end)
    action("Edit", function(auraId, target) module:RequestDisplayTable(auraId, target) end)
    action("Get Debug Log", function(auraId, target) module:RequestDebugLog(auraId, target) end)
  end
end)

return displayButtonMenuHandle
