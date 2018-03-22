# +------------------------------------------------------+
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

# -----------------------
# Define Global Variables
# -----------------------
$Global:Folder = $env:USERPROFILE+"\Documents\HostAndVM-Patching"


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
    Connect-VIServer $Global:VCName -Credential $Global:Creds -WarningAction SilentlyContinue
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

#********************************
# Function Attach-VUM-VMBaselines
#********************************
Function Attach-VUM-VMBaselines {
    [CmdletBinding()]
    Param($VMHosts, $VMToolsBaseline, $VMHardwareBaseline)
    foreach($Name in $vmhosts){
        "Attaching VUM Baselines to VMs on $Name"
        $VMs = Get-VMHost -Name $Name | Get-VM
        #Attach Tools Baseline to VMs
        $VMs | Attach-Baseline -Baseline $VMToolsBaseline
        #Attach Hardware Baseline to VMs
        $VMs | Attach-Baseline -Baseline $VMHardwareBaseline 
    }
}
#***********************************
# EndFunction Attach-VUM-VMBaselines
#***********************************

#**************************
# Function Scan-VMInventory
#**************************
Function Scan-VMInventory {
    [CmdletBinding()]
    Param($VMHosts)
    $taskTab = @{}
    ForEach($Name in $VMHosts){
        "Initiating VUM Scans for VMs on $Name"
        $VMs = Get-VMHost -Name $Name | Get-VM
        ForEach($VM in $VMs){
            $taskTab[(Scan-Inventory -entity $VM -RunAsync).Id] = $VM
        }
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
#*****************************
# EndFunction Scan-VMInventory
#*****************************

#***************************
# Function Remediate-VMTools
#***************************
Function Remediate-VMTools {
    [CmdletBinding()]
    Param($VMHosts, $VMToolsBaseline)
    $taskTab = @{}
    ForEach($Name in $VMHosts){
        "Initiating VMTools Remediation for VMs on $Name"
        $VMs = Get-VMHost -Name $Name | Get-VM
        ForEach($VM in $VMs){
            $taskTab[($VMToolsBaseline | Remediate-Inventory -entity $VM -Confirm:$false -RunAsync).Id] = $VM
        }
    }
    
    $totalTasks = $taskTab.Count
    $runningTasks = $taskTab.Count
    While($runningTasks -gt 0){
        Get-Task | % {
            if($taskTab.ContainsKey($_.ID) -and $_.State -eq "Success"){
                "Remediation complete on "+ ($_.ObjectID | Get-VIObjectByVIView | Select -expandproperty Name)
                $taskTab.Remove($_.Id)
                $runningTasks--
            }
            elseIf($taskTab.ContainsKey($_.ID) -and $_.State -eq "Error"){
                "Remediation Error on "+ ($_.ObjectID | Get-VIObjectByVIView | Select -expandproperty Name)
                $taskTab.Remove($_.Id)
                $runningTasks--       
            }
        }
        Write-Progress -Id 0 -Activity 'Remediation tasks still running' -Status "$($runningTasks) task of $($totalTasks) still running" -PercentComplete (($runningTasks/$totalTasks) * 100)
        Start-Sleep -Seconds 5
    }
    Write-Progress -Id 0 -Activity 'Remediation tasks still running' -Completed

}
#******************************
# EndFunction Remediate-VMTools
#******************************

#******************************
# Function Remediate-VMHardware
#******************************
Function Remediate-VMHardware {
    [CmdletBinding()]
    Param($VMHosts, $VMHardwareBaseline)
    $taskTab = @{}
    ForEach($Name in $VMHosts){
        "Initiating VMTools Remediation for VMs on $Name"
        $VMs = Get-VMHost -Name $Name | Get-VM
        ForEach($VM in $VMs){
            $taskTab[($VMHardwareBaseline | Remediate-Inventory -entity $VM -Confirm:$false -RunAsync).Id] = $VM
        }
    }
    
    $totalTasks = $taskTab.Count
    $runningTasks = $taskTab.Count
    While($runningTasks -gt 0){
        Get-Task | % {
            if($taskTab.ContainsKey($_.ID) -and $_.State -eq "Success"){
                "Remediation complete on "+ ($_.ObjectID | Get-VIObjectByVIView | Select -expandproperty Name)
                $taskTab.Remove($_.Id)
                $runningTasks--
            }
            elseIf($taskTab.ContainsKey($_.ID) -and $_.State -eq "Error"){
                "Remediation Error on "+ ($_.ObjectID | Get-VIObjectByVIView | Select -expandproperty Name)
                $taskTab.Remove($_.Id)
                $runningTasks--       
            }
        }
        Write-Progress -Id 0 -Activity 'Remediation tasks still running' -Status "$($runningTasks) task of $($totalTasks) still running" -PercentComplete (($runningTasks/$totalTasks) * 100)
        Start-Sleep -Seconds 5
    }
    Write-Progress -Id 0 -Activity 'Remediation tasks still running' -Completed

}
#*********************************
# EndFunction Remediate-VMHardware
#*********************************



#***************
# Execute Script
#***************
CLS
$ErrorActionPreference="SilentlyContinue"

"=========================================================="
" "
Write-Host "Get CIHS credentials" -ForegroundColor Yellow
$Global:Creds = Get-Credential -Credential $null

Get-VCenter
Connect-VC
"=========================================================="
"Get Target List"
$inputFile = Get-FileName $Global:Folder
"=========================================================="
"Reading Target List"
$VMHostList = Read-TargetList $inputFile
"=========================================================="
#Define Baselines for use later
$VMToolsBaseline = Get-Baseline -Name "VMware Tools Upgrade to Match Host*"
$VMHardwareBaseline = Get-Baseline -Name "VM Hardware Upgrade*"
"Attach VUM Baselines to VMs"
Attach-VUM-VMBaselines $VMHostList $VMToolsBaseline $VMHardwareBaseline
"=========================================================="
"Scan VMs for VUM Updates"
Scan-VMInventory $VMHostList 
"=========================================================="
"Remediate VMTools on VMs"
Remediate-VMTools $VMHostList $VMToolsBaseline
"=========================================================="
"Re-Scan VMs for VUM Updates to activate Hardware Baseline"
Scan-VMInventory $VMHostList 
"=========================================================="
"Remediate VMHardware on VMs"
Remediate-VMHardware $VMHostList $VMHardwareBaseline
"=========================================================="
