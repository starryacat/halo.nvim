-- =============================================================================
-- holon/zk/actions: Note operations for holon.nvim
-- =============================================================================

local config = require("holon.config")
local utils = require("holon.utils")
local frontmatter = require("holon.frontmatter")
local links = require("holon.links")

local M = {}

--- Create a new note from template
---@param template_path string Path to template file
---@param title string|nil Note title (uses generated ID if nil)
---@param filename string|nil Custom filename stem (uses generated ID if nil)
---@return string|nil filepath Path to created note or nil on error
function M.create_note(template_path, title, filename)
  -- Read template
  local template_content = utils.read_file(template_path)
  if not template_content then
    utils.notify("Failed to read template: " .. template_path, "error")
    return nil
  end

  -- Generate template variables
  local vars = utils.get_template_vars()
  local id = vars.ID
  local file_stem = (filename and filename ~= "") and filename or id

  -- Set title (use generated ID if not provided)
  if title and title ~= "" then
    -- Replace title in template
    template_content = template_content:gsub("title: %${UUID}", "title: " .. title)
    template_content = template_content:gsub("title: %${ID}", "title: " .. title)
  end

  -- Substitute all template variables
  local content = utils.substitute_template_vars(template_content, vars)

  -- Determine note type from template frontmatter
  local fm = frontmatter.parse(content)
  local note_type = frontmatter.get_type(fm) or "permanent"

  -- Get target directory
  local target_dir = config.get_directory(note_type)
  local extension = config.get("extension")

  -- Ensure directory exists
  if not utils.ensure_dir(target_dir) then
    utils.notify("Failed to create directory: " .. target_dir, "error")
    return nil
  end

  -- Create file path
  local filepath = target_dir .. "/" .. file_stem .. extension

  if utils.file_exists(filepath) then
    utils.notify("Note already exists: " .. filepath, "error")
    return nil
  end

  -- Write file
  if not utils.write_file(filepath, content) then
    utils.notify("Failed to create note: " .. filepath, "error")
    return nil
  end

  utils.notify("Created note: " .. (title or file_stem), "info")
  return filepath
end

--- Insert link to a note at cursor position
---@param uuid string Note path or identifier
---@param display_text string Display text for link
---@param format string|nil Link format ("wiki" or "markdown")
function M.insert_link(uuid, display_text, format)
  local link = links.generate_link(uuid, display_text, format)

  -- Get current cursor position
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()

  -- Insert link at cursor
  local new_line = line:sub(1, col) .. link .. line:sub(col + 1)
  vim.api.nvim_set_current_line(new_line)

  -- Move cursor to end of inserted link
  vim.api.nvim_win_set_cursor(0, { row, col + #link })
end

--- Create today's journal entry
---@return string|nil filepath Path to journal entry
function M.create_journal_entry()
  local today = utils.local_date("%Y-%m-%d")
  local journal_dir = config.get("notes_path") .. "/" .. config.get("directories").journal
  local filepath = journal_dir .. "/" .. today .. ".md"

  if utils.file_exists(filepath) then
    return filepath
  end

  -- Ensure directory exists
  if not utils.ensure_dir(journal_dir) then
    utils.notify("Failed to create journal directory", "error")
    return nil
  end

  -- Create journal entry with basic template
  local content = string.format([[---
title: %s
created: %s
lastmod: %s
type: journal
tags: []
---

# %s

]], today, utils.iso_timestamp(), utils.iso_timestamp(), today)

  if not utils.write_file(filepath, content) then
    utils.notify("Failed to create journal entry", "error")
    return nil
  end

  utils.notify("Created journal entry: " .. today, "info")
  return filepath
end

--- Follow link under cursor
---@param silent boolean|nil If true, don't notify when no link found
---@return boolean handled Whether a link was detected (even if target not found)
function M.follow_link_under_cursor(silent)
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local target = links.find_link_at_position(line, col)
  if target then
    local file_target, anchor = links.split_target(target)
    local filepath = links.resolve_link_target(file_target, vim.fn.expand("%:p"))
    if filepath then
      vim.cmd("edit " .. vim.fn.fnameescape(filepath))
      if anchor then
        local block = anchor:match("^%^(.*)$")
        local found
        for i, text in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
          if block then
            local marker = "%^" .. utils.escape_pattern(block) .. "%s*$"
            if text:match("^" .. marker) or text:match("%s+" .. marker) then
              found = i
              break
            end
          else
            local heading = text:match("^#+%s+(.+)%s*$")
            if heading and vim.trim(heading) == anchor:match("[^#]+$") then
              found = i
              break
            end
          end
        end
        if found then
          vim.api.nvim_win_set_cursor(0, { found, 0 })
        else
          utils.notify("Anchor not found: " .. anchor, "warn")
        end
      end
      return true
    end
    utils.notify("Note not found: " .. target, "warn")
    return true
  end
  if not silent then
    utils.notify("No link found under cursor", "warn")
  end
  return false
end

--- Smart gd: follow link if on a link, otherwise fallback to original gd
---@return nil
function M.smart_gd()
  -- Try to follow link first
  if M.follow_link_under_cursor(true) then
    return
  end

  -- Fallback: use LSP definition if available, otherwise normal gd
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  for _, client in ipairs(clients) do
    if client.supports_method("textDocument/definition") then
      vim.lsp.buf.definition()
      return
    end
  end

  vim.cmd("normal! gd")
end

return M
