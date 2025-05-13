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
  if opts.language then table.insert(params, "language=" .. opts.language) end
  if opts.initial_prompt then table.insert(params, "initial_prompt=" .. vim.fn.shellescape(opts.initial_prompt)) end
  if opts.output then table.insert(params, "output=" .. opts.output) end

  -- Append parameters to endpoint if any
  if #params > 0 then
    local query_string = table.concat(params, "&")
    table.insert(cmd, endpoint .. "?" .. query_string)
    -- Remove the original endpoint which we've now replaced
    table.remove(cmd, 4)
  end

  -- Add the file
  table.insert(cmd, "-F")
  table.insert(cmd, "audio_file=@" .. vim.fn.shellescape(file_path))

  return cmd
end

function M.transcribe(file_path, opts)
  opts = opts or {}
  opts = vim.tbl.tbl_deep_extend("force", config, opts)

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

  return output
end

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

  -- Setup buffers for stdout and stderr
  local stdout_data = {}
  local stdout_err = {}

  -- Execute curl command
  local job_id = vim.fn.jobstart(cmd, {
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
          callback(nil, "API request failed: " .. error_msg)
        end
      else
        local response = table.concat(stdout_data, "\n")
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

-- Check if the API is available by sending a small request
function M.check_availability(callback)
  local cmd = { "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", config.endpoint }

  if callback then
    -- Async version
    vim.fn.jobstart(cmd, {
      on_stdout = function(_, data)
        local status_code = tonumber(data[1])
        callback(status_code >= 200 and status_code < 300)
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

return M
