function Initialize-CertifiCatVariables{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Plural because we are initializing all variables at once')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Currently using Write-Host because it supports -NoNewLine')]
    [CmdletBinding()]
    param()

    # Dynamically read the module's definition (i.e. .psm1 file) and extract the default variables we find.
    # This eliminates the need to manually update this function with new default variables
    $varsToCheck = @()
    $foundVars = get-content "$PSModuleRoot\certificat-ps.psm1" | select-string "(\`$script:DEFAULT_(.)*)|(\`$script:VALIDATE_PATTERN(.)*)" -allmatches

    foreach($foundVar in $foundVars.Matches.Value){
        $varToCheck = ($foundVar -split " = ")[0]
        $varToCheck = ($varToCheck -split ":")[1]

        $varsToCheck += $varToCheck
    }

    foreach($varToCheck in $varsToCheck){
        $envVariable = Get-Item "env:\CERTIFICAT_$varToCheck" -ErrorAction SilentlyContinue
        if($null -ne $envVariable){
            # GetEnvironmentVariable already returns the value as a string, but we'll explicitly
            # sanitize it here, just to be sure that we aren't allowing a user to specify
            # something nefarious in the environment variable
            (Get-Variable $varToCheck -Scope Script).Value = [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($envVariable.Value)
        }
    }
}
