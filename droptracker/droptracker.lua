_addon.name = 'DropTracker'
_addon.author = 'Cuponoodle'
_addon.version = '1.9'
_addon.commands = {'dt', 'droptracker'}

local texts = require('texts')
local res = require('resources')
local packets = require('packets')

-- UI Setup: Simple and scannable
local display_box = texts.new({
    pos = {x = 400, y = 300},
    text = {font = 'Consolas', size = 10, alpha = 255},
    bg = {alpha = 200, red = 0, green = 0, blue = 0},
    flags = {draggable = true}
})

local session_drops = {} 
local tracked_indices = {}

function update_display()
    local info = " \\cs(0,255,255)-- Session Drops --\\cr \n"
    info = info .. " Item Name          | Qty \n"
    info = info .. " --------------------------\n"
    
    local sorted_names = {}
    for name in pairs(session_drops) do table.insert(sorted_names, name) end
    table.sort(sorted_names)

    if #sorted_names == 0 then
        info = info .. " Waiting for drops...\n"
    else
        for _, name in ipairs(sorted_names) do
            info = info .. string.format(" %-18s | %-3d\n", name:sub(1,18), session_drops[name])
        end
    end
    
    info = info .. " --------------------------\n"
    display_box:text(info)
    display_box:show()
end

-- TRACK TREASURE POOL DROPS
windower.register_event('incoming chunk', function(id, data)
    if id == 0x0D2 then 
        local p = packets.parse('incoming', data)
        local item_id = p['Item']
        local slot_index = p['Index']
        
        -- Filter out Gil (65535) and empty packets (0)
        if item_id == 65535 or item_id == 0 then return end
        
        local item_res = res.items[item_id]
        if item_res then
            -- Verify if slot is new or changed to prevent double counting
            if not tracked_indices[slot_index] or tracked_indices[slot_index] ~= item_id then
                tracked_indices[slot_index] = item_id
                
                local name = item_res.name
                session_drops[name] = (session_drops[name] or 0) + 1
                update_display()
            end
        end
    end
    
    -- Clear slot tracking when an item is lotted, passed, or times out
    if id == 0x0D3 then
        local p = packets.parse('incoming', data)
        tracked_indices[p['Index']] = nil
    end
end)

-- Commands
windower.register_event('addon command', function(command)
    if command == 'reset' then 
        session_drops = {} 
        tracked_indices = {}
        update_display() 
        print("DropTracker: Session Reset.")
    end
end)

update_display()