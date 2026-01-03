local M = {}

local get_urls = ya.sync(function()
    local urls = {}

    if cx.active and cx.active.selected and #cx.active.selected > 0 then
	for _, it in pairs(cx.active.selected) do
	    local u = it.url or it
	    urls[#urls + 1] = tostring(u)
	end
	return urls
    end

    if cx.yanked and #cx.yanked > 0 then
	for _, u in pairs(cx.yanked) do
	    urls[#urls + 1] = tostring(u)
	end
	return urls
    end

    local h = cx.active and cx.active.current and cx.active.current.hovered
    if h and h.url then
	urls[#urls + 1] = tostring(h.url)
    end

    return urls
end)

local function url_to_path(s)
    local url = Url(s)
    local path = tostring(url)
    if path:match("^[%w%+%.%-]+://") then
	path = tostring(url.path)
    end
    return path
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function basename(path)
    -- alles nach dem letzten /
    local name = path:gsub("^.*/", "")
    return name
end

local function strip_ext(name)
    return (name:gsub("%.[^.]+$", ""))
end

local function clean_separators(name)
    -- . _ - zu spaces, mehrere spaces zusammenfassen
    name = name:gsub("[._%-]+", " ")
    name = name:gsub("%s+", " ")
    return trim(name)
end

local function pad2(n)
    n = tonumber(n) or 0
    if n < 10 then return "0" .. tostring(n) end
    return tostring(n)
end

local function auto_title_from_filename(path)
    local name = strip_ext(basename(path))

    -- Erst Separatoren normalisieren für besseres Matching
    local raw = name
    local norm = clean_separators(name)

    -- Versuche SxxEyy zu finden (robust gegen Punkte/Spaces)
    -- Wir matchen auf dem "raw" UND auf "norm"
    local function find_se(rawstr)
	-- s01e02, S1E2, S01.E02, S01 E02, etc.
	local s, e = rawstr:match("[sS]%s*(%d+)%s*[%.%s%-%_]*[eE]%s*(%d+)")
	if s and e then return s, e end
	return nil, nil
    end

    local s, e = find_se(raw)
    if not s then s, e = find_se(norm) end

    if s and e then
	local tag = "S" .. pad2(s) .. "E" .. pad2(e)

	-- Entferne den gefundenen S/E-Teil aus dem normierten Namen, um Dopplung zu vermeiden
	-- (wir entfernen grob das Muster und räumen auf)
	local rest = norm
	rest = rest:gsub("[sS]%s*%d+%s*[eE]%s*%d+", " ")
	rest = clean_separators(rest)

	-- Wenn rest leer ist, nur Tag
	if rest == "" then
	    return tag
	end
	return tag .. " " .. rest
    end

    -- Kein S/E gefunden: einfach cleaned name
    return norm
end

function M:entry()
    local urls = get_urls()
    if not urls or #urls == 0 then
	ya.notify({ title = "mkv-meta", content = "Keine Datei ausgewählt/gehoved.", timeout = 3 })
	return
    end

    local input, event = ya.input({
	title = "MKV Titel setzen (leer = auto aus Dateiname, '-' = löschen)",
	pos = { "center", w = 72 },
    })
    if event ~= 1 then
	return
    end

    input = trim(input or "")

    local ok_n, fail_n, skip_n = 0, 0, 0
    local first_err = nil

    for _, s in ipairs(urls) do
	local path = url_to_path(s)

	if not path:lower():match("%.mkv$") then
	    skip_n = skip_n + 1
	else
	    local title
	    local do_delete = false

	    if input == "-" then
		do_delete = true
	    elseif input == "" then
		title = auto_title_from_filename(path)
	    else
		title = input
	    end

	    local cmd = Command("mkvpropedit")
		:arg(path)
		:arg("--edit")
		:arg("info")

	    if do_delete then
		cmd = cmd:arg("--delete"):arg("title")
	    else
		cmd = cmd:arg("--set"):arg("title=" .. title)
	    end

	    local out, err = cmd:output()
	    if err then
		fail_n = fail_n + 1
		first_err = first_err or ("Start fehlgeschlagen: " .. tostring(err))
	    else
		local code = out and out.status and out.status.code or -1
		if code ~= 0 then
		    fail_n = fail_n + 1
		    local msg = (out.stderr and out.stderr ~= "") and out.stderr or ("Exit=" .. tostring(code))
		    first_err = first_err or msg
		else
		    ok_n = ok_n + 1
		end
	    end
	end
    end

    if fail_n == 0 then
	ya.notify({
	    title = "mkv-meta",
	    content = ("Fertig: %d OK%s"):format(ok_n, skip_n > 0 and (", " .. skip_n .. " übersprungen") or ""),
	    timeout = 3,
	})
    else
	ya.notify({
	    title = "mkv-meta",
	    content = ("Fertig: %d OK, %d Fehler%s\nErster Fehler:\n%s")
		:format(ok_n, fail_n, skip_n > 0 and (", " .. skip_n .. " übersprungen") or "", tostring(first_err)),
	    timeout = 10,
	    level = "error",
	})
    end
end

return M
