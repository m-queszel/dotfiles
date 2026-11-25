return {
    "neovim/nvim-lspconfig",
    dependencies = {
        "hrsh7th/cmp-nvim-lsp",
        { "antosha417/nvim-lsp-file-operations", config = true },
    },
    config = function()
        local keymap = vim.keymap
        local opts = { noremap = true, silent = true }
        local cmp_nvim_lsp = require("cmp_nvim_lsp")
        local on_attach = function(client, bufnr)
            opts.buffer = bufnr
            opts.desc = "See available code action"
            keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, opts)

            opts.desc = "Go to definition"
            keymap.set("n", "gd", vim.lsp.buf.definition, opts)

            opts.desc = "Go to definition (alias for gf)"
            keymap.set("n", "gf", vim.lsp.buf.definition, opts)

            opts.desc = "Show references"
            keymap.set("n", "gr", vim.lsp.buf.references, opts)

            opts.desc = "Show documentation for what is under cursor"
            keymap.set("n", "K", vim.lsp.buf.hover, opts)
        end

        local capabilities = cmp_nvim_lsp.default_capabilities()

        vim.lsp.config("prettier", {
            capabilities = capabilities,
            on_attach = on_attach,
        })
        vim.lsp.config("emmet_ls", {
            capabilities = capabilities,
            on_attach = on_attach,
        })
        vim.lsp.config("intelephense", {
            capabilities = capabilities,
            on_attach = on_attach,
        })
        vim.lsp.config("vue_ls", {
            capabilities = capabilities,
            on_attach = on_attach,
        })
        vim.lsp.config("ts_ls", {
            capabilities = capabilities,
            on_attach = on_attach,
            init_options = {
                plugins = {
                    {
                        name = "@vue/typescript-plugin",
                        location = vim.fn.stdpath("data")
                            .. "/mason/packages/vue-language-server/node_modules/@vue/language-server",
                        languages = { "vue" },
                    },
                },
            },
            filetypes = { "typescript", "javascript", "javascriptreact", "typescriptreact", "vue" },
        })
        vim.lsp.config("lua_ls", {
            settings = { -- custom settings for lua
                Lua = {
                    workspace = {
                        -- make language server aware of runtime files
                        library = {
                            [vim.fn.expand("$VIMRUNTIME/lua")] = true,
                            [vim.fn.stdpath("config") .. "/lua"] = true,
                        },
                    },
                },
            },
        })
    end,
}
