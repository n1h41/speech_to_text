local M = {}
local ui = require("speech_to_text.ui")

local state = {
  recording = false,
  job_id = nil,
  output_file = "/tmp/nvim_speech_to_text/speech_record.wav",
  input_device = "default"
}

-- Configuration with user-modifiable options
M.config = {
  output_directory = "/tmp/nvim_speech_to_text",
  file_format = "wav",
  sample_rate = "44100",
  bit_depth = "16"
}

-- Check if a command is available
local function command_exists(cmd)
  return vim.fn.executable(cmd) == 1
end

-- Generate output filename with timestamp
local function generate_output_filename()
  local timestamp = os.date("%Y%m%d_%H%M%S")
  return string.format("%s/recording_%s.%s",
    M.config.output_directory,
    timestamp,
    M.config.file_format)
end

-- Parse PulseAudio input sources from pactl
local function parse_pulse_sources(output)
  local sources = {}
  local current_source = {}
  local in_source = false

  for line in output:gmatch("[^\r\n]+") do
    -- Start of a new source description
    if line:match("^Source #") then
      if current_source.name and current_source.description then
        table.insert(sources, {
          display = current_source.description,
          value = current_source.name,
        })
      end
      current_source = {}
      in_source = true
      -- End of source descriptions
    elseif in_source and line:match("^%s*$") then
      in_source = false
      if current_source.name and current_source.description then
        table.insert(sources, {
          display = current_source.description,
          value = current_source.name,
        })
      end
      current_source = {}
      -- Parse source info
    elseif in_source then
      local name = line:match("^%s*Name:%s*(.+)$")
      local description = line:match("^%s*Description:%s*(.+)$")

      if name then
        current_source.name = name
      elseif description then
        current_source.description = description
      end
    end
  end

  -- Handle the last source if any
  if in_source and current_source.name and current_source.description then
    table.insert(sources, {
      display = current_source.description,
      value = current_source.name,
    })
  end

  return sources
end

-- Telescope input device selector
function M.select_input_device()
  if not command_exists("pactl") then
    vim.notify("Error: 'pactl' not found. Please install PulseAudio or PipeWire-PulseAudio.", vim.log.levels.ERROR)
    return
  end

  local output = vim.fn.system("pactl list sources")
  local sources = parse_pulse_sources(output)

  if #sources == 0 then
    vim.notify("No input sources found via pactl.", vim.log.levels.WARN)
    return
  end

  -- Add special case for default source
  table.insert(sources, 1, {
    display = "System Default Source",
    value = "@DEFAULT_SOURCE@"
  })

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  pickers.new({}, {
    prompt_title = "Select Audio Input Source",
    finder = finders.new_table {
      results = sources,
      entry_maker = function(entry)
        return {
          value = entry.value,
          display = entry.display,
          ordinal = entry.display,
        }
      end
    },
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, _)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()

        -- Set up error capture
        vim.api.nvim_create_autocmd("User", {
          pattern = "SpeechToTextDeviceTestError",
          once = true,
          callback = function(event)
            M._last_test_error = {
              device = selection.display,
              error = event.data.error
            }
          end
        })

        -- Skip testing
        state.input_device = selection.value
        vim.notify("Selected input source: " .. selection.display, vim.log.levels.INFO)
      end)
      return true
    end,
  }):find()
end

-- Try to find the best default source if none is set
local function ensure_input_source()
  -- If using default but it's not been specifically set, try to find a better one
  if state.input_device == "default" then
    -- Try to get the system default source from pactl
    if command_exists("pactl") then
      local default_source = vim.fn.trim(vim.fn.system("pactl info | grep 'Default Source' | cut -d: -f2"))
      if default_source and #default_source > 0 then
        state.input_device = default_source
        return true
      end
    end
    -- If that failed, use the special PulseAudio identifier
    state.input_device = "@DEFAULT_SOURCE@"
  end
  return true
end

function M.start_recording()
  if not command_exists("ffmpeg") then
    vim.notify("Error: 'ffmpeg' not found. Please install FFmpeg.", vim.log.levels.ERROR)
    return
  end

  if not command_exists("pactl") then
    vim.notify("Error: 'pactl' not found. Please install PulseAudio or PipeWire-PulseAudio.", vim.log.levels.ERROR)
    return
  end

  if state.recording then
    vim.notify("Recording is already in progress.", vim.log.levels.WARN)
    return
  end

  -- Make sure we have a valid input source
  ensure_input_source()

  -- Generate a new filename with timestamp
  state.output_file = generate_output_filename()

  -- Create the output directory if it doesn't exist
  vim.fn.mkdir(M.config.output_directory, "p")

  ui.show_popup("Recording...")
  state.recording = true

  -- Create the FFmpeg command with PulseAudio input and better Bluetooth support
  local cmd = {
    "ffmpeg",
    "-f", "pulse",
    "-i", state.input_device,
    "-ar", M.config.sample_rate, -- Sample rate
    "-ac", "1",                  -- Mono recording often works better
    "-y",
    state.output_file
  }

  state.job_id = vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stderr = function(_, data)
      if data and #data > 0 then
        -- Log FFmpeg errors to debug info if needed
        vim.schedule(function()
          vim.api.nvim_exec_autocmds("User", {
            pattern = "SpeechToTextRecordingError",
            data = { error = table.concat(data, "\n") }
          })
        end)
      end
    end,
    on_exit = function(_, exit_code)
      if state.recording then -- Only if not explicitly stopped
        vim.schedule(function()
          state.recording = false
          ui.close_popup()

          if exit_code == 0 then
            vim.notify("Recording stopped and saved.", vim.log.levels.INFO)
          else
            vim.notify("Recording failed with exit code: " .. exit_code, vim.log.levels.ERROR)
            -- Try to clean up the file if recording failed
            pcall(os.remove, state.output_file)
          end
        end)
      end
    end,
  })

  vim.notify("Started recording from " .. state.input_device, vim.log.levels.INFO)
end

function M.stop_recording()
  if not state.recording then
    vim.notify("No active recording to stop.", vim.log.levels.WARN)
    return
  end

  local output_file = state.output_file

  -- Stop the job and reset state
  pcall(vim.fn.jobstop, state.job_id)
  state.job_id = nil
  state.recording = false
  ui.close_popup()

  -- Wait a moment for FFmpeg to finalize the file
  vim.defer_fn(function()
    if vim.fn.filereadable(output_file) == 1 then
      vim.notify("Recording saved to " .. output_file, vim.log.levels.INFO)
    else
      vim.notify("Failed to save recording to " .. output_file, vim.log.levels.ERROR)
    end
  end, 200)
end

function M.cancel_recording()
  if not state.recording then
    vim.notify("No active recording to cancel.", vim.log.levels.WARN)
    return
  end

  local output_file = state.output_file

  -- Stop the job and reset state
  pcall(vim.fn.jobstop, state.job_id)
  state.job_id = nil
  state.recording = false
  ui.close_popup()

  -- Try to remove the file
  vim.defer_fn(function()
    if pcall(os.remove, output_file) then
      vim.notify("Recording canceled and file deleted.", vim.log.levels.INFO)
    else
      vim.notify("Recording canceled but couldn't delete file.", vim.log.levels.WARN)
    end
  end, 200)
end

-- Function to setup user configuration
function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend("force", M.config, opts)

  -- Ensure output directory exists
  vim.fn.mkdir(M.config.output_directory, "p")

  return M
end

return M
