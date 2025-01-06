# Powershell
# SPDX-License-Identifier: MIT
#
# This script is used to set up the local client environment on Windows. It configures the following:
# 1. WSL2 (Windows Subsystem for Linux), with the latest LTS release of Ubuntu
# 2. Docker Desktop
# 3. Under WSL environment, optionally checkout the given repo
# 4. Under WSL environment, optionally invoke the entrypoint given
#
# Usage:
# It is recommended to run C:\> setup_wsldockergit.bat
#
# Example:
# bitsadmin /transfer setup ^
# https://raw.githubusercontent.com/jeremfg/setup/refs/heads/main/src/setup_wsldockergit.bat ^
# %cd%\setup_wsldockergit.bat & setup_wsldockergit.bat -RepoUrl "git@github.com:jeremfg/setup.git" ^
# -RepoRef "main" -EntryPoint "echo 'Welcome to Setup!'"
#
# Todo:
# - Make sure that the automatic execution after reboot uses the same arguments that were orginally passed (untested)
#
# NOTE: Designed to run on a fresh Windows 10 install or later

Param(
  [Parameter(Mandatory=$false)]
  [switch]$Help,

  [Parameter(Mandatory=$false)]
  [string]$RepoUrl,

  [Parameter(Mandatory=$false)]
  [string]$RepoRef,

  [Parameter(Mandatory=$false)]
  [string]$RepoDir,

  [Parameter(Mandatory=$false)]
  [string]$EntryPoint
)

#############
# Constants #
#############
$AutoExecName = "setup_wsldockergit_ps1"
$wslUser = $null

# Main function where the real execution begins
function main {
  # Handle help
  if ($Help) {
    Write-Host "Script that sets up a dockerized environment on Windows, optionally clones a Git repository"
    Write-Host "within WSL2 and runs a command inside that WSL2 environment."
    Write-Host ""
    Write-Host "Usage: setup_wsldockergit.ps1 [-RepoUrl <url>] [-RepoRef <ref>] [-EntryPoint <command>]"
    Write-Host "  -RepoUrl:    URL of the repository to clone"
    Write-Host "  -RepoRef:    Branch or tag to checkout"
    Write-Host "  -RepoDir:    Directory to clone the repository into, within the WSL environment"
    Write-Host "  -EntryPoint: Command to run once the WSL2 environment is up and running"
    exit 0
  }

  # Initialization
  Install-Dependencies -moduleName 'Logging'
  Install-Dependencies -moduleName 'Wsl'
  Start-Logging

  # Install WSL
  Install-WSL2
  Install-WSLDistro
  Wait-User

  # Install Docker
  Install-Winget
  Install-Docker

  # Checkout repo
  Get-Repo

  # Cleanup tasks (If we reach here, we have done everything we wanted succesfully)
  Reset-AutoExec
}

# Checkout the repo defined in the 'constants' section
function Get-Repo {

  if ($null -eq $global:RepoUrl -or $global:RepoUrl -eq "") {
    Write-Log -Level 'INFO' -Message "No repository URL provided. Skipping..."
    return
  }

  # This will probably cause an infinite loop with Reset-AutoExec later on
  Assert-NotAdmin "to Invoke WSL commands"

  if ($null -eq $global:RepoDir -or $global:RepoDir -eq "") {
    Write-Log -Level 'INFO' -Message "No git directory provided. Using default..."
    # Find out the user's 'home' directory inside the Ubuntu distro
    Write-Log -Level 'DEBUG' -Message "Finding the user's home directory in WSL"
    $homeDir = Invoke-WslCommand -Name "$(Get-LatestUbuntuDistro)" -Command "cd ~ && pwd"
    $global:RepoDir = "$homeDir/repos"
    Write-Log -Level 'DEBUG' -Message "Using $global:RepoDir as the default git directory"
  } else {
    # Replace any instance of ~, $HOME or ${HOME} with the actual home directory
    if ($global:RepoDir -match '^~|^\$HOME|^\${HOME}') {
      Write-Log -Level 'DEBUG' -Message "Expanding $global:RepoDir to the user's home directory"
      $homeDir = Invoke-WslCommand -Name "$(Get-LatestUbuntuDistro)" -Command "cd ~ && pwd"
      $global:RepoDir = $global:RepoDir -replace '^~|^\$HOME|^\${HOME}', $homeDir
    }
  }

  # Make sure RepoDir is created
  Write-Log -Level 'DEBUG' -Message "Creating $global:RepoDir"
  Invoke-WslCommand -Name "$(Get-LatestUbuntuDistro)" -Command "mkdir -p $global:RepoDir"

  # Prepare the setup_git command
  $linuxCmd = "wget -qO- 'https://raw.githubusercontent.com/jeremfg/setup/refs/heads/main/src/setup_git' | bash -s -- "
  $linuxCmd += "$global:RepoUrl"

  if ($null -ne $global:RepoRef -and $global:RepoRef -ne "") {
    $linuxCmd += " $global:RepoRef"
  }

  if ($null -ne $global:EntryPoint -and $global:EntryPoint -ne "") {
    $linuxCmd += " -- $global:EntryPoint"
  }

  # Call the setup_git script
  Write-Log -Level 'INFO' -Message "Cloning repository into $global:RepoDir"
  Invoke-WslCommand -Name "$(Get-LatestUbuntuDistro)" -WorkingDirectory "$global:RepoDir" `
    -Command "$linuxCmd"

  Write-Log -Level 'INFO' -Message "Setup completed successfully"
}

# Reset the PATH environment variable in the current process using the one from the OS.
# This is useful so newly installed programs that add themselves to PATH are working within the current process
# that installed them
function Reset-Path {
  # Get the system and user PATH environment variables
  $systemPath = [System.Environment]::GetEnvironmentVariable("PATH", [System.EnvironmentVariableTarget]::Machine)
  $userPath = [System.Environment]::GetEnvironmentVariable("PATH", [System.EnvironmentVariableTarget]::User)

  # Concatenate the system and user PATH environment variables
  $newPath = $systemPath + ";" + $userPath

  # Path delimiter cleanup/sanitize. Remove all leading, trailing or duplicate semicolons
  $newPath = $newPath -replace ";;+", ";"
  $newPath = $newPath -replace "^;|;$", ""

  # Set the new PATH environment variable for the process
  [Environment]::SetEnvironmentVariable("PATH", $newPath, [System.EnvironmentVariableTarget]::Process)
}

# Install WinGet
function Install-Winget {
  try {
    Get-Command winget -ErrorAction Stop >$null
  } catch {
      Write-Log -Level 'INFO' -Message "WinGet doesn't seem to be installed. Installing..."
      Assert-Admin "to install WinGet"
      Invoke-RestMethod "https://github.com/asheroto/winget-install/releases/latest/download/winget-install.ps1" | `
        Invoke-Expression -ArgumentList '-NoExit'
      try {
        Get-Command winget -ErrorAction Stop >$null
      } catch {
        Write-Log -Level 'ERROR' -Message "WinGet failed to install"
        exit 1
      }
  }
}

# Install DockerDesktop
function Install-Docker {
  $packageName = "Docker.DockerDesktop"
  $doINeedToRestart = $false

  # Check if package is already installed
  $packageExists = (winget list --accept-source-agreements) -match "$packageName"
  if ($false -eq $packageExists) {
    Write-Log -Level 'INFO' -Message "Preparing to install {0}..." -Arguments $packageName

    # Raise privileges immediately. They will be needed anyway during install and we don't want
    # a new PowerShell session for reboot at the end. We need to stay in context during the whole install
    Assert-Admin "to install Docker"

    # Actually install Docker
    Install-Using-Winget $packageName

    $doINeedToRestart = $true
  }

  # The PATH will have changed on the OS. Reload it so the next check works
  Reset-Path

  # Try calling Docker, to make sure it really installed
  try {
    docker --version
  } catch {
    Write-Log -Level 'ERROR' -Message "There is a problem with the installation of docker"
    exit 1
  }

  # Handle the request restart
  if ($true -eq $doINeedToRestart) {
    Write-Log -Level 'INFO' -Message "Package {0} is now installed. A restart is required" -Arguments $packageName
    Set-AutoExec
    Restart-Host
  }
}

# This function waits until the WSL Distro has been configured with a local user.
# This waits for manual internvention to be over, providing an account username and password.
# A console session will have popped-up automatically at the end of Ubuntu install,
# prompting the user for account details.
function Wait-User {
  $noUser = "root" # As long as the user is not created, the default one will be 'root'

  # Wait indefinitely for a new user to be created
  while ($true) {
    # It was observed in a few occastion that calling a command on the container would cause an exception.
    # Perhaps a race-condition? Just catch the exception and try again if it happens.
    try {
      $global:wslUser = Invoke-WslCommand -Name "$(Get-LatestUbuntuDistro)" -Command "whoami" # Retrieve the current default user
    } catch {
      $global:wslUser = $noUser # Reset to default on exception
      Write-Log -Level 'WARNING' -Message "Failure to check for user account on {0}" -Arguments "$(Get-LatestUbuntuDistro)"
    }
    Write-Log -Level 'INFO' -Message "Waiting for user to configure his account on {0}" -Arguments "$(Get-LatestUbuntuDistro)"

    # If returned user is different than 'root' for 'whoami', then the user was created successfully.
    # Break the infinite loop
    if ($global:wslUser -ne $noUser) {
      break
    }

    Start-Sleep -Seconds 1  # Sleep for 1 second before the next iteration
  }

  Write-Log -Level 'INFO' -Message "User '{0}' has been found" -Arguments $global:wslUser
}

# This function installs Ubuntu-22.04 on WSL2, make sure the proper backend version is running, and that it is the
# default distribution
function Install-WSLDistro {

  # Check if the distribution is already installed
  $WslDistribution = Get-WslDistribution "$(Get-LatestUbuntuDistro)"
  if (-not $WslDistribution) {
      Write-Log -Level 'INFO' -Message "{0} is not installed. Installing..." -Arguments "$(Get-LatestUbuntuDistro)"

      # There could be a restart during Ubuntu installation. Make sure we will resume if it happens
      Set-AutoExec

      Write-Log -Level 'INFO' -Message "Installing {0}... You will need to call 'exit' after your user is crated." `
        -Arguments "$(Get-LatestUbuntuDistro)"
      wsl --install -d "$(Get-LatestUbuntuDistro)"

      # Just a little buffer to avoid possible race condition between distro install and bootiung up.
      Start-Sleep -Seconds 5
      Write-Log -Level 'INFO' -Message "Waiting for {0} to be ready" -Arguments "$(Get-LatestUbuntuDistro)"

      # Wait for WSL to be installed
      $maxRetries = 300 # 300 * 5s = 25 minutes. Timeout waiting for Ubuntu-22.04 to be in a stable state
      $retryInterval = 5
      $currentRetry = 0

      while ($currentRetry -lt $maxRetries) {
        # Get attirbutes of Distro
        $WslDistribution = Get-WslDistribution "$(Get-LatestUbuntuDistro)"
        if ($null -ne $WslDistribution) {
          $state = $WslDistribution.State
          Write-Log -Level 'DEBUG' -Message "{0} is in state {1}" -Arguments "$(Get-LatestUbuntuDistro)", $state

          # Check if the state is "Stopped" or "Running"
          if ($state -eq "Stopped" -or $state -eq "Running") {
            Write-Log -Level 'INFO' -Message "We are done waiting for {0} to be ready" `
              -Arguments "$(Get-LatestUbuntuDistro)"
            break # WSL distro in a stable state. Exit loop.
          }
        }

        # Increment the retry count and wait for the specified interval
        $currentRetry++
        Start-Sleep -Seconds $retryInterval
      }

      # Just a last confirmation that the distro is installed
      $WslDistribution = Get-WslDistribution "$(Get-LatestUbuntuDistro)"
      if ($null -eq $WslDistribution) {
        Write-Log -Level 'ERROR' -Message "Failed to install {0}" -Arguments "$(Get-LatestUbuntuDistro)"
        exit 1
      }
  } else {
    Write-Log -Level 'DEBUG' -Message "{0} is installed" -Arguments "$(Get-LatestUbuntuDistro)"
  }

  # Check if it's runnnig WSL 2
  if ($WslDistribution.Version -ne 2) {
    Write-Log -Level 'WARNING' -Message "{0} is running WSL version {1}. Attempting an upgrade..." `
    -Arguments "$(Get-LatestUbuntuDistro)", $WslDistribution.Version

    Set-WslDistribution "$(Get-LatestUbuntuDistro)" -Version 2

    $WslDistribution = Get-WslDistribution "$(Get-LatestUbuntuDistro)"
    if ($WslDistribution.Version -ne 2) {
      Write-Log -Level 'ERROR' -Message "Failed to upgrade {0}" -Arguments "$(Get-LatestUbuntuDistro)"
      exit 1
    }
  } else {
    Write-Log -Level 'DEBUG' -Message "{0} is running WSL version {1}" `
    -Arguments "$(Get-LatestUbuntuDistro)", $WslDistribution.Version
  }

  # Check if Default
  if ($true -ne $WslDistribution.Default) {
    Write-Log -Level 'WARNING' -Message "{0} is NOT the default distro. Attemptiong to change that..." `
    -Arguments "$(Get-LatestUbuntuDistro)"

    Set-WslDistribution "$(Get-LatestUbuntuDistro)" -Default

    $WslDistribution = Get-WslDistribution "$(Get-LatestUbuntuDistro)"
    if ($true -ne $WslDistribution.Default) {
      Write-Log -Level 'ERROR' -Message "Failed to set {0} as default." -Arguments "$(Get-LatestUbuntuDistro)"
      exit 1
    }
  } else {
    Write-Log -Level 'DEBUG' -Message "{0} is the default distro" -Arguments "$(Get-LatestUbuntuDistro)"
  }
}

# Install Windows Feature: Windows-Subsystem-For-Linux (WSL)
function Install-WSL2 {
  Write-Log -Level 'INFO' -Message "Check for WSL..."

  try {
    $wslStatus = wsl --status --quiet 2>&1
    if ($null -eq $wslStatus) {
      Write-Log -Level 'WARNING' -Message "WSL is not installed or not running."
    } else {
      Write-Log -Level 'INFO' -Message "WSL is already installed and running. Make sure it's up to date"

      # Set WSL 2 as the default version
      wsl --set-default-version 2

      Write-Log -Level 'DEBUG' -Message "Call wsl --update"

      # WslRegisterDistribution failed with error: 0x800701bc
      # Error: 0x800701bc WSL 2 requires an update to its kernel component. For information please visit https://aka.ms/wsl2kernel
      wsl --update

      Write-Log -Level 'DEBUG' -Message "return from succesfully installing WSL2"

      return
    }
  } catch {
    Write-Log -Level 'ERROR' -Message "Failure to check for WSL status."
    exit 1
  }

  # Before doing anything, make sure we already are an admin so the following actions are atomic prior to restart
  # and not restarted mid-way in a new Powershell session.
  Assert-Admin "to change windows optional features"

  $doINeedToRestart = $false

  # Check for depedency VirtualMachinePlatform
  $status = Get-WindowsOptionalFeature -Online | Where-Object FeatureName -eq "VirtualMachinePlatform"
  if ($status.State -eq "Enabled") {
    Write-Log -Level 'INFO' -Message "VirtualMachinePlatform is installed."
  } else {
    Write-Log -Level 'WARNING' -Message "Virtual Machine Platform is NOT installed."

    $ProgPref = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue' # Hide progress bar
    $results = Enable-WindowsOptionalFeature -FeatureName VirtualMachinePlatform `
                -Online -NoRestart -WarningAction SilentlyContinue
    $ProgressPreference = $ProgPref
    if ($results.RestartNeeded -eq $true) {
      Write-Log -Level 'INFO' -Message "VirtualMachinePlatform requests a restart."
      $doINeedToRestart = $true
    }
  }

  # Check for feature: WSL
  $status = Get-WindowsOptionalFeature -Online | Where-Object FeatureName -eq "Microsoft-Windows-Subsystem-Linux"
  if ($status.State -eq "Enabled") {
    Write-Log -Level 'INFO' -Message "Microsoft-Windows-Subsystem-Linux is installed."
  } else {
    Write-Log -Level 'WARNING' -Message "Microsoft-Windows-Subsystem-Linux is NOT installed."

    $ProgPref = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue' # Hide progress bar
    $results = Enable-WindowsOptionalFeature -FeatureName Microsoft-Windows-Subsystem-Linux `
                -Online -NoRestart -WarningAction SilentlyContinue
    $ProgressPreference = $ProgPref
    if ($results.RestartNeeded -eq $true) {
      Write-Log -Level 'INFO' -Message "Microsoft-Windows-Subsystem-Linux requests a restart."
      $doINeedToRestart = $true
    }
  }

  # Handle the request for restart
  if ($true -eq $doINeedToRestart) {
    Write-Log -Level 'INFO' -Message "WSL is now installed. Restart is required"
    Set-AutoExec
    Restart-Host
  } else {
    Write-Log -Level 'INFO' -Message "WSL is now installed. Restart is NOT required"
  }
}

# Performs a restart of the computer (asking the user first if it's OK to do so now)
function Restart-Host {
  # This function does NOT require privilege elevation
  Write-Log -Level 'INFO' -Message "Ask user if it's ok to restart the computer"

  # Ask user if it's OK to reboot using a Yes/No MessageBox
  Add-Type -AssemblyName PresentationCore,PresentationFramework
  $ButtonType = [System.Windows.MessageBoxButton]::YesNo
  $MessageIcon = [System.Windows.MessageBoxImage]::Question
  # Create a TextBlock with line breaks
  $MessageBody = "Is it OK to restart the computer now?" + [Environment]::NewLine + [Environment]::NewLine `
                + "Regardless of your answer, this script will resume on the next logon to finish the configuration. " `
                + "If you answer 'No', simply restart your computer manually when you are ready to proceed with " `
                + "the next configuration steps."
  $MessageTitle = "Restart confirmation"
  $Result = [System.Windows.MessageBox]::Show($MessageBody,$MessageTitle,$ButtonType,$MessageIcon)

  if ($Result -eq [System.Windows.MessageBoxResult]::Yes) {
    Write-Log -Level 'INFO' -Message "User said it's ok to restart"
  } else {
    Write-Log -Level 'ERROR' -Message "User refused the restart. Exiting..."
    exit 1
  }

  # Perform the restart
  Restart-Computer -Force
}

# Configure this script to run automatically at LogOn (useful before restarting the computer)
function Set-AutoExec {
  # Check if the scheduled task already exists
  $existingTask = Get-ScheduledTask -TaskName $AutoExecName -ErrorAction SilentlyContinue
  if (-not $existingTask) {
    Assert-Admin "to create scheduled task '$AutoExecName'"
    try {
      # Define the action to run your script on startup
      $Action = New-ScheduledTaskAction -Execute 'Powershell.exe' `
      -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$($global:MyInvocation.MyCommand.Path)`" $global:args"

      # Define the trigger for the task (at startup)
      $Trigger = New-ScheduledTaskTrigger -AtLogOn

      # Register the scheduled task
      Register-ScheduledTask -Action $Action -Trigger $Trigger -TaskName $AutoExecName -User $env:USERNAME -Force
    } catch {
      Write-Log -Level 'ERROR'-Message "Failed to create '{0}'" -Arguments $AutoExecName
      exit 1
    }

    # Confirm the task really was created successfully
    $existingTask = Get-ScheduledTask -TaskName $AutoExecName -ErrorAction SilentlyContinue
    if ($existingTask) {
      Write-Log -Level 'INFO' -Message "Scheduled task '{0}' created successfully" -Arguments $AutoExecName
    } else {
      Write-Log -Level 'ERROR' -Message "Scheduled task '{0}' could not be created" -Arguments $AutoExecName
      exit 1
    }
  } else {
    Write-Log -Level 'INFO' -Message "Scheduled task '{0}' already exists" -Arguments $AutoExecName
  }
}

# Remove the scheduled task we've created to run ourselves again after restart. It is no longer needed...
function Reset-AutoExec {
  # Check if the scheduled task already exists
  $existingTask = Get-ScheduledTask -TaskName $AutoExecName -ErrorAction SilentlyContinue
  if ($existingTask) {
    # Remove it
    Write-Log -Level 'INFO' -Message "Scheduled task '{0}' exists. Removing it..." -Arguments $AutoExecName
    Assert-Admin "to remove scheduled task '$AutoExecName'"

    Unregister-ScheduledTask -TaskName $AutoExecName -Confirm:$false

    # Confirm the task no longer exists
    $existingTask = Get-ScheduledTask -TaskName $AutoExecName -ErrorAction SilentlyContinue
    if (-not $existingTask) {
      Write-Log -Level 'INFO' -Message "Scheduled task '{0}' removed" -Arguments $AutoExecName
    } else {
      Write-Log -Level 'ERROR' -Message "Scheduled task '{0}' could not be removed" -Arguments $AutoExecName
      exit 1
    }
  }
}

# Ensure we are running with privileges. If not, elevate them by calling our own script recursively.
function Assert-NotAdmin {
  param (
    [string]$taskName
  )

  Write-Log -Level 'DEBUG' -Message "Regular privileges are required {0}. Checking..." -Arguments $taskName
  $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  if (-not ($currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
    Write-Log -Level 'DEBUG' -Message "Already running with basic permissions. Proceeding..."
  } else {
    Write-Log -Level 'WARNING' -Message "You have administrative privileges currently. Unelevation required to perform this task. Unelevating..."
    try {
      # Restart the script without administrative privileges
      Start-Process -FilePath "runas" -ArgumentList `
      "/trustlevel:0x20000 /machine:amd64 `"powershell.exe -ExecutionPolicy Bypass -File $($global:MyInvocation.MyCommand.Path) $global:args`""
    } catch {
      Write-Log -Level 'ERROR' -Message "Unelevation failed. Exiting in error..."
      exit 1
   }

    Write-Log -Level 'INFO' -Message "Unelevation succeeded. Exiting..."
    exit 0
  }
}

# Ensure we are running with privileges. If not, elevate them by calling our own script recursively.
function Assert-Admin {
  param (
    [string]$taskName
  )

  # First check if we are already running as an admin or not
  Write-Log -Level 'DEBUG' -Message "Administrative privileges are required {0}. Checking..." -Arguments $taskName
  $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  if (-not ($currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
    Write-Log -Level 'WARNING' -Message "You need administrative privileges to perform this task. Elevating..."
    try {
      # Restart the script with administrative privileges
      Start-Process -FilePath "powershell.exe" -ArgumentList `
      "-NoProfile -ExecutionPolicy Bypass -File `"$($global:MyInvocation.MyCommand.Path)`" $global:args" `
      -Verb RunAs
    } catch {
      Write-Log -Level 'ERROR' -Message "Elevation failed. Exiting in error..."
      exit 1
    }

    Write-Log -Level 'INFO' -Message "Elevation succeeded. Exiting..."
    exit 0
  }
  else {
    Write-Log -Level 'DEBUG' -Message "Already running as an administrator. Proceeding..."
  }
}

function Install-Using-Winget {
  param (
    [string]$packageName
  )

  $packageExists = (winget list --accept-source-agreements) -match "$packageName"
  if ($false -eq $packageExists) {
    Write-Log -Level 'INFO' -Message "Installing {0}..." -Arguments $packageName

    winget install --accept-package-agreements --accept-source-agreements -e --id $packageName --Silent

    # Perform the same check to make sure Docker properly installed
    $packageExists = (winget list --accept-source-agreements) -match "$packageName"
    if ($false -eq $packageExists) {
      Write-Log -Level 'ERROR' -Message "{0} failed to install" -Arguments $packageName
      exit 1
    } else {
      Write-Log -Level 'INFO' -Message "{0} installed successfully" -Arguments $packageName
    }
  } else {
    Write-Log -Level 'DEBUG' -Message "{0} is already installed" -Arguments $packageName
  }
}

# In order to install some packages using Install-Module, we need NuGet first
function Install-NuGetProvider {
  # Check if NuGet provider is installed
  $providerInstalled = Get-PackageProvider | Where-Object { $_.Name -eq 'NuGet' }
  if ($null -eq $providerInstalled) {
    Write-Host "NuGet provider is not installed. Installing..."
    Install-PackageProvider -Name NuGet -Force -Scope CurrentUser

    # Check again to make sure the provider really installed
    $providerInstalled = Get-PackageProvider | Where-Object { $_.Name -eq 'NuGet' }
    if ($null -eq $providerInstalled) {
      Write-Host "NuGet provider failed to install."
      exit 1
    } else {
      Write-Host "NuGet provider installed successfully."
    }
  } else {
    Write-Host "NuGet provider is already installed."
  }
}

# Install dependency modules reuiqred by this script (Logging and Wsl)
function Install-Dependencies {
  param (
    [string]$moduleName
  )

  # Check if the module is installed
  $moduleInstalled = Get-Module -ListAvailable | Where-Object { $_.Name -eq $moduleName }
  if ($null -eq $moduleInstalled) {
    # First, we will need NuGet
    Install-NuGetProvider

    Write-Host "$moduleName module is not installed. Installing..."
    # Install the module
    Install-Module -Name $moduleName -Scope CurrentUser -Force

    # Check for the module again
    Write-Host "Check if $moduleName module is properly installed..."
    $moduleInstalled = Get-Module -ListAvailable | Where-Object { $_.Name -eq $moduleName }
    if ($null -eq $moduleInstalled) {
      Write-Host "Failed to install $moduleName module."
      exit 1
    } else {
      Write-Host "$moduleName module installed successfully."
    }
  } else {
    Write-Host "$moduleName module is already installed."
  }
}

# Configure the logger for the rest of this script's execution
function Start-Logging {
  # Import the module
  $moduleName = 'Logging'
  Import-Module -Name  $moduleName

  # Path where logs should be stored
  $logDirectory = Join-Path -Path "$(Get-Root)" -ChildPath "\.log"

  try {
    # Ensure the log directory exists
    if (-not (Test-Path -Path $logDirectory)) {
      $null = New-Item -Path $logDirectory -ItemType Directory
    }

    # Generate the log filename
    $filename = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $filename = [System.IO.Path]::GetFileNameWithoutExtension($global:MyInvocation.MyCommand.Name) + "_" + $filename
    $transcriptName = $filename + "_transcript" + ".log"
    $filename = $filename + ".log"


    Add-LoggingTarget -Name File -Configuration @{
        Path            = "$logDirectory\$filename"
        PrintBody       = $true
        PrintException  = $true
        Append          = $true
        Encoding        = 'utf8'
        Format          = "%{timestamp:+yyyy-MM-dd HH:mm:ss} [%{level:-7}] %{message}"
    }

    Add-LoggingTarget -Name Console -Configuration @{
        Format          = "%{timestamp:+yyyy-MM-dd HH:mm:ss} [%{level:-7}] %{message}"
        PrintException  = $true
    }

    # Start transcript logging as well
    Start-Transcript -Path "$logDirectory\$transcriptName" -Append
  } catch {
    Write-Error "Error: $($_.Exception.Message)"
    exit 1
  }

  # Default Level
  Set-LoggingDefaultLevel -Level DEBUG

  # Log the first message
  Write-Log -Level 'INFO' -Message "Logging is configured and started"
}

#####################
# Dynamic Constants #
#####################
# Returns the most recent version of the available Ubuntu distributions
$distroName = $null
function Get-LatestUbuntuDistro {
  #Lazy-init $distroName
  if ($null -eq $global:distroName) {
    # WSL outputs in UTF-16 LE
    $oldEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
    $lines = (wsl --list --online)
    [Console]::OutputEncoding = $oldEncoding

    # Extract Ubuntu lines
    $ubuntuLines = $lines | Where-Object { $_ -match "^Ubuntu-" }

    # Extract versions where the key is a parsed version number (for ordering) and the value is the original name
    $versionMap = @{}
    $ubuntuLines | ForEach-Object {
      $versionString = ($_ -split "-| ")[1]
      $version = New-Object System.Version $versionString
      $versionMap[$version] = "Ubuntu-$versionString"
    }

    # Select the first by descending order
    $global:distroName = $versionMap.GetEnumerator() | Sort-Object Key -Descending |
      Select-Object -First 1 -ExpandProperty Value

    Write-Log -Level 'INFO' -Message "Latest Ubuntu distro: `"$global:distroName`""
  }
  return $global:distroName
}

# Find a root for this project
$ROOT = $null
function Get-Root {
  # Lazy-ioit ROOT
  if ($null -eq $global:ROOT) {
    try {
      Get-Command git -ErrorAction Stop >$null
      $gitTopLevel = git rev-parse --show-toplevel 2>$null
      if ($gitTopLevel) {
        $global:ROOT = $gitTopLevel
        Write-Host "Root detected at `"$global:ROOT`""
      } else {
        $global:ROOT = $PSScriptRoot
        Write-Host "Git root not detected. Assuming `"$global:ROOT`" as ROOT"
      }
    } catch {
      $global:ROOT = $PSScriptRoot
      Write-Host "Git doesn't seem to be installed. Assuming `"$global:ROOT`" as ROOT"
    }
  }
  return $global:ROOT
}

try {
  ###############
  # Entry Point #
  ###############
  main

  # Ending log, and make sure everything is flushed before exiting
  Write-Log -Level 'INFO' -Message "Script execution has completed succesfully"
  Wait-Logging

  Stop-Transcript

  # Pause the script here before closing, so the user can review what happened
  Write-Host "Press Enter to exit.."
  Read-Host # Pause before the window closes
} catch {
  Write-Host "An error occurred: $($_.Exception)"
  Stop-Transcript
  Write-Host "Press Enter to exit.."
  Read-Host # Pause before the window closes
}
