local M = {}

local config = {
  endpoint = "http://localhost:9000/asr",
  encode = true,
  task = "transcribe",
  language = nil,
  initial_prompt = nil,
  output = "txt",
  timeout = 60000, -- 60 seconds timeoutanguage = nil,
}

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})
end

function M.get_config()
  return config
end

local function normalize_text(text)
  -- Replace Neovim variants
  text = text:gsub("[Nn][Ee][Oo][VvWw]?[Ii1lL][Mm]?", "Neovim")
  --Replace Yobim with Neovim
  text = text:gsub("[Yy][Oo][Bb][Ii][Mm]", "Neovim")
  -- Replace Niobim with Neovim
  text = text:gsub("[Nn][Ii][Oo][Bb][Ii][Mm]", "Neovim")
  -- Replace Neel Bim with Neovim
  text = text:gsub("[Nn][Ee][Ee][Ll]%s*[Bb][Ii][Mm]", "Neovim")


  -- Replace MCP variants
  text = text:gsub("[Mm][Cc][Pp]%s*[Tt][Oo][Oo][Ll]", "@mcp")
  text = text:gsub("^[Mm][Cc][Pp].*", "@mcp")

  -- Replace editor tool variants
  text = text:gsub("[Ee][Dd][Ii][Tt][Oo][Rr]%s+[Tt][Oo][Oo][Ll]", "@editor")

  -- Replace buffer with #buffer
  text = text:gsub("[Bb][Uu][Ff][Ff][Ee][Rr]", "#buffer")

  -- Replace buffer watch with #buffer{watch}
  text = text:gsub("[Bb][Uu][Ff][Ff][Ee][Rr]%s*[Ww][Aa][Tt][Cc][Hh]", "#buffer{watch}")

  return text
end

--- Build the curl command for transcription
---@param file_path string
---@param opts table
---@return table
local function build_curl_command(file_path, opts)
  local endpoint = opts.endpoint or config.endpoint
  local cmd = {
    "curl",
    "-s",
    "-X", "POST",
    endpoint
  }

  local params = {}
  if opts.encode ~= nil then table.insert(params, "encode=" .. tostring(opts.encode)) end
  if opts.task then table.insert(params, "task=" .. opts.task) end
  if opts.language then table.insert(params, "language=" .. opts.language) end
  if opts.initial_prompt then table.insert(params, "initial_prompt=" .. vim.fn.shellescape(opts.initial_prompt)) end
  if opts.output then table.insert(params, "output=" .. opts.output) end

  -- Append parameters to endpoint if any
  if #params > 0 then
    local query_string = table.concat(params, "&")
    table.insert(cmd, "'" .. endpoint .. "?" .. query_string .. "'")
    -- Remove the original endpoint which we've now replaced
    table.remove(cmd, 5)
  end

  -- Add the file
  table.insert(cmd, "-F")
  table.insert(cmd, "audio_file=@" .. vim.fn.shellescape(file_path))

  return cmd
end

--- Transcribe an audio file using the configured endpoint
---@param file_path string
---@param opts table
---@return nil
---@return string | nil
function M.transcribe(file_path, opts)
  opts = opts or {}
  opts = vim.tbl_deep_extend("force", config, opts)

  if not vim.fn.filereadable(file_path) then
    return nil, "File not found: " .. file_path
  end

  local cmd = build_curl_command(file_path, opts)
  local cmd_str = table.concat(cmd, " ")

  -- Execute curl command
  local output = vim.fn.system(cmd_str)
  local exit_code = vim.v.shell_error

  if exit_code ~= 0 then
    return nil, "API request failed: " .. output
  end

  return output, nil
end

---comment
---@param file_path string
---@param opts table
---@param callback function
---@return number | nil
function M.transcribe_async(file_path, opts, callback)
  opts = opts or {}
  opts = vim.tbl_deep_extend("force", config, opts)

  if not vim.fn.filereadable(file_path) then
    if callback then
      callback(nil, "File not found: " .. file_path)
    end
    return
  end

  local cmd = build_curl_command(file_path, opts)
  local cmd_str = table.concat(cmd, " ")

  -- Setup buffers for stdout and stderr
  local stdout_data = {}
  local stdout_err = {}

  -- Execute curl command
  local job_id = vim.fn.jobstart(cmd_str, {
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line and line ~= "" then
            table.insert(stdout_data, line)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line and line ~= "" then
            table.insert(stdout_err, line)
          end
        end
      end
    end,
    on_exit = function(_, exit_code)
      if exit_code ~= 0 then
        local error_msg = table.concat(stdout_err, "\n")
        if callback then
          callback(nil, "API request failed: " .. error_msg .. " (exit code: " .. exit_code .. ")")
        end
      else
        local response = table.concat(stdout_data, "\n")
        response = normalize_text(response)
        if callback then callback(response) end
      end
    end,
    stdout_buffered = true,
    stderr_buffered = true,
  })

  if job_id <= 0 then
    if callback then callback(nil, "Failed to start curl process") end
    return
  end

  if opts.timeout and opts.timeout > 0 then
    vim.defer_fn(function()
      if vim.fn.jobwait({ job_id }, 0)[1] == -1 then
        vim.fn.jobstop(job_id)
        if callback then callback(nil, "Transcription timed out after " .. opts.timeout / 1000 .. "seconds") end
      end
    end, opts.timeout)
  end

  return job_id
end

function M.check_availability(callback)
  local cmd = { "curl", "-s", "-X", "POST", "-o", "/dev/null", "-w", "%{http_code}", config.endpoint }

  if callback then
    -- Async version
    vim.fn.jobstart(cmd, {
      on_stdout = function(_, data)
        local status_code = tonumber(data[1])
        callback(status_code >= 200 and status_code < 300 or status_code == 422)
      end,
      on_exit = function(_, exit_code)
        if exit_code ~= 0 then
          callback(false)
        end
      end
    })
  else
    -- Sync version
    local status_code = tonumber(vim.fn.system(cmd))
    return status_code and status_code >= 200 and status_code < 300
  end
end

--- Detect the language of an audio file
---@param file_path string
---@param opts table
---@param callback function
---@return nil
function M.detect_language(file_path, opts, callback)
  opts = opts or {}
  local detect_opts = vim.tbl_deep_extend("force", opts, {
    endpoint = (opts.endpoint or config.endpoint):gsub("/asr$", "") .. "/detect-language",
  })

  if callback then
    return M.transcribe_async(file_path, detect_opts, callback)
  else
    return M.transcribe(file_path, detect_opts)
  end
end

-- Get list of supported languages from the API specification
function M.get_supported_languages()
  -- This is based on the OpenAPI specification
  return {
    "af", "am", "ar", "as", "az", "ba", "be", "bg", "bn", "bo", "br", "bs",
    "ca", "cs", "cy", "da", "de", "el", "en", "es", "et", "eu", "fa", "fi",
    "fo", "fr", "gl", "gu", "ha", "haw", "he", "hi", "hr", "ht", "hu", "hy",
    "id", "is", "it", "ja", "jw", "ka", "kk", "km", "kn", "ko", "la", "lb",
    "ln", "lo", "lt", "lv", "mg", "mi", "mk", "ml", "mn", "mr", "ms", "mt",
    "my", "ne", "nl", "nn", "no", "oc", "pa", "pl", "ps", "pt", "ro", "ru",
    "sa", "sd", "si", "sk", "sl", "sn", "so", "sq", "sr", "su", "sv", "sw",
    "ta", "te", "tg", "th", "tk", "tl", "tr", "tt", "uk", "ur", "uz", "vi",
    "yi", "yo", "yue", "zh"
  }
end

return M
