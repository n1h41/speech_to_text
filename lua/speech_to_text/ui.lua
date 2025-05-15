local M = {}
local Popup = require("nui.popup")

local state = {
  popup = nil,
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

  -- Calculate dimensions
  local width = math.max(50, #message + 30)
  local height = 2

  -- Create a popup using nui
  state.popup = Popup({
    position = "50%",
    size = {
      width = width,
      height = height,
    },
    border = {
      style = "rounded",
    },
    focusable = false,
    zindex = 50,
    enter = false,
  })

  -- Mount the popup
  state.popup:mount()

  -- Calculate waveform section length
  local wave_length = math.floor((width - #message - 3) / 2)

  -- Start animation timer
  state.timer = vim.uv.new_timer()
  state.timer:start(0, animation.interval_ms, vim.schedule_wrap(function()
    if state.popup and state.popup.bufnr and vim.api.nvim_buf_is_valid(state.popup.bufnr) then
      -- Generate symmetrical waveform on both sides
      local left_wave = generate_waveform(wave_length)
      local right_wave = generate_waveform(wave_length)
      local line = left_wave .. " " .. message .. " " .. right_wave
      pcall(vim.api.nvim_buf_set_lines, state.popup.bufnr, 0, -1, false, { line })
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

  if state.popup then
    state.popup:unmount()
    state.popup = nil
  end
end

-- Function to show confirmation dialog with Yes/No buttons
function M.show_confirmation(message, on_yes, on_no)
  local width = math.max(50, #message + 10)

  local popup = Popup({
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
      text = {
        top = "Confirm",
        top_align = "center",
      },
    },
    position = "50%",
    size = {
      width = width,
      height = 3,
    },
  })

  -- Set up content with highlighted buttons
  popup:mount()

  -- Center the message text
  local centered_message = ""
  if #message < width - 2 then -- accounting for border
    local padding = math.floor((width - 2 - #message) / 2)
    centered_message = string.rep(" ", padding) .. message
  else
    centered_message = message
  end

  -- Center the buttons
  local buttons_text = "   [Yes]      [No]   "
  local buttons_padding = math.floor((width - 2 - #buttons_text) / 2)
  local centered_buttons = string.rep(" ", buttons_padding) .. buttons_text

  -- Set initial content with buttons
  local lines = {
    centered_message,
    "",
    centered_buttons
  }
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)

  -- Calculate the starting positions for highlights based on centering
  local yes_start = buttons_padding + 3
  local yes_end = buttons_padding + 8
  local no_start = buttons_padding + 15
  local no_end = buttons_padding + 19

  -- Apply highlighting for buttons
  local ns_id = vim.api.nvim_create_namespace("speech_to_text_confirmation")
  vim.api.nvim_buf_add_highlight(popup.bufnr, ns_id, "SpecialKey", 2, yes_start, yes_end) -- Yes
  vim.api.nvim_buf_add_highlight(popup.bufnr, ns_id, "SpecialKey", 2, no_start, no_end)   -- No

  -- Set up mappings
  popup:map("n", "y", function()
    popup:unmount()
    if on_yes then on_yes() end
  end, { noremap = true })

  popup:map("n", "n", function()
    popup:unmount()
    if on_no then on_no() end
  end, { noremap = true })

  popup:map("n", "<Esc>", function()
    popup:unmount()
    if on_no then on_no() end
  end, { noremap = true })

  popup:map("n", "<LeftMouse>", function()
    local mouse_pos = vim.fn.getmousepos()
    if mouse_pos.winid ~= popup.winid then return end

    -- Check if click was on line 3 (0-indexed)
    if mouse_pos.line == 3 then
      -- Yes button region
      if mouse_pos.column >= yes_start + 1 and mouse_pos.column <= yes_end + 1 then
        popup:unmount()
        if on_yes then on_yes() end
        -- No button region
      elseif mouse_pos.column >= no_start + 1 and mouse_pos.column <= no_end + 1 then
        popup:unmount()
        if on_no then on_no() end
      end
    end
  end, { noremap = true })

  -- Return cursor to middle of window initially
  vim.api.nvim_win_set_cursor(popup.winid, { 2, math.floor(width / 2) })

  return popup
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

  -- Create popup for display using nui
  local popup = Popup({
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
      text = {
        top = opts.title,
        top_align = "center",
      },
    },
    position = "50%",
    size = {
      width = opts.width,
      height = opts.height,
    },
    buf_options = {
      modifiable = true,
      bufhidden = "wipe"
    },
  })

  -- Mount the window
  popup:mount()

  -- Set content
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, vim.split(text, "\n"))

  -- Set mappings for the window
  popup:map("n", "q", function()
    popup:unmount()
  end, { noremap = true })

  popup:map("n", "<Esc>", function()
    popup:unmount()
  end, { noremap = true })

  popup:map("n", "y", function()
    vim.fn.setreg("+", text)
    vim.notify("Transcription copied to clipboard", vim.log.levels.INFO)
  end, { noremap = true })

  popup:map("n", "i", function()
    popup:unmount()
    M.show_transcription(text, { insert_to_buffer = true, insert_position = "cursor" })
  end, { noremap = true })

  popup:map("n", "a", function()
    popup:unmount()
    M.show_transcription(text, { insert_to_buffer = true, insert_position = "append" })
  end, { noremap = true })

  popup:map("n", "b", function()
    popup:unmount()
    M.show_transcription(text, { insert_to_buffer = true, insert_position = "new_buffer" })
  end, { noremap = true })

  -- Show help text at the bottom
  vim.api.nvim_buf_set_lines(popup.bufnr, -1, -1, false, {
    "",
    "Press: q/Esc to close, y to copy, i to insert at cursor, a to append to buffer, b for new buffer"
  })

  return popup
end

return M
