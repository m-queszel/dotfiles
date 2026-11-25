return {
    "thesimonho/kanagawa-paper.nvim",
    lazy = false,
    priority = 1000,
    config = function()
        require("kanagawa-paper").setup({
            transparent = true,
        })
        vim.cmd("colorscheme kanagawa-paper") -- set the colorscheme
    end,
}
-- return {
--     "lbartoletti/lituus.nvim",
--     lazy = false,
--     priority = 1000,
--     config = function()
--         require("lituus").setup({
--             -- Recommended - see "Configuring" below for more config options
--             transparent = true,
--             italic_comments = true,
--             hide_fillchars = true,
--             borderless_telescope = true,
--         })
--         vim.cmd("colorscheme lituus") -- set the colorscheme
--     end,
-- }
-- return {
--     {
--         "sainnhe/everforest",
--         lazy = false,
--         priority = 1000,
--         config = function()
--             -- Optionally configure and load the colorscheme
--             -- directly inside the plugin declaration.
--             vim.g.everforest_enable_italic = true
--             vim.cmd.colorscheme("everforest")
--         end,
--     },
-- }
--
-- return {
--     {
--         "ficcdaf/ashen.nvim",
--         lazy = false,
--         priority = 1000,
--         config = function()
--             require("ashen").setup({
--                 transparent = true,
--                 borderless_telescope = true,
--             })
--             vim.cmd("colorscheme ashen")
--         end,
--     },
-- }
-- return {
--     "AlexvZyl/nordic.nvim",
--     lazy = false,
--     priority = 1000,
--     config = function()
--         require("nordic").setup({
--             transparent = {
--                 -- Enable transparent background.
--                 bg = false,
--                 -- Enable transparent background for floating windows.
--                 float = false,
--             },
--         })
--         vim.cmd("colorscheme nordic")
--     end,
-- }
