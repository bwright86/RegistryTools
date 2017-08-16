# Tests to perform for ConvertFrom-Registry.

Import-Module ..\RegistryTools

Describe "ConvertFrom-Registry" {
    $ErrorActionPreference = "silentlycontinue"
    $WarningPreference = "silentlycontinue"

    Context "when path is not a registry key" {

        

        It "Returns an error for invalid PSDrive" {

            $ErrorActionPreference = "silentlycontinue"

            {$result = "C:\Temp" | ConvertFrom-Registry -ErrorAction stop} | Should throw
            #$result | should BeNullOrEmpty

            #$error
        }

    }

    Context "when path does not exist" {
        
        

        It "Returns an error for invalid path" {

            #try {
            { "HKLM:\Softwares" | ConvertFrom-Registry -erroraction SilentlyContinue } | should throw

            #throw "no exception"
            #} catch {
            #    $_.fullyqualifiederrorid | should be "PathNotFound,Microsoft.PowerShell.Commands.GetItemCommand"
            #}
            
            #$InvalidPath | Should be "Cannot find path*"
            #$result | should BeNullOrEmpty
        }
    }

    Context "when path is valid, and defaults are used" {

        $result = 'HKCU:\Software\Microsoft\Internet Explorer\Desktop\' | ConvertFrom-Registry
        
        It "Returned object type is [RegistryTools.RegistryObject]" {

            $result.psobject.TypeNames[0] | should be "RegistryTools.RegistryObject"
        }

        It "Contains PSPath that exists" {

            $result.pspath | should exist
        }

    }

    Context "when 3 levels are requested" {
        $result = 'HKCU:\Software\Microsoft\' | ConvertFrom-Registry -Levels 3 -WarningAction SilentlyContinue

        It "Returns an object with 3 levels of key values, including the value name." {
            ($result | Get-Member | ForEach-Object { ($_.name -split "\\" ).count } | Measure-Object -Maximum).Maximum | should be 4
        }

    }

    Context "when 3 subkeys are requested" {
        $maxSubKeys = 3
        $result = 'HKLM:\Software\Microsoft\' | ConvertFrom-Registry -MaxSubKeys $maxSubKeys -WarningAction SilentlyContinue

        It "Returns upto $maxSubKeys subkeys, plus 4 common properties" {
            $result | 
                Get-Member | 
                Where-Object {$_.membertype -eq "NoteProperty"} | 
                ForEach-Object {$_.Name -split "\\" | Select-Object -First 1} | 
                Group-Object | 
                Measure-Object | 
                Select-Object -ExpandProperty Count |
                Should BeLessThan ($maxSubKeys+5)
        }
    }

    Context "confirms path to property exists, using first non-common property in result" {
        
        

        It "Tests existence, when given Path ends w/ a slash" {

            $result = 'HKLM:\Software\Microsoft\' | ConvertFrom-Registry -Levels 1 -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

            $firstNCProp = $result | 
                Get-Member | Where-Object {$_.MemberType -eq "NoteProperty" -and @("PSPath", "PSDrive", "PSParentPath", "PSChildName") -notcontains $_.Name} |
                Select-Object -First 1 -ExpandProperty Name

            Test-Path -Path $(Join-Path -Path $result.pspath -ChildPath $result.$firstNCProp)
        }

        It "Tests existence, when given Path ends w/o a slash" {

            $result = 'HKLM:\Software\Microsoft' | ConvertFrom-Registry -Levels 1 -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

            $firstNCProp = $result | 
                Get-Member | Where-Object {$_.MemberType -eq "NoteProperty" -and @("PSPath", "PSDrive", "PSParentPath", "PSChildName") -notcontains $_.Name} |
                Select-Object -First 1 -ExpandProperty Name

            Test-Path -Path $(Join-Path -Path $result.pspath -ChildPath $result.$firstNCProp)
        }
    }
}