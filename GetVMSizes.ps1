
##Get all VM sizes names per region in Azure ##

﻿$azurelocations = Get-AzureLocation
$out = @()
foreach ($location in $azurelocations)
{
    $VMSizes = $location.VirtualMachineRoleSizes
    $VMSizesStr = $VMSizes -join ', '
    $props = @{
        Name = $location.Name
        VMSizes = $VMSizesStr}
    $out += New-Object PsObject -Property $props
}

$out | Format-Table -AutoSize -Wrap Name, VMSizes
