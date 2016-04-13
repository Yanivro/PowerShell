#Add data-disks to Azure VM - ASM(Classic) mode.


param
(
 # Subscription ID for Azure.
    [Parameter(Mandatory = $true)]
    [String]
    $SubscriptionID,

   # Name of the service the VMs exists in.
    [Parameter(Mandatory = $true)]
    [String]
    $CloudService,
    
    # The computer name for the SQL server.
    [Parameter(Mandatory = $true)]
    [String]
    $VMName,
    
    # Disk size in GigaBytes - Cannot exceed 1023
    [Parameter(Mandatory = $true)]
    [Int]
    $diskSizeInGB,
	
    # User name for the Machine.
    [Parameter(Mandatory = $true)]
    [String]
    $storageAccountName,

	# Number of data disks to add to the Machine.
    [Parameter(Mandatory = $true)]
    [Int]
    $numberOfDisks,


$CloudService="hub-prod-cb0"
$VMname="epic-prod-cb4"
$storageAccountName="epicproductioncouchbase"


Select-AzureSubscription -SubscriptionId $subscriptionID

$storage=get-azurestorageaccount -storageaccountname $storageaccountname

Set-AzureSubscription -Subscriptionid $subscriptionID -CurrentStorageAccountName $storage.StorageAccountName

$vm1=Get-AzureVM -ServiceName $CloudService -Name $VMname 

 Get-AzureRmStorageAccount

	for($index=0; $index -lt $numberOfDisks; $index++ )
 {
    $label = "Data disk " + $index
    $vm1=$vm1 | Add-AzureDataDisk -CreateNew -DiskSizeInGB $diskSizeInGB -DiskLabel $label -LUN $index
	
}	

$vm1 |Update-AzureVM