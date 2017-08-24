<#
.Synopsis
   A function to retrieve properties from registry key(s), and convert it and all subkeys into an object.
.DESCRIPTION
   The path given will be the start of the search, and it will recursively search subkeys for properties to return.

   Default number of levels to recursively search is 2 levels. Use the -Levels parameter to search deeper.
   Default number of subkeys to return are 10 subkeys. Use the -MaxSubKeys parameter to return more subkeys.

   Note: Be aware that this returns properties of subkeys, if a subkey contains no properties it may not be seen in the results.
.EXAMPLE
   Example of how to use this cmdlet
.EXAMPLE
   Another example of how to use this cmdlet
.INPUTS
   Inputs to this cmdlet (if any)
.OUTPUTS
   Output from this cmdlet (if any)
.NOTES
   Updates:

   08/23/2017 - Brent Wright - Fixed an issue when registry values are retrieved from the input key. 
                               The value is now stored without a relative path, indicating the value belongs in the root key.
.COMPONENT
   The component this cmdlet belongs to

.FUNCTIONALITY
   The functionality that best describes this cmdlet
#>

function ConvertFrom-Registry {
    [cmdletbinding()]
    param(
    # Path to the base key in registry.
    [Parameter(Mandatory=$true,
               Position=0,
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$true)]
    [Alias("PSPath")]
    [string]
    $Path,
    # Number of levels to retrieve properties from. Default = 3
    [int]
    $Levels = 2,
    # Maximum number of subkeys to explore.
    [int]
    $MaxSubKeys = 10
    )

    Write-Verbose "Path given: $Path"

    # Retrieve the item from the path given.
    $regKey = Get-Item $Path -ErrorAction Stop

    # Check that path leads to a valid item.
    if ($regKey -is [Microsoft.Win32.RegistryKey]) {
        
        # Retrieves values in the key, and recurses through some level of subkeys for values.
        $results = RegistryObjectHelper -Path $regKey -Level $Levels -MaxSubKeys $MaxSubKeys

    # Otherwise, exit with the error thrown by Get-Item.
    } else {
        Write-Error -Category InvalidArgument -Message "Path does not point to a registry key."
        return
    }

    #$dupValueProps = $results | foreach {
    #    $_ | Get-Member | Where-Object { $_.membertype -eq "NoteProperty" } } |
    #    Group-Object -Property Name | Where-Object {$_.count -gt 1} | select -ExpandProperty Name
        

    $outputParams = [ordered]@{
        "PSTypeName" = "RegistryTools.RegistryObject";
        "PSPath" = $regKey.PSPath;
        "PSDrive" = $regKey.PSDrive;
        "PSParentPath" = $regKey.PSParentPath;
        "PSChildName" = $regKey.PSChildName;
    }

    foreach ($key in $results) {
        
        # Get a list of properties from each key, excluding the common properties.
        $propList = $key | Get-Member | 
            Where-Object { $_.MemberType -eq "NoteProperty"} |
            Select-Object -ExpandProperty Name | 
            Where-Object { @("PSPath","PSChildName", "PSParentPath","PSProvider") -notcontains $_}
        
        # Add the values to the output.
        foreach ($prop in $propList) {
            
            <#
            # Get the common properties for the key value.
            $propParams = @{
                'PSPath' = $key.PSPath;
                'PSChildName' = $key.PSChildName;
                'PSParentPath' = $key.PSParentPath;
                'PSProvider' = $key.PSProvider;
            }

            $propName  = ""

            # Check if value has already been stored from previous key.
            if ($dupValueProps -contains $prop) {

                $propName = "$($key.PSChildname)\$prop"
                
                # Add the name of the parent key to keep property names unique.
                $propParams += @{$propName = $key.$prop;}

            } else {
                
                $propName = "$prop"
                
                # Add the name of the property and value.
                $propParams += @{$propName = $key.$prop;}
                
            }

            # Add the value to the output hashtable.
            $outputParams += @{$propName = $(new-object psobject -Property $propParams) }

            #>

            # Removes the ending "\" in the path, if given in the parameters.
            $regKeyPath = $regKey.pspath -replace "\\$",""

            # Get the root path, based on the input registry key.
            $rootPath = $key.PSPath.substring($regKeyPath.length+1)

            # If rootpath is blank, just store the property name.
            if ($rootPath -eq "") {
                $propKey = $prop
            
            # Otherwise, join the relative path with the property name.
            } else {
                $propKey = Join-path $key.PSPath.substring($regKeyPath.length+1) $prop
            }

            $propValue = $key.$prop

            $outputParams += @{$propKey = $propValue;}

        }

    }

    # Convert the output to an object, give it a typename, then return it.
    #$outputParams = new-object psobject -Property $outputParams
    #$outputParams.psobject.typenames.insert(0,"RegistryTools.RegistryObject")
    #$outputParams | Write-Output

    new-object psobject -Property $outputParams | Write-Output

}

function RegistryObjectHelper {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true,
                   ValueFromPipeline=$true)]
        [Microsoft.Win32.RegistryKey]
        $Path,
        [int]
        $Level,
        [int]
        $MaxSubKeys

    )

    Begin {   }
    Process {

        Write-Verbose "Getting values from $($Path.pspath)"
        Get-ItemProperty -Path $Path.pspath

        if ($Path.SubKeyCount -gt 0 -and $Level -gt 0) {

            if ($Path.subkeycount -gt $MaxSubKeys) {
                Write-Warning "There are more than $MaxSubKeys subkeys under $(Split-Path $Path.pspath -NoQualifier). To view more, update the -MaxSubKeys parameter. Total subkey count is $($Path.subkeycount)."
            }

            $Path.getSubKeyNames() | 
                Select-Object -First $MaxSubKeys |
                ForEach-Object { Get-Item -path (Join-Path $Path.pspath $_); Write-Verbose "Recursing into $_" } |
                RegistryObjectHelper -Level ($Level - 1) -MaxSubKeys $MaxSubKeys

        }
    }

    End {   }
}