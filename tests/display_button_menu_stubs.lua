-- Native menu descriptions and registration lifecycle, without native frames.
local M = {}
function M.install(fixture)
  local methods = {}
  local function description(text, callback)
    local item=setmetatable({text=text,func=callback,enabled=true},{__index=methods})
    item.menuList=item
    return item
  end
  function methods:SetTag(tag,context) self.tag,self.context=tag,context end
  function methods:GetTag() return self.tag,self.context end
  function methods:Insert(item,index) table.insert(self,index or #self+1,item);return item end
  function methods:CreateButton(text,callback) return self:Insert(description(text,callback)) end
  function methods:CreateDivider() local item=description();item.divider=true;return self:Insert(item) end
  function methods:SetEnabled(enabled) self.enabled=enabled end
  function methods:IsEnabled() return self.enabled end
  function methods:EnumerateElementDescriptions() return ipairs(self) end
  function methods:SetOnEnter(callback) self.onEnter=callback end
  function methods:SetTooltip(callback) self.tooltip=callback end
  function methods:Pick() if self.enabled and self.func then self.func() end end
  local callbacks,generated={},{}
  local function invoke(callback,owner,root)
    local ok,err=pcall(callback,owner,root,root.context)
    if not ok then geterrorhandler()(err) end
  end
  _G.Menu={GetManager=function() return {CloseMenus=function()
    if fixture.nativeMenu then fixture.nativeMenu:Close() end
  end} end,ModifyMenu=function(tag,callback)
    local prior=generated[tag]
    -- Blizzard invokes late registration directly, before creating the handle.
    if prior then callback(prior.owner,prior.root,prior.root.context) end
    local registration={callback=callback,tag=tag}
    callbacks[#callbacks+1]=registration
    return {Unregister=function() registration.removed=true end}
  end}
  _G.MenuUtil={CreateButton=description,CreateDivider=function()
    local item=description();item.divider=true;return item
  end,CreateContextMenu=function(owner,generator)
    if fixture.nativeMenu then fixture.nativeMenu:Close() end
    local root=description()
    generator(owner,root)
    if root.tag then
      generated[root.tag]={owner=owner,root=root}
      for _,registration in ipairs(callbacks) do
        if registration.tag==root.tag and not registration.removed then invoke(registration.callback,owner,root) end
      end
    end
    fixture.menu,fixture.menuOwner=root,owner
    local menu={root=root,owner=owner}
    function menu:SetClosedCallback(callback) self.onClose=callback end
    function menu:Close()
      if self.closed then return end
      self.closed=true
      if self.onClose then self.onClose(self) end
    end
    fixture.nativeMenu=menu
    return menu
  end}
  fixture.menuDescription=description
end
return M
