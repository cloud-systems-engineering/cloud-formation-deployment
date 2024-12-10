[CmdletBinding(PositionalBinding=$false)]
param(
    [Parameter(Mandatory=$True, Position=0)][Hashtable]$Args
)

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

Import-Module powershell-yaml

[LogMessageRegister]::Add('CFG001', [LogLevel]::Debug, "Using configuration setting for RootPath='{0}'.", 1)
[LogMessageRegister]::Add('CFG002', [LogLevel]::Debug, "Using configuration setting for ConfigFile='{0}'.", 1)
[LogMessageRegister]::Add('CFG003', [LogLevel]::Debug, "Using ConfigFile='{0}'.", 1)
[LogMessageRegister]::Add('CFG004', [LogLevel]::Error, "Cannot find ConfigFile='{0}'.", 1)



class FileNotFoundException : Exception {
    [string] $FileClass
    [string] $FilePath

    FileNotFoundException($FileClass, $FilePath) : base(("Could not find the fileType={0} on path={1}" -f "$FileClass", "$FilePath")) {
        $this.FileClass = $FileClass
        $this.FilePath = $FilePath        
    }
}



#
#  Config file is (in order of priority)
#
#  1 - Parameter Value
#  2 - Environment Variable CFD_CONFIG
#  3 - {CWD}/etc/cdf.yaml
#  4 - /etc/cfd.yaml


class ConfigurationParams {
    [string] $RootPath
    [string] $ConfigFile
    [string] $ParamsPath
    [string] $CloudFormationPath

    ConfigurationParams() {
        $This.RootPath = (Get-Item .).FullName
        $This.ConfigFile = "etc/cfd.yaml"
        $This.ParamsPath = "etc/params"
        $This.CloudFormationPath = "cf"
    }    

}

class GlobalFlags {
    [bool]$Flag1
}

class Trigger {
    [string]$event
}

class Event {
    [string]$name
    [hashtable]$data
}

#  Resource names that contain state data, so should not be allowed to be deleted during a change event.
class StateResource {
    [string]$key
    [string[]]$value
}

class Stack {
    [string]$name
    [string]$region
    [Trigger[]]$on_create
    [Trigger[]]$on_update
    [Trigger[]]$on_create_or_update
    [Trigger[]]$on_destroy
    [Event[]]$events
    [StateResource[]]$state_data
}

#
#  Event Types:
#

#  SetParamValueFromOutput

#  Sync S3 Bucket Contents

#  Empty S3 Bucket for deletion


class Config {
    [GlobalFlags]$Global_Flags
#    [System.Collections.Generic.List[Stack]]$Stacks
    [Stack[]]$Stacks
}


function New-ConfigurationParams {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [Hashtable]$CmdArgs
    )
    BEGIN {

    }
    PROCESS {
        $CP = [ConfigurationParams]::new()
        if ($CmdArgs.ConfigRootPath) {
            Set-RootPath -CP $CP -RootPath $CmdArgs.ConfigRootPath
        }
        if ($CmdArgs.ConfigFile) {
            Set-ConfigFile -CP $CP -ConfigFile $CmdArgs.ConfigFile
        }
        if ($CmdArgs.ConfigParamsPath) {
            Set-ParamsPath -CP $CP -ParamsPath $CmdArgs.ConfigParamsPath
        }
        if ($CmdArgs.ConfigRootPath) {
            Set-CloudFormationPath -CP $CP -CloudFormationPath $CmdArgs.ConfigCloudFormationPath
        }

        $CP | Write-Output
    }
}

function Set-RootPath {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [ConfigurationParams]$CP,
        [string]$RootPath
    )
    PROCESS {
        $CP.RootPath = $RootPath
    }
}

function Set-ConfigFile {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [ConfigurationParams]$CP,
        [string]$ConfigFile
    )
    PROCESS {
        $CP.ConfigFile = $ConfigFile
    }
}

function Set-ParamsPath {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [ConfigurationParams]$CP,
        [string]$ParamsPath
    )
    PROCESS {
        $CP.ParamsPath = $ParamsPath
    }
}

function Set-CloudFormationPath {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [ConfigurationParams]$CP,
        [string]$CloudFormationPath
    )    
    PROCESS {
        $CP.CloudFormationPath = $CloudFormationPath
    }
}




function Read-ConfigurationYaml {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [ConfigurationParams]$CP
    )
    BEGIN {

    }
    PROCESS {
        try {
            LOG "CFG001" $CP.RootPath
            LOG "CFG002" $CP.ConfigFile
    
            $ConfigurationFile = "{0}/{1}" -f $CP.RootPath, $CP.ConfigFile
    
            LOG "CFG003" $ConfigurationFile
    
    
            if ((Test-Path "$ConfigurationFile" -PathType Leaf ) -eq $false)
            {
                # Config file not found
                LOG "CFG004" $ConfigurationFile
                throw [FileNotFoundException]::new("Configuration File", "$ConfigurationFile")
            }
    
            #  Read file contents into memory
            $FileContents = Get-Content $ConfigurationFile -Raw
    
            #  Parse yaml into data structure
            [Config] $Data =  ConvertFrom-Yaml $FileContents
    
            Write-Output $Data
    
        } catch {
            Write-Host $_
            throw
        }
    }
    END {

    }
}
