# setup

Setup utilities

Normally this repository is used as a library in other repositories.
It provides code to build gitops scripts that setup a development environment,
a runtime environment or otherwise.

That said, this repository offer one unique feature that can be quite useful:
Bootstrapping on vanilla environment where an Operating System was
freshly installed. In other words: Setup by calling a single command.
It currently supports the scenarios described below

## Git source on Linux

More specifically, it supports Ubuntu (apt) and CentOS (yum) currently.
Tailored for bash. It will perform the following:

1. Install git
1. Clone a specified git repository
1. Invoke an entry point for further execution

Here is an example on how this one-liner feature can be used:

<!-- markdownlint-disable MD013 -->
```bash
wget -qO- 'https://raw.githubusercontent.com/jeremfg/setup/refs/heads/main/src/setup_git' | bash -s -- git@github.com:jeremfg/setup.git main -- echo 'Welcome to Setup!'
```
<!-- markdownlint-enable MD013 -->

## Git source on WSL+docker on Windows

From Windows 10 and Later, this will perform the following:

1. Install WSL2
1. Install the latest Ubuntu LTS release
1. Installl docker
1. Clone specified git repository inside WSL
1. Invoke an entry point for further exection

Here is an example how this one-liner feature can be used:

<!-- markdownlint-disable MD013 -->
```bat
bitsadmin /transfer setup ^
https://raw.githubusercontent.com/jeremfg/setup/refs/heads/main/src/setup_wsldockergit.bat ^
%cd%\setup_wsldockergit.bat & setup_wsldockergit.bat -RepoUrl "git@github.com:jeremfg/setup.git" ^
-RepoRef "main" -RepoDir "$HOME/repos" -EntryPoint "echo 'Welcome to Setup!'"
```
<!-- markdownlint-enable MD013 -->
