-- return {
--     "thesimonho/kanagawa-paper.nvim",
--     lazy = false,
--     priority = 1000,
--     config = function()
--         require("kanagawa-paper").setup({
--             transparent = true,
--         })
--         vim.cmd("colorscheme kanagawa-paper") -- set the colorscheme
--     end,
-- }
return {
    "lbartoletti/lituus.nvim",
    lazy = false,
    priority = 1000,
    config = function()
        require("lituus").setup({
            -- Recommended - see "Configuring" below for more config options
            transparent = true,
            italic_comments = true,
            hide_fillchars = true,
            borderless_telescope = true,
        })
        vim.cmd("colorscheme lituus") -- set the colorscheme
    end,
}
