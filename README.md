# haskell-ide-engine
[![License BSD3][badge-license]][license]

[badge-license]: https://img.shields.io/badge/license-BSD3-green.svg?dummy
[license]: https://github.com/haskell/haskell-ide-engine/blob/master/LICENSE


This project aims to be __the universal interface__ to __a growing number of Haskell tools__, providing a __full-featured and easy to query backend__ for editors and IDEs that require Haskell-specific functionality.

We are currently focusing on using the Language Server Protocol as the interface via which we talk to clients.

## Features:

 - Diagnostics via hlint and GHC warnings/errors
 - Code actions and quick fixes via apply-refact
 - Type information and documentation(via hoogle) on hover
   ![Hover](previews/hover.webm?raw=true "Hover")
 - Go to definition
 - Document Symbols
 - Document Highlight
 - Completion
 - Formatting via brittany
 - Renaming via HaRe
 
## Installation 

To install HIE

```bash
git clone https://github.com/haskell/haskell-ide-engine
cd haskell-ide-engine
stack install
```

### Using HIE with vscode

Make sure HIE is installed (see above) and dir stack put the `hie` binary is in your path (usually `~/.local/bin` on linux)

```bash
git clone https://github.com/alanz/vscode-hie-server
cd vscode-hie-server
npm install .
```

Open `vscode-hie-server/` in Visual Studio Code and press `F5` to open a new window with the extension loaded.

### This is *not* yet another [`ghc-mod`](https://github.com/kazu-yamamoto/ghc-mod) or [`ide-backend`](https://github.com/fpco/ide-backend) project

 > Both the ghc-mod and ide-backend maintainers have agreed to contribute code to this new repository and then rebase the old repos on this. The reason we're using a new repo instead of modifying one of the existing ones is so that the existing projects experience no disruption during this migration process. If this was a new set of people starting a new project without support from existing projects, I'd agree with you. But Alan's reached out to existing players already, which is an important distinction.

This project is not started from scratch:

1. See why [we should supersede previous tools](/docs/Challenges.md)
2. Check the [list of existing tools and functionality](/docs/Tools.md)
3. See more [other tools and IDEs for inspiration](/docs/Inspirations.md)


## It's time to join the project!

:heart: Haskell tooling dream is near, we need your help! :heart:

 - Register in [our google group mailing list](https://groups.google.com/forum/#!forum/haskell-ide).
 - Join [our IRC channel](http://webchat.freenode.net/?channels=haskell-ide-engine) at `#haskell-ide-engine` on `freenode`.
 - Fork this repo and hack as much as you can.
 - Ask @alanz or @hvr to join the project.

## Development

Apart from stack you need [cask](https://cask.readthedocs.org/en/latest/) for the emacs tests. You can install it using

```
curl -fsSL https://raw.githubusercontent.com/cask/cask/master/go | python
```

-------------


## Architecture

Below you find a short overview of the main architectural layers of `haskell-ide-engine`.
For more info have a look in [the docs folder](/docs) at the root of this project, especially:

 - The [Architecture discussion](/docs/Architecture.md)
 - The [Protocol discussion](/docs/Protocol.md)
 - The [Design discussion](/docs/Design.md)

#### 1. BIOS layer

[`ghc-mod`](https://github.com/kazu-yamamoto/ghc-mod) stays an AGPL project,
and is used for its "awesome sauce" in terms of
the BIOS functions that it does so well. This interface is
[straightforward to use](http://alanz.github.io/haskell%20refactorer/2015/10/02/ghc-mod-for-tooling),
and if a license-constrained user wants to do something else it is also easy to
replace, if there is strong control of the operating environment.

#### 2. Plugin layer

A layer providing a point to integrate tools and existing functions, probably
including ghci.

#### 3. IDE interfacing layer

This provides a set of logical channels that can be integrated into standard
IDEs. The details still need to be worked out, but I would imagine something
like a channel for querying information about a project, one for a ghci session,
and whatever others are needed. These logical channels can then run over
whatever transport is appropriate to the specific IDE being integrated.

According to [#2](https://github.com/haskell/haskell-ide-engine/issues/2) it seems the
consensus is toward (re-)using the Idris protocol, as the languages are similar
enough and it offers cross-IDE support already.

The __Plugin layer__ and __IDE layer__ are very fuzzy at this point, and there has been some
discussion on IRC around it. These layers may well live in a single repository
(this one), as two separate layers or just be a feature of how
`haskell-ide-engine` is built.



## Documentation

All the documentation is in [the docs folder](/docs) at the root of this project.
