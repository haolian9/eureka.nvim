local M = {}

local fn = require("infra.fn")
local fs = require("infra.fs")
local jelly = require("infra.jellyfish")("grep", "debug")
local listlib = require("infra.listlib")
local project = require("infra.project")
local subprocess = require("infra.subprocess")
local vsel = require("infra.vsel")

local qltoggle = require("qltoggle")
local sting = require("sting")

local Converter
do
  ---:h setqflist-what
  ---qflist and loclist shares the same structure
  local function call(t, line)
    -- lno, col: 1-based
    local file, lno, col, text = unpack(fn.split(line, ":", 3))
    assert(file and lno and col and text)

    ---why:
    ---* git grep and rg output relative path
    ---* nvim treats non-absolute path in qflist/loclist relative to cwd
    local fname = t.resolve_fpath(file)

    return { filename = fname, col = col, lnum = lno, text = text }
  end

  ---@param root string
  ---@return fun(line: string): sting.Pickle
  function Converter(root)
    local cwd = project.working_root()

    local resolve_fpath
    if cwd == root then
      resolve_fpath = function(relpath) return relpath end
    else
      resolve_fpath = function(relpath) return fs.joinpath(root, relpath) end
    end

    ---@diagnostic disable-next-line: return-type-mismatch
    return setmetatable({ resolve_fpath = resolve_fpath }, { __call = call })
  end
end

local callbacks = {}
do
  function callbacks.output(pattern, root)
    assert(pattern and root)

    local converter = Converter(root)
    local qf = sting.quickfix.shelf(string.format("grep:%s", pattern))

    ---@param output_iter fun(): string?
    return function(output_iter)
      qf:reset()
      for line in output_iter do
        qf:append(converter(line))
      end
      qf:feed_vim()

      ---showing quickfix window lastly, maybe this can reduce the copying
      ---between quickfix buffer and internal datastructure while updating
      ---quickfix items
      qltoggle.open_qflist()
    end
  end

  function callbacks.exit(cmd, args, path)
    return function(exit_code)
      -- rg, git grep shares same meaning on return code 0 and 1
      -- 0: no error, has at least one match
      -- 1: no error, has none match
      if exit_code == 0 then return end
      if exit_code == 1 then return end
      vim.schedule(function() jelly.err("grep failed: %s args=%s, cwd=%s", cmd, table.concat(args), path) end)
    end
  end
end

local function rg(path, pattern, extra_args)
  assert(pattern ~= nil)
  if path == nil then return jelly.warn("path is nil, rg canceled") end

  local args = {
    "--column",
    "--line-number",
    "--no-heading",
    "--color=never",
    "--hidden",
    "--max-columns=512",
    "--smart-case",
  }
  do
    if extra_args ~= nil then listlib.extend(args, extra_args) end
    table.insert(args, "--")
    table.insert(args, pattern)
  end

  subprocess.spawn("rg", { args = args, cwd = path }, callbacks.output(pattern, path), callbacks.exit("rg", args, path))
end

local function gitgrep(path, pattern, extra_args)
  assert(pattern ~= nil)
  if path == nil then return jelly.warn("path is nil, git grep canceled") end

  local args = { "grep", "--line-number", "--column", "--no-color" }
  do
    if extra_args ~= nil then listlib.extend(args, extra_args) end
    table.insert(args, "--")
    table.insert(args, pattern)
  end

  subprocess.spawn("git", { args = args, cwd = path }, callbacks.output(pattern, path), callbacks.exit("gitgrep", args, path))
end

local function make_runner(runner)
  -- it happens to be same to the output of rg and git grep

  local determiners = {
    repo = project.git_root,
    cwd = project.working_root,
    dot = function() return vim.fn.expand("%:p:h") end,
  }

  return {
    input = function(path_determiner)
      local determiner = assert(determiners[path_determiner], "unknown path determiner")
      local path = assert(determiner(), "no available path")
      local regex = vim.fn.input("grep ")
      if regex == "" then return end
      runner(path, regex)
    end,
    vsel = function(path_determiner)
      local determiner = assert(determiners[path_determiner], "unknown path determiner")
      local path = assert(determiner(), "no available path")
      local fixed = vsel.oneline_text()
      if fixed == nil then return end
      runner(path, fixed, { "--fixed-strings" })
    end,
    text = function(path_determiner, regex)
      local determiner = assert(determiners[path_determiner], "unknown path determiner")
      local path = assert(determiner(), "no available path")
      runner(path, regex)
    end,
  }
end

M.rg = make_runner(rg)
M.git = make_runner(gitgrep)

return M
