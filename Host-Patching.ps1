param(
    [Parameter(Mandatory=$true)][String]$vCenter
    )

<# +------------------------------------------------------+
# |        Load VMware modules if not loaded             |
# +------------------------------------------------------+
"Loading VMWare Modules"
$ErrorActionPreference="SilentlyContinue" 
if ( !(Get-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue) ) {
    if (Test-Path -Path 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\VMware, Inc.\VMware vSphere PowerCLI' ) {
        $Regkey = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\VMware, Inc.\VMware vSphere PowerCLI'
       
    } else {
        $Regkey = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\VMware, Inc.\VMware vSphere PowerCLI'
    }
    . (join-path -path (Get-ItemProperty  $Regkey).InstallPath -childpath 'Scripts\Initialize-PowerCLIEnvironment.ps1')
}
$ErrorActionPreference="Continue"
#>

# -----------------------
# Define Global Variables
# -----------------------
$Global:Folder = $env:USERPROFILE+"\Documents\HostAndVM-Patching"



#**********************
# Function Shutdown-VMs
#**********************
Function Shutdown-VMs {
    [CmdletBinding()]
    Param($vmhost)
    $vms = get-vmhost -Name $vmhost | get-vm | where {$_.PowerState -eq "PoweredOn"}
    foreach ($vm in $vms) {
        "Shutting Down $vm on $vmhost"
        Shutdown-VMGuest -VM $vm -Confirm:$false >$null
        }
   # Sleep 60
    
}
#*************************
# EndFunction Shutdown-VMs
#*************************

#*****************
# Get VC from User
#*****************
Function Get-VCenter {
    [CmdletBinding()]
    Param()
    #Prompt User for vCenter
    Write-Host "Enter the FQHN of the vCenter containing the target Hosts: " -ForegroundColor "Yellow" -NoNewline
    $Global:VCName = Read-Host 
}
#*******************
# EndFunction Get-VC
#*******************

#*******************
# Connect to vCenter
#*******************
Function Connect-VC {
    [CmdletBinding()]
    Param()
    "Connecting to $Global:VCName"
    #Connect-VIServer $Global:VCName -Credential $Global:Creds -WarningAction SilentlyContinue
    Connect-VIServer $Global:VCName -WarningAction SilentlyContinue
}
#***********************
# EndFunction Connect-VC
#***********************

#*******************
# Disconnect vCenter
#*******************
Function Disconnect-VC {
    [CmdletBinding()]
    Param()
    "Disconnecting $Global:VCName"
    Disconnect-VIServer -Server $Global:VCName -Confirm:$false
}
#**************************
# EndFunction Disconnect-VC
#**************************

#*************************************************
# Check for Folder Structure if not present create
#*************************************************
Function Verify-Folders {
    [CmdletBinding()]
    Param()
    "Building Local folder structure" 
    If (!(Test-Path $Global:Folder)) {
        New-Item $Global:Folder -type Directory  > $null
        }
    If (!(Test-Path $Global:Folder\Temp)) {
        New-Item $Global:Folder\Temp -type Directory  > $null
        }
    "Folder Structure built" 
}
#***************************
# EndFunction Verify-Folders
#***************************

#**********************
# Function Get-FileName
#**********************
Function Get-FileName {
    [CmdletBinding()]
    Param($initialDirectory)
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.initialDirectory = $initialDirectory
    $OpenFileDialog.filter = "TXT (*.txt)| *.txt"
    $OpenFileDialog.ShowDialog() | Out-Null
    Return $OpenFileDialog.filename
}
#*************************
# EndFunction Get-FileName
#*************************

#*************************
# Function Read-TargetList
#*************************
Function Read-TargetList {
    [CmdletBinding()]
    Param($TargetFile)
    $Targets = Get-Content $TargetFile
    Return $Targets
}
#****************************
# EndFunction Read-TargetList
#****************************

#****************************
# Function Initiate-HostScans
#****************************
Function Initiate-HostScans {
    [CmdletBinding()]
    Param($vmHosts)
    $taskTab = @{}
    foreach($Name in $vmhosts){
        $taskTab[(Scan-Inventory -entity $Name -RunAsync).Id] = $Name 
    }
    $totalTasks = $taskTab.Count
    $runningTasks = $taskTab.Count
    While($runningTasks -gt 0){
        Get-Task | % {
            if($taskTab.ContainsKey($_.ID) -and $_.State -eq "Success"){
                "Scanning complete on "+ ($_.ObjectID | Get-VIObjectByVIView | Select -expandproperty Name)
                $taskTab.Remove($_.Id)
                $runningTasks--
            }
        }
        Write-Progress -Id 0 -Activity 'Scan tasks still running' -Status "$($runningTasks) task of $($totalTasks) still running" -PercentComplete (($runningTasks/$totalTasks) * 100)
        Start-Sleep -Seconds 5
    }
    Write-Progress -Id 0 -Activity 'Scan tasks still running' -Completed
}
#*******************************
# EndFunction Initiate-HostScans
#*******************************


#********************
# Function PatchHosts
#********************
Function PatchHost {
    [CmdletBinding()]
    Param($vmHosts)
    $taskTab = @{}
    foreach($Name in $vmhosts){
        "Initiate VM Shutdowns on $Name"
        Store-PoweredOnVMs $Name
        Shutdown-VMs $Name
        "Put $Name in to Maintenance Mode"
        Get-VMHost $Name | Set-VMHost -State Maintenance > $null
        "Initiate Patching Job on $Name"
        $taskTab[(Get-Baseline -Name "ESXi Patches" | Remediate-Inventory -entity $Name -Confirm:$false -runAsync).Id] = $Name 
        "----------------------------------------------------------"
    }
    $totalTasks = $taskTab.Count
    $runningTasks = $taskTab.Count
    While($runningTasks -gt 0){
        Get-Task | % {
            if($taskTab.ContainsKey($_.ID) -and $_.State -eq "Success"){
                $HostName = ($_.ObjectID | Get-VIObjectByVIView | Select -expandproperty Name)
                "Patching complete on $HostName" 
                "Taking $HostName out of Maintenance Mode"
                Get-VMHost $HostName | Set-VMHost -State Connected > $null
                Start-VMs $HostName
                $taskTab.Remove($_.Id)
                $runningTasks--
            }
        }
        Write-Progress -Id 0 -Activity 'Patching tasks still running' -Status "$($runningTasks) task of $($totalTasks) still running" -PercentComplete (($runningTasks/$totalTasks) * 100)
        Start-Sleep -Seconds 5
    }
    Write-Progress -Id 0 -Activity 'Patching tasks still running' -Completed
}
#*******************
# Function PatchHost
#*******************

#****************************
# Function Store-PoweredOnVMs
#****************************
Function Store-PoweredOnVMs {
    [CmdletBinding()]
    Param($Target)
    Get-VMHost -Name $Target | Get-VM | where {$_.PowerState -eq "PoweredOn"} | Select -expandProperty Name | Out-File $Global:Folder\temp\$Target.txt        
}
#*******************************
# EndFunction Store-PoweredOnVMs
#*******************************

#*******************
# Function Start-VMs
#*******************
Function Start-VMs {
    [CmdletBinding()]
    Param($Target)
    $VMs = Get-Content $Global:Folder\Temp\$Target.txt
    ForEach ($VM in $VMs){
        "Starting $vm on $Target"
        Start-VM -RunAsync -VM $VM -Confirm:$false >$null
    }
}
#**********************
# EndFunction Start-VMs
#**********************

#******************
# Function Clean-Up
#******************
Function Clean-Up {
    [CmdletBinding()]
    Param()
    Remove-Item $Global:Folder\Temp -Force -Recurse > $null
}
#*********************
# EndFunction Clean-Up
#*********************

#***************
# Execute Script
#***************
CLS
$ErrorActionPreference="SilentlyContinue"

"=========================================================="
" "
#Write-Host "Get CIHS credentials" -ForegroundColor Yellow
#$Global:Creds = Get-Credential -Credential $null

#Get-VCenter
$Global:VCName = $vCenter
Connect-VC
"=========================================================="
Verify-Folders
"=========================================================="
"Get Target List"
$inputFile = Get-FileName $Global:Folder
"=========================================================="
"Reading Target List"
$VMHostList = Read-TargetList $inputFile
"=========================================================="
"Initiate Scanning for required Patches on Hosts" 
"and waiting for completion"
"=========================================================="
Initiate-HostScans $VMHostList
"----------------------------------------------------------"
"Initiate Patching on Hosts"
"=========================================================="
PatchHost $VMHostList
"----------------------------------------------------------"
Clean-Up


Disconnect-VC