if not M33kAuras.IsLibsOK() then return end
local _, OptionsPrivate = ...

-- Entries retain selection and preview state when filtered views or pooled rows change.
function OptionsPrivate.CreateAuraListModel(createEntry)
  local model = {byUID = {}, byID = {}, roots = {}, filter = "", matches = {}}

  function model:Ensure(data)
    local entry = self.byUID[data.uid]
    if not entry then
      entry = createEntry(data)
      self.byUID[data.uid] = entry
    end
    -- Saved data is renamed in place; retain the previously indexed name separately.
    if entry.indexedID ~= data.id and self.byID[entry.indexedID] == entry then
      self.byID[entry.indexedID] = nil
    end
    entry.indexedID = data.id
    entry.data = data
    entry.searchName = data.id:lower()
    self.byID[data.id] = entry
    return entry
  end

  function model:Remove(uid)
    local entry = self.byUID[uid]
    if entry then
      if self.byID[entry.indexedID] == entry then self.byID[entry.indexedID] = nil end
      self.byUID[uid] = nil
    end
    return entry
  end

  function model:Sync(displays, loaded, filter)
    local alive = {}
    wipe(self.byID)
    wipe(self.roots)
    for _, data in pairs(displays) do
      local entry = self:Ensure(data)
      alive[data.uid] = true
      entry.children = {}
      entry.parent = nil
    end
    for uid in pairs(self.byUID) do
      if not alive[uid] then self.byUID[uid] = nil end
    end
    for id, entry in pairs(self.byID) do
      if not entry.data.parent or not self.byID[entry.data.parent] then
        self.roots[#self.roots + 1] = entry
      end
      for _, childID in ipairs(entry.data.controlledChildren or {}) do
        local child = self.byID[childID]
        if child and child.data.parent == id then
          entry.children[#entry.children + 1] = child
          child.parent = entry
        end
      end
    end
    table.sort(self.roots, function(a, b)
      local left, right = a.searchName, b.searchName
      return left == right and a.data.id < b.data.id or left < right
    end)
    local visited = {}
    local function summarize(entry)
      if visited[entry] then return end
      visited[entry] = true
      local active, standby, unloaded, allowed = 0, 0, 0, false
      if entry.data.controlledChildren then
        for _, child in ipairs(entry.children) do
          summarize(child)
          active = active + (child.activeCount or 0)
          standby = standby + (child.standbyCount or 0)
          unloaded = unloaded + (child.unloadedCount or 0)
          allowed = allowed or not child.neverLoad
        end
      else
        active = loaded[entry.data.id] == true and 1 or 0
        standby = loaded[entry.data.id] == false and 1 or 0
        unloaded = loaded[entry.data.id] == nil and 1 or 0
        allowed = not (entry.data.load and entry.data.load.use_never)
      end
      entry.activeCount, entry.standbyCount, entry.unloadedCount = active, standby, unloaded
      entry.neverLoad = not allowed
      entry.section = (active > 0 or standby > 0 or
        (entry.data.controlledChildren and #entry.data.controlledChildren == 0)) and "loaded" or "unloaded"
    end
    for _, entry in ipairs(self.roots) do summarize(entry) end
    self:SetFilter(filter == nil and self.filter or filter)
  end

  function model:SetFilter(filter)
    self.filter = (filter or ""):lower()
    wipe(self.matches)
    if self.filter == "" then return end
    local terms = OptionsPrivate.Private.splitAtOr(self.filter)
    for id, entry in pairs(self.byID) do
      for _, term in ipairs(terms) do
        if entry.searchName:find(term, 1, true) then
          local current = entry
          while current and not self.matches[current.data.uid] do
            self.matches[current.data.uid] = true
            current = current.parent
          end
          break
        end
      end
    end
  end

  function model:Includes(entry)
    return self.filter == "" or self.matches[entry.data.uid] == true
  end

  function model:VisibleEntries(isExpanded, isSectionExpanded)
    local result = {}
    local function visit(entry)
      if not self:Includes(entry) then return end
      result[#result + 1] = entry
      if isExpanded(entry) then
        for _, child in ipairs(entry.children) do visit(child) end
      end
    end
    for _, section in ipairs({"loaded", "unloaded"}) do
      if isSectionExpanded(section) then
        for _, root in ipairs(self.roots) do
          if root.section == section then visit(root) end
        end
      end
    end
    return result
  end

  return model
end
