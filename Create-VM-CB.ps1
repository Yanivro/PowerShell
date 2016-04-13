<#--This script creates a VM from an Image in any location. 
It does this by moving the image's VHD to another storage account that is specified And creating an Image in that storage account.
Then, it adds the desired amount of datadisks(Each Machine size has a diffenrent number of maxium attached Disks, please see
https://azure.microsoft.com/en-us/documentation/articles/virtual-machines-linux-sizes/)
After adding the disks, the script connects remotely to the machine, stripes all the data disks into one volume as Drive F,
Creates the directory "F:/data" and "D:/CBlogs" and disables all windows firewall profiles
--#>



####Please run Powershell in an elevated mode(Run as administrator)####

##Vm Sizes##
<#--A5, A6, A7, Basic_A0, Basic_A1, Basic_A2, Basic_A3, Basic_A4, ExtraLarge, Extr
                    aSmall, Large, Medium, Small, Standard_D1, Standard_D1_v2, Standard_D11, Stand
                    ard_D11_v2, Standard_D12, Standard_D12_v2, Standard_D13, Standard_D13_v2, Stan
                    dard_D14, Standard_D14_v2, Standard_D2, Standard_D2_v2, Standard_D3, Standard_
                    D3_v2, Standard_D4, Standard_D4_v2, Standard_D5_v2, Standard_DS1, Standard_DS1
                    1, Standard_DS12, Standard_DS13, Standard_DS14, Standard_DS2, Standard_DS3, Standard_DS4  --#>					
					
param
(
	# Subscription ID for Azure.
    [Parameter(Mandatory = $true)]
    [String]
    $SubscriptionID,

	# Name of the service the VMs will be deployed to. If the service exists, the 
    # VMs will be deployed ot this service, otherwise, it will be created.
    [Parameter(Mandatory = $true)]
    [String]
    $ServiceName,
    
    # The target region the VMs will be deployed to. This is used to create the 
    # affinity group if it does not exist. If the affinity group exists, but in
    # a different region, the commandlet displays a warning.
    [Parameter(Mandatory = $true)]
    [String]
    $DestLocation,
    
    # The computer name for the SQL server.
    [Parameter(Mandatory = $true)]
    [String]
    $VMName,
    
    # Instance size for the SQL server. We will use 4 disks, so it has to be a 
    # minimum Medium size. The validate set checks that.
    [Parameter(Mandatory = $true)]
    [String]
    $VmSize,
	
    # User name for the Machine.
    [Parameter(Mandatory = $true)]
    [String]
    $VmUser,

	# Password for the Machine.
    [Parameter(Mandatory = $true)]
    [String]
    $VMPass,

	# Number of data disks to add to the Machine.
    [Parameter(Mandatory = $true)]
    [Int]
    $numberOfDisks,

	# Name of the Virtual Network to deploy the Machine into.
    [Parameter(Mandatory = $true)]
    [String]
    $VNetName,
	
	# Name of the subnet in the Vnet to deploy the Machine into
    [Parameter(Mandatory = $true)]
    [String]
    $SubnetName,
	
	# Static internal IP to attach to the Machine.
    [Parameter(Mandatory = $true)]
    [String]
    $staticIP,

	# Image Source storage account.
    [Parameter(Mandatory = $true)]
    [String]
    $SrcStorageAccount,

	# Image Destination storage account.
    [Parameter(Mandatory = $true)]
    [String]
    $DestStorageAccount,

	# Image Source container name.
    [Parameter(Mandatory = $true)]
    [String]
    $SrcContainerName,

	# Image Source VHD name.
    [Parameter(Mandatory = $true)]
    [String]
    $SrcImageVHD,

	# Image source name.
    [Parameter(Mandatory = $true)]
    [String]
    $SrcImageName)


#Get VM credentials to use.
$secPassword = ConvertTo-SecureString $VMPass -AsPlainText -Force
$VmCred = New-Object System.Management.Automation.PSCredential($VmUser, $secPassword)


#Is Powershell run in elevated mode?
Function IsAdmin
{
    $IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()` 
        ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator") 
    
    return $IsAdmin
}


if((IsAdmin) -eq $false)
	{
		Write-Error "Must run PowerShell elevated(Run As Administrator) to install WinRM certificates."
		return
	}


<#
.SYNOPSIS
   Installs a Windows Remote Management (WinRm) certificate to the local store
.DESCRIPTION
   Gets the WinRM certificate from the Virtual Machine in the Service Name specified, and 
   installs it on the Current User's personal store. 
.EXAMPLE
    Install-WinRmCertificate -ServiceName testservice -vmName testVm
.INPUTS
   None
.OUTPUTS
   None
#>
function Install-WinRmCertificate($ServiceName, $VMName)
{
    $vm = Get-AzureVM -ServiceName $ServiceName -Name $VMName
    $winRmCertificateThumbprint = $vm.VM.DefaultWinRMCertificateThumbprint
    
    $winRmCertificate = Get-AzureCertificate -ServiceName $ServiceName -Thumbprint $winRmCertificateThumbprint -ThumbprintAlgorithm sha1
    
    $installedCert = Get-Item Cert:\CurrentUser\My\$winRmCertificateThumbprint -ErrorAction SilentlyContinue
    
    if ($installedCert -eq $null)
    {
        $certBytes = [System.Convert]::FromBase64String($winRmCertificate.Data)
        $x509Cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate
        $x509Cert.Import($certBytes)
        
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store "Root", "LocalMachine"
        $store.Open("ReadWrite")
        $store.Add($x509Cert)
        $store.Close()
    }
}


$DestImageName=$SrcImageName+"-"+$DestStorageAccount;
$DestImageVHD=$SrcImageName+".vhd";
$DestContainerName=$SrcContainerName;

#Add the azure account to the session
Add-azureaccount

# Pick the current subscription
Select-AzureSubscription -SubscriptionID $SubscriptionID;
Set-AzureSubscription -SubscriptionId $SubscriptionID -CurrentStorageAccountName $DestStorageAccount;

#Check if storage account exists - if not, create it.
$storagecheck=Get-AzureStorageAccount -StorageAccountName $DestStorageAccount -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

if (!$storagecheck)
{  
    Write-Host "Creating Storage Account $DestStorageAccount"
    New-AzureStorageAccount -StorageAccountName $DestStorageAccount -Location $DestLocation 
}
#Check if cloud service exists - if not, create it.
$servicecheck=Get-AzureService -ServiceName $ServiceName -ErrorAction SilentlyContinue
if (!$servicecheck)
{  
    Write-Host "Creating Cloud Service $ServiceName"
	New-AzureService -Location $DestLocation -ServiceName $ServiceName
}

# Context to source storage
$SrcStgKey = (Get-AzureStorageKey -StorageAccountName $SrcStorageAccount).Primary;
$SrcStorageContext=New-AzureStorageContext -StorageAccountName $SrcStorageAccount -StorageAccountKey $SrcStgKey -Protocol Https;

# Context to destination storage
$DestStgKey = (Get-AzureStorageKey -StorageAccountName $DestStorageAccount).Primary;
$DestStorageContext=New-AzureStorageContext -StorageAccountName $DestStorageAccount -StorageAccountKey $DestStgKey -Protocol Https;

#Create Container in the destination Storage Account

New-AzureStorageContainer -Name $DestContainerName -Context $DestStorageContext -ErrorAction SilentlyContinue

# Copy image blob from source storage to dest storage; note that initial image blob is 
# in "vhds" container not "images", even though going forward, we want to use "images"
$ImageBlob=Start-CopyAzureStorageBlob -Context $SrcStorageContext -SrcBlob $SrcImageVHD -SrcContainer $SrcContainerName -DestContext $DestStorageContext -DestContainer $DestContainerName -DestBlob $DestImageVHD


# Wait for copy to complete

$blobcopy=Get-AzureStorageBlobCopyState -Container $DestContainerName -Blob $DestImageVHD -context $DestStorageContext
 
 while ($blobCopy.Status -eq "Pending")
{
    Start-Sleep -s 30
   $blobcopy=Get-AzureStorageBlobCopyState -Container $DestContainerName -Blob $DestImageVHD -context $DestStorageContext
   $Message = $blobcopy.Source.AbsolutePath + " " + $blobcopy.Status + " {0:N2}%" -f (($blobcopy.BytesCopied/$blobcopy.TotalBytes)*100) 
   Write-Output $Message
}
$ImageBlob | Get-AzureStorageBlobCopyState -WaitForComplete;


# Create image out of the copied blob
# The newly created image will be physically located in the "images" container using the MediaLocation parameter
$DestImageURI = "https://$DestStorageAccount.blob.core.windows.net/$DestContainerName/$DestImageVHD";

Add-AzureVMImage -ImageName $DestImageName -OS "Windows" -MediaLocation  $DestImageURI -Label "Couchbase - VM Windows copy";

# Create a VM using the image just created

$MediaLocation="http://$DestStorageAccount.blob.core.windows.net/$SrcContainerName/$VMName.vhd";

# The newly created VM will be placed in the "vhds" container as instructed via the MediaLocation parameter
$vm= New-AzureVMConfig -Name $VMName -ImageName $DestImageName -InstanceSize $VmSize | 
    Add-AzureProvisioningConfig -Windows -AdminUsername $VmUser -NoRDPEndpoint -Password $VmPass | 
    Add-AzureEndpoint -Name 'VMRDP' -Protocol 'TCP' -LocalPort 3389 -PublicPort 3389 |
    Set-AzureSubnet -SubnetNames $SubnetName | 
	Set-AzureStaticVNetIP -IPAddress $staticIP

#Create the VM	
    New-AzureVM -VMs $vm  -ServiceName $ServiceName -VNetName $VNetName -WaitForBoot

Write-host "VM created - Waiting for it to boot up..."

	#Add data disks
$addDisks=Get-azurevm  -ServiceName $ServiceName -Name $VMName
	
for ($index = 0; $index -lt $numberOfDisks; $index++)
{
    $label = "Data disk " + $index
    $addDisks = $addDisks | Add-AzureDataDisk -CreateNew -DiskSizeInGB 1023 -DiskLabel $label -LUN $index
	
}	
	$addDisks	| update-azureVM
	
# Get the RemotePS/WinRM Uri to connect to
$winRmUri = Get-AzureWinRMUri -ServiceName $ServiceName -Name $VMName

Install-WinRmCertificate $ServiceName $VMName
	
	
#Stripping the disks
	
$numberOfDisksPerPool = $numberOfDisks
$numberOfPools = 1
	
	$setDiskStripingScript = 
{
    param ([Int] $numberOfPools, [Int] $numberOfDisksPerPool)
    
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned
    
    $uninitializedDisks = Get-PhysicalDisk -CanPool $true 
    
    $virtualDiskJobs = @()
    
    for ($index = 0; $index -lt $numberOfPools; $index++)
    {         
        $poolDisks = $uninitializedDisks | Select-Object -Skip ($index * $numberOfDisksPerPool) -First $numberOfDisksPerPool 
        
        $poolName = "Pool" + $index
        $newPool = New-StoragePool -FriendlyName $poolName -StorageSubSystemFriendlyName "Storage Spaces*" -PhysicalDisks $poolDisks
        
        $virtualDiskJobs += New-VirtualDisk -StoragePoolFriendlyName $poolName  -FriendlyName $poolName -ResiliencySettingName Simple -ProvisioningType Fixed -Interleave 1048576 `
        -NumberOfDataCopies 1 -NumberOfColumns $numberOfDisksPerPool -UseMaximumSize -AsJob
    }
    
    Receive-Job -Job $virtualDiskJobs -Wait
    Wait-Job -Job $virtualDiskJobs                        
    Remove-Job -Job $virtualDiskJobs
    
    # Initialize and format the virtual disks on the pools
    $formatted = Get-VirtualDisk | Initialize-Disk -PassThru | New-Partition -DriveLetter "F" -UseMaximumSize | Format-Volume -FileSystem NTFS -AllocationUnitSize 65536 -Confirm:$false
    
    # Create the data directory
    $formatted | ForEach-Object {
        # Get current drive letter.
        $downloadDriveLetter = $_.DriveLetter
        $LogsDriveLetter = "D"
        
        # Create the data directory
        $dataDirectory = "$($downloadDriveLetter):\Data"
        $logsDirectory = "$($LogsDriveLetter):\CBlogs"
        
        New-Item $dataDirectory -Type directory -Force | Out-Null
        New-Item $logsDirectory -Type directory -Force | Out-Null
    }
	# Disabling all firewall profiles
	Get-NetFirewallProfile | Set-NetFirewallProfile -Enabled false -PassThru

    # Dive time to the storage service to pick up the changes
    Start-Sleep -Seconds 120
}

# Following is a special condition for striping for this deployment, 
# with 2 groups, 2 disks each (thus @(2, 2) parameters)"
Invoke-Command -ConnectionUri $winRmUri.ToString() -Credential $VMcred `
    -ScriptBlock $setDiskStripingScript -ArgumentList @($numberOfPools, $numberOfDisksPerPool)
