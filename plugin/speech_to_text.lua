local recorder = require("speech_to_text.recorder")

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

vim.keymap.set("n", "<leader>sr", ":StartRecording<CR>", { desc = "Start Recording" })
vim.keymap.set("n", "<leader>sp", ":StopRecording<CR>", { desc = "Stop Recording" })
vim.keymap.set("n", "<leader>sc", ":CancelRecording<CR>", { desc = "Cancel Recording" })
vim.keymap.set("n", "<leader>si", ":SelectInputDevice<CR>", { desc = "Select Input Device" })
