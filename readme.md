# Timeline.nvim

A Neovim plugin that adds reading time estimates to Markdown headers. It displays timestamps as virtual text showing when each section will be reached based on average reading speed.

![Timeline.nvim Demo](./demo.gif)

## Features

- 📊 Estimates reading time for each section based on word count
- ⏱️ Shows timestamps in HH:mm:ss format
- 🎨 Multiple display formats (full, range, short)
- ⚡ Configurable words per minute (WPM)
- 🔄 Auto-updates on file changes
- 📝 Skips code blocks in time estimation
- ✨ Handles Markdown formatting

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):
```lua
{
    "nick-skriabin/timeline.nvim",
    config = function()
        require("timeline").setup({})
    end,
}
```

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):
```lua
use {
    'nick-skriabin/timeline.nvim',
    config = function()
        require('timeline').setup({})
    end
}
```

## Configuration

Timeline.nvim comes with the following defaults:

```lua
require('timeline').setup({
    words_per_minute = 200,    -- Average reading speed
    format = 'full',           -- 'full', 'range', or 'short'
    enabled = true,            -- Enable on startup
})
```

### Display Formats

The plugin supports three display formats:

- `full`: `[00:00:00 - 00:01:30 @ 01:30]` (start - end @ duration)
- `range`: `[00:00:00 - 00:01:30]` (start - end)
- `short`: `[00:00:00]` (start time only)

## Usage

The plugin automatically activates for Markdown files. You can control it with:

### Commands

- `:TimelineToggle` - Toggle timeline visibility

### API

```lua
-- Toggle timeline visibility
require('timeline').toggle()

-- Update timeline calculations
require('timeline').update()

-- Change display format
require('timeline').set_format('short')

-- Change reading speed
require('timeline').set_wpm(250)
```

## Example

```markdown
# Introduction [00:00:00 - 00:01:30 @ 01:30]
Content...

## First Section [00:01:30 - 00:03:45 @ 02:15]
More content...

## Second Section [00:03:45 - 00:05:00 @ 01:15]
Final content...
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - Copyright (c) 2024 Nick Skriabin

## Acknowledgments

Thanks to all contributors and the Neovim community!

