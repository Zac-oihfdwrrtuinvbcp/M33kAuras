local testsDir=arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path=testsDir.."/?.lua;"..package.path
local T=require("helpers")
local f=require("aura_list_stubs").install(T)
local options=f.options
f:add("Group",nil,{"Child"});f:add("Child","Group");f:add("Other")
options.RefreshAuraList("")
f.frame.window="default"
local file=assert(io.open(T.repoRoot.."/M33kAuras/M33kAuras.lua"))
local source=file:read("*a");file:close()
local first=assert(source:find("function M33kAuras.OpenOptionsForAura(",1,true))
local last=assert(source:find("function Private.PrintHelp()",first,true))
assert(loadstring("local Private=...;"..source:sub(first,last-1)))(f.private)
local ready,combat,repair,importing,paused=true,false,false,false,false
M33kAuras.IsLoginFinished=function() return ready end
InCombatLockdown=function() return combat end
f.private.NeedToRepairDatabase=function() return repair end
M33kAuras.IsImporting=function() return importing end
f.private.IsOptionsProcessingPaused=function() return paused end
local loads,opens=0,0
local initialized,constructed=0,0
local centerRequests=0
local scrollTo=f.box.ScrollToElementDataByPredicate
f.box.ScrollToElementDataByPredicate=function(self,predicate,alignment,...)
  if alignment==ScrollBoxConstants.AlignCenter then centerRequests=centerRequests+1 end
  return scrollTo(self,predicate,alignment,...)
end
local loadFailed=false
f.private.LoadOptions=function()
  loads=loads+1
  if loadFailed then return false end
  if not M33kAuras.ToggleOptions then
    f:loadMain()
    -- Exercise real initialization and ShowOptions, replacing only frame construction.
    options.Private=nil
    options.registerRegions={function() initialized=initialized+1 end}
    options.CreateFrame=function() constructed=constructed+1;return f.frame end
    f.private.SetFakeStates=function() end
    M33kAuras.spellCache.Build=function() end
    GetScreenWidth=function() return 1920 end
    GetScreenHeight=function() return 1080 end
    f.frame.moversizer.OptionsOpened=function() end
    f.frame.NewAura=function() end
    f.frame.ShowTip=function() end
    local showOptions=M33kAuras.ShowOptions
    for i=1,30 do
      local name=debug.getupvalue(showOptions,i)
      if name=="frame" then debug.setupvalue(showOptions,i,nil);break end
    end
    M33kAuras.ShowOptions=function(...) opens=opens+1;return showOptions(...) end
  end
  return true
end
local function rejected(reason,id)
  local selection,filter,scrolls,shown=f.frame.pickedDisplay,f.frame.filterInput:GetText(),f.scrolls,f.frame:IsShown()
  local ok,actual=M33kAuras.OpenOptionsForAura(id or "Child")
  T.expect(ok==false and actual==reason and selection==f.frame.pickedDisplay
    and filter==f.frame.filterInput:GetText() and scrolls==f.scrolls and shown==f.frame:IsShown(),
    "navigation returns "..reason.." without changing the view or selection")
end
rejected("aura-not-found","Missing")
ready=false
local getData=M33kAuras.GetData
M33kAuras.GetData=function() error("database is not initialized") end
rejected("not-ready")
M33kAuras.GetData=getData;ready=true
combat=true;rejected("in-combat");combat=false
repair=true;rejected("database-repair-required");repair=false
importing=true;rejected("options-busy");importing=false
paused=true;rejected("options-busy");paused=false
T.expect(loads==0 and not M33kAuras.ToggleOptions,"rejected requests do not load options")
loadFailed=true;rejected("options-load-failed");loadFailed=false
f.frame:Hide()
options.SetCollapsed("Group","displayButton","",true)
f.frame.filterInput:SetText("Other")
options.RefreshAuraList("Other")
local ok=M33kAuras.OpenOptionsForAura("Child")
T.expect(ok and opens==1 and f.frame:IsShown() and f.frame.pickedDisplay=="Child",
  "the core API loads options, opens the window and selects the requested aura")
T.expect(initialized==1 and constructed==1,"first navigation initializes options and constructs its frame once")
T.expect(f.frame.filterInput:GetText()=="" and options.GetDisplayEntry("Child").row
  and not options.IsCollapsed("Group","displayButton","",true),
  "navigation clears a hiding filter, expands ancestors and reveals the display button")
T.expect(centerRequests==1,"external navigation requests centered alignment")
options.PickDisplayMultiple("Other")
ok=M33kAuras.OpenOptionsForAura("Child")
T.expect(ok and opens==1 and f.frame:IsShown() and f.frame.pickedDisplay=="Child"
  and #options.tempGroup.controlledChildren==0,"an open window stays open and multiple selection becomes single selection")
f.frame.filterInput:SetText("Child");options.RefreshAuraList("Child")
local beforeCenter=centerRequests
ok=M33kAuras.OpenOptionsForAura("Child")
T.expect(ok and f.frame.filterInput:GetText()=="Child","a matching search is preserved, including repeated navigation")
T.expect(centerRequests==beforeCenter+1,"external navigation centers even an already-visible selected display button")
local nearestBefore=centerRequests
options.RevealDisplay("Child")
T.expect(centerRequests==nearestBefore,"ordinary reveal does not request centered alignment")
paused=true
options.RevealDisplay("Child",false,ScrollBoxConstants.AlignCenter)
local child=M33kAurasSaved.displays.Child
M33kAurasSaved.displays.Child=nil;child.id="Renamed Child";M33kAurasSaved.displays[child.id]=child
M33kAurasSaved.displays.Group.controlledChildren[1]=child.id
paused=false
local centeredId
local scrollPending=f.box.ScrollToElementDataByPredicate
f.box.ScrollToElementDataByPredicate=function(self,predicate,alignment,...)
  if alignment==ScrollBoxConstants.AlignCenter then
    for uid,node in pairs(options.auraListNodes) do
      if predicate(node) then centeredId=node:GetData().entry.data.id end
    end
  end
  return scrollPending(self,predicate,alignment,...)
end
options.RefreshAuraList("")
T.expect(centerRequests==nearestBefore+1 and centeredId=="Renamed Child",
  "a deferred reveal retains centered alignment and resolves a renamed target by UID")
f.box.ScrollToElementDataByPredicate=scrollPending
M33kAurasSaved.displays[child.id]=nil;child.id="Child";M33kAurasSaved.displays.Child=child
M33kAurasSaved.displays.Group.controlledChildren[1]=child.id
options.RefreshAuraList("")
f.frame.window="texteditor";rejected("options-busy");f.frame.window="default"
options.massDelete=true;rejected("options-busy");options.massDelete=nil
options.movingAuras=true;rejected("options-busy");options.movingAuras=nil
options.StartAuraDrag(options.GetDisplayEntry("Child"))
rejected("options-busy")
options.EndAuraDrag()
local before=opens
combat=true;rejected("in-combat");combat=false
f:flush()
T.expect(opens==before,"blocked requests never schedule a later opening")
M33kAuras.ToggleOptions(nil,f.private)
T.expect(not f.frame:IsShown(),"ordinary ToggleOptions still closes an open window")
ok=M33kAuras.OpenOptionsForAura("Other")
T.expect(ok and f.frame:IsShown() and f.frame.pickedDisplay=="Other" and opens==2
  and initialized==1 and constructed==1,"reopening uses the existing frame and changes selection without reinitializing")
f.frame.unloadedButton:Collapse()
ok=M33kAuras.OpenOptionsForAura("Group")
T.expect(ok and f.frame.pickedDisplay=="Group" and f.frame.unloadedButton:GetExpanded()
  and options.GetDisplayEntry("Group").row,"group navigation expands a collapsed unloaded section")
T.expect(#f.errors==0,"navigation reports no hidden callback errors")
T.finish()
