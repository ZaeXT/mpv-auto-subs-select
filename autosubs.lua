local utils = require 'mp.utils'

-- Config
local video_exts = {'mkv', 'mp4', 'avi', 'mov', 'flv', 'wmv', 'webm'}
local sub_exts = {'ass', 'srt', 'ssa', 'sub', 'vtt'}

local state = {
    sub_dir = nil,
    offset = nil
}

-- Debu Functin: Configure whether to print the log to the console and osd, only print to the console by default.
local function print_msg(msg)
    print("[AutoSub-Debug] " .. msg)
    -- mp.osd_message(msg, 3)
end

function get_extension(path)
    if not path then return nil end
    return path:match("%.([^%.]+)$")
end

function is_in_list(val, list)
    for _, v in ipairs(list) do
        if val:lower() == v then return true end
    end
    return false
end

function get_sorted_files(dir, exts)
    local files = utils.readdir(dir, "files")
    if not files then 
        print_msg("Failed to read the directory: " .. (dir or "nil"))
        return {} 
    end
    local filtered = {}
    for _, f in ipairs(files) do
        if is_in_list(get_extension(f) or "", exts) then
            table.insert(filtered, f)
        end
    end
    table.sort(filtered)
    return filtered
end

function find_index(file_name, list)
    for i, f in ipairs(list) do
        if f == file_name then return i end
    end
    return nil
end

-- Core: Scan the currently loaded track to find external subtitles
function check_and_update_pairing()
    local vid_path = mp.get_property("path")
    if not vid_path then return end
    
    local vid_dir, vid_name = utils.split_path(vid_path)
    local vid_files = get_sorted_files(vid_dir, video_exts)
    local v_idx = find_index(vid_name, vid_files)
    
    if not v_idx then 
        print_msg("Unable to locate the video position in the folder")
        return 
    end

    local tracks = mp.get_property_native("track-list")
    for _, track in ipairs(tracks) do
        -- Find external subtitles in non-video dirs
        if track.type == "sub" and track.external and track["external-filename"] then
            local s_full_path = track["external-filename"]
            local s_dir, s_name = utils.split_path(s_full_path)
            
            -- Standardized path comparison (to prevent Windows path slash problems)
            if s_dir ~= vid_dir then
                local sub_files = get_sorted_files(s_dir, sub_exts)
                local s_idx = find_index(s_name, sub_files)
                
                if s_idx then
                    state.sub_dir = s_dir
                    state.offset = v_idx - s_idx
                    print_msg(string.format("Link established!\nVideo index: %d\nSubtitle index: %d\noffset: %d", v_idx, s_idx, state.offset))
                    return true
                end
            end
        end
    end
    return false
end

-- Automatic loading logic
function try_auto_load()
    if not state.sub_dir or not state.offset then 
        print_msg("No association has been established. Please manually load the subtitles once.")
        return 
    end

    local vid_path = mp.get_property("path")
    local vid_dir, vid_name = utils.split_path(vid_path)
    local vid_files = get_sorted_files(vid_dir, video_exts)
    local v_idx = find_index(vid_name, vid_files)

    if v_idx then
        local sub_files = get_sorted_files(state.sub_dir, sub_exts)
        local target_s_idx = v_idx - state.offset
        
        print_msg(string.format("Try to match: video index %d -> subtitle index %d", v_idx, target_s_idx))
        
        if sub_files[target_s_idx] then
            local sub_path = utils.join_path(state.sub_dir, sub_files[target_s_idx])
            mp.commandv("sub-add", sub_path, "select")
            print_msg("Loading successfully:" .. sub_files[target_s_idx])
        else
            print_msg("Error: The subtitle file corresponding to the index could not be found.")
        end
    end
end

--Listen to file loading (when changing episodes)
mp.register_event("file-loaded", function()
    print_msg("A new file has been detected to be loaded...")
    -- First, check whether the correct subtitles have been brought (such as the built-in one). If not, try to complete it automatically.
    -- Delay the execution by 0.1 seconds to ensure that mpv has parsed all paths.
    mp.add_timeout(0.1, function()
        if not check_and_update_pairing() then
            try_auto_load()
        end
    end)
end)

-- Monitor track changes (when manually loading subtitles)
mp.observe_property("track-list", "native", function(name, value)
    -- When load the new subtitle, the track-list will change. Try to update the offset.
    check_and_update_pairing()
end)
