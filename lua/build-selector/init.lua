local M = {}

local opts = {}

local function getcwd()
  return vim.uv.cwd()
end

--- Search up the working directory for files with the given names
--- @param files string[]|string files
--- @param cwd string|nil Current working directory. nil for vim's cwd.
---@return string[]
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

--- Get a list of Makefiles
M.makefiles = function(cwd)
  return M.find_files({'Makefile', 'makefile' }, cwd)
end

--- Get a list of CMakeLists.txt files
M.cmakelists = function(cwd)
  return M.find_files({'CMakeLists.txt'}, cwd)
end

--- Get a list of Odin-language directories
M.odindirs = function(cwd)
  cwd = cwd or getcwd()
  local odin_dirs = {}
  local cache = {}
  vim.fs.find(function(name, path)
    if vim.endswith(name, '.odin') then
      if not cache[path] then
        cache[path] = true
        table.insert(odin_dirs, path)
      end
    end
    return false -- we only use this function for its side-effects
  end, {
    path = cwd, type = 'file', limit = math.huge
  })
  return odin_dirs
end

--- Get a list of Jai-language files beneath the cwd
M.jai_files = function(cwd)
  cwd = cwd or getcwd()
  local jai_files = {}
  local priority = {}
  vim.fs.find(function(name, path)
    if vim.endswith(name, '.jai') then
      local f = vim.fs.joinpath(path, name)
      if vim.startswith(name, 'first') or vim.startswith(name, 'build') then
        table.insert(priority, f)
      else
        table.insert(jai_files, f)
      end
    end
    return false -- we only use this function for its side-effects
  end, {
    path = cwd, type = 'file', limit = math.huge
  })

  -- Append after the priority items
  for _, v in ipairs(jai_files) do
    table.insert(priority, v)
  end
  return priority
end

--- Get a list of devcontainer.json files
M.devcontainers = function(cwd)
  cwd = cwd or getcwd()
  --[[ valid locations are:
  --  .devcontainer.json
  --  .devcontainer/devcontainer.json
  --  .devcontainer/<one-folder>/devcontainer.json
  --]]
  local result = M.find_files(".devcontainer.json", cwd) or {}
  local folders = vim.fs.find(".devcontainer", {
    upward = true,
    type = 'directory',
    limit = math.huge,
    stop = vim.uv.os_homedir(),
    path = cwd,
  })
  for _, folder in ipairs(folders) do
    for subdir, subtype in vim.fs.dir(folder, { depth = 1 }) do
      if subtype == 'directory' then
        local f = vim.fs.joinpath(folder, subdir, 'devcontainer.json')
        if vim.fn.filereadable(f) == 1 then
          table.insert(result, f)
        end
      elseif subdir == 'devcontainer.json' then
        local f = vim.fs.joinpath(folder, subdir)
        if vim.fn.filereadable(f) == 1 then
          table.insert(result, f)
        end
      end
    end
  end

  return result
end

--- Simplify the path as a relative path
M.simplify_raw = function(path, cwd)
  local ok, plenary = pcall(require, 'plenary')
  if ok then
    return plenary.path:new(path):make_relative()
  else
    return path
  end
end

M.simplify = function(path, cwd)
  if not opts or opts.simplify == nil or opts.simplify == true then
    return M.simplify_raw(path, cwd)
  elseif type(opts.simplify) == "function" then
    return opts.simplify(path, cwd)
  else
    return path
  end
end

--- Create a single makefile choice from the given Makefile
M.choice_makefile = function(file)
  return "make -f " .. M.simplify(file)
end

--- Create a table of choices from the given CMakeLists.txt file
M.choice_cmake = function(file)
  -- Find a build directory next to this file
  local results = {}
  local dirname = vim.fs.dirname(file)
  for subdir_name, type in vim.fs.dir(dirname) do
    if vim.startswith(subdir_name, "build") and type == 'directory' then
      local cmake_cache = vim.fs.joinpath(dirname, subdir_name, "CMakeCache.txt")
      if vim.fn.filereadable(cmake_cache) == 1 then
        table.insert(results, 'cmake --build ' .. M.simplify(vim.fs.joinpath(dirname, subdir_name)) .. " --parallel")
      end
    end
  end
  return results
end

M.choice_odin = function(dir)
  return 'odin build ' .. M.simplify(dir) .. ' -error-pos-style:unix'
end

M.choice_jai = function(file)
  return 'jai -x64 ' .. M.simplify(file)
end

--- Table of variables to expand
M.expand_table = {
  localWorkspaceFolderBasename = function(cwd)
    cwd = cwd or getcwd()
    return vim.fs.basename(cwd)
  end
}

--- Expand variables of the form '${...}' using M.expand_table
M.expand_vars = function(name, cwd)
  -- local modname = string.gsub(name, "%$%b%{%}", function(match)
  local modname = string.gsub(name, "%$%{([%w_]+)%}", function(match)
    local expander = M.expand_table[match]
    return expander and expander(cwd) or match
  end)
  return modname
end

--- Create a single devcontainer docker choice from the given file
---@param file string File path
---@param arg "run"|"exec"|nil Docker run type
---@param command string Command (e.g. 'make -f Makefile')
---@param cwd string? current working directory
---@return string? devcommand Final command to be run (e.g. 'docker exec ... make -f Makefile')
M.choice_devcontainer = function(file, arg, command, cwd)
  arg = arg or "exec"
  local buffer = vim.uri_to_bufnr(vim.uri_from_fname(file))
  vim.fn.bufload(buffer)
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  -- devcontainer is 'json with comments' which wrecks the json parser
  -- Try to remove the comments
  for i, line in ipairs(lines) do
    local filtered = string.gsub(line, "//.*", "")
    if line ~= filtered then lines[i] = filtered end
  end
  local file_contents = table.concat(lines, "\n")
  local ok, json = pcall(vim.json.decode, file_contents)
  if not ok then print("failed to json decode " .. file) return end

  local name = json.name
  if json.runArgs then
    for _, value in ipairs(json.runArgs) do
      if vim.startswith(value, "--name=") then
        name = string.sub(value, #"--name=" + 1)
      end
    end
  end
  name = M.expand_vars(name, cwd)

  if name then
    -- docker exec DEVNAME cmake --build build-x --parallel
    return 'docker ' .. arg .. ' ' .. name .. ' ' .. command
  end
end


--- Get a list of all detected choices
M.choices = function(cwd, opts_)
  local opts = opts_ or opts
  local result = {}

  if opts.makefile ~= false then
    for _, file in pairs(M.makefiles(cwd)) do
      table.insert(result, M.choice_makefile(file))
    end
  end

  if opts.cmake ~= false then
    for _, file in pairs(M.cmakelists(cwd)) do
      local entries = M.choice_cmake(file)
      for _, entry in ipairs(entries) do
        if entry then table.insert(result, entry) end
      end
    end
  end

  if opts.odin ~= false then
    for _, file in pairs(M.odindirs(cwd)) do
      table.insert(result, M.choice_odin(file))
    end
  end

  if opts.jai ~= false then
    for _, file in pairs(M.jai_files(cwd)) do
      table.insert(result, M.choice_jai(file))
    end
  end

  if opts.devcontainer ~= false then
    local original = vim.tbl_map(function(x) return x end, result)
    for _, file in ipairs(M.devcontainers(cwd)) do
      for _, other_entry in ipairs(original) do
        local deventry = M.choice_devcontainer(file, nil, other_entry, cwd)
        if deventry then table.insert(result, deventry) end
      end
    end
  end
  return result
end

--- Ask the user to select a new make program based on calculated choices
---@param choices table? Choices override, or nil for default
M.choose = function(choices)
  choices = choices or M.choices()
  if choices and #choices > 0 then
    vim.ui.select(choices, { prompt = 'Set make program to::', kind = opts.ui_select_kind }, function(item, index)
      if item then
        if opts.selected_callback then
          opts.selected_callback(item)
        else
          print("makeprg set to " .. item)
          vim.opt.makeprg = item
        end
      end
    end)
  else
    print("Could not find anything to build")
  end
end

--- Calls M.choose() with nil arguments.
--- Useful in callback functions which supply arguments which you don't need.
M.choose_default = function()
  M.choose()
end

--- Setup the plugin with given options
M.setup = function(opts_)
  opts = opts_ or opts
  if opts.add_command ~= false then
    vim.api.nvim_create_user_command('BuildSelector', M.choose_default, { desc = 'Select a makeprg' })
  end
end

return M
