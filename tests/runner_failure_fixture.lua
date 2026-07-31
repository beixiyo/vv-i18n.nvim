local tests_dir = debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$')
local H = dofile(tests_dir .. '/helper.lua')
local check, done = H.checker()

print = function(message)
  io.write('[render]' .. tostring(message))
end

check('fixture pass', true)
check('fixture failure', false)
done()

vim.cmd('qa!')
