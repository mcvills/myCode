# Neovim configured with nixvim (lazy.nvim compatible plugin management)
# This mirrors a modern lazy.nvim setup but fully declarative
{pkgs, ...}: {
  programs.nixvim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;

    # ── Catppuccin colorscheme ────────────────────────────────────────────────
    colorschemes.catppuccin = {
      enable = true;
      settings = {
        flavour = "mocha";
        transparent_background = true;
        integrations = {
          cmp = true;
          gitsigns = true;
          treesitter = true;
          telescope.enabled = true;
          which_key = true;
          mini.enabled = true;
          noice = true;
          notify = true;
        };
      };
    };

    # ── Global options ────────────────────────────────────────────────────────
    opts = {
      number = true;
      relativenumber = true;
      shiftwidth = 2;
      tabstop = 2;
      expandtab = true;
      smartindent = true;
      wrap = false;
      ignorecase = true;
      smartcase = true;
      cursorline = true;
      termguicolors = true;
      scrolloff = 8;
      sidescrolloff = 8;
      signcolumn = "yes";
      updatetime = 100;
      undofile = true;
      splitright = true;
      splitbelow = true;
    };

    # ── Keymaps ───────────────────────────────────────────────────────────────
    globals.mapleader = " ";
    keymaps = [
      # Navigation
      { key = "<C-h>"; action = "<C-w>h"; }
      { key = "<C-l>"; action = "<C-w>l"; }
      { key = "<C-j>"; action = "<C-w>j"; }
      { key = "<C-k>"; action = "<C-w>k"; }
      # Buffer
      { key = "<S-h>"; action = ":bprevious<CR>"; }
      { key = "<S-l>"; action = ":bnext<CR>"; }
      { key = "<leader>bd"; action = ":bdelete<CR>"; }
      # Files
      { key = "<leader>ff"; action = "<cmd>Telescope find_files<CR>"; }
      { key = "<leader>fg"; action = "<cmd>Telescope live_grep<CR>"; }
      { key = "<leader>fb"; action = "<cmd>Telescope buffers<CR>"; }
      { key = "<leader>fh"; action = "<cmd>Telescope help_tags<CR>"; }
      # Tree
      { key = "<leader>e"; action = "<cmd>Neotree toggle<CR>"; }
      # LSP
      { key = "gd"; action = "<cmd>lua vim.lsp.buf.definition()<CR>"; }
      { key = "gr"; action = "<cmd>Telescope lsp_references<CR>"; }
      { key = "K";  action = "<cmd>lua vim.lsp.buf.hover()<CR>"; }
      { key = "<leader>ca"; action = "<cmd>lua vim.lsp.buf.code_action()<CR>"; }
      { key = "<leader>rn"; action = "<cmd>lua vim.lsp.buf.rename()<CR>"; }
      { key = "<leader>lf"; action = "<cmd>lua vim.lsp.buf.format()<CR>"; }
      # Diagnostics
      { key = "[d"; action = "<cmd>lua vim.diagnostic.goto_prev()<CR>"; }
      { key = "]d"; action = "<cmd>lua vim.diagnostic.goto_next()<CR>"; }
      { key = "<leader>d"; action = "<cmd>lua vim.diagnostic.open_float()<CR>"; }
      # Git
      { key = "<leader>gs"; action = "<cmd>Telescope git_status<CR>"; }
      { key = "<leader>gc"; action = "<cmd>Telescope git_commits<CR>"; }
    ];

    # ── Plugins ───────────────────────────────────────────────────────────────
    plugins = {
      # Treesitter
      treesitter = {
        enable = true;
        settings = {
          highlight.enable = true;
          indent.enable = true;
          incremental_selection.enable = true;
        };
      };
      treesitter-context.enable = true;
      treesitter-textobjects.enable = true;

      # LSP
      lsp = {
        enable = true;
        servers = {
          nixd.enable = true;       # Nix
          lua_ls.enable = true;     # Lua
          rust_analyzer = {
            enable = true;
            installRustc = false;
            installCargo = false;
          };
          pyright.enable = true;    # Python
          ts_ls.enable = true;      # TypeScript / JS
          gopls.enable = true;      # Go
          bashls.enable = true;     # Bash
          cssls.enable = true;
          html.enable = true;
          jsonls.enable = true;
          yamlls.enable = true;
        };
      };

      # Autocompletion
      cmp = {
        enable = true;
        settings = {
          sources = [
            {name = "nvim_lsp";}
            {name = "luasnip";}
            {name = "path";}
            {name = "buffer";}
          ];
          mapping = {
            "<C-Space>" = "cmp.mapping.complete()";
            "<C-e>" = "cmp.mapping.abort()";
            "<CR>" = "cmp.mapping.confirm({ select = true })";
            "<Tab>" = "cmp.mapping(cmp.mapping.select_next_item(), {'i', 's'})";
            "<S-Tab>" = "cmp.mapping(cmp.mapping.select_prev_item(), {'i', 's'})";
          };
        };
      };
      luasnip.enable = true;
      cmp_luasnip.enable = true;
      friendly-snippets.enable = true;

      # Telescope
      telescope = {
        enable = true;
        extensions.fzf-native.enable = true;
        extensions.ui-select.enable = true;
      };

      # File tree
      neo-tree = {
        enable = true;
        window.width = 30;
        filesystem.filteredItems = {
          visible = true;
          hideGitignored = false;
        };
      };

      # Git
      gitsigns = {
        enable = true;
        settings.current_line_blame = true;
      };
      lazygit.enable = true;

      # UI enhancements
      lualine = {
        enable = true;
        settings.options.theme = "catppuccin";
      };
      bufferline = {
        enable = true;
        settings.options.diagnostics = "nvim_lsp";
      };
      noice.enable = true;
      notify.enable = true;
      which-key.enable = true;
      indent-blankline.enable = true;
      rainbow-delimiters.enable = true;

      # Editing helpers
      mini = {
        enable = true;
        modules = {
          pairs = {};
          surround = {};
          comment = {};
          ai = {};
        };
      };
      todo-comments.enable = true;
      trouble.enable = true;

      # Formatting
      conform-nvim = {
        enable = true;
        settings = {
          format_on_save = {
            timeout_ms = 500;
            lsp_fallback = true;
          };
          formatters_by_ft = {
            nix = ["alejandra"];
            python = ["black" "isort"];
            javascript = ["prettier"];
            typescript = ["prettier"];
            json = ["prettier"];
            yaml = ["prettier"];
            markdown = ["prettier"];
            lua = ["stylua"];
            rust = ["rustfmt"];
            go = ["gofmt"];
            sh = ["shfmt"];
          };
        };
      };

      # Dashboard
      dashboard = {
        enable = true;
        settings.config = {
          header = [
            "                                                     "
            "  ███╗   ██╗███████╗ ██████╗ ██╗   ██╗██╗███╗   ███╗"
            "  ████╗  ██║██╔════╝██╔═══██╗██║   ██║██║████╗ ████║"
            "  ██╔██╗ ██║█████╗  ██║   ██║██║   ██║██║██╔████╔██║"
            "  ██║╚██╗██║██╔══╝  ██║   ██║╚██╗ ██╔╝██║██║╚██╔╝██║"
            "  ██║ ╚████║███████╗╚██████╔╝ ╚████╔╝ ██║██║ ╚═╝ ██║"
            "  ╚═╝  ╚═══╝╚══════╝ ╚═════╝   ╚═══╝  ╚═╝╚═╝     ╚═╝"
            "                                                     "
          ];
          shortcut = [
            {action = "Telescope find_files"; desc = " Find File"; icon = "󰱼 "; key = "f";}
            {action = "ene | startinsert"; desc = " New File"; icon = " "; key = "n";}
            {action = "Telescope live_grep"; desc = " Find Word"; icon = "󰊄 "; key = "g";}
            {action = "e /etc/nixos/flake.nix"; desc = " NixOS Config"; icon = "󱄅 "; key = "c";}
            {action = "qa"; desc = " Quit"; icon = "󰅚 "; key = "q";}
          ];
        };
      };

      # Terminal
      toggleterm = {
        enable = true;
        settings = {
          direction = "float";
          float_opts.border = "curved";
        };
      };

      # Markdown preview
      markdown-preview.enable = true;

      # Copilot (optional — enable if you have a GitHub Copilot subscription)
      # copilot-lua.enable = true;
    };

    # ── Extra packages available to nvim ──────────────────────────────────────
    extraPackages = with pkgs; [
      # Formatters
      alejandra nodePackages.prettier black isort stylua shfmt rustfmt
      # LSP servers (extras)
      nodePackages.typescript-language-server
    ];
  };
}
