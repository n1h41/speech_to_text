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

-- Parse arecord output
local function parse_devices(output)
  local devices = {}
  for line in output:gmatch("[^\r\n]+") do
    local card, device, name = line:match("card (%d+):.-device (%d+): ([^%[]+)")
    if card and device and name then
      table.insert(devices, {
        display = string.format("hw:%s,%s - %s", card, device, name:gsub("^%s*(.-)%s*$", "%1")),
        value = string.format("hw:%s,%s", card, device),
      })
    end
  end
  return devices
end

-- Test if a device is actually working
local function test_device(device)
  local test_file = os.tmpname()
  local test_success = false

  local job_id = vim.fn.jobstart({
    "ffmpeg",
    "-f", "alsa",
    "-i", device,
    "-t", "0.1", -- Record for 0.1 seconds
    "-y",
    test_file
  }, {
    on_exit = function(_, exit_code)
      test_success = (exit_code == 0)
      os.remove(test_file)
    end,
  })

  -- Wait briefly for job to complete
  vim.wait(500, function() return test_success ~= false end)
  vim.fn.jobstop(job_id)

  return test_success
end

-- Telescope input device selector
function M.select_input_device()
  if not command_exists("arecord") then
    vim.notify("Error: 'arecord' not found. Please install ALSA utilities.", vim.log.levels.ERROR)
    return
  end

  local output = vim.fn.system("arecord -l")
  local devices = parse_devices(output)

  if #devices == 0 then
    vim.notify("No input devices found via arecord.", vim.log.levels.WARN)
    return
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  pickers.new({}, {
    prompt_title = "Select Audio Input Device",
    finder = finders.new_table {
      results = devices,
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

        -- Show testing notification
        vim.notify("Testing device " .. selection.display .. "...", vim.log.levels.INFO)

        -- Test if the device works
        if test_device(selection.value) then
          state.input_device = selection.value
          vim.notify("Selected input device: " .. selection.display, vim.log.levels.INFO)
        else
          vim.notify("Device test failed for: " .. selection.display, vim.log.levels.ERROR)
        end
      end)
      return true
    end,
  }):find()
end

function M.start_recording()
  if not command_exists("ffmpeg") then
    vim.notify("Error: 'ffmpeg' not found. Please install FFmpeg.", vim.log.levels.ERROR)
    return
  end

  if state.recording then
    vim.notify("Recording is already in progress.", vim.log.levels.WARN)
    return
  end

  -- Generate a new filename with timestamp
  state.output_file = generate_output_filename()

  -- Create the output directory if it doesn't exist
  vim.fn.mkdir(M.config.output_directory, "p")

  ui.show_popup("Recording...")
  state.recording = true

  -- Create the FFmpeg command with configurable options
  local cmd = {
    "ffmpeg",
    "-f", "alsa",
    "-i", state.input_device,
    "-ar", M.config.sample_rate,
    "-sample_fmt", "s" .. M.config.bit_depth,
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
