-- holon/links: Obsidian-compatible note links

local utils = require("holon.utils")
local M = {}
local file_indexes = setmetatable({}, { __mode = "k" })

local function note_files(notes_path)
  local extension = require("holon.config").get("extension")
  return vim.fn.globpath(notes_path, "**/*" .. extension, false, true)
end

local function paths_by_name(files)
  local index = file_indexes[files]
  if index then return index end
  index = {}
  for _, filepath in ipairs(files) do
    local name = vim.fn.fnamemodify(filepath, ":t")
    index[name] = index[name] or {}
    table.insert(index[name], vim.fs.normalize(filepath))
  end
  file_indexes[files] = index
  return index
end

local function decode_url(value)
  return (value:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

local function encode_url(value)
  return (value:gsub("([^%w%-%._~/])", function(char)
    return string.format("%%%02X", char:byte())
  end))
end

--- Split a destination into its file target and optional heading/block anchor.
function M.split_target(target)
  local file_target, anchor = target:match("^(.-)#(.+)$")
  if not file_target then file_target = target end
  return decode_url(file_target), anchor and decode_url(anchor) or nil
end

--- Extract Wiki and Markdown links; uuid is retained for API compatibility.
function M.extract_all_links(content)
  local result = {}
  for body in content:gmatch("%[%[([^%]]+)%]%]") do
    local target, display_text = body:match("^(.-)|(.+)$")
    target = target or body
    if target ~= "" then
      table.insert(result, { uuid = target, display_text = display_text or target, format = "wiki" })
    end
  end
  for display_text, target in content:gmatch("%[([^%]]+)%]%(([^%)]+)%)") do
    if not target:match("^[%a][%w+.-]*:") then
      table.insert(result, { uuid = target, display_text = display_text, format = "markdown" })
    end
  end
  return result
end

--- Resolve a note target. Unqualified ambiguous names fail instead of picking at random.
function M.resolve_link_target(target, context_filepath, candidates)
  local config = require("holon.config")
  local notes_path = vim.fs.normalize(config.get("notes_path"))
  local extension = config.get("extension")
  local file_target = M.split_target(target)
  if file_target == "" then
    return context_filepath and vim.fs.normalize(context_filepath) or nil
  end
  file_target = file_target:gsub("/+$", "")
  if file_target:sub(-#extension) ~= extension then
    file_target = file_target .. extension
  end
  local function existing(path)
    path = vim.fs.normalize(path)
    return utils.file_exists(path) and path or nil
  end
  if file_target:sub(1, 1) == "/" then return existing(file_target) end
  if file_target:match("^%.%./") or file_target:match("^%./") then
    if context_filepath then
      return existing(vim.fn.fnamemodify(context_filepath, ":h") .. "/" .. file_target)
    end
    return nil
  end
  if file_target:find("/", 1, true) then
    return existing(notes_path .. "/" .. file_target)
  end
  if context_filepath then
    local adjacent = existing(vim.fn.fnamemodify(context_filepath, ":h") .. "/" .. file_target)
    if adjacent then return adjacent end
  end
  local root_file = existing(notes_path .. "/" .. file_target)
  if root_file then return root_file end
  local files = candidates or note_files(notes_path)
  local matches = paths_by_name(files)[file_target] or {}
  if #matches == 1 then return matches[1] end
  if #matches > 1 then return nil end

  -- Older vaults may have a UUID embedded in a longer filename.
  local legacy_uuid = file_target:sub(1, -#extension - 1)
  if not legacy_uuid:match("^[a-f0-9]+%-[a-f0-9]+%-[a-f0-9]+%-[a-f0-9]+%-[a-f0-9]+$") then
    return nil
  end
  local match
  for _, filepath in ipairs(files) do
    if utils.extract_uuid_from_path(filepath) == legacy_uuid then
      if match then return nil end
      match = vim.fs.normalize(filepath)
    end
  end
  return match
end

local function link_target(target)
  local config = require("holon.config")
  local notes_path = vim.fs.normalize(config.get("notes_path"))
  local extension = config.get("extension")
  local filepath = M.resolve_link_target(target)
  if not filepath then return target end
  local stem = vim.fn.fnamemodify(filepath, ":t:r")
  local count = #((paths_by_name(note_files(notes_path)))[stem .. extension] or {})
  if count == 1 then return stem end
  local relative = filepath:sub(#notes_path + 2)
  return relative:sub(1, -#extension - 1)
end

--- Generate a link using a unique filename or vault-root path.
function M.generate_link(target, display_text, format)
  local config = require("holon.config")
  local file_target, anchor = M.split_target(target)
  local destination = file_target == "" and "" or link_target(file_target)
  local suffix = anchor and "#" .. anchor or ""
  format = format or config.get("default_link_format")
  if format == "markdown" then
    local text = display_text or vim.fn.fnamemodify(destination, ":t")
    local path = destination ~= "" and encode_url(destination .. config.get("extension")) or ""
    local fragment = anchor and "#" .. encode_url(anchor) or ""
    return string.format("[%s](%s%s)", text, path, fragment)
  end
  if display_text and display_text ~= "" and display_text ~= destination .. suffix then
    return string.format("[[%s|%s]]", destination .. suffix, display_text)
  end
  return string.format("[[%s]]", destination .. suffix)
end

--- Find the target of the Wiki or Markdown link under a 0-indexed cursor.
function M.find_link_at_position(line, col)
  local pos = 1
  while true do
    local first, last, body = line:find("%[%[([^%]]+)%]%]", pos)
    if not first then break end
    if col >= first - 1 and col < last then return body:match("^([^|]+)") end
    pos = last + 1
  end
  pos = 1
  while true do
    local first, last, _, target = line:find("%[([^%]]+)%]%(([^%)]+)%)", pos)
    if not first then break end
    if col >= first - 1 and col < last then
      if not target:match("^[%a][%w+.-]*:") then return target end
      return nil
    end
    pos = last + 1
  end
  return nil
end

--- Find backlinks, including path and anchor links.
function M.find_backlinks(identifier, notes_path)
  notes_path = notes_path or require("holon.config").get("notes_path")
  local target_path = M.resolve_link_target(identifier)
  if not target_path then return {} end
  local backlinks = {}
  local files = note_files(notes_path)
  for _, filepath in ipairs(files) do
    if vim.fs.normalize(filepath) ~= target_path then
      local content = utils.read_file(filepath)
      if content then
        for _, link in ipairs(M.extract_all_links(content)) do
          if M.resolve_link_target(link.uuid, filepath, files) == target_path then
            table.insert(backlinks, filepath)
            break
          end
        end
      end
    end
  end
  return backlinks
end

return M
