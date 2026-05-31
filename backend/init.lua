local PLUGIN_NAME = "kzt_rub_converter"
local STORE_REGEX = "^https://store\\.steampowered\\.com/.*"
local RELATIVE_JS_PATH = "plugins/kzt_rub_converter/converter.js"
local RELATIVE_CSS_PATH = "plugins/kzt_rub_converter/converter.css"

local millennium = nil
local logger = nil
local plugin_log_path = nil
local js_module_id = nil
local css_module_id = nil
local FALLBACK_RUB_PER_KZT = 1 / 6
local RATE_TIMEOUT_SECONDS = 1
local RATE_PROVIDERS = {
    {
        name = "cbr-xml-daily.ru",
        url = "https://www.cbr-xml-daily.ru/latest.js",
        pick = function(body)
            local kzt_per_rub = tonumber(body:match('"KZT"%s*:%s*([0-9.]+)'))
            if kzt_per_rub and kzt_per_rub > 0 then
                return 1 / kzt_per_rub
            end
            return nil
        end
    },
    {
        name = "ratata.money",
        url = "https://ratata.money/api/v1/rates/latest?base=KZT&symbols=RUB",
        pick = function(body)
            return tonumber(body:match('"RUB"%s*:%s*([0-9.]+)'))
        end
    },
    {
        name = "api.frankfurter.dev",
        url = "https://api.frankfurter.dev/v2/rate/KZT/RUB",
        pick = function(body)
            return tonumber(body:match('"rate"%s*:%s*([0-9.]+)'))
        end
    },
    {
        name = "open.er-api.com",
        url = "https://open.er-api.com/v6/latest/KZT",
        pick = function(body)
            return tonumber(body:match('"RUB"%s*:%s*([0-9.]+)'))
        end
    }
}

local function normalize_path(path)
    local normalized = tostring(path or "")

    normalized = normalized:gsub("/", "\\")
    normalized = normalized:gsub("\\+", "\\")

    if normalized:match("^%a:\\$") then
        return normalized
    end

    normalized = normalized:gsub("\\$", "")
    return normalized
end

local function path_join(...)
    local parts = { ... }
    local result = ""
    local i

    for i = 1, #parts do
        local part = tostring(parts[i] or "")
        if part ~= "" then
            part = normalize_path(part)

            if result == "" then
                result = part
            else
                result = result:gsub("\\$", "")
                part = part:gsub("^\\+", "")
                result = result .. "\\" .. part
            end
        end
    end

    return normalize_path(result)
end

local function get_current_plugin_dir()
    local info = debug.getinfo(1, "S")
    local source = info and info.source or ""

    if source:sub(1, 1) == "@" then
        source = source:sub(2)
    end

    source = normalize_path(source)
    source = source:gsub("\\[^\\]+$", "")

    return source:gsub("\\backend$", "")
end

local function append_file_log(level, message)
    if not plugin_log_path then
        return
    end

    local handle = io.open(plugin_log_path, "ab")
    if not handle then
        return
    end

    handle:write("[" .. os.date("%Y-%m-%d %H:%M:%S") .. "] [" .. level .. "] " .. tostring(message) .. "\n")
    handle:close()
end

local function log_to_millennium(level, message)
    if not logger then
        return
    end

    if level == "ERROR" and logger.error then
        pcall(function()
            logger:error(message)
        end)
    elseif level == "WARN" and logger.warn then
        pcall(function()
            logger:warn(message)
        end)
    elseif logger.info then
        pcall(function()
            logger:info(message)
        end)
    end
end

local function log_message(level, message)
    local formatted = "[" .. PLUGIN_NAME .. "] " .. tostring(message)

    append_file_log(level, formatted)
    log_to_millennium(level, formatted)
end

local function log_info(message)
    log_message("INFO", message)
end

local function log_warn(message)
    log_message("WARN", message)
end

local function log_error(message)
    log_message("ERROR", message)
end

local function fail(message)
    log_error(message)
    error(message, 2)
end

local function command_succeeded(result)
    if result == true or result == 0 then
        return true
    end

    if type(result) == "number" and result == 0 then
        return true
    end

    return false
end

local function can_write_to_directory(path)
    local normalized = normalize_path(path)
    local probe_path = path_join(normalized, ".kzt_rub_converter_write_test.tmp")
    local handle = io.open(probe_path, "wb")

    if not handle then
        return false
    end

    handle:write("ok")
    handle:close()
    os.remove(probe_path)

    return true
end

local function file_exists(path)
    local handle = io.open(normalize_path(path), "rb")
    if handle then
        handle:close()
        return true
    end
    return false
end

local function directory_exists(path)
    local normalized = normalize_path(path)
    local command = 'if exist "' .. normalized .. '\\NUL" (exit /b 0) else (exit /b 1)'

    return command_succeeded(os.execute(command))
end

local function read_file(path)
    local normalized = normalize_path(path)
    local handle, open_err = io.open(normalized, "rb")
    if not handle then
        return nil, "failed to open file for reading: " .. normalized .. " (" .. tostring(open_err) .. ")"
    end

    local content = handle:read("*a")
    local close_ok, close_err = handle:close()
    if close_ok == false then
        return nil, "failed to close file after reading: " .. normalized .. " (" .. tostring(close_err) .. ")"
    end

    if content == nil then
        return nil, "failed to read file: " .. normalized
    end

    return content
end

local function write_file(path, content)
    local normalized = normalize_path(path)
    local handle, open_err = io.open(normalized, "wb")
    if not handle then
        return nil, "failed to open file for writing: " .. normalized .. " (" .. tostring(open_err) .. ")"
    end

    local ok, write_err = handle:write(content)
    local close_ok, close_err = handle:close()

    if ok == nil then
        return nil, "failed to write file: " .. normalized .. " (" .. tostring(write_err) .. ")"
    end

    if close_ok == false then
        return nil, "failed to close file after writing: " .. normalized .. " (" .. tostring(close_err) .. ")"
    end

    return true
end

local function ensure_directory(path)
    local normalized = normalize_path(path)

    if normalized == "" then
        return nil, "directory path is empty"
    end

    if directory_exists(normalized) or can_write_to_directory(normalized) then
        return true
    end

    local command = 'mkdir "' .. normalized .. '" >nul 2>nul'
    if command_succeeded(os.execute(command)) then
        return true
    end

    if directory_exists(normalized) or can_write_to_directory(normalized) then
        return true
    end

    log_warn("could not verify directory after mkdir, continuing so file write can report the real error: " .. normalized)
    return true
end

local function copy_file(source, destination)
    local content, read_err = read_file(source)
    if not content then
        return nil, read_err
    end

    local destination_dir = normalize_path(destination):gsub("\\[^\\]+$", "")
    local ok, ensure_err = ensure_directory(destination_dir)
    if not ok then
        return nil, ensure_err
    end

    local write_ok, write_err = write_file(destination, content)
    if not write_ok then
        return nil, write_err
    end

    return true
end

local function escape_js_string(value)
    return tostring(value or ""):gsub("\\", "\\\\"):gsub('"', '\\"')
end

local function fetch_url_content(url, destination_path, timeout_seconds)
    local command = 'curl.exe -L --silent --show-error --max-time ' .. tostring(timeout_seconds)
        .. ' -o "' .. normalize_path(destination_path) .. '" "' .. tostring(url) .. '"'

    if not command_succeeded(os.execute(command)) then
        return nil, "request failed"
    end

    local content, read_err = read_file(destination_path)
    os.remove(destination_path)

    if not content then
        return nil, read_err
    end

    return content
end

local function resolve_exchange_rate()
    local plugin_dir = get_current_plugin_dir()
    local temp_path = path_join(plugin_dir, "kzt_rub_rate.tmp")
    local i

    for i = 1, #RATE_PROVIDERS do
        local provider = RATE_PROVIDERS[i]
        local body
        local fetch_err
        local rate

        log_info("Requesting data from " .. provider.name .. "...")
        body, fetch_err = fetch_url_content(provider.url, temp_path, RATE_TIMEOUT_SECONDS)
        if body then
            rate = provider.pick(body)
            if rate and rate > 0 then
                log_info("[COMPLETE] " .. provider.name .. ": " .. tostring(rate))
                return rate, provider.name
            end
            log_warn("[FAILED] " .. provider.name .. ": bad response")
        else
            log_warn("[FAILED] " .. provider.name .. ": " .. tostring(fetch_err))
        end
    end

    log_info("Requesting data from Offline converter...")
    log_info("[COMPLETE] Offline converter: " .. tostring(FALLBACK_RUB_PER_KZT))
    return FALLBACK_RUB_PER_KZT, "Offline converter"
end

local function build_converter_js(source_path, destination_path, rate, source_name)
    local content, read_err = read_file(source_path)
    local destination_dir
    local ok
    local ensure_err
    local write_ok
    local write_err

    if not content then
        return nil, read_err
    end

    content = content:gsub("__KZT_RUB_RATE__", string.format("%.12f", rate), 1)
    content = content:gsub("__KZT_RUB_SOURCE__", escape_js_string(source_name), 1)

    destination_dir = normalize_path(destination_path):gsub("\\[^\\]+$", "")
    ok, ensure_err = ensure_directory(destination_dir)
    if not ok then
        return nil, ensure_err
    end

    write_ok, write_err = write_file(destination_path, content)
    if not write_ok then
        return nil, write_err
    end

    return true
end

local function load_runtime_modules()
    local ok, result

    ok, result = pcall(require, "logger")
    if ok then
        logger = result
        log_info("Millennium logger module loaded")
    else
        append_file_log("WARN", "[" .. PLUGIN_NAME .. "] failed to load Millennium logger module: " .. tostring(result))
    end

    ok, result = pcall(require, "millennium")
    if ok then
        millennium = result
        log_info("Millennium API module loaded")
    else
        fail("failed to load Millennium API module: " .. tostring(result))
    end
end

local function get_steam_path()
    local ok, result = pcall(function()
        return millennium.steam_path()
    end)

    if not ok then
        fail("millennium.steam_path() failed: " .. tostring(result))
    end

    if not result or tostring(result) == "" then
        fail("millennium.steam_path() returned an empty path")
    end

    return normalize_path(result)
end

local function prepare_browser_assets()
    local plugin_dir = get_current_plugin_dir()
    local steam_path = get_steam_path()
    local steamui_dir = path_join(steam_path, "steamui")
    local target_dir = path_join(steamui_dir, "plugins", PLUGIN_NAME)
    local source_js = path_join(plugin_dir, "webkit", "converter.js")
    local source_css = path_join(plugin_dir, "webkit", "converter.css")
    local target_js = path_join(target_dir, "converter.js")
    local target_css = path_join(target_dir, "converter.css")
    local ok, err
    local rate, rate_source

    log_info("backend loading")
    log_info("plugin path: " .. plugin_dir)
    log_info("steam path: " .. steam_path)
    log_info("steamui path: " .. steamui_dir)
    log_info("source JS: " .. source_js)
    log_info("source CSS: " .. source_css)
    log_info("destination JS: " .. target_js)
    log_info("destination CSS: " .. target_css)

    if not file_exists(source_js) then
        fail("source JS does not exist: " .. source_js)
    end

    if not file_exists(source_css) then
        fail("source CSS does not exist: " .. source_css)
    end

    ok, err = ensure_directory(target_dir)
    if not ok then
        fail("failed to prepare destination directory: " .. tostring(err))
    end
    log_info("destination directory is ready")

    rate, rate_source = resolve_exchange_rate()
    log_info("Selected exchange rate source: " .. tostring(rate_source))

    ok, err = build_converter_js(source_js, target_js, rate, rate_source)
    if not ok then
        fail("failed to copy JS: " .. tostring(err))
    end
    log_info("copied JS successfully")

    ok, err = copy_file(source_css, target_css)
    if not ok then
        fail("failed to copy CSS: " .. tostring(err))
    end
    log_info("copied CSS successfully")
end

local function register_browser_modules()
    css_module_id = millennium.add_browser_css(RELATIVE_CSS_PATH, STORE_REGEX)
    if not css_module_id or css_module_id == 0 then
        fail("failed to register browser CSS module: " .. RELATIVE_CSS_PATH)
    end
    log_info("browser CSS registered successfully, module id: " .. tostring(css_module_id) .. ", regex: " .. STORE_REGEX)

    js_module_id = millennium.add_browser_js(RELATIVE_JS_PATH, STORE_REGEX)
    if not js_module_id or js_module_id == 0 then
        if css_module_id and css_module_id ~= 0 then
            millennium.remove_browser_module(css_module_id)
            css_module_id = nil
            log_warn("removed CSS module after JS registration failure")
        end
        fail("failed to register browser JS module: " .. RELATIVE_JS_PATH)
    end
    log_info("browser JS registered successfully, module id: " .. tostring(js_module_id) .. ", regex: " .. STORE_REGEX)
end

local function log_convertation_providers()
    log_info("Convertation providers:")
    log_info("- cbr-xml-daily.ru")
    log_info("- ratata.money")
    log_info("- api.frankfurter.dev")
    log_info("- open.er-api.com")
    log_info("- Offline converter")
end

local function on_load_impl()
    plugin_log_path = path_join(get_current_plugin_dir(), "kzt_rub_converter.log")
    append_file_log("INFO", "[" .. PLUGIN_NAME .. "] file logger initialized: " .. plugin_log_path)

    load_runtime_modules()
    log_convertation_providers()
    prepare_browser_assets()
    register_browser_modules()

    log_info("calling millennium.ready()")
    millennium.ready()
end

local function on_unload_impl()
    if css_module_id and css_module_id ~= 0 and millennium then
        millennium.remove_browser_module(css_module_id)
        css_module_id = nil
        log_info("browser CSS module removed")
    end

    if js_module_id and js_module_id ~= 0 and millennium then
        millennium.remove_browser_module(js_module_id)
        js_module_id = nil
        log_info("browser JS module removed")
    end
end

local function on_load()
    local ok, err = xpcall(on_load_impl, debug.traceback)
    if not ok then
        log_error("on_load failed:\n" .. tostring(err))

        if millennium and millennium.ready then
            pcall(function()
                millennium.ready()
            end)
            log_warn("called millennium.ready() after on_load failure to keep plugin logs visible")
        end
    end
end

local function on_unload()
    local ok, err = xpcall(on_unload_impl, debug.traceback)
    if not ok then
        log_error("on_unload failed:\n" .. tostring(err))
    end
end

return {
    on_load = on_load,
    on_unload = on_unload
}
