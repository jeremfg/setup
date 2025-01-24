#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
#
# This is the entry point invoked by pre-commit to run the PSScriptAnalyzer


import os
import sys
import subprocess

if os.name == "nt":
    # Replace this with the path to your PowerShell script
    command = ["./tools/PSScriptAnalyzer/Invoke-PSSAPreCommitHook.ps1"]
    # Append any additional arguments to the command
    command.extend(sys.argv[1:])
    result = subprocess.run(command)
    sys.exit(result.returncode)
else:
    sys.exit(0)
