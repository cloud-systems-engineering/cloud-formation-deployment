#
# cfd - Cloud Formation Deployment
#
# Powershell scripts that assist with the deployment of Cloud Formation
# 
# Copyright (C) 2024  Michael Shaw trading as Cloud Systems Engineering

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# I may be contacted at support@cloudsystems.engineering



#
#   When you create a process and want to reliably capture the stdout and stderr
#   you have to capture the output asynchronously.  This is awkward when pwsh is
#   not officially a thread aware environment.  - so we have to hack it in C#.
#

$ProcessStreamReaderCode = @"
using System;
using System.Diagnostics;
using System.Text;

namespace PsrCode
{
    public class Reader
    {
        public StringBuilder ReadStdOutAsync(Process process)
        {
            StringBuilder stdOut = new StringBuilder();
            process.OutputDataReceived +=
                new DataReceivedEventHandler((sender, e) => {
                    if (stdOut.Length > 0) {
                        stdOut.Append("\n");
                    }
                    stdOut.Append(e.Data);
                });
            // process.ErrorDataReceived += DataReceivedEventHandler((sender, e) => { stdOut += e.Data });
            return stdOut;
        }

        public StringBuilder ReadStdErrAsync(Process process)
        {
            StringBuilder stdErr = new StringBuilder();
            process.ErrorDataReceived +=
                new DataReceivedEventHandler((sender, e) => {
                    if (stdErr.Length > 0) {
                        stdErr.Append("\n");
                    }
                    stdErr.Append(e.Data);
                });
            return stdErr;
        }
    }
}
"@

Add-Type -TypeDefinition $ProcessStreamReaderCode -Language CSharp


enum CommandStream {
    StdIn
    StdOut
    StdErr
}


# New-SystemCommand
# Start-SystemCommand
# Show-SystemCommandOutput
# Complete-SystemCommand
# Wait-SystemCommand

# Trace-SystemCommand : New | Start | Show
# Invoke-SystemCommand : New | Start | Wait | Complete


function New-SystemCommand {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [String]$Cmd,
        [String[]]$CmdArgs
    )
    BEGIN {

    }
    PROCESS {
        $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo

        $ProcessInfo.FileName = $Cmd
        $ProcessInfo.RedirectStandardError = $true
        $ProcessInfo.RedirectStandardOutput = $true
        $ProcessInfo.UseShellExecute = $false
        $ProcessInfo.Arguments = $CmdArgs

        $Process = New-Object System.Diagnostics.Process
        $Process.StartInfo = $ProcessInfo

        # Connect up the StdOut and StdErr readers
        $AsyncReader = Invoke-Expression "[PsrCode.Reader]::new()"
        $StdOut = $AsyncReader.ReadStdOutAsync($Process)
        $StdErr = $AsyncReader.ReadStdErrAsync($Process)

        [pscustomobject]@{
            Process = $Process
            StdOut = $StdOut
            StdErr = $StdErr
        } | Write-Output
    }
    END {

    }
}

function Start-SystemCommand {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [System.Diagnostics.Process]$Process
    )
    BEGIN {

    }
    PROCESS {
        $Process.Start() | Out-Null
        $Process.BeginErrorReadLine()
        $Process.BeginOutputReadLine()
    }
    END {

    }
}


function Wait-SystemCommand {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [System.Diagnostics.Process]$Process
    )
    BEGIN {

    }
    PROCESS {
        $Process.WaitForExit();
    }
    END {

    }
}

function Complete-SystemCommand {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [System.Diagnostics.Process]$Process,
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [System.Text.StringBuilder]$StdOut,
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [System.Text.StringBuilder]$StdErr
    )
    BEGIN {

    }
    PROCESS {
        [pscustomobject]@{
            StdOut = $StdOut.ToString()
            StdErr = $StdErr.ToString()
            ExitCode = $Process.ExitCode
        } | Write-Output
        
    }
    END {

    }
}




#
#   Synchronous Invocation
#
function Invoke-SystemCommand {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [String]$Cmd,
        [String[]]$CmdArgs
    )
    BEGIN {

    }
    PROCESS {
        $ProcessData = $(New-SystemCommand -Cmd $Cmd -CmdArgs $CmdArgs)

        $ProcessData | Start-SystemCommand
        $ProcessData | Wait-SystemCommand
        $ProcessData | Complete-SystemCommand | Write-Output
    }
    END {

    }
}

#
#   Synchronous Invocation
#
function Trace-SystemCommand {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [String]$Cmd,
        [String[]]$CmdArgs
    )
    BEGIN {

    }
    PROCESS {
        $ProcessData = $(New-SystemCommand -Cmd $Cmd -CmdArgs $CmdArgs)

        $ProcessData | Start-SystemCommand

        $StdOutPosition = 0
        $StdErrPosition = 0

        while ($ProcessData.Process.HasExited -eq $false)
        {
            $StdOutContent = Read-CommandOutput -Position $StdOutPosition -Stream $ProcessData.StdOut
            if ($StdOutContent.Length -gt 0)
            {
                $StdOutPosition = $StdOutPosition + $StdOutContent.Length
                $StdOutContent |
                    Format-CommandOutput -Stream StdOut |
                    Write-Output
            }

            $StdErrContent = Read-CommandOutput -Position $StdErrPosition -Stream $ProcessData.StdErr
            if ($StdErrContent.Length -gt 0)
            {
                $StdErrPosition = $StdErrPosition + $StdErrContent.Length
                $StdErrContent |
                    Format-CommandOutput -Stream StdErr |
                    Write-Output
            }

            Start-Sleep -Seconds 1
        }
    }
    END {

    }
}

function Read-CommandOutput {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [Int]$Position,
        [System.Text.StringBuilder]$Stream
    )
    BEGIN {
        $NextPosition = $Stream.Length
        $NewText = ""
        if ($NextPosition -gt $Position)
        {
            $NewText = $Stream.ToString().Substring($Position, $NextPosition - $Position)
        }
        Write-Output $NewText
    }
    PROCESS {

    }
    END {

    }
}

function Format-CommandOutput {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [CommandStream]$StreamEnum,
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [String]$Text
    )
    BEGIN {
    }
    PROCESS {
        [pscustomobject]@{
            Stream = $StreamEnum
            Text = $Text
        } | Write-Output    
    }
    END {

    }
}

function Write-CommandTrace {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [pscustomobject]$Output
    )
    BEGIN {
    }
    PROCESS {
        if ($Output.Stream -eq [CommandStream]::StdOut) {
            Write-Host $Output.Text
        }
        if ($Output.Stream -eq [CommandStream]::StdErr) {
            $Text = $Output.Text
            Write-Host "STDERR: ${Text}"
        }
    }
    END {

    }
}


# function Test-World {
#     [CmdletBinding(PositionalBinding=$false)]
#     param()
#     BEGIN {

#     }
#     PROCESS {
#         # $Output = Invoke-SystemCommand -Cmd "whereis" -CmdArgs @('-b', 'aws')
#         # $Output = Invoke-SystemCommand -Cmd $AWS_CLI_PATH -CmdArgs @('s3', 'ls', '--profile', 'pct-ct')
        
#         Trace-SystemCommand -Cmd $AWS_CLI_PATH -CmdArgs @('sso', 'login', '--profile', 'pct-ct') | Write-CommandTrace
#         # $ExitCode = $Output.ExitCode

#         # Write-Host "Results"
#         # Write-Host "Exit Code: ${ExitCode}"
#         # Write-Host $Output.StdOut

#     }
#     END {

#     }
# }


# Test-World
