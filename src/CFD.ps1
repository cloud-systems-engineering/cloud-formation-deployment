[CmdletBinding(PositionalBinding=$false)]
param(
    [String]$LogLevel,
    [String]$LogLevel_Internal,

    [String]$ConfigRootPath,
    [String]$ConfigFile,
    [String]$ConfigParamsPath,
    [String]$ConfigCloudFormationPath

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

##############################################################################
##############################################################################

# Process the params into a structure
$CFD_Args = @{
    # Logging
    ApplicationName = "CFD"
    LogLevel = $LogLevel
    LogLevel_Internal = $LogLevel_Internal

    # Configuration files
    ConfigRootPath = $ConfigRootPath
    ConfigFile = $ConfigFile
    ConfigParamsPath = $ConfigParamsPath
    ConfigCloudFormationPath = $ConfigCloudFormationPath
}






function Invoke-CFD {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [hashtable]$CFD_Args
    )
    BEGIN {
        . "${PSScriptRoot}/StructuredLogs.ps1" $CFD_Args


        #
        #  Register the CFD log entries
        #
        REGISTER_LOG 'CFD001' Debug "Imported Powershell script='{0}'." 1
        REGISTER_LOG 'CFD100' Info "Processing stack='{0}'." 1
        REGISTER_LOG 'CFD900' Fatal "The application is exiting after an error" 0
        REGISTER_LOG 'CFD901' Error "There is no active AWS session. Please run 'aws sso login'" 0
        REGISTER_LOG 'CFD902' Error "There has been an unhandled exception containing the message='{0}'" 1

        LOG "CFD001" "StructuredLogs.ps1"

        . "${PSScriptRoot}/Configuration.ps1" $CFD_Args
        LOG "CFD001" "Configuration.ps1"

        . "${PSScriptRoot}/Exec.ps1"
        LOG "CFD001" "Exce.ps1"

        . "${PSScriptRoot}/CloudFormation.ps1"
        LOG "CFD001" "CloudFormation.ps1"

    }
    PROCESS {
        try {
            $CP = New-ConfigurationParams -CmdArgs $CFD_Args
        
            # . "${Configuration}"
            # . "/Users/cse/Repos/cse/cloud-formation-deployment/src/Configuration.ps1"
            
            
            $Data = Read-ConfigurationYaml -CP $CP
            
            $Data.Stacks | ForEach-Object {
                $StackName = $_.Name
                Deploy-Stack -StackName $StackName -TemplateFile "file://examples/cf/${StackName}.yaml" -AwsRegion 'ap-southeast-2' -AwsProfile 'pct-cdf2-sandbox'
            }
        } catch [AwsSsoTokenExpired] {
            LOG 'CFD901'
            throw $_
        } catch {
            LOG 'CFD902' $_
            throw $_
        }
    }
    END {
    
    }
}

try {
    Invoke-CFD -CFD_Args $CFD_Args
} catch {
    LOG 'CFD900'
}
