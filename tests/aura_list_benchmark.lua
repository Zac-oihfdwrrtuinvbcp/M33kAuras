-- Synthetic CPU/lifecycle comparison; these are not in-game frame-time measurements.
-- lua5.1 tests/aura_list_benchmark.lua tree 1000
-- lua5.1 tests/aura_list_benchmark.lua original 1000 <baseline-directory>
-- Baseline directory needs M33kAurasOptions.lua and AceGUIWidget-M33kAurasDisplayButton.lua from 13ff1d02.
local testsDir=arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path=testsDir.."/?.lua;"..package.path
local T=require("helpers")
local f=require("aura_list_stubs").install(T)
local mode,count=arg[1] or "tree",tonumber(arg[2]) or 1000
for i=1,count do f:add(("Aura %05d"):format(i)) end
local options,frame=f.options,f.frame
local open,search,scroll
if mode=="original" then
  local function read(name)
    local file=assert(io.open(assert(arg[3],"baseline directory required").."/"..name))
    local text=file:read("*a");file:close();return text
  end
  local main=read("M33kAurasOptions.lua")
  assert(loadstring(read("AceGUIWidget-M33kAurasDisplayButton.lua")))("M33kAurasOptions",options)
  options.displayButtons={}
  options.GetDisplayButton=function(id) return options.displayButtons[id] end
  f.private.TraverseLeafsOrAura=f.private.TraverseLeafs
  local layout
  f.ace.RegisterLayout=function(_,_,fn) layout=fn end
  local a=assert(main:find('AceGUI:RegisterLayout("ButtonsScrollLayout"',1,true))
  local b=assert(main:find("function OptionsPrivate.MultipleDisplayTooltipDesc",a,true))
  assert(loadstring("local AceGUI=...;"..main:sub(a,b-1)))(f.ace)
  local top=0
  frame.buttonsScroll={children={},GetScrollPos=function() return top,top+16*34 end}
  local content={obj=frame.buttonsScroll}
  frame.buttonsScroll.DoLayout=function(self) layout(content,self.children) end
  frame.CenterOnPicked=function() end
  a=assert(main:find("local function addButton(",1,true))
  b=assert(main:find("function OptionsPrivate.IsPickedMultiple",a,true))
  local prefix="local OptionsPrivate,frame=...;local displayButtons=OptionsPrivate.displayButtons;local AceGUI=LibStub('AceGUI-3.0');local L=M33kAuras.L;local tinsert=table.insert; "
  assert(loadstring(prefix..main:sub(a,b-1)))(options,frame)
  open=function()
    for id,data in pairs(M33kAurasSaved.displays) do
      local row=f.ace:Create("M33kAurasDisplayButton")
      options.displayButtons[id]=row
      row:SetData(data);row:Initialize();row:UpdateWarning()
    end
    options.SortDisplayButtons("")
  end
  search=function(text) options.SortDisplayButtons(text) end
  scroll=function(i) top=i*34;frame.buttonsScroll:DoLayout() end
else
  f.view.count=16
  open=function() options.RefreshAuraList("") end
  search=function(text) options.RefreshAuraList(text) end
  scroll=function(i) f.view:Render(i,16) end
end
local function timed(fn)
  local start=os.clock();fn();return (os.clock()-start)*1000
end
collectgarbage("collect")
local opening=timed(open)
local searching=timed(function() for i=1,10 do search(i%2==0 and "aura" or "009") end end)/10
search("")
local rowsBefore=f.acquired-4
local scrolling=timed(function() for i=1,100 do scroll(1+(i*37)%(count-16)) end end)/100
print(("%s,%d,%.3f,%.3f,%.3f,%d,%d"):format(mode,count,opening,searching,scrolling,rowsBefore,f.acquired-4))
