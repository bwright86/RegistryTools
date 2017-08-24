

<#
.Synopsis
   Takes an object, retrieved using "ConvertFrom-Registry" and has been modified, to update the registry with the changes.
.DESCRIPTION
   Takes a [RegistryTools.RegistryObject] and uses each non-common property to check if modifications were made, and to update the registry with the changes.

   Common Properties:
   - PSPath
   - PSDrive
   - PSParentPath
   - PSChildName

   Each non-common property will contain the relative path to the registry value.
   The value of the non-common property will be the data value for the registry value.

   Registry Structure overview:
   . Registry Key
   . . Registry Key
   . . + Registry Value = Data Value

.EXAMPLE
    # Making a simple update to a registry key.
    PS C:\> $update = Get-Item -Path "HKCU:\Software\Microsoft\Internet Explorer\Desktop" | ConvertFrom-Registry
    PS C:\> $update."General\WallpaperSource" = "$env:USERPROFILE\Pictures\newWallpaper.jpg"
    PS C:\> $update | Set-RegistryObject -BackupFile c:\temp\
.EXAMPLE
    # Copying one key to another key, with the same values.
    PS C:\> $update = Get-Item -Path "HKCU:\Software\Key1" | ConvertFrom-Registry
    PS C:\> $update.PSPath = Join-Path $update.PSParentPath "Key2"
    PS C:\> $update | Set-RegistryObject -BackupFile c:\temp\
.INPUTS
   Inputs to this cmdlet (if any)
.OUTPUTS
   Output from this cmdlet (if any)
.NOTES
   Updates:

   08/24/2017 - Brent Wright - Fixed an issue when registry values are being set at the root input key level.
                               Values can be set at the root key level now.
                             - Restore commands are better suited now for the different types of registry key kinds.
.COMPONENT
   The component this cmdlet belongs to
.ROLE
   The role this cmdlet belongs to
.FUNCTIONALITY
   The functionality that best describes this cmdlet
#>

function Set-RegistryObject {
    [cmdletbinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
    Param(
    # A [RegistryTool.RegistryObject] object that has been modified, and will be used to update the registry.
    [Parameter(Mandatory=$true,
               ValueFromPipeline=$true)]
    $InputObject,
    # Path for a backup file to be created. This will contain a script that restores the updated registry values.
    [Parameter(Mandatory=$true)]
    $BackupFile,
    # Forces the registry to be updated with the InputObject values. Also can force the backup file to be created.
    [switch]
    $Force
    )
    
    Begin {
        
        # Common Properties
        $commonProp = @("PSPath", "PSDrive", "PSParentPath", "PSChildName")

        $backupFileHeader = @"
### Registry Restore Script ###

# Username: $env:USERDNSDOMAIN\$env:USERNAME
# Created: $(Get-Date -Format "MMMM dd yyyy @ hh:mm:ss tt")

# Registry Root Path: $($InputObject.PSPath)

# Instructions for use:
# Execute this script to restore the previous registry settings.

"@

        # Check if backup file exists, otherwise create it. Restore commands will be appended to files that already exist.
        if (Test-Path -Path $BackupFile -PathType Leaf) {
            Write-Verbose "Backup file exists, restore commands will be appended."

            $backupFileCreated = $false
        } else {
            
            # Check if path is a directory. Assumption is that a file has an extension.
            if ($([System.IO.FileInfo]$BackupFile).Extension -eq "") {
                
                # Add a filename to the backup path.
                $BackupFileName = "RegistryRestore-$(get-date -Format 'yyyyMMdd_HH.mm.ss').ps1"

                Write-Verbose "BackupFile given is a directory, adding $BackupFileName"

                # Add the filename to the backup file path.
                $backupFile = Join-Path $BackupFile $BackupFileName
            }

            New-Item -Path $BackupFile -ItemType File -Force:$Force | Out-Null

            Write-Verbose "Backup file created, restore commands will be added."

            $backupFileCreated = $true
        }

        # Flag to remove backup file if not used.
        $backupFileUpdated = $false

    }

    End {
        
        # If backup file was created and not used, remove it.
        if ($backupFileUpdated -eq $false -and $backupFileCreated -eq $true) {

            Write-Verbose "Registry not updated, removing created backup file."
            Remove-Item -Path $BackupFile -Force
        }
    }

    Process {
        
        if ($InputObject.psobject.typenames[0] -ne "RegistryTools.RegistryObject") {
            Write-Error -Category InvalidData -Message "InputObject is expected to be a [RegistryTools.RegistryObject] from ConvertFrom-Registry."
        }
        
        # Get a list of registry properties in the object.
        $propertyList = $InputObject | 
            Get-Member -MemberType NoteProperty | 
            Where-Object {$commonProp -notcontains $_.Name} | 
            Select-Object -ExpandProperty Name

        # Process each non-common property in the object.
        $results = $propertyList | CompareRegValueHelper -RegistryObject $InputObject -Force:$Force

        if ($results.RestoreCommands.count -gt 0) {
            
            # Set flag to preserve the backup file.
            $backupFileUpdated = $true

            # Add the restore commands to the backup file.
            $results.RestoreCommands | Out-File -FilePath $backupFile -Encoding ascii -Append
        }

    } # Process

}

Function CompareRegValueHelper {
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory=$true,
                   ValueFromPipeline=$true)]
        $RegObjProperty,
        $RegistryObject,
        [switch]
        $Force
    )

    Begin {

        # Prepare to confirm each registry update.
        $yesToAll = $Force # Sets initial value from -Force
        $noToAll = $false

        # Prepare to confirm after permission denied exception.
        $permYesToAll = $Force # Sets initial value from -Force
        $permNoToAll = $false

        $output = New-Object psobject -Property @{'UpdatedKeys'=@{};'RestoreCommands'=@();}

        $continue = $true

    }

    Process {

        # Continue to process updates, unless permission denied and user aborts.
        if ($continue) {

            # Join the PSPath and the relative path to the property together. Leaving out the registry property name.
            if ($RegObjProperty.contains("\")) {
                $regPath = Join-Path $RegistryObject.pspath $(Split-Path $RegObjProperty -Parent)

                # Extract the registry value name from the object property.
                $propertyName = Split-Path $RegObjProperty -Leaf
            
            # Otherwise, the registry value belongs in the root key.
            } else {
                $regPath = $RegistryObject.pspath

                # The registry value name is the object property.
                $propertyName = $RegObjProperty

            }

            
            
            # Get the current value of the registry property.
            $currentValue = Get-ItemProperty -Path $regPath -Name $propertyName -ErrorAction SilentlyContinue | 
                Select-Object -ExpandProperty $propertyName

            # Capture registry errors on update or creation.
            $registryErrors = $null

            if ($null -eq $currentValue) {

                Write-Verbose "$RegObjProperty property does not exist, and will be created."

                $confirmMessage = "Create $regPath : $propertyName with value `"$($RegistryObject.$RegObjProperty)`""

                # Confirm creating the registry key value.
                if ($PSCmdlet.ShouldContinue("New-ItemProperty",$confirmMessage,[ref]$yesToAll,[ref]$noToAll)) {

                    # Add a remove line to the backup file.
                    $output.RestoreCommands += "Remove-ItemProperty -Path $regPath -Name $propertyName -Force"

                    # Check if registry key exists, otherwise create it.
                    if (!(Test-Path $regPath)) {
                        New-Item -Path $regPath -Force:$Force
                    }

                    New-ItemProperty -Path $regPath -Name $propertyName -Value $RegistryObject.$RegObjProperty -Force:$Force -ErrorVariable registryErrors

                    # Add the created registry key to the output.
                    $output.UpdatedKeys += @{$RegObjProperty = $($RegistryObject.$RegObjProperty)}
                }

            } elseif (@(Compare-Object -ReferenceObject $currentValue -DifferenceObject $RegistryObject.$RegObjProperty).count -eq 0) {
                Write-Verbose "$RegObjProperty property is the same, no update necessary."
            } else {

                Write-Verbose "$RegObjProperty property is different, and will be updated."

                $confirmMessage = "Update $regPath : $propertyName `nOldValue: $currentValue`nNew Value: $($RegistryObject.$RegObjProperty)"

                # Confirm updating the registry key.
                if ($PSCmdlet.ShouldContinue("Set-ItemProperty",$confirmMessage,[ref]$yesToAll,[ref]$noToAll)) {
                    
                    $restoreValue = switch ($currentValue) {
                        {$currentValue -is [array]} {
                            Write-Verbose "Restore value is an [array]."
                            "@(`"$($currentValue -join '`", `"')`")"
                            break
                        }
                        {$currentValue -is [int]} {
                            Write-Verbose "Restore value is an [int]."
                            $currentValue
                            break
                        }
                        default {
                            Write-Verbose "Restore value is something else."
                            "`"$currentValue`""
                        }
                    }

                    # Add the restore line to the backup file.
                    $output.RestoreCommands += "Set-ItemProperty -Path $regPath -Name $propertyName -Value $restoreValue`n`n"
                    
                    # Check if registry key exists, otherwise create it.
                    if (!(Test-Path $regPath)) {
                        New-Item -Path $regPath -Force:$Force
                    }

                    Set-ItemProperty -Path $regPath -Name $propertyName -Value $RegistryObject.$RegObjProperty -Force:$Force -ErrorVariable registryErrors

                    # Add the registry key update to the output.
                    $output.UpdatedKeys += @{ $RegObjProperty = $($RegistryObject.$RegObjProperty) }

                } # If: ShouldContinue - Update Registry

                # Check if errors occured during registry update.
                if ($registryErrors.count -gt 0) {

                    # Process each error.
                    foreach ($err in $registryErrors) {
                        
                        # Perform the checks on whether to continue or stop attempting to update
                        $permissionDenied = $err.CategoryInfo.Category -eq "PermissionDenied"
                        $permDeniedshouldContinue = $PSCmdlet.ShouldContinue("Set-ItemProperty","Unable to update registry key(PermissionDenied), continue updating other registry keys?",[ref]$permYesToAll,[ref]$permNoToAll)
                        
                        # Check if error is "PermissionDenied" and the user wants to continue.
                        if ($permissionDenied -and $permDeniedshouldContinue) {
                            
                            Write-Verbose "Continuing to update registry keys after receiving `"PermissionDenied`" error."
                        
                        } else {
                            

                            $continue = $false

                            return # exit the function
                        } # If: ShouldContinue - PermissionDenied

                    } # Foreach: registryErrors

                } # If: RegistryError > 0

            } # Else: Values are 

        } # If: Continue
    } # Process

    End {   

        Write-Output $output
    }
}