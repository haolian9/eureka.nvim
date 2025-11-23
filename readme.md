to populate matched target to qflist

## prerequisites
* linux
* git or ripgrep
* nvim 0.11.*
* haolian9/infra.nvim
* haolian9/puff.nvim
* haolian9/sting.nvim

## status
* just work

## usage

here is my personal config:
```
do --eureka
  m.n([[\\]], function() require("eureka").input() end)
  m.x([[\\]], [[:lua require("eureka").vsel()<cr>]])

  do --:Eureka
    local spell = cmds.Spell("Eureka", function(args)
      local eureka = require("eureka")
      if args.regex then
        eureka.text(args.regex)
      else
        eureka.input()
      end
    end)
    spell:add_arg("regex", "string", false)
    cmds.cast(spell)
  end

  do
    local root_comp = cmds.FlagComp.variable("root", common_root_comp_cands)
    local function root_default() return project.git_root() or project.working_root() end
    -- see: rg --type-list
    local type_comp = cmds.FlagComp.constant("type", { "c", "go", "h", "lua", "py", "sh", "systemd", "vim", "zig" })

    do --:Todo
      local spell = cmds.Spell("Todo", function(args)
        local root = args.root
        if root ~= nil then root = fs.abspath(root) end
        local extra = {}
        if args.type then table.insert(extra, string.format("--type=%s", args.type)) end
        local pattern = args.pattern
        require("eureka").rg(root, pattern, extra)
      end)
      spell:add_flag("root", "string", false, root_default, root_comp)
      spell:add_flag("type", "string", false, nil, type_comp)
      spell:add_arg("pattern", "string", false, [[\btodo\b]])
      cmds.cast(spell)
    end

    do --:Rg
      local sort_comp = cmds.FlagComp.constant("sort", { "none", "path", "modified", "accessed", "created" })
      local function is_extra_flag(flag) return flag ~= "root" and flag ~= "pattern" end

      local spell = cmds.Spell("Rg", function(args)
        local root = args.root
        if root ~= nil then root = fs.abspath(root) end

        local extra = {}
        ---@diagnostic disable-next-line: param-type-mismatch
        local iter = itertools.filtern(dictlib.items(args), is_extra_flag)
        for key, val in iter do
          if val == true then
            table.insert(extra, string.format("--%s", key))
          elseif val == false then
          --pass
          else
            table.insert(extra, string.format("--%s=%s", key, val))
          end
        end

        require("eureka").rg(root, args.pattern, extra)
      end)

      do
        spell:add_flag("root", "string", false, root_default, root_comp)
        spell:add_flag("fixed-strings", "true", false)
        spell:add_flag("hidden", "true", false)
        spell:add_flag("max-depth", "number", false)
        spell:add_flag("multiline", "true", false)
        spell:add_flag("no-ignore", "true", false)
        spell:add_flag("sort", "string", false, nil, sort_comp)
        spell:add_flag("sortr", "string", false, nil, sort_comp)
        spell:add_flag("type", "string", false, nil, type_comp)
      end
      spell:add_arg("pattern", "string", true)
      cmds.cast(spell)
    end
  end
end
```
