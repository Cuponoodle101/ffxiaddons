-- invexport.lua
-- Export all items from all containers to CSV
-- - Clickable FFXIAH link / BGWiki link columns.
-- Output path: addons/invexport/data/<CharacterName>/<filename>

_addon.name     = 'invexport'
_addon.version  = '2.3'
_addon.author   = 'Cuponoodle'
_addon.commands = {'invexport'}

require('tables')
files   = require('files')
res     = require('resources')
extdata = require('extdata')

-- Containers to scan; add/remove as you like.
local containers = {
    'inventory', 'safe', 'safe2',
    'storage', 'locker',
    'satchel', 'sack', 'case',
    'wardrobe', 'wardrobe2', 'wardrobe3', 'wardrobe4',
    'wardrobe5', 'wardrobe6', 'wardrobe7', 'wardrobe8',
}

----------------------------------------------------------------
-- Helpers for URLs and CSV
----------------------------------------------------------------

local function ffxiah_url(item_id)
    if not item_id or item_id == 0 then
        return ''
    end
    return string.format('https://www.ffxiah.com/item/%d', item_id)
end

local function bgwiki_url(name)
    if not name or name == '' then
        return ''
    end
    local page = name:gsub(' ', '_')
    return string.format('https://www.bg-wiki.com/ffxi/%s', page)
end

local function csv_escape(s)
    if s == nil then
        return ''
    end
    s = tostring(s)
    if s:find('[,"\n]') then
        s = '"' .. s:gsub('"', '""') .. '"'
    end
    return s
end

local function hyperlink_formula(url, label)
    if not url or url == '' then
        return ''
    end
    label = label or url
    local f = string.format('=HYPERLINK("%s","%s")', url, label)
    return f
end

----------------------------------------------------------------
-- Category / slot / job helpers
----------------------------------------------------------------

local function get_slot_name(item_res)
    if not item_res or not item_res.slots then
        return ''
    end
    for slot_id, enabled in pairs(item_res.slots) do
        if enabled and res.slots[slot_id] then
            return res.slots[slot_id].english
        end
    end
    return ''
end

-- Single Category column with heuristics for non-equippables.
local function get_category(item_res)
    if not item_res then
        return ''
    end

    local name = (item_res.en or ''):lower()

    -- 1) Armor / Weapon via equip/skill
    if item_res.slots and next(item_res.slots) ~= nil then
        local skill_name = ''
        if item_res.skill and res.skills and res.skills[item_res.skill] then
            skill_name = res.skills[item_res.skill].english
        end
        if skill_name ~= '' then
            return 'Weapon'
        end
        return 'Armor'
    end

    -- 2) Try item_categories if present (may be limited on some setups).
    if item_res.category and res.item_categories and res.item_categories[item_res.category] then
        local cat = res.item_categories[item_res.category].english
        if cat and cat ~= '' then
            return cat
        end
    end

    -- 3) Heuristics for common non-equippable categories.

    -- Ammo.
    if name:find('arrow') or name:find('bolt') or name:find('bullet')
        or name:find('quiver') or name:find('pouch') then
        return 'Ammo'
    end

    -- Food.
    if name:find('sushi') or name:find('stew') or name:find('steak')
        or name:find('pizza') or name:find('sandwich') or name:find('bun')
        or name:find('cookies') or name:find('cake') or name:find('roast')
        or name:find('kabob') or name:find('kebab') or name:find('soup')
        or name:find('salad') or name:find('drink') or name:find('juice')
        or name:find('tea') or name:find('coffee') then
        return 'Food'
    end

    -- Furnishings.
    if name:find('table') or name:find('chair') or name:find('desk')
        or name:find('bed') or name:find('stool') or name:find('bench')
        or name:find('plant') or name:find('flower') or name:find('tree')
        or name:find('lamp') or name:find('candle') or name:find('bookshelf')
        or name:find('shelf') or name:find('dresser') or name:find('chest')
        or name:find('cabinet') or name:find('plaque') or name:find('partition')
        or name:find('hanger') or name:find('screen') or name:find('pot ') then
        return 'Furnishing'
    end

    -- Pet items.
    if name:find('broth') or name:find('biscuit') or name:find('sauce')
        or name:find('pet food') then
        return 'Pet Item'
    end

    -- Crystals / clusters.
    if name:find(' crystal') or name:find(' cluster') then
        return 'Crystal'
    end

    -- Scrolls.
    if name:find('scroll of') then
        return 'Spell Scroll'
    end

    -- Medicines.
    if name:find('potion') or name:find('ether') or name:find('elixir')
        or name:find('remedy') then
        return 'Medicine'
    end

    return 'Misc'
end

local function get_jobs(item_res)
    if not item_res or not item_res.jobs then
        return ''
    end
    local job_names = {}
    for job_id, enabled in pairs(item_res.jobs) do
        if enabled and res.jobs and res.jobs[job_id] then
            table.insert(job_names, res.jobs[job_id].english_short)
        end
    end
    table.sort(job_names)
    return table.concat(job_names, '/')
end

local function get_levels(item_res)
    if not item_res then
        return '', ''
    end
    local level = item_res.level or ''
    local ilvl  = item_res.item_level or ''
    return level, ilvl
end

----------------------------------------------------------------
-- Augment helper
----------------------------------------------------------------

local function get_augments(entry)
    if not entry or not entry.extdata then
        return ''
    end
    local ok, decoded = pcall(extdata.decode, entry)
    if not ok or not decoded then
        return ''
    end

    local aug_list = decoded.augments or decoded.augments_raw or decoded.augments_list
    if type(aug_list) ~= 'table' then
        return ''
    end

    local texts = {}
    for _, aug in ipairs(aug_list) do
        if aug and aug ~= '' then
            table.insert(texts, aug)
        end
    end
    if #texts == 0 then
        return ''
    end
    return table.concat(texts, ' | ')
end

----------------------------------------------------------------
-- Export logic
----------------------------------------------------------------

local function do_export(filename)
    local items_data = windower.ffxi.get_items()
    if not items_data then
        windower.add_to_chat(123, '[invexport] Could not get items.')
        return
    end

    local rows = {}

    local headers = {
        'Character',
        'Container',
        'Slot',
        'ItemID',
        'ItemName',
        'Count',
        'Category',
        'EquipSlot',
        'Jobs',
        'Level',
        'ItemLevel',
        'Current Augment',
        'FFXIAH',
        'BGWiki',
    }
    local header = table.concat(headers, ',')
    table.insert(rows, header)

    local me = windower.ffxi.get_player()
    local charname = me and me.name or 'Unknown'

    for _, bag in ipairs(containers) do
        local bag_data = items_data[bag]
        if bag_data and type(bag_data) == 'table' then
            for slot, entry in pairs(bag_data) do
                if type(entry) == 'table' and entry.id and entry.id > 0 then
                    local item_res = res.items[entry.id]
                    local name = item_res and item_res.en or ('ID_' .. entry.id)

                    local category  = get_category(item_res)
                    local slot_name = get_slot_name(item_res)
                    local jobs      = get_jobs(item_res)
                    local level, ilvl = get_levels(item_res)
                    local augments  = get_augments(entry)

                    local f_url  = ffxiah_url(entry.id)
                    local b_url  = bgwiki_url(name)

                    local f_link = hyperlink_formula(f_url, 'FFXIAH link')
                    local b_link = hyperlink_formula(b_url, 'BGWiki link')

                    local row = table.concat({
                        csv_escape(charname),
                        csv_escape(bag),
                        csv_escape(slot),
                        csv_escape(entry.id),
                        csv_escape(name),
                        csv_escape(entry.count or 1),
                        csv_escape(category),
                        csv_escape(slot_name),
                        csv_escape(jobs),
                        csv_escape(level),
                        csv_escape(ilvl),
                        csv_escape(augments),
                        csv_escape(f_link),
                        csv_escape(b_link),
                    }, ',')

                    table.insert(rows, row)
                end
            end
        end
    end

    local info_row = csv_escape(
        'NOTE: When opening in Excel/Sheets, select all data and use "Format as Table" / "Create a filter" with "My table has headers".'
    )
    table.insert(rows, info_row)

    ----------------------------------------------------------------
    -- Per-character folder under data
    ----------------------------------------------------------------

    -- Base data folder for the addon.
    local base_data_dir = windower.addon_path .. 'data\\'

    -- Character subfolder, e.g. .../addons/invexport/data/Name/
    local char_dir_name = charname or 'Unknown'
    local export_dir = base_data_dir .. char_dir_name .. '\\'

    -- Create base data and character directories (ignore errors if they exist).
    os.execute('mkdir "' .. base_data_dir .. '" >nul 2>nul')
    os.execute('mkdir "' .. export_dir .. '" >nul 2>nul')

    local full_path = export_dir .. filename

    local fh, err = io.open(full_path, 'w')
    if not fh then
        windower.add_to_chat(123,
            '[invexport] Failed to open file for writing: ' .. tostring(err))
        return
    end

    fh:write(table.concat(rows, '\n'))
    fh:close()

    windower.add_to_chat(122,
        string.format('[invexport] Exported %d item rows to %s', #rows - 2, full_path))
end

----------------------------------------------------------------
-- Command handler
----------------------------------------------------------------

windower.register_event('addon command', function(cmd, ...)
    cmd = cmd and cmd:lower() or ''
    local args = {...}

    if cmd == 'export' or cmd == '' then
        local filename = args[1] or 'inventory_export.csv'
        do_export(filename)
    else
        windower.add_to_chat(122,
            '[invexport] Usage: //invexport [export [filename]]')
    end
end)
