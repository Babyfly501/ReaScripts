-- Batch Region Rename Tool for Reaper
-- Requires REAPER 6.82+ with ImGui support

local script_title = "Region Name Editor"
local window_flags = reaper.ImGui_WindowFlags_TopMost()

-- Data structures
local state = {
  filter_text = "",
  selected_regions = {},
  remove_start = "",
  remove_end = "",
  find_text = "",
  replace_text = "",
  prefix_text = "",
  suffix_text = "",
  all_regions = {},
  visible_regions = {},
  open = true
}

-- Initialize ImGui context
local ctx = reaper.ImGui_CreateContext(script_title)
if not ctx then
  reaper.ShowConsoleMsg("ImGui context creation failed!\n")
  return
end

-- Get all regions from the project
local function RefreshRegions()
  state.all_regions = {}
  
  local marker_count = reaper.CountProjectMarkers(0)
  
  for i = 1, marker_count do
    local retval, isrgn, pos, rgnend, name, markidx, color = reaper.EnumProjectMarkers3(0, i - 1)
    
    -- Check if it's a region (isrgn == true means it's a region, false means it's a marker)
    if isrgn then
      table.insert(state.all_regions, {
        index = i,
        rgnidx = i - 1,
        id = markidx,
        name = tostring(name),
        start = pos,
        endpos = rgnend,
        color = color or 0
      })
    end
  end
  
  -- Update visible regions based on filter
  UpdateVisibleRegions()
  
  -- Initialize selection state
  for _, region in ipairs(state.all_regions) do
    if state.selected_regions[region.index] == nil then
      state.selected_regions[region.index] = true
    end
  end
end

-- Update visible regions based on filter text
function UpdateVisibleRegions()
  state.visible_regions = {}
  local filter_lower = string.lower(state.filter_text)
  
  for _, region in ipairs(state.all_regions) do
    if filter_lower == "" or string.find(string.lower(region.name), filter_lower, 1, true) then
      table.insert(state.visible_regions, region)
    end
  end
end

-- Apply transformations to a name
local function TransformName(name)
  local new_name = name
  
  local r_start = tonumber(state.remove_start) or 0
  local r_end = tonumber(state.remove_end) or 0
  
  -- 1. Remove from start
  if r_start > 0 then
    if r_start < string.len(new_name) then
      new_name = string.sub(new_name, r_start + 1)
    else
      new_name = ""
    end
  end
  
  -- 2. Remove from end
  if r_end > 0 then
    if r_end < string.len(new_name) then
      new_name = string.sub(new_name, 1, string.len(new_name) - r_end)
    else
      new_name = ""
    end
  end
  
  -- 3. Find / Replace (Literal)
  if state.find_text ~= "" then
    -- Escape Lua pattern magic characters to make it a literal search
    local pattern = string.gsub(state.find_text, "([%(%)%.%%%+%-%*%?%[%^%$%]])", "%%%1")
    -- Escape % in replace text to prevent capture group errors
    local repl = string.gsub(state.replace_text, "%%", "%%%%")
    new_name = string.gsub(new_name, pattern, repl)
  end
  
  -- 4. Prefix / Suffix
  if state.prefix_text ~= "" then
    new_name = state.prefix_text .. new_name
  end
  
  if state.suffix_text ~= "" then
    new_name = new_name .. state.suffix_text
  end
  
  return new_name
end

-- Draw the main window
local function DrawWindow()
  local changed = false
  
  local visible, open = reaper.ImGui_Begin(ctx, script_title, state.open, window_flags)
  state.open = open
  
  if visible then
    local avail_width = reaper.ImGui_GetContentRegionAvail(ctx)
    
    -- Title and description
    reaper.ImGui_TextWrapped(ctx, "Choose which regions to affect. If none are checked, ALL regions will be affected.")
    reaper.ImGui_Spacing(ctx)
  
  -- Filter section
  reaper.ImGui_Text(ctx, "Filter (by name):")
  changed, state.filter_text = reaper.ImGui_InputText(ctx, "##filter", state.filter_text)
  if changed then
    UpdateVisibleRegions()
  end
  reaper.ImGui_Spacing(ctx)
  
  -- Regions section
  reaper.ImGui_Text(ctx, "Regions (with Preview)")
  reaper.ImGui_Separator(ctx)
  
  if reaper.ImGui_BeginChild(ctx, "regions_list", avail_width, 200) then
    -- Check if any region is selected
    local any_checked = false
    for _, r in ipairs(state.all_regions) do
      if state.selected_regions[r.index] then
        any_checked = true
        break
      end
    end

    for _, region in ipairs(state.visible_regions) do
      local checked = state.selected_regions[region.index] or false
      local will_affect = checked or not any_checked
      
      local display_text = region.index .. " | " .. region.name
      if will_affect then
        local new_name = TransformName(region.name)
        if new_name ~= region.name then
          display_text = display_text .. " -> " .. new_name
        end
      end
      
      changed, state.selected_regions[region.index] = reaper.ImGui_Checkbox(
        ctx,
        display_text .. "##region_" .. region.index,
        checked
      )
    end
    reaper.ImGui_EndChild(ctx)
  end
  
  reaper.ImGui_Spacing(ctx)
  
  -- Selection buttons
  if reaper.ImGui_Button(ctx, "Select All") then
    for _, region in ipairs(state.all_regions) do
      state.selected_regions[region.index] = true
    end
  end
  reaper.ImGui_SameLine(ctx)
  
  if reaper.ImGui_Button(ctx, "Clear Selection") then
    for _, region in ipairs(state.all_regions) do
      state.selected_regions[region.index] = false
    end
  end
  reaper.ImGui_SameLine(ctx)
  
  if reaper.ImGui_Button(ctx, "Refresh") then
    RefreshRegions()
  end
  
  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)
  
  -- Transformations section
  reaper.ImGui_Text(ctx, "Transformations")
  reaper.ImGui_Spacing(ctx)
  
  reaper.ImGui_Text(ctx, "Remove characters (from start / from end):")
  
  local item_w = 40 -- Width for both input boxes and buttons
  local input_flags = reaper.ImGui_InputTextFlags_CharsDecimal()
  
  -- === Left Group (remove from start) ===
  reaper.ImGui_PushID(ctx, "start_group")
  reaper.ImGui_SetNextItemWidth(ctx, item_w)
  changed, state.remove_start = reaper.ImGui_InputText(ctx, "##input", tostring(state.remove_start), input_flags)
  reaper.ImGui_SameLine(ctx, 0, 4)
  if reaper.ImGui_Button(ctx, "-", item_w, 0) then
    local val = tonumber(state.remove_start) or 0
    if val > 0 then state.remove_start = tostring(val - 1) end
  end
  reaper.ImGui_SameLine(ctx, 0, 4)
  if reaper.ImGui_Button(ctx, "+", item_w, 0) then
    local val = tonumber(state.remove_start) or 0
    state.remove_start = tostring(val + 1)
  end
  reaper.ImGui_PopID(ctx)
  
  -- Add some spacing between the two groups
  reaper.ImGui_SameLine(ctx, 0, 20)
  
  -- === Right Group (remove from end) ===
  reaper.ImGui_PushID(ctx, "end_group")
  reaper.ImGui_SetNextItemWidth(ctx, item_w)
  changed, state.remove_end = reaper.ImGui_InputText(ctx, "##input", tostring(state.remove_end), input_flags)
  reaper.ImGui_SameLine(ctx, 0, 4)
  if reaper.ImGui_Button(ctx, "-", item_w, 0) then
    local val = tonumber(state.remove_end) or 0
    if val > 0 then state.remove_end = tostring(val - 1) end
  end
  reaper.ImGui_SameLine(ctx, 0, 4)
  if reaper.ImGui_Button(ctx, "+", item_w, 0) then
    local val = tonumber(state.remove_end) or 0
    state.remove_end = tostring(val + 1)
  end
  reaper.ImGui_PopID(ctx)
  
  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)
  
  -- Find / Replace section
  reaper.ImGui_Text(ctx, "Find / Replace")
  reaper.ImGui_Spacing(ctx)
  
  reaper.ImGui_Text(ctx, "Find (literal):")
  changed, state.find_text = reaper.ImGui_InputText(ctx, "##find", state.find_text)
  
  reaper.ImGui_Text(ctx, "Replace with (leave empty to remove):")
  changed, state.replace_text = reaper.ImGui_InputText(ctx, "##replace", state.replace_text)
  
  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)
  
  -- Prefix / Suffix section
  reaper.ImGui_Text(ctx, "Prefix / Suffix")
  reaper.ImGui_Spacing(ctx)
  
  reaper.ImGui_Text(ctx, "Prefix:")
  changed, state.prefix_text = reaper.ImGui_InputText(ctx, "##prefix", state.prefix_text)
  
  reaper.ImGui_Text(ctx, "Suffix:")
  changed, state.suffix_text = reaper.ImGui_InputText(ctx, "##suffix", state.suffix_text)
  
  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Spacing(ctx)
  
  -- Apply Button
  if reaper.ImGui_Button(ctx, "Apply Changes", avail_width, 30) then
    reaper.Undo_BeginBlock()
    local changed_count = 0
    
    local any_checked = false
    for _, r in ipairs(state.all_regions) do
      if state.selected_regions[r.index] then
        any_checked = true
        break
      end
    end
    
    for _, region in ipairs(state.all_regions) do
      if state.selected_regions[region.index] or not any_checked then
        local new_name = TransformName(region.name)
        if new_name ~= region.name then
          if new_name == "" then
            -- Reaper API treats "" as "do not change name" in SetProjectMarker
            -- So to actually clear the name, we must delete and recreate the region
            reaper.DeleteProjectMarker(0, region.id, true)
            reaper.AddProjectMarker2(0, true, region.start, region.endpos, "", region.id, region.color)
          else
            -- Use region.id (actual marker ID) rather than sequential index
            reaper.SetProjectMarker3(0, region.id, true, region.start, region.endpos, new_name, region.color)
          end
          changed_count = changed_count + 1
        end
      end
    end
    
    reaper.Undo_EndBlock("Batch Rename Regions", -1)
    
    if changed_count > 0 then
      RefreshRegions()
    end
    
    -- Reset all transformation input fields to default state
    state.remove_start = ""
    state.remove_end = ""
    state.find_text = ""
    state.replace_text = ""
    state.prefix_text = ""
    state.suffix_text = ""
  end
  
  reaper.ImGui_End(ctx)
  end -- end if visible
end

-- Initialize
RefreshRegions()

-- Main loop using deferred execution
local function MainLoop()
  DrawWindow()
  
  if state.open then
    reaper.defer(MainLoop)
  end
end

reaper.defer(MainLoop)
