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

$AWS_CLI_PATH="/opt/homebrew/bin/aws"

[LogMessageRegister]::Add('CFT001', [LogLevel]::Trace, "Tested StackStatus='{0}' for isChanging='{1}'. ", 2)
[LogMessageRegister]::Add('CFT002', [LogLevel]::Trace, "Tested StackStatus='{0}' for stackExists='{1}'. ", 2)
[LogMessageRegister]::Add('CFT003', [LogLevel]::Debug, "The stack={0} is currently in stackStatus='{1}", 2)
[LogMessageRegister]::Add('CFT004', [LogLevel]::Debug, "The stack='{0}' has changed to stackStatus='{1}'.", 2)
[LogMessageRegister]::Add('CFT005', [LogLevel]::Info, "Waiting for the stack='{0}' to finish any pending actions.", 1)
[LogMessageRegister]::Add('CFT006', [LogLevel]::Notice, "creating stack='{0}' as Arn='{1}'", 2)


class AwsException : Exception {
    [string] $ErrorType
    [string] $AwsFunction

    AwsException($AwsFunction, $ErrorType, $Message) : base($Message) {
        $this.AwsFunction = $ErrorType
        $this.ErrorType = $ErrorType        
    }
}

class AwsSsoTokenExpired : AwsException {
    AwsSsoTokenExpired() : base("None", "Authentication", "AWS SSO Authentication Expired") {

    }
}

class ValidationError : AwsException {

    ValidationError($AwsFunction, $ErrorType, $Message) : base($AwsFunction, $ErrorType, $Message) {

    }
}

class NoStack : AwsException {
    [string] $StackName

    NoStack($StackName, $AwsFunction, $ErrorType, $Message) : base($AwsFunction, $ErrorType, $Message) {
        $this.StackName = $StackName
    }
}


function New-ErrorException {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [String]$ErrorMessage
    )
    BEGIN {

    }
    PROCESS {
        $ErrorType = $null
        $AwsFunction = $null
        

        if($ErrorMessage -match '^An error occurred \(([A-Za-z]+)\) when calling the ([A-Za-z]+) operation:') {
            $ErrorType = $Matches.1
            $AwsFunction = $Matches.2
        }

        if ($ErrorMessage -match ': Stack with id ([A-Za-z0-9]+) does not exist') {
            $StackNameDoesNotExist = $Matches.1
        }

        #
        #  First we do the specific errors
        #
        if ($ErrorMessage -match '^Error when retrieving token from sso: Token has expired and refresh failed') {
            throw [AwsSsoTokenExpired]::new()
        }

        #  Stack does not exist
        if ($ErrorType -eq "ValidationError" -and $null -ne $StackNameDoesNotExist) {
            throw [NoStack]::new($StackNameDoesNotExist, $AwsFunction, $ErrorType, $ErrorMessage)
        }

        #
        #   Now we do the general errors
        #
        if ($ErrorType -eq "ValidationError") {
            throw [ValidationError]::new($AwsFunction, $ErrorType, $ErrorMessage)
        }

        # Generic AWS Exception
        if ($null -ne $ErrorType) {
            throw [AwsException]::new($AwsFunction, $ErrorType, $ErrorMessage)
        }

        # Generic Exception
        throw [Exception]::new($ErrorMessage)
    }
    END {

    }
}

###############################################################################
#
#  Invoke the AWS commands to handle stacks
#
###############################################################################

function Invoke-CreateStack {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [String]$StackName,
        [String]$TemplateFile,
        [String]$AwsRegion,
        [String]$AwsProfile
    )
    BEGIN {

    }
    PROCESS {
        try {
            $Output = Invoke-SystemCommand -Cmd $AWS_CLI_PATH -CmdArgs @(
                'cloudformation', 'create-stack', 
                '--stack-name', "${StackName}",
                '--template-body', "${TemplateFile}",
                '--region', "${AwsRegion}",
                '--profile', "${AwsProfile}",
                '--output', 'yaml'
            )
            if ($Output.ExitCode -ne 0) {
                New-ErrorException $Output.StdErr
            }
            $Data = ConvertFrom-Yaml $Output.StdOut
            LOG "CFT006" $StackName $Data.StackId
        }
        catch {
            throw $_
        }
    }
    END {

    }
}


function Invoke-DeleteStack {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [String]$StackName,
        [String]$AwsRegion,
        [String]$AwsProfile
    )
    BEGIN {

    }
    PROCESS {
        $Output = Invoke-SystemCommand -Cmd $AWS_CLI_PATH -CmdArgs @(
            'cloudformation', 'delete-stack', 
            '--stack-name', "${StackName}",
            '--region', "${AwsRegion}",
            '--profile', "${AwsProfile}"
        )

        Write-Host $Output
    }
    END {

    }
}


function Invoke-DescribeStacks {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [String]$StackName,
        [String]$AwsRegion,
        [String]$AwsProfile
    )
    BEGIN {
    }
    PROCESS {
        $Output = Invoke-SystemCommand -Cmd $AWS_CLI_PATH -CmdArgs @(
            'cloudformation', 'describe-stacks', 
            '--stack-name', "${StackName}",
            '--region', "${AwsRegion}",
            '--profile', "${AwsProfile}",
            '--output', "json"
        )
        Write-Output $Output
    }

    END {

    }
}



###############################################################################
#
#  Invoke the AWS commands to handle change sets
#
###############################################################################


function Invoke-CreateChangeSet {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [String]$StackName,
        [String]$ChangeSetName,
        [String]$TemplateFile,
        [String]$AwsRegion,
        [String]$AwsProfile
    )
    BEGIN {

    }
    PROCESS {
        $Output = Invoke-SystemCommand -Cmd $AWS_CLI_PATH -CmdArgs @(
            'cloudformation', 'create-change-set', 
            '--stack-name', "${StackName}",
            '--change-set-name', "${ChangeSetName}",
            '--template-body', "${TemplateFile}"
            '--region', "${AwsRegion}",
            '--profile', "${AwsProfile}"
        )

        Write-Host $Output


    }
    END {

    }
}


function Invoke-ApplyChangeSet {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [String]$StackName,
        [String]$ChangeSetName,
        [String]$TemplateFile,
        [String]$AwsRegion,
        [String]$AwsProfile
    )
    BEGIN {

    }
    PROCESS {
        $Output = Invoke-SystemCommand -Cmd $AWS_CLI_PATH -CmdArgs @(
            'cloudformation', 'apply-change-set', 
            '--stack-name', "${StackName}",
            '--change-set-name', "${ChangeSetName}",
            '--template-body', "${TemplateFile}"
            '--region', "${AwsRegion}",
            '--profile', "${AwsProfile}"
        )

        Write-Host $Output


    }
    END {

    }
}

function Invoke-DeleteChangeSet {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [String]$StackName,
        [String]$ChangeSetName,
        [String]$AwsRegion,
        [String]$AwsProfile
    )
    BEGIN {

    }
    PROCESS {
        $Output = Invoke-SystemCommand -Cmd $AWS_CLI_PATH -CmdArgs @(
            'cloudformation', 'delete-change-set', 
            '--stack-name', "${StackName}",
            '--change-set-name', "${ChangeSetName}",
            '--region', "${AwsRegion}",
            '--profile', "${AwsProfile}"
        )

        Write-Host $Output


    }
    END {

    }
}





function Invoke-DescribeChangeSet {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [String]$StackName,
        [String]$ChangeSetName,
        [String]$PagingToken=$null,
        [String]$TemplateFile,
        [String]$AwsRegion,
        [String]$AwsProfile
    )
    BEGIN {

    }
    PROCESS {
        $CmdArgs = @(
            'cloudformation', '--describe-change-set', 
            '--stack-name', "${StackName}",
            '--change-set-name', "${ChangeSetName}",
            '--template-body', "${TemplateFile}"
        )
        if ($PagingToken -ne $null) {
            $CmdArgs += @(
                '--starting-token', 'PagingToken'
            ) 
        }

        $CmdArgs += @(
            '--region', "${AwsRegion}",
            '--profile', "${AwsProfile}"
        )

        $Output = Invoke-SystemCommand -Cmd $AWS_CLI_PATH -CmdArgs $CmdArgs

        Write-Host $Output


    }
    END {

    }
}

function Wait-ForAnyPendingStackSetChangeToComplete {

}


# Get-StackStatus
function Get-StackStatus {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [String]$StackName,
        [String]$AwsRegion,
        [String]$AwsProfile
    )
    BEGIN {

    }
    PROCESS {
        try {
            $Output = Invoke-DescribeStacks -StackName $StackName -AwsRegion $AwsRegion -AwsProfile $AwsProfile
            if ($Output.ExitCode -ne 0) {
                New-ErrorException -ErrorMessage $Output.StdErr
            }
            $JsonOutput = $Output.StdOut | ConvertFrom-Json
            $StackStatus = $JsonOutput.Stacks[0].StackStatus
    
            Write-Output $StackStatus    
        } catch [NoStack] {
            Write-Output "NoStack"
        }

    }
    END {

    }
}


# Invoke-DeleteStack

# Invoke-CreateStackSet
# Invoke-ApplyStackSet
# Invoke-StackSetStatus
# Invoke-DescribeStackSet
# Invoke-DeleteStackSet


function Test-StackExists {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [String]$StackStatus
    )
    PROCESS {
        $Status = $true
        if (@("NoStack") -contains $StackStatus)
        {
            $Status = $false
        }
        LOG "CFT002" "$StackStatus" "$Status"
        $Status | Write-Output
    }
}

function Test-StackChanging {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [String]$StackStatus
    )
    PROCESS {
        $Status = $false
        if ($StackStatus -match '.+IN_PROGRESS')
        {
            $Status = $true
        }
        LOG "CFT001" "$StackStatus" "$Status"
        $Status | Write-Output
    }
}

function Wait-ForAnyPendingStackChangeToComplete {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [String]$StackName,
        [String]$AwsRegion,
        [String]$AwsProfile
    )
    BEGIN {
    }
    PROCESS {
        LOG 'CFT005' "$StackName"
        $CurrentStatus = Get-StackStatus -StackName $StackName -AwsRegion $AwsRegion -AwsProfile $AwsProfile
        LOG 'CFT003' "$StackName" "$CurrentStatus"

        While (Test-StackChanging -StackStatus $CurrentStatus)
        {
            Start-Sleep -Seconds 5
            $NextStatus = Get-StackStatus -StackName $StackName -AwsRegion $AwsRegion -AwsProfile $AwsProfile
            if ($NextStatus -ne $CurrentStatus) {
                LOG 'CFT004' "$StackName" "$NextStatus"
            }
            $CurrentStatus = $NextStatus
            LOG 'CFT003' "StackName" "CurrentStatus"
        }
        Write-Output $CurrentStatus
    }
    END {

    }            
}


function Deploy-Stack {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [String]$StackName,
        [String]$TemplateFile,
        [String]$AwsRegion,
        [String]$AwsProfile
    )
    BEGIN {

    }
    PROCESS {
        $StackStatus = Wait-ForAnyPendingStackChangeToComplete -StackName $StackName -AwsRegion $AwsRegion -AwsProfile $AwsProfile

        If(Test-StackExists -StackStatus $StackStatus) {
            # Update
            $Result = Invoke-UpdateStack -StackName "${StackName}" -AwsRegion "${AwsRegion}" -AwsProfile "${AwsProfile}" -TemplateFile "${TemplateFile}"
        } else {
            if ($StackStatus -ne "NoStack") {
                # Delete
                $Result = Invoke-DeleteStack -StackName "${StackName}" -AwsRegion "${AwsRegion}" -AwsProfile "${AwsProfile}"
                $Result.StdOut
        
            }
            # Create
            $Result = Invoke-CreateStack -StackName "${StackName}" -AwsRegion "${AwsRegion}" -AwsProfile "${AwsProfile}" -TemplateFile "${TemplateFile}"
            $Result.StdOut
        }
        $StackStatus = Wait-ForAnyPendingStackChangeToComplete -StackName $StackName -AwsRegion $AwsRegion -AwsProfile $AwsProfile

    }
    END {

    }
}


# Remove-Stack
function Remove-Stack {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [String]$StackName,
        [String]$AwsRegion,
        [String]$AwsProfile
    )
    BEGIN {
        try {
            $StackStatus = Wait-ForAnyPendingStackChangeToComplete -StackName $StackName -AwsRegion $AwsRegion -AwsProfile $AwsProfile
            if ($StackStatus -eq "NoStack")
            {
                # No Stack to remove.
                return
            }
            $Result = Invoke-DeleteStack -StackName "${StackName}" -AwsRegion "${AwsRegion}" -AwsProfile "${AwsProfile}"


        }
        catch {
            <#Do this if a terminating exception happens#>
        }

        $StackStatus = Get-StackStatus -StackName "${StackName}" -AwsRegion "${AwsRegion}" -AwsProfile "${AwsProfile}"

        If(Test-StackExists -StackStatus $StackStatus) {
            
        }

    }
    PROCESS {
    }
    END {
    
    }
}



function Update-StackUsingChangeSets {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [String]$StackName,
        [String]$TemplateFile,
        [String]$AwsRegion,
        [String]$AwsProfile
    )
    BEGIN {
    }
    PROCESS {
        #  All stack operations should have finished, and the stack is in a stable state that
        #  can be updated.

        # A changeset needs a unique ID.  We ensure uniqueness by using a GUID.
        $ChangeSetName = "{0}-{1}" -f $StackName, (New-Guid)


        #  Trigger Create-StackSet.
        Invoke-CreateChangeSet -StackName $StackName -ChangeSetName $ChangeSetName -TemplateFile $TemplateFile -AwsRegion $AwsRegion -AwsProfile $AwsProfile

        #  Review StackSet contents
        $ BlockingResources = Get-ChangeSet-Details | Select-StatefullResources

        #  Apply StackSet
        Invoke-CreateChangeSet -StackName $StackName -ChangeSetName $ChangeSetName -AwsRegion $AwsRegion -AwsProfile $AwsProfile

        #  Wait for StackSet to be applied
        Wait-ForAnyPendingStackChangeToComplete -StackName $StackName -AwsRegion $AwsRegion -AwsProfile $AwsProfile

        #  Delete ChangeSet
        Invoke-DeleteChangeSet -StackName $StackName -ChangeSetName $ChangeSetName -AwsRegion $AwsRegion -AwsProfile $AwsProfile

    }
    END {

    }
}
