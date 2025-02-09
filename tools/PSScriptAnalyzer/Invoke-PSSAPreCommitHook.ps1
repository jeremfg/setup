#!/usr/bin/env powershell
# SPDX-License-Identifier: MIT
#
# Copied from:
# https://github.com/martukas/dotfiles/blob/master/common/powershell/Invoke-PSSAPreCommitHook.ps1

# Check if a string contains any one of a set of terms to search for
# Returns True if found or False otherwise
function containsArrayValue {
  param (
      [Parameter(Mandatory=$True)]
      [string]$description,

      [Parameter(Mandatory=$True)]
      [array]$searchTerms
  )

  foreach($searchTerm in $searchTerms) {
      if($description -like "*$($searchTerm)*") {
          return $true;
      }
  }

  return $false;
}

# Run Analyzer on everything recursively
$Results = Invoke-ScriptAnalyzer -Path . -Recurse

# Find the paths of git sub-modules
$SubModulePaths = git submodule --quiet foreach --recursive pwd

# If in Windows, have to convert unix paths provided by git
if ($IsWindows)
{
  $Command = "$Env:Programfiles\Git\usr\bin\cygpath.exe"

  $SubModulePaths = $SubModulePaths | ForEach-Object {
      $Params = "-w $_".Split(" ")
      & "$Command" $Params
  }
}

# Eliminate results for files in git sub-modules if any
$FilteredResults = $Results
if ($SubModulePaths) {
  $FilteredResults = $Results | Where-Object {-Not (containsArrayValue $_.ScriptPath $SubModulePaths)}
}

# Sanitize paths and and add links to rule pages
foreach ($item in $FilteredResults)
{
  Add-Member -InputObject $item -MemberType NoteProperty -Name "RelPath" `
      -Value ($item.ScriptPath | Resolve-Path -Relative)
  $Link = "https://github.com/PowerShell/PSScriptAnalyzer/blob/master/docs/Rules/" `
          + $item.RuleName.Substring(2) + ".md"
  Add-Member -InputObject $item -MemberType NoteProperty -Name "RuleLink" -Value $Link
}

if ($null -ne $FilteredResults)
{
  # List all violations
  $FilteredResults | Sort-Object RelPath, Line | Format-Table `
      -Property Severity, ScriptPath, Line, Column, RuleName, RuleLink `
      -AutoSize -Wrap

  $SeverityValues = [Enum]::GetNames("Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticSeverity")

  # Calculate severity statistics
  $SeverityStats = $SeverityValues | ForEach-Object {
      $ourObject = New-Object -TypeName psobject;
      $ourObject | Add-Member -MemberType NoteProperty -Name "Severity" -Value $_;
      $ourObject | Add-Member -MemberType NoteProperty -Name "Count" -Value (
      $FilteredResults | Where-Object -Property Severity -EQ -Value $_ | Measure-Object
      ).Count;
      $ourObject
  }

  # Print severity stats
  $SeverityStats | Format-Table

  $NumFailures = ($FilteredResults).Count

  # Since there was at least one failure, get mad now
  throw "ScriptAnalyzer failed with $($NumFailures) violations"
}
