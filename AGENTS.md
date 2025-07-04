# Speech to Text Neovim Plugin - Agent Guidelines

## Build/Test Commands
- No specific build system or test framework is implemented
- Plugin is pure Lua, no compilation needed
- Manual testing via `:Startrecording` and other commands

## Code Style Guidelines

### Formatting & Structure
- Use local `M` table pattern for module exports
- 2-space indentation
- Keep lines under 100 characters
- Use snake_case for functions, variables, and modules

### Documentation
- Use LuaDoc comments (---@param, ---@return) for function signatures
- Include brief descriptions for non-obvious functions

### Organization
- Store config in local module variables
- Organize functions logically by feature area
- Expose minimal public API through the M table

### Error Handling
- Use vim.notify with appropriate log levels (ERROR, WARN, INFO)
- Check prerequisites (ffmpeg, pactl) before operations
- Validate file paths before operations
- Provide useful error messages with context

### Dependencies
- Requires: nvim-telescope/telescope.nvim for UI interfaces
- Depends on: nui.popup for UI components
- External dependencies: FFmpeg, PulseAudio/PipeWire

### Naming Conventions
- Prefix private functions with local
- Module-specific state in `local state = {}`
- Clear, descriptive function names