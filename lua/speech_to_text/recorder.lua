local M = {}
local ui = require("speech_to_text.ui")
local transcriber = require("speech_to_text.transcriber")

local state = {
  recording = false,
  job_id = nil,
  output_file = "/tmp/nvim_speech_to_text/speech_record.wav",
  input_device = "default",
  playback_command = "ffplay -nodisp -autoexit", -- Default player
  players = {                                    -- Available players
    { name = "FFplay", cmd = "ffplay -nodisp -autoexit" },
    { name = "mpv",    cmd = "mpv --no-video" },
    { name = "cvlc",   cmd = "cvlc --play-and-exit" },
  },
}


-- Configuration with user-modifiable options
M.config = {
  output_directory = "/tmp/nvim_speech_to_text",
  file_format = "wav",
  sample_rate = "44100",
  bit_depth = "16",
  playback_command = "ffplay -nodisp -autoexit", -- Default player
  players = {                                    -- Available players
    { name = "FFplay", cmd = "ffplay -nodisp -autoexit" },
    { name = "mpv",    cmd = "mpv --no-video" },
    { name = "cvlc",   cmd = "cvlc --play-and-exit" },
  },
}

-- Check if a command is available
local function command_exists(cmd)
  return vim.fn.executable(cmd) == 1
end

-- Function to play audio file
function M.play_audio(file_path)
  if not file_path or vim.fn.filereadable(file_path) == 0 then
    vim.notify("Invalid audio file: " .. (file_path or "nil"), vim.log.levels.ERROR)
    return
  end

  -- Extract just the command name for executable check
  local cmd_name = M.config.playback_command:match("^(%S+)")
  if not command_exists(cmd_name) then
    vim.notify("Playback command not found: " .. cmd_name, vim.log.levels.ERROR)
    return
  end

  -- Show playback notification
  ui.show_popup("Playing audio...")

  -- Build the command
  local cmd = M.config.playback_command .. " " .. vim.fn.shellescape(file_path)

  -- Run the playback command
  local job_id = vim.fn.jobstart(cmd, {
    on_exit = function(_, exit_code)
      vim.schedule(function()
        ui.close_popup()
        if exit_code ~= 0 then
          vim.notify("Playback failed with exit code: " .. exit_code, vim.log.levels.ERROR)
        end
      end)
    end
  })

  if job_id <= 0 then
    ui.close_popup()
    vim.notify("Failed to start playback", vim.log.levels.ERROR)
  end
end

-- Function to select playback command from available options
function M.select_playback_command()
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  -- Create a new picker for player selection
  pickers.new({}, {
    prompt_title = "Select Audio Player",
    finder = finders.new_table {
      results = M.config.players,
      entry_maker = function(entry)
        return {
          value = entry.cmd,
          display = entry.name,
          ordinal = entry.name,
        }
      end
    },
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, _)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        M.config.playback_command = selection.value
        vim.notify("Selected audio player: " .. selection.display, vim.log.levels.INFO)
      end)
      return true
    end,
  }):find()
end

-- Generate output filename with timestamp
local function generate_output_filename()
  local timestamp = os.date("%Y%m%d_%H%M%S")
  return string.format("%s/recording_%s.%s",
    M.config.output_directory,
    timestamp,
    M.config.file_format)
end

-- Lists all recordings in a Telescope finder
function M.browse_recordings()
  -- Check if telescope is installed
  local has_telescope, _ = pcall(require, "telescope.builtin")
  if not has_telescope then
    vim.notify("Telescope is required for this feature", vim.log.levels.ERROR)
    return
  end

  -- Ensure output directory exists
  vim.fn.mkdir(M.config.output_directory, "p")

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local previewers = require("telescope.previewers")

  -- Custom file previewer with metadata
  local file_previewer = previewers.new_termopen_previewer({
    get_command = function(entry)
      return { "ffprobe", "-hide_banner", entry.value }
    end
  })

  -- Find all audio files
  local audio_pattern = string.format("*.%s", M.config.file_format)
  local files = vim.fn.glob(M.config.output_directory .. "/" .. audio_pattern, true, true)

  -- Build entries with metadata
  local entries = {}
  for _, file in ipairs(files) do
    local filename = vim.fn.fnamemodify(file, ":t")
    local date_str = filename:match("recording_(%d%d%d%d%d%d%d%d_%d%d%d%d%d%d)")

    if date_str then
      -- Format as YYYY-MM-DD HH:MM:SS
      local year = date_str:sub(1, 4)
      local month = date_str:sub(5, 6)
      local day = date_str:sub(7, 8)
      local hour = date_str:sub(10, 11)
      local min = date_str:sub(12, 13)
      local sec = date_str:sub(14, 15)

      local display_date = string.format("%s-%s-%s %s:%s:%s",
        year, month, day, hour, min, sec)

      table.insert(entries, {
        path = file,
        date = display_date,
        size = vim.fn.getfsize(file),
      })
    end
  end

  -- Sort by date (newest first)
  table.sort(entries, function(a, b)
    return a.date > b.date
  end)

  -- Create the picker
  pickers.new({}, {
    prompt_title = "Speech Recordings",
    finder = finders.new_table {
      results = entries,
      entry_maker = function(entry)
        -- Convert size to human readable format
        local size_str
        if entry.size < 1024 then
          size_str = string.format("%d B", entry.size)
        elseif entry.size < 1024 * 1024 then
          size_str = string.format("%.2f KB", entry.size / 1024)
        else
          size_str = string.format("%.2f MB", entry.size / (1024 * 1024))
        end

        return {
          value = entry.path,
          display = string.format("%s (%s)", entry.date, size_str),
          ordinal = entry.date,
        }
      end
    },
    sorter = conf.generic_sorter({}),
    previewer = file_previewer,
    attach_mappings = function(prompt_bufnr, map)
      -- Play on selection
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        M.play_audio(selection.value)
      end)

      -- Delete with <c-d>
      map("i", "<c-d>", function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)

        -- Confirm deletion
        vim.ui.select({ "Yes", "No" }, {
          prompt = "Delete recording " .. vim.fn.fnamemodify(selection.value, ":t") .. "?",
        }, function(choice)
          if choice == "Yes" then
            -- Delete file
            if pcall(os.remove, selection.value) then
              vim.notify("Recording deleted", vim.log.levels.INFO)
              -- Reopen browser
              vim.defer_fn(function()
                M.browse_recordings()
              end, 100)
            else
              vim.notify("Failed to delete recording", vim.log.levels.ERROR)
            end
          else
            -- Reopen browser if canceled
            M.browse_recordings()
          end
        end)
      end)

      return true
    end,
  }):find()
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

      -- Show confirmation dialog after successful recording
      ui.show_confirmation("Transcribe this recording now?",
        -- On Yes
        function()
          -- Use the saved output file path for transcription
          M.transcribe_audio(output_file)
        end,
        -- On No - just a simple notification
        function()
          vim.notify("You can transcribe later using TranscribeRecent command", vim.log.levels.INFO)
        end
      )
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

-- Transcribe an audio recording
--[[ function M.transcribe_audio(file_path, opts)
  opts = opts or {}

  -- Validate the file
  if not file_path or vim.fn.filereadable(file_path) == 0 then
    vim.notify("Invalid audio file: " .. (file_path or "nil"), vim.log.levels.ERROR)
    return
  end

  -- Show transcribing notification
  ui.show_popup("Transcribing audio...")

  -- Call the transcriber
  transcriber.transcribe_async(file_path, opts, function(text, err)
    ui.close_popup()

    if err then
      vim.notify("Transcription failed: " .. err, vim.log.levels.ERROR)
      return
    end

    if not text or text == "" then
      vim.notify("Received empty transcription", vim.log.levels.WARN)
      return
    end

    -- Display the transcription
    ui.show_transcription(text, { title = "Transcription: " .. vim.fn.fnamemodify(file_path, ":t") })
    vim.notify("Transcription completed", vim.log.levels.INFO)
  end)
end  ]]

-- Transcribe an audio recording
function M.transcribe_audio(file_path, opts)
  opts = opts or {}

  -- Validate the file
  if not file_path or vim.fn.filereadable(file_path) == 0 then
    vim.notify("Invalid audio file: " .. (file_path or "nil"), vim.log.levels.ERROR)
    return
  end

  -- Show transcribing notification
  ui.show_popup("Transcribing audio...")

  local text, err = transcriber.transcribe(file_path, opts)

  ui.close_popup()

  if err then
    vim.notify("Transcription failed: " .. err, vim.log.levels.ERROR)
    return
  end

  if not text or text == "" then
    vim.notify("Received empty transcription", vim.log.levels.WARN)
    return
  end

  ui.show_transcription(text, { title = "Transcription: " .. vim.fn.fnamemodify(file_path, ":t") })
  vim.notify("Transcription completed", vim.log.levels.INFO)
end

-- Open file selection and transcribe
function M.transcribe_recording()
  -- Check if transcriber is configured
  --[[ if not transcriber.check_availability() then
    vim.notify("The API server is not available. Check your configuration.", vim.log.levels.ERROR)
    return
  end ]]

  -- Check if telescope is installed
  local has_telescope, _ = pcall(require, "telescope.builtin")
  if not has_telescope then
    vim.notify("Telescope is required for this feature", vim.log.levels.ERROR)
    return
  end

  -- Ensure output directory exists
  vim.fn.mkdir(M.config.output_directory, "p")

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  -- Find all audio files
  local audio_pattern = string.format("*.%s", M.config.file_format)
  local files = vim.fn.glob(M.config.output_directory .. "/" .. audio_pattern, true, true)

  -- Build entries with metadata
  local entries = {}
  for _, file in ipairs(files) do
    local filename = vim.fn.fnamemodify(file, ":t")
    local date_str = filename:match("recording_(%d%d%d%d%d%d%d%d_%d%d%d%d%d%d)")

    if date_str then
      -- Format as YYYY-MM-DD HH:MM:SS
      local year = date_str:sub(1, 4)
      local month = date_str:sub(5, 6)
      local day = date_str:sub(7, 8)
      local hour = date_str:sub(10, 11)
      local min = date_str:sub(12, 13)
      local sec = date_str:sub(14, 15)

      local display_date = string.format("%s-%s-%s %s:%s:%s",
        year, month, day, hour, min, sec)

      table.insert(entries, {
        path = file,
        date = display_date,
        size = vim.fn.getfsize(file),
      })
    end
  end

  -- Sort by date (newest first)
  table.sort(entries, function(a, b)
    return a.date > b.date
  end)

  -- Create the picker
  pickers.new({}, {
    prompt_title = "Select Recording to Transcribe",
    finder = finders.new_table {
      results = entries,
      entry_maker = function(entry)
        -- Convert size to human readable format
        local size_str
        if entry.size < 1024 then
          size_str = string.format("%d B", entry.size)
        elseif entry.size < 1024 * 1024 then
          size_str = string.format("%.2f KB", entry.size / 1024)
        else
          size_str = string.format("%.2f MB", entry.size / (1024 * 1024))
        end

        return {
          value = entry.path,
          display = string.format("%s (%s)", entry.date, size_str),
          ordinal = entry.date,
        }
      end
    },
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, _)
      -- Transcribe on selection
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        M.transcribe_audio(selection.value)
      end)

      return true
    end,
  }):find()
end

-- Transcribe the most recent recording
function M.transcribe_recent()
  -- Check if transcriber is configured
  if not transcriber.check_availability() then
    vim.notify("The API server is not available. Check your configuration.", vim.log.levels.ERROR)
    return
  end

  -- Find the most recent recording
  local audio_pattern = string.format("*.%s", M.config.file_format)
  local files = vim.fn.glob(M.config.output_directory .. "/" .. audio_pattern, true, true)

  if #files == 0 then
    vim.notify("No recordings found", vim.log.levels.ERROR)
    return
  end

  -- Sort files by modification time (newest first)
  table.sort(files, function(a, b)
    return vim.fn.getftime(a) > vim.fn.getftime(b)
  end)

  -- Transcribe the most recent file
  M.transcribe_audio(files[1])
end

-- Function to setup user configuration
function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend("force", M.config, opts)

  -- Ensure output directory exists
  vim.fn.mkdir(M.config.output_directory, "p")

  -- Initialize transcriber
  if opts.transcriber then
    transcriber.setup(opts.transcriber)
  end

  return M
end

return M
