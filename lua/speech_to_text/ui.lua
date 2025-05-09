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
  state.timer = vim.loop.new_timer()
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

return M
