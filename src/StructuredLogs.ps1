[CmdletBinding(PositionalBinding=$false)]
param(
    [Parameter(Mandatory=$True)][String]$ApplicationName,
    [Parameter(Mandatory=$False)][String]$LogLevel = "Info",
    [Parameter(Mandatory=$False)][String]$LogLevel_Internal = "Debug"
)

Set-Variable -Scope Script -Name "LogReportingLevel_Internal" -Value "$LogLevel_Internal"

# Valid Log Levels
enum LogLevel {
    Trace = 100
    Debug = 200
    Info = 300
    Notice = 400
    Warn = 500
    Error = 600
    Fatal = 700
}

class LogUtils {
    static hidden [system.collections.generic.dictionary[LogLevel, string]] $LogLevelStringDictionary
    static hidden [system.collections.generic.dictionary[string, LogLevel]] $LogLevelEnumDictionary
    static hidden [system.collections.generic.dictionary[LogLevel, string]] $LogLevelColourDictionary

    static LogUtils() {
        [LogUtils]::LogLevelStringDictionary =
            [system.collections.generic.dictionary[LogLevel, string]]::new()
            [LogUtils]::LogLevelEnumDictionary =
            [system.collections.generic.dictionary[string, LogLevel]]::new()
        [LogUtils]::LogLevelColourDictionary =
            [system.collections.generic.dictionary[LogLevel, string]]::new()

        #  Names for log levels
        [LogUtils]::LogLevelStringDictionary.Add([LogLevel]::Trace, "Trace")
        [LogUtils]::LogLevelStringDictionary.Add([LogLevel]::Debug, "Debug")
        [LogUtils]::LogLevelStringDictionary.Add([LogLevel]::Info, "Info")
        [LogUtils]::LogLevelStringDictionary.Add([LogLevel]::Notice, "Notice")
        [LogUtils]::LogLevelStringDictionary.Add([LogLevel]::Warn, "Warn")
        [LogUtils]::LogLevelStringDictionary.Add([LogLevel]::Error, "Error")
        [LogUtils]::LogLevelStringDictionary.Add([LogLevel]::Fatal, "Fatal")                    

        [LogUtils]::LogLevelEnumDictionary.Add("Trace", [LogLevel]::Trace)
        [LogUtils]::LogLevelEnumDictionary.Add("Debug", [LogLevel]::Debug)
        [LogUtils]::LogLevelEnumDictionary.Add("Info", [LogLevel]::Info)
        [LogUtils]::LogLevelEnumDictionary.Add("Notice", [LogLevel]::Notice)
        [LogUtils]::LogLevelEnumDictionary.Add("Warn", [LogLevel]::Warn)
        [LogUtils]::LogLevelEnumDictionary.Add("Error", [LogLevel]::Error)
        [LogUtils]::LogLevelEnumDictionary.Add("Fatal", [LogLevel]::Fatal)                    


        # Colours for log levels
        [LogUtils]::LogLevelColourDictionary.Add([LogLevel]::Trace, "Gray")
        [LogUtils]::LogLevelColourDictionary.Add([LogLevel]::Debug, "Gray")
        [LogUtils]::LogLevelColourDictionary.Add([LogLevel]::Info, "White")
        [LogUtils]::LogLevelColourDictionary.Add([LogLevel]::Notice, "White")
        [LogUtils]::LogLevelColourDictionary.Add([LogLevel]::Warn, "Yellow")
        [LogUtils]::LogLevelColourDictionary.Add([LogLevel]::Error, "Red")
        [LogUtils]::LogLevelColourDictionary.Add([LogLevel]::Fatal, "Red")
    }

    static [string] StringFromLogLevel([LogLevel]$LogLevel) {
        if (-not [LogUtils]::LogLevelStringDictionary.ContainsKey($LogLevel)) {
            #!TODO: Throw exception
        }
        return [LogUtils]::LogLevelStringDictionary[$LogLevel]
    }

    static [LogLevel] LogLevelFromString([string]$LogLevel) {
        if (-not [LogUtils]::LogLevelEnumDictionary.ContainsKey($LogLevel)) {
            #!TODO: Throw exception
        }
        return [LogUtils]::LogLevelEnumDictionary[$LogLevel]
    }


    static [string] ColourFromLogLevel([LogLevel]$LogLevel) {
        $ColourString = "Blue"
        if ([LogUtils]::LogLevelStringDictionary.ContainsKey($LogLevel)) {
            $ColourString = [LogUtils]::LogLevelColourDictionary[$LogLevel]            
        }
        return $ColourString
    }
}

function SetLogLevel {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [String]$LogLevel
    )
    BEGIN {
    }
    PROCESS {
        $LogLevelAsEnum = [LogUtils]::LogLevelFromString($LogLevel)
        Set-Variable -Scope Script -Name "ReportingLogLevel" -Value $LogLevelAsEnum
    }
    END {

    }
}


class LogMessageRegister {
    static hidden [LogMessageRegister] $Singleton
    hidden [system.collections.generic.dictionary[string, LogMessageTemplate]] $LogMessageDictionary

    static LogMessageRegister() {
        [LogMessageRegister]::Singleton = [LogMessageRegister]::new()
    }

    LogMessageRegister() {
        $this.LogMessageDictionary = 
            [system.collections.generic.dictionary[string, LogMessageTemplate]]::new()
    }    
    
    static [LogMessageRegister] Instance() {
        return [LogMessageRegister]::Singleton
    }

    static [void]Add(
        [string]$LogRef,
        [LogLevel]$LogLevel,
        [string]$MessageFormat,
        [int]$ArgCount

    ) {
        [LogMessageRegister]::Instance().InternalAdd($LogRef, $LogLevel, $MessageFormat, $ArgCount)
    }
    
    hidden [void]InternalAdd(
        [string]$LogRef,
        [LogLevel]$LogLevel,
        [string]$MessageFormat,
        [int]$ArgCount
    ) {
        $LogMessageTemplate = [LogMessageTemplate]::new($LogRef, $LogLevel, $MessageFormat, $ArgCount)
        if ($this.LogMessageDictionary.ContainsKey($LogRef)) {
            $this.LogMessageDictionary[$LogRef] = $LogMessageTemplate
        } else {
            $this.LogMessageDictionary.Add($LogRef, $LogMessageTemplate)
        }
    }

    [LogMessageTemplate]Get(
        [string]$LogRef
    ) {
        $LogMessageTemplate = $null

        if ($this.LogMessageDictionary.ContainsKey($LogRef))
        {
            $LogMessageTemplate = $this.LogMessageDictionary[$LogRef]
        }
        if ($null -eq $LogMessageTemplate -and $LogRef -match '^LOG[0-9]{3}$')
        {
            $LogMessageTemplate = [LogMessageTemplate]::new(
                [LogLevel]::Debug, "{0}", 1
            )
        } elseif ($null -eq $LogMessageTemplate)
        {
            throw [Exception]::new("Invalid Log Reference")
        }
        return $LogMessageTemplate
    }
}

class LogPresenter {
    static [string] $RawMessageTemplate

    static LogPresenter() {
        [LogPresenter]::RawMessageTemplate = "[{0}] {1}"
    }

    static [void] LOG(
        [LogMessageTemplate]$MessageTemplate,
        [LogLevel]$MinVisibleLogLevel,
        [String[]]$LogValues
    ) {
        if ([LogPresenter]::isVisible($MessageTemplate, $MinVisibleLogLevel)) {
            $FormattedMessage = [LogPresenter]::Generate($MessageTemplate, $LogValues)
            [LogPresenter]::Emit($MessageTemplate, $FormattedMessage)    
        }
    }

    hidden static [boolean] isVisible(
        [LogMessageTemplate] $MessageTemplate,
        [LogLevel]$MinVisibleLogLevel
    ) {
        $LogLevel = $MessageTemplate.GetLogLevel()

        # Is the message importance above the the reporting threashold?
        return ($LogLevel -ge $MinVisibleLogLevel)
    }

    hidden static [string] Generate(
        [LogMessageTemplate] $MessageTemplate,
        [String[]] $LogValues
    ) {
        # Populate the log message args
        $MessageFormat = $MessageTemplate.GetMessageFormat()
        $Message = $MessageFormat -f $LogValues

        $LogLevel = $MessageTemplate.GetLogLevel()
        # Format the raw message
        $GeneratedMessage = [LogPresenter]::RawMessageTemplate -f $LogLevel, $Message
        return $GeneratedMessage
    }

    hidden static [void] Emit(
        [LogMessageTemplate] $MessageTemplate,
        [string]$Message
    ) {
        $LogLevel = $MessageTemplate.GetLogLevel()
        # Output the message
        Write-Host $Message -ForegroundColor ([LogUtils]::ColourFromLogLevel($LogLevel))        
    }
}


class LogMessageTemplate {
    hidden [string] $LogRef
    hidden [LogLevel] $LogLevel
    hidden [string] $MessageFormat
    hidden [int] $ArgCount

    LogMessageTemplate(
        [string] $LogRef,
        [LogLevel]$LogLevel,
        [string]$MessageFormat,
        [int]$ArgCount
    ) {
        $this.LogRef = $LogRef
        $this.LogLevel = $LogLevel
        $this.MessageFormat = $MessageFormat
        $this.ArgCount = $ArgCount
    }

   [LogLevel] GetLogLevel() {
        return $this.LogLevel
    }

    [string] GetMessageFormat() {
        return $this.MessageFormat
    }
}

#
#  This file uses the LOG_SCRIPT function to log its entries
#  This avoids the bootstrap problem of needing logging to be
#  initialised, to be able to log, but wanting to log the
#  initialisation process.
#
function LOG_SCRIPT {
    [CmdletBinding(PositionalBinding=$true)]
    param(
        [Parameter(Position = 0)][String]$LogRef,
        [Parameter(Position = 1)][LogLevel]$LogLevel,
        [Parameter(
            Mandatory=$False,
            ValueFromRemainingArguments=$true,
            Position = 2
        )][String[]]$LogValues
    )
    BEGIN {

    }
    PROCESS {
        # Generate a standard message template on the fly...
        $MessageTemplate = [LogMessageTemplate]::new($LogRef, $LogLevel, "{0}", 1 )

        $ReportingLevel = (Get-Variable -Scope Script -Name "LogReportingLevel_Internal").Value
        [LogPresenter]::LOG($MessageTemplate, $ReportingLevel, $LogValues)
    }
    END {

    }
}

function LOG {
    [CmdletBinding(PositionalBinding=$true)]
    param(
        [Parameter(Position = 0)][String]$LogRef,
        [Parameter(
            Mandatory=$False,
            ValueFromRemainingArguments=$true,
            Position = 1
        )][String[]]$LogValues
    )
    BEGIN {
    }
    PROCESS {
        [LogMessageTemplate]$MessageTemplate = [LogMessageRegister]::Instance().Get($LogRef)
        $ReportingLevel = (Get-Variable -Scope Script -Name "ReportingLogLevel").Value
        [LogPresenter]::LOG($MessageTemplate, $ReportingLevel, $LogValues)
    }
    END {

    }            
}


#  Initialize Logging
try {

    #
    #   Phase 1 - Set the log level for log messages.
    #
    SetLogLevel -LogLevel $LogRef


    #
    #  Phase 2 - register log messages relating to logging.
    #

    [LogMessageRegister]::Add('LOG001', [LogLevel]::Notice, "Logging started for application='{0}'", 1)    
    [LogMessageRegister]::Add('LOG002', [LogLevel]::Notice, "Logging is now capturing events with at least the logLevel='{0}' severity", 1)

    #
    #  Phase 3 - Record that logging has been enabled.
    #

    LOG "LOG001" $ApplicationName
}
catch {
    Write-Host $_
    throw
}


