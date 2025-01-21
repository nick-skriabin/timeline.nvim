--- Timeline.nvim - Reading time estimator for Markdown files
--- Copyright (c) 2024 Nick Skriabin
--- MIT License

--- A Neovim plugin that adds reading time estimates to Markdown headers.
--- Displays timestamps as virtual text showing when each section will be reached
--- based on average reading speed.

--- Features:
--- - Estimates reading time for each section based on word count
--- - Shows timestamps in HH:mm:ss format
--- - Multiple display formats (full, range, short)
--- - Configurable words per minute (WPM)
--- - Auto-updates on file changes
--- - Skips code blocks in time estimation
--- - Handles Markdown formatting

--- Usage:
--- ```lua
--- -- Basic setup with defaults
--- require('timeline').setup{}

--- -- Custom configuration
--- require('timeline').setup{
---     words_per_minute = 250,  -- Set custom reading speed
---     format = 'full',         -- 'full', 'range', or 'short'
---     enabled = true          -- Enable on startup
--- }
--- ```

--- Commands:
--- - `:TimelineToggle` - Toggle timeline visibility

--- Display formats:
--- - full:  [00:00:00 - 00:01:30 @ 01:30]
--- - range: [00:00:00 - 00:01:30]
--- - short: [00:00:00]

local M = {
	namespace_id = nil,
	enabled = true,
	words_per_minute = 200, -- Default WPM
	format = "full", -- Default format
}

local valid_formats = { short = true, range = true, full = true }

-- Helper function to convert minutes to HH:mm:ss
local function minutes_to_hhmmss(mins)
	local total_seconds = math.floor(mins * 60)
	local hours = math.floor(total_seconds / 3600)
	local remaining = total_seconds % 3600
	local minutes = math.floor(remaining / 60)
	local seconds = remaining % 60
	return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end

-- Helper function to convert minutes to mm:ss
local function minutes_to_mmss(mins)
	local total_seconds = math.floor(mins * 60)
	local minutes = math.floor(total_seconds / 60)
	local seconds = total_seconds % 60
	return string.format("%02d:%02d", minutes, seconds)
end

-- Helper function to format time range with options
local function format_time_range(start_minutes, section_minutes)
	local start_time = minutes_to_hhmmss(start_minutes)
	local end_minutes = start_minutes + section_minutes
	local end_time = minutes_to_hhmmss(end_minutes)
	local duration = minutes_to_mmss(section_minutes)

	if M.format == "short" then
		return string.format("[%s]", start_time)
	elseif M.format == "range" then
		return string.format("[%s - %s]", start_time, end_time)
	else -- "full"
		return string.format("[%s - %s @ %s]", start_time, end_time, duration)
	end
end

-- Helper function to check if content is empty
local function has_content(text_lines)
	if not text_lines or #text_lines == 0 then
		return false
	end

	-- Skip leading and trailing empty lines
	local start_idx = 1
	local end_idx = #text_lines

	-- Find first non-empty line
	while start_idx <= #text_lines do
		if text_lines[start_idx]:match("%S") then
			break
		end
		start_idx = start_idx + 1
	end

	-- Find last non-empty line
	while end_idx > 0 do
		if text_lines[end_idx]:match("%S") then
			break
		end
		end_idx = end_idx - 1
	end

	-- If no non-empty lines were found
	if start_idx > end_idx then
		return false
	end

	return true
end

-- Helper function to estimate reading time
local function estimate_reading_time(text_lines)
	if not text_lines or #text_lines == 0 then
		return 0
	end

	local total_words = 0
	local in_code_block = false

	-- Process each line independently to preserve paragraph structure
	for _, line in ipairs(text_lines) do
		-- Check for code block boundaries
		if line:match("^```") then
			in_code_block = not in_code_block
			goto continue
		end

		-- Skip if we're in a code block
		if in_code_block then
			goto continue
		end

		-- Remove markdown formatting for this line
		local cleaned_line = line
			:gsub("%[.-%]%(.-%)", "") -- Remove links
			:gsub("%*%*(.-)%*%*", "%1") -- Remove bold
			:gsub("%*(.-)%*", "%1") -- Remove italic
			:gsub("`.-`", "") -- Remove inline code
			:gsub("^%s*-%s*", "") -- Remove list markers
			:gsub("^%s*%d+%.%s*", "") -- Remove numbered list markers

		-- Count words in this line if it's not empty
		if cleaned_line:match("%S") then
			for word in cleaned_line:gmatch("%S+") do
				total_words = total_words + 1
			end
		end

		::continue::
	end

	-- Convert to minutes using configured WPM
	return total_words / M.words_per_minute
end

-- Helper function to set virtual text
local function set_timestamp_virtual_text(bufnr, namespace_id, row, timestamp)
	vim.api.nvim_buf_clear_namespace(bufnr, namespace_id, row, row + 1)
	vim.api.nvim_buf_set_extmark(bufnr, namespace_id, row, 0, {
		virt_text = { { timestamp, "Comment" } },
		virt_text_pos = "eol",
		priority = 100,
	})
end

-- Function to clear all timestamps
function M.clear_timestamps(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_clear_namespace(bufnr, M.namespace_id, 0, -1)
end

--- Toggle the visibility of timeline timestamps
--- Enables or disables the plugin and updates the display accordingly.
--- Also shows a notification about the new state.
function M.toggle()
	M.enabled = not M.enabled
	if M.enabled then
		M.parse_file()
	else
		M.clear_timestamps()
	end
	-- Notify user of new state
	local state = M.enabled and "enabled" or "disabled"
	vim.notify("Timeline " .. state, vim.log.levels.INFO)
end

function M.parse_file(bufnr)
	-- Only proceed if enabled
	if not M.enabled then
		return
	end

	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local parser = vim.treesitter.get_parser(bufnr, "markdown")
	local tree = parser:parse()[1]
	local root = tree:root()

	-- Clear all existing virtual text
	vim.api.nvim_buf_clear_namespace(bufnr, M.namespace_id, 0, -1)

	-- Query to match markdown headers
	local query = vim.treesitter.query.parse(
		"markdown",
		[[
        (atx_heading [
            (atx_h1_marker)
            (atx_h2_marker)
            (atx_h3_marker)
            (atx_h4_marker)
            (atx_h5_marker)
            (atx_h6_marker)
        ] heading_content: (_)) @heading
    ]]
	)

	-- Get all headers
	local headers = {}
	for id, node in query:iter_captures(root, bufnr, 0, -1) do
		local start_row, start_col, end_row, end_col = node:range()

		local level = 0
		for child in node:iter_children() do
			local child_type = child:type()
			if child_type:match("atx_h(%d)_marker") then
				level = tonumber(child_type:match("atx_h(%d)_marker"))
				break
			end
		end

		local heading_content = ""
		for child in node:iter_children() do
			if child:type() == "heading_content" then
				heading_content = vim.treesitter.get_node_text(child, bufnr)
				break
			end
		end

		table.insert(headers, {
			level = level,
			title = heading_content:gsub("^%s*(.-)%s*$", "%1"),
			range = {
				start = { row = start_row, col = start_col },
				ending = { row = end_row, col = end_col },
			},
		})
	end

	-- Sort headers by position
	table.sort(headers, function(a, b)
		return a.range.start.row < b.range.start.row
	end)

	local sections = {}
	local cumulative_minutes = 0
	local total_lines = vim.api.nvim_buf_line_count(bufnr)

	-- Process sections
	for i, header in ipairs(headers) do
		-- Skip the title/h1 if it's the first header
		if i == 1 and header.level == 1 then
			goto continue
		end

		-- Get content range for current section
		local content_start = header.range.ending.row
		local content_end

		if headers[i + 1] then
			content_end = headers[i + 1].range.start.row - 1
		else
			content_end = total_lines - 1
		end

		-- Get all lines between headers, including empty lines
		local content_lines = {}
		if content_end >= content_start then
			content_lines = vim.api.nvim_buf_get_lines(bufnr, content_start, content_end + 1, false)

			-- Remove the first line if it's part of the header
			if #content_lines > 0 and content_lines[1]:match("^#+ ") then
				table.remove(content_lines, 1)
			end
		end

		-- Only process sections with actual content
		if has_content(content_lines) then
			local section_reading_minutes = estimate_reading_time(content_lines)

			-- Only display timestamp if we have a valid reading time
			if section_reading_minutes > 0 then
				local time_range = format_time_range(cumulative_minutes, section_reading_minutes)
				set_timestamp_virtual_text(bufnr, M.namespace_id, header.range.start.row, time_range)

				-- Store section information
				table.insert(sections, {
					header = {
						level = header.level,
						title = header.title,
						time_range = time_range,
						location = {
							start = { row = header.range.start.row + 1, col = header.range.start.col },
							ending = { row = header.range.ending.row + 1, col = header.range.ending.col },
						},
					},
					content = {
						reading_time = {
							minutes = section_reading_minutes,
						},
						location = {
							start = { row = content_start + 1, col = 0 },
							ending = { row = content_end + 1, col = -1 },
						},
					},
				})

				-- Update cumulative time for next section
				cumulative_minutes = cumulative_minutes + section_reading_minutes
			end
		end

		::continue::
	end

	return sections
end

function M.setup(opts)
	opts = opts or {}
	M.words_per_minute = opts.words_per_minute or 200
	M.enabled = opts.enabled ~= false -- Enable by default unless explicitly disabled

	-- Validate and set format option
	if opts.format then
		if valid_formats[opts.format] then
			M.format = opts.format
		else
			vim.notify("Invalid timeline format. Using default 'full'.", vim.log.levels.WARN)
		end
	end

	-- Create namespace for virtual text
	M.namespace_id = vim.api.nvim_create_namespace("markdown_reading_time")

	-- Create autocommand group
	local group = vim.api.nvim_create_augroup("MarkdownReadingTime", { clear = true })

	-- Create a debounced version of the update function
	local pending_update = false
	local function update_timestamps()
		if pending_update then
			return
		end
		pending_update = true

		vim.schedule(function()
			if vim.bo.filetype == "markdown" then
				M.parse_file()
			end
			pending_update = false
		end)
	end

	-- Set up autocommands including BufRead
	vim.api.nvim_create_autocmd({
		"InsertLeave",
		"TextChanged",
		"TextChangedI",
		"TextChangedP",
		"BufRead",
	}, {
		group = group,
		pattern = "*.md",
		callback = update_timestamps,
		desc = "Update markdown reading time timestamps",
	})

	-- Create user command for toggling
	vim.api.nvim_create_user_command("TimelineToggle", function()
		M.toggle()
	end, {
		desc = "Toggle markdown reading time timestamps",
	})
end

--- Force update of all timestamps in the current buffer
--- Recalculates reading times and refreshes virtual text for all headers
function M.update()
	M.parse_file()
end

--- Set the reading speed in words per minute (WPM)
--- @param wpm number|nil The reading speed in WPM (default: 200)
function M.set_wpm(wpm)
	M.words_per_minute = wpm or 200
end

--- Set the display format for timestamps
--- @param format string The format to use: 'full' ([00:00:00 - 00:01:30 @ 01:30]),
---                                        'range' ([00:00:00 - 00:01:30]),
---                                        or 'short' ([00:00:00])
function M.set_format(format)
	if valid_formats[opts.format] then
		M.format = format
		M.update()
	else
		vim.notify("Invalid timeline format. Using default 'full'.", vim.log.levels.WARN)
	end
end

return M
