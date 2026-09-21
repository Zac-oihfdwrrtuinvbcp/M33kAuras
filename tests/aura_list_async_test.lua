local testsDir=arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path=testsDir.."/?.lua;"..package.path
local T=require("helpers")
local f=require("aura_list_stubs").install(T)
local options=f.options
f:add("Group",nil,{})
f:add("A");f:add("B")
options.RefreshAuraList("");f:loadMain()
-- Run the real scheduler with a deterministic clock and WoW argument helpers.
local tick=0
_G.floor=math.floor
_G.debugprofilestop=function() tick=tick+1;return tick end
_G.debugstack=function() return "test stack" end
_G.SafePack=function(...) return {n=select("#",...),...} end
_G.SafeUnpack=function(t) return unpack(t,1,t.n) end
_G.IsInInstance=function() return false end
_G.IsEncounterInProgress=function() return false end
_G.tDeleteItem=function(t,item) for i,v in ipairs(t) do if v==item then table.remove(t,i);return end end end
T.loadAddonFile("M33kAuras/Async.lua","M33kAuras",f.private)
local scheduler=f.frames[#f.frames]
local tasks={}
local async=f.private.Async
f.private.Async=function(self,...)
  local task=async(self,...);tasks[#tasks+1]=task;return task
end
local function pump()
  for i=1,500 do
    if not scheduler:IsShown() then f:flush();return end
    scheduler:GetScript("OnUpdate")(scheduler,0.016)
    f:flush() -- WoW timers also run between scheduler frames.
  end
  error("scheduler did not drain")
end
options.StartAuraDrag=function() end
local source=options.GetDisplayEntry("A")
local target=options.GetDisplayEntry("Group")
M33kAuras.PickDisplay("A")
options.PickDisplayMultiple("B")
options.StartDrag(source.data)
local moved={}
local function action(entry,destination)
  moved[#moved+1]=entry.data.id
  entry.data.parent=destination.data.id
  table.insert(destination.data.controlledChildren,entry.data.id)
end
options.Drop(source.data,target,action,"GROUP")
T.expect(options.movingAuras==true,"a queued drop reserves the operation before its first scheduler slice")
options.DragReset() -- Closing options invokes this while a move is still queued.
pump()
T.expect(#moved==2 and moved[1]=="B" and moved[2]=="A","closing options cannot erase the selection captured by a queued drop")
T.expect(not options.movingAuras and not source.dragging,"completed moves clear operation and drag state")

M33kAuras.PickDisplay("A")
options.StartDrag(source.data)
options.Drop(source.data,target,function() error("injected drop failure") end,"GROUP")
pump()
T.expect(#f.errors==1 and f.errors[1]:find("injected drop failure",1,true),"the real scheduler reports an action error")
T.expect(not options.movingAuras and source:IsEnabled() and not source.dragging,"action errors restore interaction and clear drag state")

options.StartDrag(source.data)
options.Drop(source.data,target,action,"GROUP")
local before=#moved
tasks[#tasks]:Kill()
f:flush()
T.expect(#moved==before and not options.movingAuras and not source.dragging,"cancelling before the first slice also releases the drag and operation lock")

options.StartDrag(source.data)
options.Drop(source.data,target,action,"GROUP")
M33kAurasSaved.displays.Group=nil
pump()
T.expect(#moved==before,"deleting the drop target before execution prevents stale-target writes")
local paused,resumed=0,0
f.private.PauseAllDynamicGroups=function() paused=paused+1;return {} end
f.private.ResumeAllDynamicGroups=function() resumed=resumed+1 end
local function upvalue(fn,key)
  for i=1,100 do local name,value=debug.getupvalue(fn,i);if not name then break end;if name==key then return value end end
end
local layout=assert(upvalue(M33kAuras.ShowOptions,"LayoutDisplayButtons"))
layout()
scheduler:GetScript("OnUpdate")(scheduler,0.016)
tasks[#tasks]:Kill()
f:flush()
T.expect(paused==1 and resumed==1,"cancelling a preview coroutine resumes every suspended dynamic group exactly once")
local errorsBefore=#f.errors
M33kAuras.Delete=function() error("injected delete failure") end
options.DeleteAuras({source.data},{})
pump()
T.expect(#f.errors==errorsBefore+1 and not options.massDelete and paused==resumed,
  "failed asynchronous deletion resumes groups and releases the list refresh guard")
-- Queued deletion must target the confirmed identity, not a later name reuse.
local deleted={}
M33kAuras.Delete=function(data) deleted[#deleted+1]=data.uid;M33kAurasSaved.displays[data.id]=nil end
local doomed=f:add("Delete original")
local deletion={doomed}
options.DeleteAuras(deletion,{})
T.expect(options.massDelete==true,"queued deletion reserves the refresh guard before its first slice")
local replacement=f:add("Delete original");replacement.uid="replacement-delete-uid"
local unrelated=f:add("Keep unrelated")
deletion[1]=unrelated
pump()
T.expect(#deleted==0 and M33kAuras.GetData("Delete original")==replacement and M33kAuras.GetData("Keep unrelated")==unrelated,
  "queued deletion ignores name reuse and later changes to the caller's array")
local reused=f:add("Reused deletion name")
options.DeleteAuras({reused},{})
local reusedReplacement=f:add("Reused deletion name");reusedReplacement.uid="different-reused-uid"
pump()
T.expect(#deleted==0 and M33kAuras.GetData(reusedReplacement.id)==reusedReplacement,
  "a queued deletion cannot delete another UID that reuses the confirmed name")
local renamed=f:add("Delete before rename")
options.DeleteAuras({renamed,renamed},{})
M33kAurasSaved.displays[renamed.id]=nil
renamed=CopyTable(renamed);renamed.id="Delete after rename";M33kAuras.Add(renamed)
pump()
T.expect(#deleted==1 and deleted[1]==renamed.uid and not M33kAuras.GetData(renamed.id),
  "queued deletion resolves a renamed replacement table by UID and deduplicates its inputs")
local firstDelete=f:add("Delete first")
local secondDelete=f:add("Delete second")
options.DeleteAuras({firstDelete},{})
local firstTask=tasks[#tasks]
options.DeleteAuras({secondDelete},{})
firstTask:Kill()
T.expect(options.massDelete==true,"cancelling one queued deletion keeps another deletion's refresh guard")
pump()
T.expect(M33kAuras.GetData("Delete first")==firstDelete and not M33kAuras.GetData("Delete second") and not options.massDelete,
  "the remaining deletion completes and releases its guard after another is cancelled")
local parent=f:add("Queued parent",nil,{})
local parents={[parent.id]=true}
local updatedParents={}
local updateOrders=M33kAuras.UpdateGroupOrders
M33kAuras.UpdateGroupOrders=function(data) updatedParents[#updatedParents+1]=data.uid end
options.DeleteAuras({},parents)
M33kAurasSaved.displays[parent.id]=nil
parent=CopyTable(parent);parent.id="Renamed queued parent";M33kAuras.Add(parent)
local otherParent=f:add("Queued parent",nil,{});otherParent.uid="new-parent-uid"
parents["Keep unrelated"]=true
pump()
T.expect(#updatedParents==1 and updatedParents[1]==parent.uid,
  "deletion finishing resolves captured parent UIDs across renames and ignores caller mutations")
T.expect(not options.massDelete and paused==resumed,"all deletion paths balance suspension scopes and refresh guards")
M33kAuras.UpdateGroupOrders=updateOrders
T.loadAddonFile("M33kAurasOptions/OptionsFrames/Update.lua","M33kAurasOptions",options)
local methods=upvalue(upvalue(options.UpdateFrame,"ConstructUpdateFrame"),"methods")
local importing=false
f.private.SetImporting=function(value) importing=value end
M33kAuras.IsImporting=function() return importing end
M33kAuras.IsClassicEra=function() return false end
M33kAuras.IsForever=function() return false end
local function control() return {SetEnabled=function(self,value) self.enabled=value end} end
local importer=setmetatable({pendingData={data={}},userChoices={mode="import"},
  importButton=control(),closeButton=control(),viewCodeButton=control(),
  ReleaseChildren=function() error("injected import failure") end},{__index=methods})
errorsBefore=#f.errors
importer:Import()
pump()
T.expect(#f.errors==errorsBefore+1 and not importing and importer.closeButton.enabled and importer.importButton.enabled,
  "a failed real import releases its global import lock and restores controls")
local function noop() end
local root={id="Incoming",uid="incoming-root",regionType="group",controlledChildren={"Incoming child"},load={},triggers={}}
local child={id="Incoming child",uid="incoming-child",regionType="icon",parent="Incoming",load={},triggers={}}
importer.pendingData={data=root,children={child}}
importer.ReleaseChildren=noop
importer.AddBasicInformationWidgets=noop
importer.AddProgressWidgets=noop
importer.progressBar={SetProgress=noop}
local closedID,events,history=nil,0,{}
importer.Close=function(_,_,id) closedID=id end
f.private.FindUnusedId=function(id)
  local candidate,n=id,2
  while M33kAuras.GetData(candidate) do candidate=id.." "..n;n=n+1 end
  return candidate
end
f.private.callbacks.Fire=function(_,event)
  if event=="Import" then
    events=events+1
    assert(not importing and options.auraListNodes[root.uid],"completion fired before tree publication")
  end
end
f.private.SetHistory=function(uid,data) history[uid]=data end
errorsBefore=#f.errors
local tasksBefore=#tasks
importer:Import();importer:Import()
T.expect(#tasks==tasksBefore+1,"repeated import clicks cannot queue duplicate import coroutines")
pump()
T.expect(#f.errors==errorsBefore and not importing and not importer.importTask and events==1,
  "full import succeeds through both real phases, publication and completion notification")
T.expect(#f.view.containers>0,"a completed new import leaves a materialized list viewport")
T.expect(closedID=="Incoming" and f.frame.pickedDisplay=="Incoming",
  "full import closes the dialog and selects its root")
T.expect(M33kAurasSaved.displays.Incoming.controlledChildren[1]=="Incoming child"
  and M33kAurasSaved.displays["Incoming child"].parent=="Incoming"
  and options.auraListModel.byUID[child.uid].parent==options.auraListModel.byUID[root.uid],
  "full import publishes consistent saved and model parent/child links")
T.expect(history[root.uid] and history[child.uid],"full import records history for its root and child")
-- Load the real update category definitions without constructing unrelated type tables.
local typesFile=assert(io.open(T.repoRoot.."/M33kAuras/Types.lua"))
local typesSource=typesFile:read("*a");typesFile:close()
local first=assert(typesSource:find("Private.update_categories =",1,true))
local last=assert(typesSource:find("Private.non_transmissable_fields_v2000 =",first,true))
assert(loadstring("local Private,L=...;"..typesSource:sub(first,last-1)))(f.private,M33kAuras.L)
_G.ipairs_reverse=function(t)
  local i=#t+1
  return function() i=i-1;if i>0 then return i,t[i] end end
end
local onRename=upvalue(M33kAuras.ToggleOptions,"OnRename")
local onDelete=upvalue(M33kAuras.ToggleOptions,"OnAboutToDelete")
M33kAuras.Rename=function(data,id)
  local old=data.id
  M33kAurasSaved.displays[old]=nil;data.id=id;M33kAurasSaved.displays[id]=data
  if data.parent then local list=M33kAurasSaved.displays[data.parent].controlledChildren;list[assert(tIndexOf(list,old))]=id end
  for _,childID in ipairs(data.controlledChildren or {}) do M33kAurasSaved.displays[childID].parent=id end
  onRename("Rename",data.uid,old,id)
end
M33kAuras.Delete=function(data)
  onDelete("AboutToDelete",data.uid,data.id)
  if data.parent then table.remove(M33kAurasSaved.displays[data.parent].controlledChildren,assert(tIndexOf(M33kAurasSaved.displays[data.parent].controlledChildren,data.id))) end
  M33kAurasSaved.displays[data.id]=nil
end
local obsolete=f:add("Obsolete","Incoming")
table.insert(M33kAurasSaved.displays.Incoming.controlledChildren,"Obsolete")
M33kAuras.NewDisplayButton(obsolete);f:flush()
local retained=options.GetDisplayEntry("Incoming child")
local newRoot=CopyTable(M33kAurasSaved.displays.Incoming)
newRoot.controlledChildren={"Child renamed by update","Added by update"}
local renamedChild=CopyTable(M33kAurasSaved.displays["Incoming child"])
renamedChild.id="Child renamed by update"
local added={id="Added by update",uid="added-update-uid",parent="Incoming",regionType="icon",load={},triggers={}}
importer.pendingData={data=newRoot,children={renamedChild,added}}
_G.CreateFromMixins=function(...)
  local result={}
  for i=1,select("#",...) do for k,v in pairs(select(i,...)) do result[k]=v end end
  return result
end
local match=assert(upvalue(methods.Open,"MatchInfo"))
importer.matchInfo=assert(match(newRoot,importer.pendingData.children,M33kAurasSaved.displays.Incoming))
importer.userChoices={mode="update",activeCategories={}}
for _,category in ipairs(f.private.update_categories) do importer.userChoices.activeCategories[category.name]=true end
errorsBefore=#f.errors
importer:Import()
pump()
T.expect(#f.errors==errorsBefore and events==2 and not importing,"a full update completes and publishes its completion event"..(#f.errors>errorsBefore and (": "..f.errors[#f.errors]) or ""))
T.expect(table.concat(M33kAurasSaved.displays.Incoming.controlledChildren,",")=="Child renamed by update,Added by update"
  and not M33kAurasSaved.displays.Obsolete,"a full update applies additions, deletions and canonical child order")
T.expect(options.GetDisplayEntry("Child renamed by update")==retained and not options.displayEntries["Incoming child"],
  "a full update preserves the retained child's UID identity across its rename")
T.finish()
