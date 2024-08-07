
-- Config
local EXT = "mdmc"
local DIR = "mdmc/"
local URL = "https://raw.githubusercontent.com/SollyBunny/midi2mccc/mdmc/"
local NAME = "midi2mccc"

function speakerFindPeripheral()
	return peripheral.find("speaker")
end

local prompt = {
	colors.blue, "exit", colors.white, ": Exit\n",
	colors.blue, "list", colors.white, ": List downloaded songs\n",
	colors.blue, "repo", colors.white, ": List songs on repo\n",
	colors.blue, "all", colors.white, ": Play all songs (shuffled)\n",
	"<", colors.blue, "song name", colors.white, ", ", colors.blue, "...", colors.white, ">: Play songs\n",
	colors.gray, "At any time hold ctrl+t to exit the program"
}

local intro = {
	colors.blue, "MIDI Player for CC:Tweaked"
}

-- Utils

local function anyKeyToContinue()
	local colorDefault = term.getTextColor()
	term.setTextColor(colors.yellow)
	write("\nPress any key to continue...")
	term.setTextColor(colorDefault)
	os.pullEvent("key")
	print()
end

local function trim(s)
    -- Remove leading spaces
    local startIndex = s:find("%S")
    if not startIndex then return "" end
    -- Remove trailing spaces
    local endIndex = s:find("%S%s*$")
    if not endIndex then return s:sub(startIndex) end
	-- Substring
    return s:sub(startIndex, endIndex)
end

local function printColor(...)
	local args = { ... }
	local colorDefault = term.getTextColor()
	for i = 1, #args do
		local arg = args[i]
		if type(arg) == "string" then
			write(arg)
		elseif type(arg) == "boolean" then
			term.setTextColor(colorDefault)
			if arg then write("\n") end
			return
		elseif type(arg) == "number" then
			term.setTextColor(arg)
		end
	end
	term.setTextColor(colorDefault)
	write("\n")
end

local function printError(msg)
	printColor(colors.red, "Error: ", colors.white, msg)
	anyKeyToContinue()
end

local function shuffleTable(t)
	math.randomseed(os.time())
    local rand = math.random
    local n = #t
    for i = n, 2, -1 do
        local j = rand(i)
        t[i], t[j] = t[j], t[i]
    end
	return t
end

function httpGet(url)
	local request = http.get(url, nil, true)
	if request == nil then return nil end
	local data = request.readAll()
	request.close()
	return data
end

function fsWrite(file, data)
	local file = fs.open(file, "wb")
	local out = file.write(data)
	file.close()
	return out
end

-- Player

local volume = 1.0
local speaker, speakerConnected
local function speakerFind()
	speakerConnected = false
	speaker = speakerFindPeripheral()
	if speaker == nil then
		speaker = "Cannot find speaker!"
		return
	end
	if speaker.playNote == nil then
		speaker = "Speaker does not support playNote"
		return
	end
	speakerConnected = true
end
speakerFind()

local function progressBar(filename, time, total, paused)
	local __, y = term.getCursorPos()
	term.setCursorPos(1, y - 2)
	local colorDefault = term.getTextColor()
	if paused or speakerConnected == false then
		printColor(colors.orange, "Paused:  ", colors.white, filename)
	else
		printColor(colors.blue, "Playing: ", colors.white, filename)
	end
	local percentage = time / total
	local widthTotal, _ = term.getSize()
	if speakerConnected == false then
		term.clearLine()
		printColor(colors.red, speaker)
	else
		local widthBar = math.floor(widthTotal * percentage)
		local widthRemaining = widthTotal - widthBar
		term.setTextColor(colors.green)
		write(string.rep(string.char(0x7F), widthBar))
		term.setTextColor(colors.red)
		print(string.rep(string.char(0x7F), widthRemaining))
		term.setTextColor(colors.white)
	end
	printColor(
		colors.green, string.format("%02d:%02d", math.floor(time / 60), time % 60),
		colors.gray, " / ",
		colors.red, string.format("%02d:%02d", math.floor(total / 60), total % 60),
		colors.white, string.format(" %2d%%", math.floor(percentage * 100)),
		false
	)
	term.setCursorPos(widthTotal - 5, y)
	write(string.char(0x0E))
	if volume < 0.5 then
		term.setTextColor(colors.red)
	elseif volume > 2.5 then
		term.setTextColor(colors.purple)
	elseif volume > 1.5 then
		term.setTextColor(colors.green)
	else
		term.setTextColor(colors.yellow)
	end
	write(string.format(" %3d%%", math.floor(volume * 100)))
	term.setTextColor(colorDefault)
end
local function progressBarRemove()
	local __, y = term.getCursorPos()
	term.setCursorPos(1, y - 2)
	term.clearLine()
	print()
	term.clearLine()
	print()
	term.clearLine()
	term.setCursorPos(1, y - 2)
end

local instruments = { "nothing", "harp", "basedrum", "snare", "hat", "bass", "flute", "bell", "guitar", "chime", "xylophone", "iron_xylophone", "cow_bell", "didgeridoo", "pling" }
local function playMdmc(filename)
	local file = fs.open(filename, "rb")
	if file == nil then
		printError(filename .. " couldn't be opened")
		return
	end
	if (
		file.read() ~= string.byte("M") or
		file.read() ~= string.byte("D") or
		file.read() ~= string.byte("M") or
		file.read() ~= string.byte("C")
	) then
		printError(filename .. " is not a valid .mdmc file")
		file.close()
		return
	end
	write("\n\n") -- for progress bar
	local duration = (
		file.read() * 256 * 256 * 256 +
		file.read() * 256 * 256 +
		file.read() * 256 +
		file.read()
	)
	duration = math.ceil(duration / 1000)
	local time = 0
	local timeSinceUpdate = 9999
	local paused = false
	local pendingDelta = 0
	while true do
		local instrument = file.read()
		if instrument == 0 then break end
		local delta = file.read() * 256 + file.read()
		local note = file.read()
		if delta < 5 then
			pendingDelta = pendingDelta + delta
		else
			local endTime = os.clock() + (delta + pendingDelta) / 1000
			pendingDelta = 0
			while true do
				os.queueEvent("dummy")
				while true do
					local event, key, held = os.pullEvent()
					if event == "dummy" then break end
					if event == "peripheral_detach" or event == "peripheral" then
						speakerFind()
					elseif event == "key" then
						if held then
							if key == keys.up then
								if volume < 3 then
									volume = volume + 0.1
									progressBar(filename, math.floor(time / 1000), duration, paused)
								end
							elseif key == keys.down then
								if volume > 0.1 then
									volume = volume - 0.1
									progressBar(filename, math.floor(time / 1000), duration, paused)
								end
							end
						else
							if key == keys.space or key == keys.enter then
								paused = not paused
								progressBar(filename, math.floor(time / 1000), duration, paused)
							elseif key == keys.backspace then
								file.close()
								progressBarRemove()
								printColor(colors.orange, "Skipped: ", colors.white, filename)
								return
							end
						end
					end
				end
				if paused == false and os.clock() >= endTime then break end
			end
		end
		if speakerConnected == false then
			progressBar(filename, math.floor(time / 1000), duration, paused)
			while speakerConnected == false do
				os.pullEvent("peripheral")
				speakerFind()
			end
			progressBar(filename, math.floor(time / 1000), duration, paused)
		end
		if instrument > 1 then
			speaker.playNote(instruments[instrument], volume, note)
		end
		time = time + delta
		if timeSinceUpdate >= 1000 then
			timeSinceUpdate = 0
			progressBar(filename, math.floor(time / 1000), duration, false)
		else
			timeSinceUpdate = timeSinceUpdate + delta
		end
	end
	progressBarRemove()
	printColor(colors.green, "Finished: ", colors.white, filename)
	file.close()
end

-- Main

local function mainPlaySong(name)
	if name == nil then return end
	if string.find(name, "%.") == nil then
		name = name .. "." .. EXT
	end
	local filename = DIR .. name
	local url = URL .. string.gsub(name, " ", "%%20")
	if fs.exists(filename) == false then
		local data = httpGet(url)
		if data == nil then
			printError("Download failed at " .. url)
			return
		end
		printColor(colors.blue, "Downloaded: ", colors.white, url)
		if fs.exists(DIR) == false then fs.makeDir(DIR) end
		fsWrite(filename, data)
	end
	playMdmc(filename)
end

local function mainPlayAll()
	local pattern = "%." .. EXT .. "$"
	local all = {}
	for _, file in ipairs(fs.list(DIR)) do
		if file:match(pattern) then
			table.insert(all, file)
		end
	end
	shuffleTable(all)
	for _, file in ipairs(all) do
		mainPlaySong(file)
	end
end

local function mainPlay(names)
	for name in string.gmatch(names, "([^,;]+)") do
		mainPlaySong(trim(name))
	end
end

local function mainList()
	local pattern = "%." .. EXT .. "$"
	printColor(colors.blue, "Downloaded songs:")
	local songs = false
	if fs.exists(DIR) then
		for _, file in ipairs(fs.list(DIR)) do
			if file:match(pattern) then
				songs = true
				printColor(colors.blue, "* ", colors.white, file:gsub(pattern, ""))
			end
		end
	end
	if songs == false then
		printColor(colors.orange, "No songs downloaded")
	end
	printColor(colors.gray, "Downloaded songs can be found in " .. DIR)
	anyKeyToContinue()
end

local function mainRepo()
	local data = httpGet(URL .. "liststatic")
	if data == nil then
		printError("Downloading repo failed")
		return
	end
	local pattern = "%." .. EXT .. "$"
	local undownloaded = {}
	printColor(colors.blue, "Songs in repo:")
	local songs = false
	if fs.exists(DIR) then
		for name in string.gmatch(data, "([^;]+)") do
			songs = true
			local nameClean = name:gsub(pattern, "")
			if fs.exists(DIR .. name) then
				printColor(colors.blue, "* ", colors.white, nameClean, colors.green, " (downloaded)")
			else
				table.insert(undownloaded, nameClean)
			end
		end
		for _, name in ipairs(undownloaded) do
			printColor(colors.blue, "* ", colors.white, name)
		end
	else
		for name in string.gmatch(data, "([^;]+)") do
			songs = true
			local nameClean = name:gsub(pattern, "")
			printColor(colors.blue, "* ", colors.white, nameClean)
		end
	end
	if songs == false then
		printColor(colors.orange, "No songs in repo")
	end
	printColor(colors.gray, "The repo is at " .. URL)
	anyKeyToContinue()
end

local function mainCmd(msg)
	local msgl = string.lower(msg)
	if msgl == "list" or msgl == "ls" then
		mainList()
	elseif msgl == "repo" then
		mainRepo()
	elseif msgl == "all" or msgl == "playall" then
		mainPlayAll()
	else
		mainPlay(msg)
	end
end

local mainCmdList = {
	"list", "ls",
	"repo",
	"all", "playall",
	"exit"
}
function mainAutocomplete(msg)
	if #msg < 1 then return {} end
	local msgl = string.lower(msg)
	local matches = {}
	for _, cmd in ipairs(mainCmdList) do
        local startIndex, endIndex = string.find(cmd, msgl)
        if startIndex == 1 then
            local continuation = string.sub(cmd, endIndex + 1)
            table.insert(matches, continuation)
        end
    end
	return matches
end

function main()
	print()
	printColor(unpack(intro))
	local history = {}
	while true do
		print()
		printColor(unpack(prompt))
		if speakerConnected == false then
			printColor(colors.red, speaker)
		end
		print()
		local _, pos = term.getCursorPos()
		local msg
		print()
		while true do
			term.setCursorPos(1, pos - 1)
			term.clearLine()
			term.setTextColor(colors.yellow)
			write(NAME .. "> ")
			term.setTextColor(colors.white)
			msg = read(nil, history, mainAutocomplete)
			if msg ~= nil and #msg > 0 then break end
		end
		print()
		if string.lower(msg) == "exit" then return end
		table.insert(history)
		mainCmd(msg)
	end
end

main()
