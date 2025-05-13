local M = {}
local state = {
  win_id = nil,
  buf_id = nil,
  timer = nil
}

-- Animation configuration
local animation = {
  blocks = { '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█' },
  interval_ms = 100
}

-- Generate a random waveform string of given length
local function generate_waveform(length)
  local wave = {}
  for i = 1, length do
    wave[i] = animation.blocks[math.random(#animation.blocks)]
  end
  return table.concat(wave)
end

-- Show popup with an audio waveform animation
function M.show_popup(message)
  -- Ensure any existing popup is closed properly
  M.close_popup()

  -- Create buffer
  state.buf_id = vim.api.nvim_create_buf(false, true)
  if not state.buf_id then return end

  -- Set initial content
  vim.api.nvim_buf_set_lines(state.buf_id, 0, -1, false, { message })

  -- Calculate dimensions
  local width = math.max(50, #message + 30)
  local height = 2
  local opts = {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded"
  }

  -- Create window
  state.win_id = vim.api.nvim_open_win(state.buf_id, false, opts)
  if not state.win_id then
    vim.api.nvim_buf_delete(state.buf_id, { force = true })
    state.buf_id = nil
    return
  end

  -- Calculate waveform section length
  local wave_length = math.floor((width - #message - 3) / 2)

  -- Start animation timer
  state.timer = vim.uv.new_timer()
  state.timer:start(0, animation.interval_ms, vim.schedule_wrap(function()
    if state.buf_id and vim.api.nvim_buf_is_valid(state.buf_id) then
      -- Generate symmetrical waveform on both sides
      local left_wave = generate_waveform(wave_length)
      local right_wave = generate_waveform(wave_length)
      local line = left_wave .. " " .. message .. " " .. right_wave
      pcall(vim.api.nvim_buf_set_lines, state.buf_id, 0, -1, false, { line })
    else
      -- Buffer was deleted externally
      M.close_popup()
    end
  end))
end

function M.close_popup()
  if state.timer then
    pcall(function()
      state.timer:stop()
      state.timer:close()
    end)
    state.timer = nil
  end

  if state.win_id and vim.api.nvim_win_is_valid(state.win_id) then
    pcall(vim.api.nvim_win_close, state.win_id, true)
    state.win_id = nil
  end

  if state.buf_id and vim.api.nvim_buf_is_valid(state.buf_id) then
    pcall(vim.api.nvim_buf_delete, state.buf_id, { force = true })
    state.buf_id = nil
  end
end

-- Show transcription in a floating window
function M.show_transcription(text, opts)
  opts = opts or {}
  local default_opts = {
    width = 80,
    height = 10,
    title = "Transcription",
    insert_to_buffer = false,
    insert_position = "cursor" -- cursor, append, new_buffer
  }
  opts = vim.tbl_deep_extend("force", default_opts, opts)

  -- If requested, insert text directly into current buffer
  if opts.insert_to_buffer then
    if opts.insert_position == "cursor" then
      local row, col = unpack(vim.api.nvim_win_get_cursor(0))
      vim.api.nvim_buf_set_text(0, row - 1, col, row - 1, col, vim.split(text, "\n"))
    elseif opts.insert_position == "append" then
      local line_count = vim.api.nvim_buf_line_count(0)
      vim.api.nvim_buf_set_lines(0, line_count, line_count, false, vim.split(text, "\n"))
    elseif opts.insert_position == "new_buffer" then
      local buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n"))
      vim.api.nvim_win_set_buf(0, buf)
    end
    return
  end

  -- Create buffer for display
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n"))

  -- Set buffer options
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  -- vim.api.nvim_buf_set_option(buf, "modifiable", false)
  -- vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")

  -- Create window options
  local win_opts = {
    relative = "editor",
    width = opts.width,
    height = opts.height,
    row = math.floor((vim.o.lines - opts.height) / 2),
    col = math.floor((vim.o.columns - opts.width) / 2),
    style = "minimal",
    border = "rounded",
    title = opts.title,
    title_pos = "center"
  }

  -- Create window
  local win = vim.api.nvim_open_win(buf, true, win_opts)

  -- Set mappings for the window
  local keymap_opts = { noremap = true, silent = true, buffer = buf }
  vim.keymap.set("n", "q", ":close<CR>", keymap_opts)
  vim.keymap.set("n", "<Esc>", ":close<CR>", keymap_opts)
  vim.keymap.set("n", "y", function()
    vim.fn.setreg("+", text)
    vim.notify("Transcription copied to clipboard", vim.log.levels.INFO)
  end, keymap_opts)
  vim.keymap.set("n", "i", function()
    vim.api.nvim_win_close(win, true)
    M.show_transcription(text, { insert_to_buffer = true, insert_position = "cursor" })
  end, keymap_opts)
  vim.keymap.set("n", "a", function()
    vim.api.nvim_win_close(win, true)
    M.show_transcription(text, { insert_to_buffer = true, insert_position = "append" })
  end, keymap_opts)
  vim.keymap.set("n", "b", function()
    vim.api.nvim_win_close(win, true)
    M.show_transcription(text, { insert_to_buffer = true, insert_position = "new_buffer" })
  end, keymap_opts)

  -- Show help text at the bottom
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, {
    "",
    "Press: q/Esc to close, y to copy, i to insert at cursor, a to append to buffer, b for new buffer"
  })

  return win, buf
end

return M
