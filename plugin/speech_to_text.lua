local recorder = require("speech_to_text.recorder")
local transcriber = require("speech_to_text.transcriber")

-- Default setup with configuration
recorder.setup({
  -- Default recorder settings
  output_directory = "/tmp/nvim_speech_to_text",
  file_format = "wav",
  sample_rate = "44100",
  bit_depth = "16",

  -- Transcription settings
  transcriber = {
    endpoint = "http://localhost:9000/asr",
    task = "transcribe",
    encode = true,
    language = "en", -- Default language
    output = "txt"
  }
})

vim.api.nvim_create_user_command("StartRecording", function()
  recorder.start_recording()
end, {})

vim.api.nvim_create_user_command("StopRecording", function()
  recorder.stop_recording()
end, {})

vim.api.nvim_create_user_command("CancelRecording", function()
  recorder.cancel_recording()
end, {})

vim.api.nvim_create_user_command("SelectInputDevice", function()
  recorder.select_input_device()
end, {})

vim.api.nvim_create_user_command("PlayRecording", function()
  recorder.browse_recordings()
end, {})

vim.api.nvim_create_user_command("SelectAudioPlayer", function()
  recorder.select_playback_command()
end, {})

vim.api.nvim_create_user_command("TranscribeRecording", function()
  recorder.transcribe_recording()
end, {})

vim.api.nvim_create_user_command("TranscribeRecent", function()
  recorder.transcribe_recent()
end, {})


vim.keymap.set("n", "<leader>sr", ":StartRecording<CR>", { desc = "Start Recording" })
vim.keymap.set("n", "<leader>ss", ":StopRecording<CR>", { desc = "Stop Recording" })
vim.keymap.set("n", "<leader>sc", ":CancelRecording<CR>", { desc = "Cancel Recording" })
vim.keymap.set("n", "<leader>si", ":SelectInputDevice<CR>", { desc = "Select Input Device" })
vim.keymap.set("n", "<leader>sp", ":PlayRecording<CR>", { desc = "Play Recording" })
vim.keymap.set("n", "<leader>sa", ":SelectAudioPlayer<CR>", { desc = "Select Audio Player" })
vim.keymap.set("n", "<leader>st", ":TranscribeRecording<CR>", { desc = "Transcribe Recording" })
vim.keymap.set("n", "<leader>sT", ":TranscribeRecent<CR>", { desc = "Transcribe Most Recent Recording" })
