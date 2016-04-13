##Before running this script, you must create a new Virtual network.
##to create a new Virtual network, please export the configuration file and edit it with the new virtual network.
##Then use the command : set-AzureVNetConfig -configurationpath x:/xmlfilepath/xmlconfigfile.xml

#Azure Subscription ID
$subid="Fill in the subscriptionID"

#Vnet name
$Vnet="{Please fill in the Virtual network name}"
#subnet name for the VMs"
$dbsubnet="{Please fill in the name of the subnet that the DB servers will reside in}"
$rdpsubnet="{Please fill in the name of the subnet that the RDP server will reside in}"

#Storage account names
$storageapp01="{Please fill in the name of the app01 storage account in all lower case characters - for example 'onedropamdocsapp01'}"
$storagedb01="{Please fill in the name of the app01 storage account in all lower case characters - for example 'onedropamdocsdbst01'}"
$storagedb02="{Please fill in the name of the app01 storage account in all lower case characters - for example 'onedropamdocsdbst02'}"
$storagemediasvc01 = "{Please fill in the name of the app01 storage account in all lower case characters - for example 'onedropamdocsmediasvc01'}"
$storageremote = "{Please fill in the name of the app01 storage account in all lower case characters - for example 'onedropamdocsremote01'}"

#Cloud services names
$csdb= "{Please fill in the name of the cloud service for the database servers  - example - onedrop-amdocs-db-cs}"
$csrdp="{Please fill in the name of the cloud service for the database servers  - example -onedrop-amdocs-rdp-cs}"
$Location="{Fill in the location  - example West Europe}"

##VM Properties

#VM Image name
$dbimage="0b11de9248dd4d87b18621318e037d37__RightImage-Ubuntu-14.04-x64-v14.2.1"
$rdpimage="a699494373c04fc0bc8f2bb1389d6106__Windows-Server-2012-R2-20151214-en.us-127GB.vhd"

#VM vhd names:
$vhdnamedb01="Ubuntu-1404db01"
$vhdnamedb02="Ubuntu-1404db02"
$vhdnamerdp="Win2012"

#VM Names(not more than 15 characters long if windows)
$vmdb01="{Please fill in the name of the first DB server - example - OD-Amdocs-DB-Vm01}"
$vmdb02="{Please fill in the name of the second DB server - example - OD-Amdocs-DB-Vm02}"
$vmrdp="{Please fill in the name of RDP server- example - OD-Amdocs-RD-Vm}"

#Availability set name

$AVSname="DBAvset"

#Internal IP addresses

$IpAddressdb01 = {Please fill in the internal IP address you wish the first DB server will have - example 10.0.1.37}
$IpAddressdb02 = {Please fill in the internal IP address you wish the first DB server will have - example 10.0.1.38}
$IpAddressrdp  = {Please fill in the internal IP address you wish the first DB server will have - example 10.0.1.4}


#Credentials for the machines
$User="{Admin username for the servers}"
$Password="{Admin password for the servers}"



#Add azure account:
Add-azureaccount

Select-AzureSubscription -SubscriptionId $subid

#Configure A new Azure Vnet by changing the network-configuration.xml file that can be imported from azure networks section
Set-AzureVNetConfig -ConfigurationPath c:\json\NetworkConfigAmdocs.xml

#Create storage accounts
New-AzureStorageAccount -StorageAccountName $storageapp01 -Label $storageapp01 -Location $Location -Type "Standard_LRS"

New-AzureStorageAccount -StorageAccountName $storagedb01 -Label $storagedb01 -Location $Location -Type "Standard_LRS"

New-AzureStorageAccount -StorageAccountName $storagedb02 -Label $storagedb02 -Location $Location -Type "Standard_LRS"

New-AzureStorageAccount -StorageAccountName $storagemediasvc01 -Label $storagemediasvc01 -Location $Location -Type "Standard_LRS"

New-AzureStorageAccount -StorageAccountName $storageremote -Label $storageremote -Location $Location -Type "Standard_LRS"

#Create new cloud services for both machine types:
New-AzureService -ServiceName $csdb  -Location $Location -Label $csdb
New-AzureService -ServiceName $csrdp -Location $Location -Label $csrdp


#Create the virtual Machines in the exsting Vnet with the storageaccount and cloud service

#First, the Ubuntu VMs

#Set the current storage account as demanded by the VM demployment command
Set-AzureSubscription -SubscriptionId $subid -CurrentStorageAccountName $storagedb01


#Set up and create the VMs
$newVM = New-AzureVMConfig -Name $vmdb01 -InstanceSize Standard_DS2   -ImageName $dbimage -AvailabilitySetName $AVSname -HostCaching ReadWrite -DiskLabel "OS"  -MediaLocation "https://$storagedb01.blob.core.windows.net/vhds/$vhdnamedb01.vhd" | Add-AzureProvisioningConfig -Linux -LinuxUser $User –Password $Password ` |
 Set-AzureSubnet -SubnetNames $dbsubnet
 New-AzureVM -VMs $newVm -vnetname $Vnet -ServiceName $csdb

Set-AzureSubscription -SubscriptionId $subid -CurrentStorageAccountName $storagedb02

$newVM2 = New-AzureVMConfig -Name $vmdb02 -InstanceSize Standard_DS2   -ImageName $dbimage -AvailabilitySetName $AVSname -HostCaching ReadWrite -DiskLabel "OS"  -MediaLocation "https://$storagedb01.blob.core.windows.net/vhds/$vhdnamedb02.vhd" | Add-AzureProvisioningConfig -Linux -LinuxUser $User -Password $Password ` |
 Set-AzureSubnet -SubnetNames $dbsubnet
 New-AzureVM -VMs $newVm2 -vnetname $Vnet -ServiceName $csdb

#Now the Windows RDP VM
Set-AzureSubscription -SubscriptionId $subid -CurrentStorageAccountName $storageremote
 
$newVM3 = New-AzureVMConfig -Name $vmrdp -InstanceSize Standard_D2  -ImageName $rdpimage -HostCaching ReadWrite -DiskLabel "OS"  -MediaLocation "https://$storageremote.blob.core.windows.net/vhds/$vhdnamerdp.vhd" | Add-AzureProvisioningConfig -Windows -AdminUsername $User -Password  $Password ` |
 Set-AzureSubnet -SubnetNames $rdpsubnet
 New-AzureVM -VMs $newVm3 -vnetname $Vnet -ServiceName $csrdp

 
  Get-AzureVM -ServiceName $csdb -Name $vmdb01 `
| Set-AzureStaticVNetIP -IPAddress $IpAddressdb01 `
| Update-AzureVM

 Get-AzureVM -ServiceName $csdb -Name $vmdb02 `
| Set-AzureStaticVNetIP -IPAddress $IpAddressdb02 `
| Update-AzureVM

 Get-AzureVM -ServiceName $csdb -Name $vmrdp `
| Set-AzureStaticVNetIP -IPAddress $IpAddressrdp `
| Update-AzureVM