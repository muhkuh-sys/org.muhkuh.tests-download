local t = ...
local tResult

-- Install the complete "doc" folder.
--t:install('doc/', '${install_doc}/')

-- Install the complete "lua" folder.
t:install('lua/', '${install_lua_path}/')

-- Install the complete "netx" folder.
--t:install('netx/', '${install_base}/netx/')

tResult = true

return tResult
