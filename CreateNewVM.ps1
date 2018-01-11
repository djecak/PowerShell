#Login to your Azure Account and select subscription:

Login-AzureRmAccount
$SubscriptionId = (Get-AzureRmSubscription | Out-GridView -Title "Select Azure Subscription..."-PassThru).SubscriptionID
Select-AzureRmSubscription -SubscriptionId $SubscriptionId
#Select-AzureRmProfile -Path C:\ZiScript\AzureTest\AzureTestRmProfile.json
$locName = "australiasoutheast"
$publisher=(Get-AzureRmVMImagePublisher -Location $locName | OGV -Title "Select Azure Publisher (hint: use 'Add criteria' to filter)..." -passthru).PublisherName #check all the publishers available
$offer=(Get-AzureRmVMImageOffer -Location $locName -PublisherName $publisher | OGV -Title "Select Azure Offer (hint: use 'Add criteria' to filter)..." -passthru).Offer #look for offers for a publisher
$osSKU=(Get-AzureRmVMImageSku -Location $locName -PublisherName $publisher -Offer $offer | OGV -Title "Select OS SKU (hint: use 'Add criteria' to filter)..." -passthru).Skus #view SKUs for an offer

$vmSize = (Get-AzureRmVmSize -Location $locName | Select-Object Name, NumberOfCores, MemoryInMB, MaxDataDiskCount, ResourceDiskSizeInMB | OGV -PassThru).Name

$VMcred = Get-Credential -Message "Type the name and password of the VM local administrator account. The password must be at 12-123 characters long and have at least one lower case character, one upper case character, one number, and one special character."

$rgName = read-host "Enter Resource Group name"
$storaccName = read-host "Enter Storage Account name"
$vmName = read-host "Enter VM name"
$stType = "Standard_LRS"
$subnetName = "$rgName-subnet"
$vnetName = "$rgName-vnet"
$compName = $vmName
$diskName = "$vmName-osdisk"
$vnetRange = "172.21.0.0/16"
$SubnetRange = "172.21.0.0/24"

#Create a resource group, skip if already exists:

try {     
    Get-AzureRmResourceGroup -Name $rgName -Location $locName -ErrorAction Stop     
    Write-Host 'RG already exists... skipping' -foregroundcolor yellow -backgroundcolor red 
} catch {     
  New-AzureRmResourceGroup -Name $rgName -Location $locName 
}

#Create a storage account (Standard LRS):


#Check for storage name availability (needs to be unique in globally) 
do  {
$StorAccNameAvail = Get-AzureRmStorageAccountNameAvailability -Name $storaccName
    if ($StorAccNameAvail.NameAvailable -eq 'True')
    { New-AzureRmStorageAccount -Name $storaccName -ResourceGroupName $rgName -Type $stType -Location $locName }
    else
        {Write-Host -Separator `n
         Write-Host "The storage account named $storaccName is already taken" -ForegroundColor yellow -BackgroundColor Red
         Write-Host -Separator `n
         $storaccName = read-host "Enter new storage account name" 
         }
    }
until ($StorAccNameAvail.NameAvailable -eq 'True')
$storacct = Get-AzureRmStorageAccount -ResourceGroupName $rgName -StorageAccountName $storaccName

#Create a virtual network and subnet:

$singleSubnet = New-AzureRmVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $SubnetRange


#$vnet = New-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $rgName -Location $locName -AddressPrefix 10.0.0.0/16 -Subnet $singleSubnet
try {     
    $vnet = Get-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $rgName -ErrorAction Stop     
    Write-Host 'VNET already exists... skipping' -foregroundcolor yellow -backgroundcolor red 
} catch {     
    $vnet = New-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $rgName -Location $locName -AddressPrefix $vnetRange -Subnet $singleSubnet 
}
$subnet = Get-AzureRmVirtualNetworkSubnetConfig -VirtualNetwork $vnet

#Create a public IP address and network interface:

$pip = New-AzureRmPublicIpAddress -Name "${vmname}_PIP1" -ResourceGroupName $rgName -Location $locName -AllocationMethod Dynamic

$nic = New-AzureRmNetworkInterface -Name "${vmname}_nic1" -ResourceGroupName $rgName -Location $locName -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id

#Create a virtual machine:

    #set the administrator account name and password for the virtual machine. 
    #The password must be at 12-123 characters long and have at least one lower case character, one upper case character, one number, and one special character.
    
    #Create the variable and the virtual machine configuration
    $vm = New-AzureRmVMConfig -VMName $vmName -VMSize $vmSize
    # Create the computer name variable and add the operating system information to the configuration
    
    $vm = Set-AzureRmVMOperatingSystem -VM $vm -Windows -ComputerName $compName -Credential $VMcred -ProvisionVMAgent -EnableAutoUpdate
    #Define the image to use to provision the virtual machine
    $vm = Set-AzureRmVMSourceImage -VM $vm -PublisherName $publisher -Offer $offer -Skus $osSKU -Version "latest"
    #Add the network interface that you created to the configuration
    $vm = Add-AzureRmVMNetworkInterface -VM $vm -Id $nic.Id
    #Create the variables vhd and disk uri
    $blobPath = "vhds/$vmName-Disk.vhd"
    $osDiskUri = $storAcct.PrimaryEndpoints.Blob.ToString() + $blobPath
    #Create the OS disk variable and add the disk information to the configuration
    
    $vm = Set-AzureRmVMOSDisk -VM $vm -Name $diskName -VhdUri $osDiskUri -CreateOption fromImage
    #Create the VM
    New-AzureRmVM -ResourceGroupName $rgName -Location $locName -VM $vm

#Get VM's public IP
$rdpIP = (Get-AzureRmPublicIpAddress -Name $pip.Name -ResourceGroupName $rgName).IpAddress

#$rdpString = $vmName + '.' + $rdpVM.Location + '.cloudapp.azure.com:3389' 
Get-AzurermRemoteDesktopFile -ResourceGroupName $rgName -Name $vmName -LocalPath "c:\temp\$vmName.rdp"

Write-Host "Azure VM provisioning succeeded!" -foregroundcolor Green
Write-Host "Connect to the VM using the IP below or using $vmName.rdp file in C:\Temp" -foregroundcolor Green
Write-Host $rdpIP -foregroundcolor Green
