-- Deterministic mutation sequences checked against saved-data traversal, not model links.
local testsDir=arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path=testsDir.."/?.lua;"..package.path
local T=require("helpers")
local f=require("aura_list_stubs").install(T)
local options=f.options
local function expectInvariant(condition,message) assert(condition,message) end
for _,seed in ipairs({17,83,271,409}) do
  math.randomseed(seed)
  local model=options.CreateAuraListModel(function(data) return {data=data,uid=data.uid,visibility=0} end)
  local displays,loaded,groups,expanded,identity={},{},{},{},{}
  local nextUID=0
  local function create(id,parent,isGroup)
    nextUID=nextUID+1
    local data={id=id,uid="seed"..seed.."-"..nextUID,parent=parent and parent.id,load={},controlledChildren=isGroup and {} or nil}
    displays[id]=data
    if parent then table.insert(parent.controlledChildren,id) end
    return data
  end
  groups[1]=create("Group A",nil,true);groups[2]=create("Group B",nil,true);groups[3]=create("Group C",groups[1],true)
  for i=1,25 do create("Leaf "..i,i%3==0 and nil or groups[1+i%3]) end
  local filters={"","A","x","[","%","group","leaf|renamed"," or ","[|%"}
  local function unlink(data)
    if data.parent then
      local children=displays[data.parent].controlledChildren
      table.remove(children,assert(tIndexOf(children,data.id)))
    end
    data.parent=nil
  end
  local function check(filter)
    local originalLoaded=CopyTable(loaded)
    model:Sync(displays,loaded,filter)
    local alive,roots={},{ }
    for id,data in pairs(displays) do
      local entry=model.byID[id]
      expectInvariant(entry and entry.uid==data.uid and entry.data==data,"ID lookup points at the wrong saved aura")
      expectInvariant(model.byUID[data.uid]==entry,"UID and ID indexes disagree")
      expectInvariant(not identity[data.uid] or identity[data.uid]==entry,"existing UID lost its state object")
      identity[data.uid]=entry;alive[data.uid]=true
      expectInvariant((entry.parent and entry.parent.data.id)==data.parent,"parent link differs from saved data")
      expectInvariant(#entry.children==#(data.controlledChildren or {}),"child count differs from saved data")
      for i,child in ipairs(data.controlledChildren or {}) do expectInvariant(entry.children[i].data.id==child,"child ordering changed") end
      if not data.parent then roots[#roots+1]=data end
    end
    for uid in pairs(model.byUID) do expectInvariant(alive[uid],"deleted UID survived synchronization") end
    for id,entry in pairs(model.byID) do expectInvariant(displays[id] and entry.data==displays[id],"stale ID alias survived") end
    for id,value in pairs(originalLoaded) do expectInvariant(loaded[id]==value,"model changed runtime load state") end
    for id,value in pairs(loaded) do expectInvariant(originalLoaded[id]==value,"model added runtime load state") end
    local function count(data)
      local a,b,c,allowed=0,0,0,false
      if data.controlledChildren then
        for _,id in ipairs(data.controlledChildren) do
          local x,y,z,w=count(displays[id]);a,b,c=a+x,b+y,c+z;allowed=allowed or w
        end
      else
        a=loaded[data.id]==true and 1 or 0;b=loaded[data.id]==false and 1 or 0;c=loaded[data.id]==nil and 1 or 0
        allowed=not data.load.use_never
      end
      local e=model.byID[data.id]
      expectInvariant(e.activeCount==a and e.standbyCount==b and e.unloadedCount==c,"incorrect load aggregation")
      expectInvariant(e.neverLoad==not allowed,"incorrect never-load aggregation")
      return a,b,c,allowed
    end
    table.sort(roots,function(a,b) if a.id:lower()==b.id:lower() then return a.id<b.id end;return a.id:lower()<b.id:lower() end)
    local matches={}
    for id,data in pairs(displays) do
      for term in filter:lower():gsub(" or ","|"):gmatch("[^|]+") do
        if id:lower():find(term,1,true) then
          local node=data
          while node do matches[node.id]=true;node=node.parent and displays[node.parent] end
        end
      end
    end
    for id,e in pairs(model.byID) do expectInvariant(model:Includes(e)==(filter=="" or matches[id]==true),"filter projection differs from saved-data matches") end
    local expected={}
    local function visit(data)
      if filter~="" and not matches[data.id] then return end
      expected[#expected+1]=data.id
      if expanded[data.uid] then for _,id in ipairs(data.controlledChildren or {}) do visit(displays[id]) end end
    end
    for _,section in ipairs({"loaded","unloaded"}) do
      for _,root in ipairs(roots) do
        local active,standby=count(root)
        local expectedSection=(active>0 or standby>0 or (root.controlledChildren and #root.controlledChildren==0)) and "loaded" or "unloaded"
        expectInvariant(model.byID[root.id].section==expectedSection,"wrong root section")
        if expectedSection==section then visit(root) end
      end
    end
    local actual=model:VisibleEntries(function(e) return expanded[e.uid] end,function() return true end)
    expectInvariant(#actual==#expected,"visible entry count differs")
    for i,e in ipairs(actual) do expectInvariant(e.data.id==expected[i],"visible order differs") end
  end
  check("")
  for step=1,250 do
    local leaves={}
    for _,data in pairs(displays) do if not data.controlledChildren then leaves[#leaves+1]=data end end
    table.sort(leaves,function(a,b) return a.uid<b.uid end)
    local data=leaves[math.random(#leaves)]
    local op=step%7
    if op==0 then
      local old=data.id
      displays[old]=nil;data.id="Renamed ["..step.."]%";displays[data.id]=data
      if data.parent then local children=displays[data.parent].controlledChildren;children[assert(tIndexOf(children,old))]=data.id end
      loaded[data.id],loaded[old]=loaded[old],nil
      local e=model:Ensure(data)
      expectInvariant(not model.byID[old] and e==identity[data.uid],"rename lookup left stale state")
    elseif op==1 then
      unlink(data)
      local parent=math.random(4);if parent<=3 then data.parent=groups[parent].id;table.insert(groups[parent].controlledChildren,data.id) end
    elseif op==2 then
      loaded[data.id]=({true,false})[math.random(3)];data.load.use_never=math.random(2)==1
    elseif op==3 then
      expanded[groups[math.random(3)].uid]=math.random(2)==1
    elseif op==4 then
      if data.parent then local children=displays[data.parent].controlledChildren;table.remove(children,assert(tIndexOf(children,data.id)));table.insert(children,math.random(#children+1),data.id) end
    elseif op==5 then
      local id=data.id;unlink(data);displays[id]=nil;loaded[id]=nil
      -- Reuse the old name with a new UID to test identity isolation.
      create(id,groups[math.random(3)])
    else
      local e=model.byUID[data.uid];e.visibility=(e.visibility+1)%3
    end
    local selected=model.byUID[data.uid]
    local visibility=selected and selected.visibility
    check(filters[math.random(#filters)])
    if displays[data.id]==data then expectInvariant(model.byUID[data.uid].visibility==visibility,"preview state changed across a projection rebuild") end
  end
  T.expect(true,"250 mutation steps preserve indexes, saved order, filtering, load counters and UID state; seed "..seed)
end
T.finish()
