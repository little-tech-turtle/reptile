
# Neovim LSP setup

This was really annoying to setup. I found this [guide](https://blog.akring.com/posts/make-swiftui--great-again-on-neovim/) which gave me a good chunk of the puzzle pieces

I had to make a slight tweak in Step 2 of the guide. The setup shown in step 2 looks like this:

```
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        sourcekit = {
          cmd = { "xcrun", "sourcekit-lsp" },
          filetypes = { "swift", "objective-c", "objective-cpp" },
          root_dir = require("lspconfig.util").root_pattern("Package.swift", ".git"),
        },
      },
    },
  },
}
```

But it seems that you don't need to specify which commands to run as neovim takes care of that. So my config looks like this:

```
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        sourcekit = {},
      },
    },
  },
}
```

Additionally, since it's unavoidable that you'll have to use xcode I setup xcode with the following settings:

1. Go to `File -> Project Settings`

2. Here I set `Derived data` to `Project Relative Location`

3. `Show Shared Schemes` set it to `true`/`ticked`

4. `Compilation caching`  set that to `Disabled`
