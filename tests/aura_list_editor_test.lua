local testsDir=arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path=testsDir.."/?.lua;"..package.path
local T=require("helpers")
local f=require("aura_list_stubs").install(T)
local options=f.options
f:add("A");f:add("B")
options.RefreshAuraList("");f:loadMain()
local entry=options.GetDisplayEntry("A")
entry:BeginRename()
entry.row.renamebox:SetText("Draft name")
options.SortDisplayButtons()
T.expect(entry.row.renamebox:IsShown() and entry.row.renamebox:GetText()=="Draft name" and entry.row.renamebox:HasFocus(),
  "a list rebuild retains the active rename draft")
entry.row.renamebox:SetText("B")
entry.row.renamebox:GetScript("OnEnterPressed")()
T.expect(entry.renaming and entry.row.renamebox:IsShown() and entry.renameText=="A",
  "a duplicate name is rejected while the editor stays active")
entry.row.renamebox:SetText("Offscreen draft")
f.view:Render(1000)
T.expect(not entry.row and entry.renameText=="Offscreen draft", "scrolling away retains the rename draft without retaining its row")
options.RevealDisplay("A")
T.expect(entry.row and entry.row.renamebox:GetText()=="Offscreen draft" and entry.row.renamebox:HasFocus(),
  "revealing the edited aura restores its draft and requested focus")
entry.row.renamebox:GetScript("OnEscapePressed")()
options.SortDisplayButtons()
T.expect(not entry.renaming and not entry.row.renamebox:IsShown(),"Escape cancels a rename across later rebuilds")

f.view:Render(1000) -- Ensure the callback reuses this row, not another visible B row.
local container=CreateFrame("Frame")
options.BindAuraListRow(container,options.auraListNodes[entry.uid])
local row=container.widget
row.renamebox:SetText("Committed name")
local renamed
M33kAuras.Rename=function(data,newid)
  renamed=newid
  -- A real rename callback can release and reuse the row synchronously.
  options.ReleaseAuraListRow(container)
  options.BindAuraListRow(container,options.auraListNodes[options.GetDisplayEntry("B").uid])
end
row.renamebox:GetScript("OnEnterPressed")()
T.expect(renamed=="Committed name","the rename callback receives the draft captured before row recycling")
T.expect(container.widget==row and row.title:GetText()=="B","rename completion never overwrites the title of a newly rebound aura")
options.ReleaseAuraListRow(container)

local parses=0
f.private.StringToTable=function() parses=parses+1;return "invalid payload" end
local companion={encoded="broken"}
options.GetCompanionPreview(companion);options.GetCompanionPreview(companion)
T.expect(parses==1,"invalid Companion payloads are decoded only once per payload")
companion.encoded="changed"
options.GetCompanionPreview(companion)
T.expect(parses==2,"a changed Companion payload invalidates a cached decode failure")

f.private.StringToTable=function() return {d={id="preview",uid="preview",regionType="icon",load={}}} end
local previewNode={GetData=function() return {kind="M33kAurasPendingUpdateButton",id="slug",companion={encoded="valid",name="Preview"}} end}
options.BindAuraListRow(container,previewNode)
local update=container.widget
options.ReleaseAuraListRow(container)
T.expect(not update.frame:GetScript("OnEnter") and not update.frame:GetScript("OnLeave"),
  "releasing a Companion update removes its data-dependent tooltip callbacks")
T.expect(#f.errors==0,"editor and Companion lifecycle checks have no callback errors")
T.finish()
