local M = {}

local function getcwd()
  return vim.uv.cwd()
end

M.find_files = function(files, cwd)
  cwd = cwd or getcwd()
  local result = vim.fs.find(files , {
    upward = true,
    type = 'file',
    limit = math.huge,
    stop = vim.uv.os_homedir(),
    path = cwd,
  })
  return result
end

M.makefiles = function(cwd)
  return M.find_files({'Makefile', 'makefile' }, cwd)
end

M.cmakelists = function(cwd)
  return M.find_files({'CMakeLists.txt'}, cwd)
end

M.devcontainers = function(cwd)
  return {}
end

M.simplify = function(path, cwd)
  local ok, plenary = pcall(require, 'plenary')
  if ok then
    return plenary.path:new(path):make_relative()
  else
    return path
  end
end

M.choice_makefile = function(file)
  return "make -f " .. M.simplify(file)
end

M.choice_cmake = function(file)
  -- Find a build directory next to this file
  local dirname = vim.fs.dirname(file)
  for subdir_name, type in vim.fs.dir(dirname) do
    if vim.startswith(subdir_name, "build") and type == 'directory' then
      local cmake_cache = vim.fs.joinpath(dirname, subdir_name, "CMakeCache.txt")
      if vim.fn.filereadable(cmake_cache) then
        return 'cmake --build ' .. M.simplify(vim.fs.joinpath(dirname, subdir_name)) .. " --parallel"
      end
    end
  end
end

M.make_choices = function(cwd)
  local result = {}
  for _, file in pairs(M.makefiles(cwd)) do
    table.insert(result, M.choice_makefile(file))
  end
  for _, file in pairs(M.cmakelists(cwd)) do
    local entry = M.choice_cmake(file)
    if entry then table.insert(result, entry) end
  end
  return result
end

M.choose = function()
  local choices = M.make_choices()
  if choices and #choices > 0 then
    vim.ui.select(choices, { prompt = 'Set make program to::' }, function(item, index)
      if item then
        print("makeprg set to " .. item)
        vim.opt_local.makeprg = item
      end
    end)
  else
    print("Could not find anything to build")
  end
end


M.setup = function()
  vim.api.nvim_create_user_command('BuildSelector', M.choose, { desc = 'Select a makeprg' })
end

return M
