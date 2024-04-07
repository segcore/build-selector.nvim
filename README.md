# Build Selector for Neovim

Utility to intelligently calculate likely `makeprg` targets to easily select a
build target. This allows follow-up use of `:make` commands to compile the
programs.

## Overview

Detects files such as `Makefile` and `CMakeLists.txt` and builds up options
that you may want to use as `makeprg`.

### Makefile

Detects `Makefile` and `makefile`, and adds options `make -f <FILE>`

### CMake

Detects `CMakeLists.txt` and then searches for `build*/CMakeCache.txt` and adds
`cmake --build <PATH> --parallel` for each of them.

### Devcontainers

Detects `.devcontainer.json`, `.devcontainer/devcontainer.json`,
`.devcontainer/*/devcontainer/json` (depth one) to find devcontainers.

Each devcontainer duplicates previous entries with
`docker exec <NAME> <COMMAND>` where `NAME` is the devcontainer name, and
`COMMAND` is one of the earlier detected makeprg options. For example,

```
docker exec MyContainerName cmake --build build-gcc-debug --parallel
```

## Setup

Lazy:

```lua
{
    "segcore/build-selector.nvim",
    dependencies = {
        "nvim-lua/plenary.nvim", -- Optional; to simplify file paths
    },
    opts = {},
}
```

## Usage

```
:BuildSelector
```

Pops up the default ui-select menu with selections, e.g.

```
1. make -f Makefile
2. cmake --build build-gcc-debug --parallel
3. cmake --build build-gcc-release --parallel
4. cmake --build build-rpi-release --parallel
```
