# Speech to Text for Neovim

A Neovim plugin that enables speech-to-text conversion directly within your editor. Record audio using your system microphone, then transcribe it automatically into your buffer.

![Plugin Demo](https://example.com/demo.gif)

## Features

- Record audio directly from Neovim using your system microphone
- Save recordings with timestamps for easy reference
- Choose between multiple audio input devices
- Play back your recordings
- Transcribe recordings to text
- Insert transcriptions directly into your buffer
- Support for various audio players (FFplay, mpv, VLC)

## Requirements

- Neovim 0.7+ 
- FFmpeg (for recording and processing audio)
- PulseAudio or PipeWire-PulseAudio (for audio input management)
- An audio playback utility (one of):
  - FFplay (included with FFmpeg)
  - mpv
  - VLC (cvlc command-line interface)
- A transcription API server (optional, for speech-to-text functionality)

## Installation

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'n1h41/speech_to_text.nvim',
  requires = { 'nvim-telescope/telescope.nvim' },  -- For file browser interfaces
  config = function()
    require("speech_to_text.recorder").setup({
      -- Configuration options (see below)
    })
  end
}
```

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'n1h41/speech_to_text.nvim',
  dependencies = { 'nvim-telescope/telescope.nvim' },  -- For file browser interfaces
  opts = {
    -- Configuration options (see below)
  }
}
```

## Configuration

The plugin can be configured with these options:

```lua
require("speech_to_text.recorder").setup({
  -- Default recorder settings
  output_directory = "/tmp/nvim_speech_to_text",  -- Directory to save recordings
  file_format = "wav",                           -- Audio format
  sample_rate = "44100",                         -- Sample rate in Hz
  bit_depth = "16",                              -- Bit depth
  
  -- Transcription settings
  transcriber = {
    endpoint = "http://localhost:9000/asr",      -- URL of the transcription API
    task = "transcribe",                         -- Transcription task type
    encode = true,                               -- Encode audio for the API
    language = "en",                             -- Default language
    output = "txt"                               -- Output format
  }
})
```

## Commands

The plugin creates the following commands:

| Command | Description |
|---------|-------------|
| `:StartRecording` | Begin recording audio |
| `:StopRecording` | Stop and save the recording |
| `:CancelRecording` | Cancel recording and delete file |
| `:SelectInputDevice` | Select audio input device |
| `:PlayRecording` | Browse and play saved recordings |
| `:SelectAudioPlayer` | Choose audio playback application |
| `:TranscribeRecording` | Select recording to transcribe |
| `:TranscribeRecent` | Transcribe most recent recording |

## Default Keymaps

The plugin sets up these default keymaps:

| Keymap | Description |
|--------|-------------|
| `<leader>sr` | Start recording |
| `<leader>ss` | Stop recording |
| `<leader>sc` | Cancel recording |
| `<leader>si` | Select input device |
| `<leader>sp` | Play recording |
| `<leader>sa` | Select audio player |
| `<leader>st` | Transcribe recording |
| `<leader>sT` | Transcribe most recent recording |

## Usage

### Basic Workflow:

1. Start a recording with `:StartRecording` or `<leader>sr`
2. Speak into your microphone
3. Stop the recording with `:StopRecording` or `<leader>ss`
4. Transcribe it with `:TranscribeRecent` or `<leader>sT`
5. The transcription will appear in a floating window
6. From there, you can:
   - Press `i` to insert at cursor position
   - Press `a` to append to current buffer
   - Press `b` to open in a new buffer
   - Press `y` to copy to clipboard
   - Press `q` or `<Esc>` to close

### Selecting Input Device

If you have multiple microphones, use `:SelectInputDevice` or `<leader>si` to choose which one to record from.

### Managing Recordings

Use `:PlayRecording` or `<leader>sp` to browse your saved recordings. From this view, you can:
- Select a recording to play it
- Press `<c-d>` to delete a recording

### Changing Audio Player

The plugin supports multiple audio playback applications. Use `:SelectAudioPlayer` or `<leader>sa` to choose between:
- FFplay (default)
- mpv
- VLC (cvlc)

## Setting Up a Transcription API

For the transcription functionality to work, you need a compatible API service running. The plugin is configured to work with ASR (Automated Speech Recognition) APIs that accept POST requests with audio files.

You can use open-source solutions like:
- [Whisper API](https://github.com/openai/whisper) (local server)
- [Coqui STT](https://github.com/coqui-ai/STT)

Configure the endpoint in the setup function.

## Troubleshooting

If you encounter issues:

- Make sure FFmpeg is installed and in your PATH
- Verify that PulseAudio or PipeWire-PulseAudio is installed and running
- Check that your microphone is working with other applications
- For transcription issues, verify that your API endpoint is accessible

## License

MIT

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
