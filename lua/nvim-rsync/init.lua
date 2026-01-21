local M = {}

--------------------------------------------------
-- State
--------------------------------------------------

M.enabled = false
M.debounce_ms = 800
M._timer = nil
M._running = false

M.augroup = vim.api.nvim_create_augroup("RsyncSync", { clear = true })

--------------------------------------------------
-- Helpers
--------------------------------------------------

local function get_project_root()
  local git_root = vim.fn.systemlist("git rev-parse --show-toplevel 2>/dev/null")[1]
  if git_root and git_root ~= "" then
    return git_root
  end
  return vim.fn.getcwd()
end

local function get_rsync_target(root)
  local dotfile = root .. "/.rsync-target"
  if vim.fn.filereadable(dotfile) == 0 then
    return nil
  end
  return vim.fn.readfile(dotfile)[1]
end

--------------------------------------------------
-- Rsync runner (debounced)
--------------------------------------------------

local function run_rsync(manual)
  -- Debounce automatic syncs
  if not manual then
    if M._timer then
      M._timer:stop()
      M._timer:close()
    end

    M._timer = vim.loop.new_timer()
    M._timer:start(M.debounce_ms, 0, vim.schedule_wrap(function()
      M._timer:stop()
      M._timer:close()
      M._timer = nil
      run_rsync(true)
    end))

    return
  end

  -- Prevent overlapping rsyncs
  if M._running then
    return
  end
  M._running = true

  local root = get_project_root()
  local target = get_rsync_target(root)

  if not target or target == "" then
    M._running = false
    vim.print(vim.inspect(root))
    vim.print(vim.inspect(target))
    vim.notify("rsync-sync: missing or empty .rsync-target", vim.log.levels.WARN)
    return
  end

  local cmd = {
    "rsync",
    "-az",

    -- Always ignored
    "--exclude=.git",
    "--exclude=.rsync-*",
  }

  -- Optional ignore file
  local ignore_file = root .. "/.rsync-ignore"
  if vim.fn.filereadable(ignore_file) == 1 then
    table.insert(cmd, "--exclude-from=" .. ignore_file)
  end

  table.insert(cmd, root .. "/")
  table.insert(cmd, target)

  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_exit = function(_, code)
      M._running = false
      if code == 0 then
        vim.notify("rsync-sync: synced", vim.log.levels.INFO)
      else
        vim.notify("rsync-sync: rsync failed", vim.log.levels.ERROR)
      end
    end,
  })
end

--------------------------------------------------
-- Public API
--------------------------------------------------

function M.enable()
  if M.enabled then
    return
  end

  local root = get_project_root()
  local target = get_rsync_target(root)
  if not target or target == "" then
	  return
  end
  M.enabled = true

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = M.augroup,
    callback = function()
      run_rsync(false)
    end,
  })

  vim.notify("rsync-sync: enabled", vim.log.levels.INFO)
end

function M.disable()
  if not M.enabled then
    return
  end

  M.enabled = false
  vim.api.nvim_clear_autocmds({ group = M.augroup })

  vim.notify("rsync-sync: disabled", vim.log.levels.INFO)
end

function M.toggle()
  if M.enabled then
    M.disable()
  else
    M.enable()
  end
end

function M.sync_now()
  run_rsync(true)
end

--------------------------------------------------
-- Statusline helper (MiniStatusline-friendly)
--------------------------------------------------

function M.statusline()
  if not M.enabled then
    return " Sync OFF"
  end
  if M._running then
    return " Syncing…"
  end
  return " Sync ON"
end

--------------------------------------------------
-- User commands
--------------------------------------------------

vim.api.nvim_create_user_command("RsyncToggle", function()
  M.toggle()
end, {})

vim.api.nvim_create_user_command("RsyncNow", function()
  M.sync_now()
end, {})

return M
