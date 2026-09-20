if not M33kAuras.IsLibsOK() then return end
---@type string
local AddonName = ...
---@class OptionsPrivate
local OptionsPrivate = select(2, ...)

-- Lua APIs
local pairs, error, coroutine = pairs, error, coroutine

-- WoW APIs
local IsSpellKnown = IsSpellKnown
local neverSecret = Enum.SecrecyLevel.NeverSecret
local getAuraSecrecy = C_Secrets.GetSpellAuraSecrecy
local getCooldownSecrecy = C_Secrets.GetSpellCooldownSecrecy
local getCastSecrecy = C_Secrets.GetSpellCastSecrecy

---@class M33kAuras
local M33kAuras = M33kAuras

local spellCache = {}
M33kAuras.spellCache = spellCache

local cache
local metaData
local bestIcon = {}
local secrecyEntries = {}
local emptySecrecyEntries = {}

-- These lists describe fixed spell flags, not the current restriction state.
-- Cache filtered data separately from the visible rows; scrolling never searches the cache.
function spellCache.GetNeverSecretSpells(kind, search)
  local complete = metaData and not metaData.needsRebuild and not metaData.rebuilding
  -- Do not repeatedly copy and sort an incomplete background scan.
  if not complete then return emptySecrecyEntries, 0, false end
  local entries = secrecyEntries[kind]
  if not entries then
    entries = {}
    for id, name in pairs(metaData.neverSecretSpells[kind]) do
      entries[#entries + 1] = { id = id, name = name, searchName = name:lower(), searchId = tostring(id) }
    end
    table.sort(entries, function(a, b) return a.id < b.id end)
    secrecyEntries[kind] = entries
  end
  search = (search or ""):lower():match("^%s*(.-)%s*$")
  if search == "" then return entries, #entries, true end
  if entries.search ~= search then
    entries.search = search
    entries.matches = {}
    for i = 1, #entries do
      local entry = entries[i]
      if entry.searchName:find(search, 1, true) or entry.searchId:find(search, 1, true) then
        entries.matches[#entries.matches + 1] = entry
      end
    end
  end
  return entries.matches, #entries.matches, complete
end

local secrecyList

local function GetSpellSecrecyList(parent)
  if not secrecyList then
    local L = M33kAuras.L
    local list = CreateFrame("Frame", nil, parent)
    list.scrollBox = CreateFrame("Frame", nil, list, "WowScrollBoxList")
    list.scrollBox:SetPoint("TOPLEFT", 0, -2)
    list.scrollBox:SetPoint("BOTTOMRIGHT", -24, 2)
    list.scrollBar = CreateFrame("EventFrame", nil, list, "MinimalScrollBar")
    list.scrollBar:SetPoint("TOPRIGHT", -2, -16)
    list.scrollBar:SetPoint("BOTTOMRIGHT", -2, 16)
    list.empty = list:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    list.empty:SetPoint("CENTER")

    -- ScrollBox acquires frames only for the visible range and pools them as
    -- they scroll out of view. The list and its frame pool survive popup reuse.
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(44)
    view:SetElementInitializer("Button", function(row, entry)
      if not row.icon then
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(32, 32)
        row.icon:SetPoint("LEFT", 4, 0)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetPoint("TOPLEFT", 44, -6)
        row.name:SetPoint("RIGHT", -104, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.id = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.id:SetPoint("TOPLEFT", 44, -24)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.copyButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.copyButton:SetSize(90, 24)
        row.copyButton:SetPoint("RIGHT", -4, 0)
        row.copyButton:SetText(L["Copy ID"])
        row.copyButton:SetScript("OnClick", function()
          if row.entry and list.onCopy then list.onCopy(row.entry.id) end
        end)
        row:SetScript("OnEnter", function()
          if not row.entry then return end
          GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
          GameTooltip:SetSpellByID(row.entry.id)
          GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
          if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
        end)
      end
      row.entry = entry
      row.icon:SetTexture(OptionsPrivate.Private.ExecEnv.GetSpellIcon(entry.id) or 134400)
      row.name:SetText("|cffffd200" .. entry.name .. "|r")
      row.id:SetText(L["Spell ID: %d"]:format(entry.id))
    end)
    view:SetElementResetter(function(row)
      if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
      row.entry = nil
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(list.scrollBox, list.scrollBar, view)
    secrecyList = list
  end
  secrecyList:SetParent(parent)
  secrecyList:ClearAllPoints()
  secrecyList:SetAllPoints()
  secrecyList:Show()
  return secrecyList
end

local closeSecrecyWindow

function OptionsPrivate.OpenSpellSecrecyList(kind)
  spellCache.Build()
  if closeSecrecyWindow then
    closeSecrecyWindow()
  end

  local L = M33kAuras.L
  local AceGUI = LibStub("AceGUI-3.0")
  local titles = {
    aura = L["Never-secret auras"],
    cooldown = L["Never-secret cooldowns"],
    cast = L["Never-secret casts"],
  }
  local window = AceGUI:Create("Frame")
  window:SetTitle(titles[kind])
  window:SetWidth(650)
  window:SetHeight(650)
  window:EnableResize(false)
  window:SetLayout("Flow")

  local help = AceGUI:Create("Label")
  help:SetFullWidth(true)
  help:SetText(L["Spells Blizzard marks as never secret for this list's category. Search by spell name or ID. This list includes spells from all classes and NPCs, not just spells you know. The list becomes available when the spell cache finishes building."])
  window:AddChild(help)

  local search = AceGUI:Create("EditBox")
  search:SetLabel(L["Search"])
  search:SetFullWidth(true)
  search:DisableButton(true)
  window:AddChild(search)

  local results = AceGUI:Create("SimpleGroup")
  results:SetFullWidth(true)
  results:SetAutoAdjustHeight(false)
  results:SetHeight(400)
  window:AddChild(results)
  local list = GetSpellSecrecyList(results.content)

  local copy = AceGUI:Create("EditBox")
  copy:SetLabel(L["Selected spell ID (press Ctrl+C to copy)"])
  copy:SetFullWidth(true)
  copy:DisableButton(true)
  window:AddChild(copy)
  local selectedID = ""
  copy:SetCallback("OnTextChanged", function(_, _, value)
    if value ~= selectedID then copy:SetText(selectedID) end
  end)

  list.onCopy = function(id)
    selectedID = tostring(id)
    copy:SetText(selectedID)
    copy:SetFocus()
    copy:HighlightText()
  end

  local ticker
  local closed = false
  local copyEscape = copy.editbox:GetScript("OnEscapePressed")
  local searchEscape = search.editbox:GetScript("OnEscapePressed")
  local function Close()
    if closed then return end
    closed = true
    if ticker then ticker:Cancel(); ticker = nil end
    list.onCopy = nil
    list.scrollBox:RemoveDataProvider()
    list:Hide()
    list:SetParent(UIParent)
    copy.editbox:SetScript("OnEscapePressed", copyEscape)
    search.editbox:SetScript("OnEscapePressed", searchEscape)
    closeSecrecyWindow = nil
    AceGUI:Release(window)
  end
  closeSecrecyWindow = Close
  window:SetCallback("OnClose", Close)
  copy.editbox:SetScript("OnEscapePressed", Close)
  search.editbox:SetScript("OnEscapePressed", Close)

  local displayedEntries, displayedSearch
  local function Refresh()
    local query = search:GetText()
    local entries, count, complete = spellCache.GetNeverSecretSpells(kind, query)
    if displayedEntries ~= entries then
      list.scrollBox:SetDataProvider(CreateDataProvider(entries), displayedSearch == query)
      displayedEntries, displayedSearch = entries, query
    end
    list.empty:SetText(complete and L["No spells match your search."] or L["The spell list will appear when the spell cache finishes building."])
    list.empty:SetShown(count == 0)
    local status = L["%d matching spells"]:format(count)
    if not complete then
      status = L["Building spell list..."]
    elseif ticker then
      ticker:Cancel()
      ticker = nil
    end
    window:SetStatusText(status)
    return complete
  end
  search:SetCallback("OnTextChanged", Refresh)
  if not Refresh() then
    ticker = C_Timer.NewTicker(1, Refresh)
  end
  search:SetFocus()
end

-- Builds a cache of name/icon pairs from existing spell data
-- This is a rather slow operation, so it's only done once, and the result is subsequently saved
function spellCache.Build()
  if not cache  then
    error("spellCache has not been loaded. Call M33kAuras.spellCache.Load(...) first.")
  end

  if not metaData.needsRebuild or metaData.rebuilding then
    return
  end

  if IsTestBuild() and not M33kAuras.IsForever() then -- disable for 12.0.7
    return
  end

  local holes
  if M33kAuras.IsClassicEra() then
    holes = {}
    holes[63707] = 81743
    holes[81748] = 219002
    holes[219004] = 285223
    holes[285224] = 301088
    holes[301101] = 324269
    holes[474742] = 1213143
  elseif M33kAuras.IsCataClassic() then
    holes = {}
    holes[121820] = 158262
    holes[158263] = 186402
    holes[186403] = 219002
    holes[219004] = 243805
    holes[243806] = 261127
    holes[262591] = 281624
    holes[301101] = 324269
  elseif M33kAuras.IsMists() then
    holes = {}
    holes[171557] = 186402
    holes[186403] = 219002
    holes[219004] = 243805
    holes[243819] = 261127
    holes[262591] = 281624
    holes[301101] = 324269
    holes[473745] = 1214175
  elseif M33kAuras.IsRetail() then
    holes = {}
    holes[474771] = 556604
    holes[556606] = 936050
    holes[936051] = 1049295
    holes[1049296] = 1213133
  end
  wipe(cache)
  wipe(bestIcon)
  metaData.neverSecretSpells = { aura = {}, cooldown = {}, cast = {} }
  secrecyEntries = {}
  metaData.rebuilding = true
  -- Secrecy flags are static for this cache build. Resolve destination tables
  -- once, rather than dispatching by category for every spell.
  local auraSpells = metaData.neverSecretSpells.aura
  local cooldownSpells = metaData.neverSecretSpells.cooldown
  local castSpells = metaData.neverSecretSpells.cast
  local getSpellName = OptionsPrivate.Private.ExecEnv.GetSpellName
  local getSpellIcon = OptionsPrivate.Private.ExecEnv.GetSpellIcon
  local co = coroutine.create(function()
    -- if true then return end -- Spell cache crashes the game
    local id = 0
    local misses = 0
    while misses < 80000 do
      id = id + 1
      local name = getSpellName(id)
      local icon = getSpellIcon(id)
      -- Only the normal cache rebuild collects these static flags. Include
      -- named spells even when the icon picker excludes their icon.
      if name and name ~= "" then
        if getAuraSecrecy(id) == neverSecret then
          auraSpells[id] = name
        end
        if getCooldownSecrecy(id) == neverSecret then
          cooldownSpells[id] = name
        end
        if getCastSecrecy(id) == neverSecret then
          castSpells[id] = name
        end
      end

      if(icon == 136243) then -- 136243 is the a gear icon, we can ignore those spells
        misses = 0;
      elseif name and name ~= "" and icon then
        cache[name] = cache[name] or {}

        if not cache[name].spells or cache[name].spells == "" then
          cache[name].spells = id .. "=" .. icon
        else
          cache[name].spells = cache[name].spells .. "," .. id .. "=" .. icon
        end
        misses = 0
      else
        misses = misses + 1
      end
      if holes and holes[id] then
        id = holes[id]
      end
      coroutine.yield(0.01, "spells")
    end

    if M33kAuras.IsCataOrMistsOrRetail() then
      for _, category in pairs(GetCategoryList()) do
        local total = GetCategoryNumAchievements(category, true)
        for i = 1, total do
          local id,name,_,_,_,_,_,_,_,iconID = GetAchievementInfo(category, i)
          if name and iconID then
            cache[name] = cache[name] or {}
            if not cache[name].achievements or cache[name].achievements == "" then
              cache[name].achievements = id .. "=" .. iconID
            else
              cache[name].achievements = cache[name].achievements .. "," .. id .. "=" .. iconID
            end
          end
          coroutine.yield(0.1, "achievements")
        end
        coroutine.yield(0.1, "categories")
      end
    end

    metaData.needsRebuild = false
    metaData.rebuilding = false
  end)
  OptionsPrivate.Private.Threads:Add("spellCache", co, 'background')
end

--[[ function to help find big holes in spellIds to help speedup Build()

local id = 0
local misses = 0
local lastId
print("####")
while misses < 4000000 do
   id = id + 1
   local spellInfo = C_Spell.GetSpellInfo(id)
   local name = spellInfo and spellInfo.name
   local icon = C_Spell.GetSpellTexture(id)
   if icon == 136243 then -- 136243 is the a gear icon, we can ignore those spells
      misses = 0
   elseif name and name ~= "" and icon then
      if misses > 10000 then
         print(("holes[%s] = %s"):format(lastId, id - 1))
      end
      lastId = id
      misses = 0
   else
      misses = misses + 1
   end
end
print("lastId", lastId)
]]

function spellCache.GetIcon(name)
  if (name == nil) then
    return nil;
  end
  if cache then
    if (bestIcon[name]) then
      return bestIcon[name]
    end

    local icons = cache[name]
    local bestMatch = nil
    if (icons) then
      if (icons.spells) then
        for spell, icon in icons.spells:gmatch("(%d+)=(%d+)") do
          local spellId = tonumber(spell)

          if not bestMatch or (spellId and spellId ~= 0 and IsSpellKnown(spellId)) then
            bestMatch = tonumber(icon)
          end
        end
      end
    elseif metaData.rebuilding then
      OptionsPrivate.Private.Threads:SetPriority('spellCache', 'normal')
    end

    bestIcon[name] = bestMatch
    return bestIcon[name]
  else
    error("spellCache has not been loaded. Call M33kAuras.spellCache.Load(...) first.")
  end
end

function spellCache.GetSpellsMatching(name)
  if cache[name] then
    if cache[name].spells then
      local result = {}
      for spell, icon in cache[name].spells:gmatch("(%d+)=(%d+)") do
        local spellId = tonumber(spell)
        local iconId = tonumber(icon)
        result[spellId] = icon
      end
      return result
    end
  elseif metaData.rebuilding then
    OptionsPrivate.Private.Threads:SetPriority('spellCache', 'normal')
  end
end

function spellCache.AddIcon(name, id, icon)
  if not cache then
    error("spellCache has not been loaded. Call M33kAuras.spellCache.Load(...) first.")
    return
  end

  if name and id and icon then
    cache[name] = cache[name] or {}
    if not cache[name].spells or cache[name].spells == "" then
      cache[name].spells = id .. "=" .. icon
    else
      cache[name].spells = cache[name].spells .. "," .. id .. "=" .. icon
    end
  end
end

function spellCache.Get()
  if cache then
    return cache
  else
    error("spellCache has not been loaded. Call M33kAuras.spellCache.Load(...) first.")
  end
end

function spellCache.Load(data)
  metaData = data
  cache = metaData.spellCache
  local interrupted = metaData.rebuilding
  metaData.rebuilding = false
  secrecyEntries = {}
  wipe(bestIcon)

  local _, build = GetBuildInfo();
  local locale = GetLocale();
  local version = M33kAuras.versionString

  local num = 0;
  for _ in pairs(cache) do
    num = num + 1;
    if num >= 39000 then break end
  end

  if(num < 39000 or metaData.locale ~= locale or metaData.build ~= build
     or metaData.version ~= version or not metaData.spellCacheStrings or interrupted
     or type(metaData.neverSecretSpells) ~= "table"
     or type(metaData.neverSecretSpells.aura) ~= "table"
     or type(metaData.neverSecretSpells.cooldown) ~= "table"
     or type(metaData.neverSecretSpells.cast) ~= "table")
  then
    metaData.build = build;
    metaData.locale = locale;
    metaData.version = version;
    metaData.spellCacheAchievements = true
    metaData.spellCacheStrings = true
    metaData.needsRebuild = true
    metaData.neverSecretSpells = { aura = {}, cooldown = {}, cast = {} }
    wipe(cache)
  end
end

-- This function computes the Levenshtein distance between two strings
-- It is used in this program to match spell icon textures with "good" spell names; i.e.,
-- spell names that are very similar to the name of the texture
local function Lev(str1, str2)
  local matrix = {};
  for i=0, str1:len() do
    matrix[i] = {[0] = i};
  end
  for j=0, str2:len() do
    matrix[0][j] = j;
  end
  for j=1, str2:len() do
    for i =1, str1:len() do
      if(str1:sub(i, i) == str2:sub(j, j)) then
        matrix[i][j] = matrix[i-1][j-1];
      else
        matrix[i][j] = math.min(matrix[i-1][j], matrix[i][j-1], matrix[i-1][j-1]) + 1;
      end
    end
  end

  return matrix[str1:len()][str2:len()];
end

function spellCache.BestKeyMatch(nearkey)
  local bestKey = "";
  local bestDistance = math.huge;
  local partialMatches = {};
  if cache[nearkey] then
    return nearkey
  end
  for key, value in pairs(cache) do
    if key:lower() == nearkey:lower() then
      return key
    end
    if(key:lower():find(nearkey:lower(), 1, true)) then
      partialMatches[key] = value;
    end
  end
  for key, value in pairs(partialMatches) do
    local distance = Lev(nearkey, key);
    if(distance < bestDistance) then
      bestKey = key;
      bestDistance = distance;
    end
  end

  return bestKey;
end

---@param input string | number
---@return string name, number? id
function spellCache.CorrectAuraName(input)
  if (not cache) then
    error("spellCache has not been loaded. Call M33kAuras.spellCache.Load(...) first.")
  end

  local spellId = M33kAuras.SafeToNumber(input)
  if type(input) == "string" and input:find("|", nil, true) then
    spellId = M33kAuras.SafeToNumber(input:match("|Hspell:(%d+)"))
  end
  if(spellId) then
    local name, _, icon = OptionsPrivate.Private.ExecEnv.GetSpellInfo(spellId);
    if(name) then
      spellCache.AddIcon(name, spellId, icon)
      return name, spellId;
    else
      return "Invalid Spell ID", spellId;
    end
  else
    local ret = spellCache.BestKeyMatch(input);
    if(ret == "") then
      return "No Match Found", nil;
    else
      return ret, nil;
    end
  end
end
