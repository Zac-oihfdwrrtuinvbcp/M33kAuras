if not M33kAuras.IsLibsOK() then return end
---@type string
local AddonName = ...
---@class OptionsPrivate
local OptionsPrivate = select(2, ...)

local pairs, next, type, unpack = pairs, next, type, unpack

local Type, Version = "M33kAurasPendingInstallButton", 5
local AceGUI = LibStub and LibStub("AceGUI-3.0", true)

if not AceGUI or (AceGUI:GetWidgetVersion(Type) or 0) >= Version then
  return
end

--[[-----------------------------------------------------------------------------
Methods
-------------------------------------------------------------------------------]]
local methods = {
  ["OnAcquire"] = function(self)
    self:SetWidth(1000)
    self:SetHeight(32)
    self.hasThumbnail = false
    self:SetLogo([[Interface\AddOns\M33kAuras\Media\Textures\wagoupdate_logo.tga]])
    self:SetRefreshLogo([[Interface\AddOns\M33kAuras\Media\Textures\wagoupdate_refresh.tga]])
  end,
  ["Initialize"] = function(self, id, companionData)
    self.callbacks = {}
    self.id = id
    self.companionData = companionData

    function self.callbacks.OnUpdateClick()
      M33kAuras.Import(self.companionData.encoded)
    end

    self:SetTitle(self.companionData.name)
    self.update:SetScript("OnClick", self.callbacks.OnUpdateClick)
    self.data = OptionsPrivate.GetCompanionPreview(self.companionData)
    if not self.data then self:Disable(); return end
    self.frame:EnableKeyboard(false)
    self:Enable()
    self.frame:Hide()
  end,
  ["SetLogo"] = function(self, path)
    self.frame.updateLogo.tex:SetTexture(path)
  end,
  ["SetRefreshLogo"] = function(self, path)
    self.frame.update:SetNormalTexture(path)
  end,
  ["Disable"] = function(self)
    self.background:Hide()
    self.frame:Disable()
    self.update:Disable()
  end,
  ["Enable"] = function(self)
    self.background:Show()
    self.frame:Enable()
    self.update:Show()
    self.update:Enable()
    self.updateLogo:Show()
    self:UpdateThumbnail()
  end,
  ["OnRelease"] = function(self)
    self:ReleaseThumbnail()
    self:Enable()
    self.title:Show()
    self.frame:SetScript("OnEnter", nil)
    self.frame:SetScript("OnLeave", nil)
    self.frame:SetScript("OnClick", nil)
    self.frame:ClearAllPoints()
    self.frame:Hide()
    self.update.animGroup:Stop()
    self.update:SetScript("OnClick", nil)
    self.companionData = nil
    self.frame.description = nil
    self.menu = nil
    self.callbacks = nil
    self.iconRegion = nil
    self.orgIcon = nil
    self.linkedAuras = nil
    self.linkedChildren = nil
    self.data = nil
  end,
  ["SetTitle"] = function(self, title)
    self.titletext = title
    self.title:SetText(title)
  end,
  ["SetClick"] = function(self, func)
    self.frame:SetScript("OnClick", func)
  end,
  ["UpdateThumbnail"] = OptionsPrivate.AuraListThumbnail.Update,
  ["ReleaseThumbnail"] = OptionsPrivate.AuraListThumbnail.Release,
  ["AcquireThumbnail"] = function(self) OptionsPrivate.AuraListThumbnail.Acquire(self, true) end,
  ["SetIcon"] = function(self, icon)
    self.orgIcon = icon
    if (type(icon) == "string" or type(icon) == "number") then
      self.icon:SetTexture(icon)
      self.icon:Show()
      if (self.iconRegion and self.iconRegion.Hide) then
        self.iconRegion:Hide()
      end
    else
      self.iconRegion = icon
      icon:SetAllPoints(self.icon)
      icon:SetParent(self.frame)
      icon:Show()
      self.iconRegion:Show()
      self.icon:Hide()
    end
  end,
}

--[[-----------------------------------------------------------------------------
Constructor
-------------------------------------------------------------------------------]]

local function Constructor()
  local name = "M33kAurasPendingInstallButton" .. AceGUI:GetNextWidgetNum(Type)
  local button = CreateFrame("Button", name, UIParent)
  button:SetHeight(32)
  button:SetWidth(1000)
  button.data = {}

  local background = button:CreateTexture(nil, "BACKGROUND")
  button.background = background
  background:SetTexture("Interface\\BUTTONS\\UI-Listbox-Highlight2.blp")
  background:SetBlendMode("ADD")
  background:SetVertexColor(0.5, 1, 0.5, 0.3)
  background:SetPoint("TOP", button, "TOP")
  background:SetPoint("BOTTOM", button, "BOTTOM")
  background:SetPoint("LEFT", button, "LEFT")
  background:SetPoint("RIGHT", button, "RIGHT")

  local icon = button:CreateTexture(nil, "OVERLAY")
  button.icon = icon
  icon:SetWidth(32)
  icon:SetHeight(32)
  icon:SetPoint("LEFT", button, "LEFT")

  local title = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  button.title = title
  title:SetHeight(14)
  title:SetJustifyH("LEFT")
  title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 2, 0)
  title:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT")
  title:SetVertexColor(0.6, 0.6, 0.6)

  button.description = {}

  local update = CreateFrame("Button", nil, button)
  button.update = update
  update.disabled = true
  update.func = function()
  end
  update:SetNormalTexture([[Interface\AddOns\M33kAuras\Media\Textures\wagoupdate_refresh.tga]])
  update:Disable()
  update:SetWidth(24)
  update:SetHeight(24)
  update:SetPoint("RIGHT", button, "RIGHT", -2, 0)

  local updateLogo = CreateFrame("Frame", nil, button)
  button.updateLogo = updateLogo
  local tex = updateLogo:CreateTexture()
  tex:SetTexture([[Interface\AddOns\M33kAuras\Media\Textures\wagoupdate_logo.tga]])
  tex:SetAllPoints()
  updateLogo.tex = tex
  updateLogo:SetSize(24, 24)
  updateLogo:SetPoint("CENTER", update)
  updateLogo:SetFrameStrata(update:GetFrameStrata())
  updateLogo:SetFrameLevel(update:GetFrameLevel()-1)

  local animGroup = update:CreateAnimationGroup()
  update.animGroup = animGroup

  local animRotate = animGroup:CreateAnimation("rotation")
  animRotate:SetDegrees(-360)
  animRotate:SetDuration(1)
  animRotate:SetSmoothing("OUT")
  animGroup:SetScript("OnFinished", function()
    if update:IsMouseOver() then
      animGroup:Play()
    end
  end)
  update:SetScript("OnEnter", function()
    animGroup:Play()
  end)
  update:Hide()
  updateLogo:Hide()

  --- @type table<string, any>
  local widget = {
    frame = button,
    title = title,
    icon = icon,
    background = background,
    update = update,
    updateLogo = updateLogo,
    type = Type,
  }

  for method, func in pairs(methods) do
    widget[method] = func
  end

  return AceGUI:RegisterAsWidget(widget)
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
