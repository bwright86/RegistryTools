# Tests to perform for Set-RegistryObject.

Import-Module ..\RegistryTools

Describe "Set-RegistryObject" {
    Context "checks that registry key is updated." {
        
        # Path, property and text to test with.
        $regKey = HKEY_LOCAL_MACHINE\SOFTWARE\Brent-Test\Test1\Settings
        $regValue = "Description"
        $testValue = "This is a description."

        # Change the registry key value to something else.
        Set-ItemProperty -Path $regKey -Name $regValue -Value "Before test text."
        

        It "Updates a registry key with the modified RegistryObject" {
            
            # Get the registry key and all properties, only the single level.
            $result = $regKey | ConvertFrom-Registry -Levels 0
            
            # Update the object property.
            $result.$regValue = $testValue
            
            # Update the registry with the modified data.
            $result | Set-RegistryObject

            # Test that the updated text is present in the registry.
            Get-ItemProperty -Path $regKey -Name $regValue | should be $testValue

        }
    }
}