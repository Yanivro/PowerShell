#This script creates an Azure RM Windows Image from a syspreped VM.

param
(
 # Subscription ID for Azure.
    [Parameter(Mandatory = $true)]
    [String]
    $vmname,

   # Name of the resource group the VM will be deployed to.
    [Parameter(Mandatory = $true)]
    [String]
    $rgname,
	
	   # Name of the service the VMs will be deployed to. If the service exists, the 
    # VMs will be deployed ot this service, otherwise, it will be created.
    [Parameter(Mandatory = $true)]
    [String]
    $subscriptionID,
    
    # containter the Image will reside in 

    [Parameter(Mandatory = $true)]
    [String]
    $imageContainer,
    
    # Name of the VHD file.
    [Parameter(Mandatory = $true)]
    [String]
    $VHDname)
	
#Add the azure account to the session
Login-AzureRmAccount

# Pick the current subscription	
Select-AzureSubscription -subscriptionid $subscriptionID

Set-AzureRmContext -subscriptionid $subscriptionID

stop-AzureRmVM -ResourceGroupName $rgname -Name $vmname

$VMStatus=1
Do {
$VMDetail = Get-AzureRmVM -ResourceGroupName $rgname -Name $VMName -Status

        foreach ($VMStatus in $VMDetail.Statuses)
        { 
            if($VMStatus.Code.CompareTo("PowerState/deallocated") -eq 0)
            {
              
            }
        }
Start-Sleep -Seconds 30

 } # End of 'Do'
While ($VMStatus.Code.CompareTo("PowerState/deallocated") -ne 0)

 write-output "Machine has stopped...Proceeding."

Set-AzureRmVm -ResourceGroupName $rgname -Name $vmname -Generalized

Save-AzureRmVMImage -ResourceGroupName $rgname -VMName $vmname -DestinationContainerName $imageContainer -VHDNamePrefix $VHDname 
