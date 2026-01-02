_addon.name = 'Missed'
_addon.author = 'Gemini'
_addon.version = '1.5'
_addon.commands = {'missed', 'wym'}

local texts = require('texts')
local files = require('files')

-- Explicitly define visual settings to ensure it's not invisible
local display_settings = {
    pos = {x = 400, y = 400},
    bg = {alpha = 200, red = 0, green = 0, blue = 0},
    text = {size = 12, font = 'Consolas', alpha = 255, red = 255, green = 255, blue = 255},
    padding = 10,
    visible = true,
    flags = {draggable = true}
}

local missed_box = texts.new(display_settings)
local messages = {}

local blacklist_modes = {
    [104]=true, [105]=true, [106]=true, [107]=true, [108]=true, [109]=true, 
    [110]=true, [111]=true, [112]=true, [113]=true, [114]=true, [115]=true, 
    [116]=true, [117]=true, [118]=true, [119]=true, [120]=true, [121]=true, 
    [122]=true, [123]=true
}

local function update_display()
    local content = ""
    if #messages == 0 then
        content = "What You Missed: \n(Waiting for chat...)"
    else
        local display_table = {}
        local start_index = math.max(1, #messages - 14)
        for i = start_index, #messages do
            table.insert(display_table, messages[i])
        end
        content = "What You Missed:\n" .. table.concat(display_table, '\n')
    end
    
    missed_box:text(content)
    missed_box:show() -- Force visibility update
end

windower.register_event('incoming text', function(new, old, mode)
    if not blacklist_modes[mode] then
        -- This print will show in your main chat console to confirm it captured something
        -- print("Missed captured mode " .. mode .. ": " .. new:sub(1, 20))
        
        local timestamp = os.date("[%H:%M]")
        local clean_text = new:gsub('\7%d%d%d', ''):gsub('\127', ''):gsub('%s+', ' '):trim()
        
        if clean_text ~= "" then
            table.insert(messages, timestamp .. " " .. clean_text)
            update_display()
        end
    end
end)

windower.register_event('addon command', function(input, ...)
    local cmd = input and input:lower() or nil
    if cmd == 'clear' or cmd == 'reset' then
        messages = {}
        update_display()
    elseif cmd == 'pos' then
        local args = {...}
        if args[1] and args[2] then
            missed_box:pos(tonumber(args[1]), tonumber(args[2]))
        end
    end
end)

-- Initialize visibility on load
update_display()
missed_box:show()