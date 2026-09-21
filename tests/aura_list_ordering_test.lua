local testsDir=arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path=testsDir.."/?.lua;"..package.path
local T=require("helpers")
local f=require("aura_list_stubs").install(T)
local options=f.options
f:add("Source",nil,{"A","B","C"})
for _,id in ipairs({"A","B","C"}) do f:add(id,"Source") end
f:add("Destination",nil,{"Anchor 1","Anchor 2"})
f:add("Anchor 1","Destination");f:add("Anchor 2","Destination")
local dynamic=f:add("Dynamic",nil,{})
dynamic.regionType="dynamicgroup"
options.RefreshAuraList("");f:loadMain()
options.StartAuraDrag=function() end
local function upvalue(fn,key)
  for i=1,100 do local name,value=debug.getupvalue(fn,i);if not name then break end;if name==key then return value end end
  error("missing upvalue "..key)
end
local getAction=upvalue(options.UpdateAuraDropIndicator,"GetAction")
local function drop(ids,targetID,area)
  f.frame:ClearPicks()
  M33kAuras.PickDisplay(ids[1])
  for i=2,#ids do options.PickDisplayMultiple(ids[i]) end
  options.SortDisplayButtons("Anchor") -- Selected sources have no rendered rows.
  local source,target=options.GetDisplayEntry(ids[1]),options.GetDisplayEntry(targetID)
  options.StartDrag(source.data)
  options.Drop(source.data,target,assert(getAction(target,area)),area)
  f:flush()
end
local function order(id) return table.concat(M33kAurasSaved.displays[id].controlledChildren,",") end
drop({"A","C"},"Anchor 2","BEFORE")
T.expect(order("Source")=="B" and order("Destination")=="Anchor 1,A,C,Anchor 2",
  "real BEFORE action reparents an offscreen batch in saved sibling order")
drop({"A","C"},"Anchor 2","AFTER")
T.expect(order("Destination")=="Anchor 1,Anchor 2,A,C","real AFTER action preserves order while moving within the same parent")
drop({"A","C"},"Destination","GROUP")
T.expect(order("Destination")=="A,C,Anchor 1,Anchor 2","real GROUP action inserts a batch at the front without reversing it")
T.expect(options.auraListModel.filter=="anchor","drop completion preserves the active search")

drop({"Source"},"Destination","GROUP")
T.expect(order("Destination")=="Source,A,C,Anchor 1,Anchor 2" and M33kAurasSaved.displays.B.parent=="Source",
  "moving a nested group preserves its descendant parent links and child order")
local group=options.GetDisplayEntry("Source")
options.StartDrag(group.data)
T.expect(not options.GetDisplayEntry("Dynamic"):IsEnabled(),"group drags cannot target a dynamic group")
options.DragReset()

local source=options.GetDisplayEntry("B")
options.StartGrouping(source.data)
local target=options.GetDisplayEntry("Dynamic")
target.callbacks.OnClickGrouping()
f:flush()
T.expect(M33kAurasSaved.displays.B.parent=="Dynamic" and order("Source")=="" and order("Dynamic")=="B",
  "the real grouping callback removes nested ancestors and updates both canonical child lists")
T.expect(source.data.xOffset==0 and source.data.yOffset==0 and not source.grouping,
  "dynamic grouping resets child offsets and exits grouping mode")
_G.min=math.min
M33kAuras.InternalVersion=function() return 1 end
M33kAuras.DeepMixin=function(target,defaults)
  for key,value in pairs(defaults) do if target[key]==nil then target[key]=type(value)=="table" and CopyTable(value) or value end end
end
f.private.data_stub={controlledChildren={},load={},triggers={},desc=""}
f.private.regionTypes={group={default={}},dynamicgroup={default={}}}
f.private.validate=function(data) data.uid=M33kAuras.GenerateUniqueID() end
f.private.FindUnusedId=function(id)
  local candidate,n=id,2
  while M33kAuras.GetData(candidate) do candidate=id.." "..n;n=n+1 end
  return candidate
end
local function groupSelection(ids,kind)
  f.frame:ClearPicks()
  f.frame:PickDisplayBatch(ids)
  local menu=f.menuDescription()
  local uids={}
  for _,id in ipairs(ids) do uids[#uids+1]=M33kAuras.GetData(id).uid end
  options.BuildDisplayButtonMenu(menu,{auraId=ids[1],auraUID=uids[1],selectedIds=ids,selectedUIDs=uids})
  menu[kind=="dynamicgroup" and 2 or 1].func()
  f:flush()
  return M33kAuras.GetData(M33kAuras.GetData(ids[1]).parent)
end
f:add("Mixed parent",nil,{"Nested leaf"});f:add("Nested leaf","Mixed parent");f:add("Top leaf")
options.SortDisplayButtons("")
local mixed=groupSelection({"Top leaf","Nested leaf"},"group")
T.expect(not mixed.parent and order("Mixed parent")=="",
  "a top-level-first mixed-parent selection creates its group at the top level")
T.expect(table.concat(mixed.controlledChildren,",")=="Top leaf,Nested leaf",
  "a new mixed-parent group retains selected child order")
f:add("Reverse parent",nil,{"Reverse nested"});f:add("Reverse nested","Reverse parent");f:add("Reverse top")
options.SortDisplayButtons("")
local reversed=groupSelection({"Reverse nested","Reverse top"},"group")
T.expect(not reversed.parent and order("Reverse parent")=="",
  "mixed-parent grouping is independent of which parent appears first")
f:add("Other parent one",nil,{"One child"});f:add("One child","Other parent one")
f:add("Other parent two",nil,{"Two child"});f:add("Two child","Other parent two")
options.SortDisplayButtons("")
local different=groupSelection({"One child","Two child"},"group")
T.expect(not different.parent and order("Other parent one")=="" and order("Other parent two")=="",
  "different nested parents create a top-level group and clean both old parents")
f:add("Sibling parent",nil,{"Before","First selected","Middle","Last selected","After"})
for _,id in ipairs({"Before","First selected","Middle","Last selected","After"}) do f:add(id,"Sibling parent") end
options.SortDisplayButtons("")
local siblings=groupSelection({"First selected","Last selected"},"group")
T.expect(siblings.parent=="Sibling parent" and order("Sibling parent")=="Before,"..siblings.id..",Middle,After",
  "same-parent grouping inserts at the first selected sibling and retains surrounding order")
f:add("Dynamic first");f:add("Dynamic second")
M33kAuras.GetData("Dynamic first").xOffset=12;M33kAuras.GetData("Dynamic first").yOffset=34
options.SortDisplayButtons("")
local dynamicGroup=groupSelection({"Dynamic first","Dynamic second"},"dynamicgroup")
T.expect(dynamicGroup.regionType=="dynamicgroup" and M33kAuras.GetData("Dynamic first").xOffset==0
  and M33kAuras.GetData("Dynamic first").yOffset==0,"new dynamic grouping resets child positions")
T.expect(#f.errors==0,"real ordering and grouping callbacks complete without UI errors")
T.finish()
