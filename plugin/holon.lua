-- =============================================================================
-- Halo.nvim: Plugin initialization
-- =============================================================================
-- This file is automatically loaded by Neovim.
-- It sets up Halo commands and compatibility aliases.
-- =============================================================================

if vim.g.loaded_holon then
  return
end
vim.g.loaded_holon = true

-- User commands
local function create_command(name, callback, opts)
  vim.api.nvim_create_user_command(name, callback, opts)
  vim.api.nvim_create_user_command(name:gsub("^Halo", "Holon"), callback, opts)
end

create_command("Halo", function(opts)
  require("holon.zk.pickers").notes()
end, { desc = "Open Halo notes picker" })

create_command("HaloNew", function(opts)
  require("holon.zk.pickers").templates()
end, { desc = "Create new Halo note" })

create_command("HaloGrep", function(opts)
  require("holon.zk.pickers").grep_notes({ default_text = opts.args })
end, { nargs = "?", desc = "Grep Halo notes" })

create_command("HaloBacklinks", function(opts)
  require("holon.zk.pickers").backlinks()
end, { desc = "Show backlinks to current note" })

create_command("HaloLinks", function(opts)
  require("holon.zk.pickers").forward_links()
end, { desc = "Show forward links from current note" })

create_command("HaloIndexes", function(opts)
  require("holon.zk.pickers").indexes()
end, { desc = "Browse index notes" })

create_command("HaloJournal", function(opts)
  require("holon.zk.pickers").journal()
end, { desc = "Open journal picker" })

create_command("HaloTags", function(opts)
  require("holon.zk.pickers").filter_tags()
end, { desc = "Filter notes by tags" })

create_command("HaloTypes", function(opts)
  require("holon.zk.pickers").filter_type()
end, { desc = "Filter notes by type" })

create_command("HaloOrphans", function(opts)
  require("holon.zk.pickers").orphans()
end, { desc = "Find orphan notes with no links" })

create_command("HaloFollow", function(opts)
  require("holon.zk.actions").follow_link_under_cursor()
end, { desc = "Follow link under cursor" })

create_command("HaloToday", function(opts)
  local filepath = require("holon.zk.actions").create_journal_entry()
  if filepath then
    vim.cmd("edit " .. vim.fn.fnameescape(filepath))
  end
end, { desc = "Open or create today's journal entry" })

create_command("HaloGtd", function(opts)
  require("holon.gtd.board").open()
end, { desc = "Open GTD board" })

create_command("HaloBrowse", function(opts)
  require("holon.zk.link_browser").open()
end, { desc = "Open link browser" })

-- Setup gd mapping for markdown files in notes directory
-- vim.schedule ensures this runs after other LspAttach handlers in the same event loop
local function setup_gd_mapping(bufnr)
  local config = require("holon.config")
  local notes_path = config.get("notes_path")
  if not notes_path then
    return
  end

  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if not filepath:find(notes_path, 1, true) then
    return
  end

  vim.keymap.set("n", "gd", function()
    require("holon.zk.actions").smart_gd()
  end, { buffer = bufnr, desc = "Halo: Go to definition / Follow link" })
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function(args)
    setup_gd_mapping(args.buf)
  end,
})

-- Re-apply after LspAttach with vim.schedule to run after all synchronous
-- LspAttach handlers (e.g., LSP plugins that set gd to vim.lsp.buf.definition)
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    if vim.bo[args.buf].filetype == "markdown" then
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(args.buf) then
          setup_gd_mapping(args.buf)
        end
      end)
    end
  end,
})
