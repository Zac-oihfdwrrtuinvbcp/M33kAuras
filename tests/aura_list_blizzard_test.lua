-- Optional provider contract check against a separately downloaded Blizzard UI source tree.
-- lua5.1 tests/aura_list_blizzard_test.lua <directory-containing-DataProvider.lua-and-TreeListDataProvider.lua> [test-file]
local testsDir=arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path=testsDir.."/?.lua;"..package.path
local source=assert(arg[1],"Blizzard provider source directory required")
local stubs=require("aura_list_stubs")
local install=stubs.install
stubs.install=function(T)
  local fixture=install(T)
  function CreateFromMixins(...)
    local result={}
    for i=1,select("#",...) do for k,v in pairs(select(i,...)) do result[k]=v end end
    return result
  end
  CallbackRegistryMixin={OnLoad=function() end,TriggerEvent=function() end}
  function CallbackRegistryMixin:GenerateCallbackEvents(names)
    self.Event={};for _,name in ipairs(names) do self.Event[name]=name end
  end
  function ipairs_reverse(values)
    local index=#values+1
    return function() index=index-1;if index>0 then return index,values[index] end end
  end
  assert(loadfile(source.."/DataProvider.lua"))()
  assert(loadfile(source.."/TreeListDataProvider.lua"))()
  return fixture
end
assert(loadfile(testsDir.."/"..(arg[2] or "aura_list_test.lua")))()
