#requires -version 4

<#

.NOTES

Information on running PowerShell scripts can be found here:
    -http://ss64.com/ps/syntax-run.html
    -https://technet.microsoft.com/en-us/library/bb613481.aspx
    -http://www.netapp.com/us/media/tr-4475.pdf

File Name:  is_iscsi_mulitpath.ps1
Author: Boris Aelen 
Version: 2.0 (Also reflected in -ShowVersion parameter)

.COMPONENT  

    -PowerShell version 4.0 or greater required (which requires .NET Framework 4.5 or greater be installed first)
    -NetApp PowerShell Toolkit 3.2.1 or newer: http://mysupport.netapp.com/NOW/download/tools/powershell_toolkit/

.SYNOPSIS
This script checks if all iSCSi sessions are multipath connected on a given Cluster.

.DESCRIPTION

BlaBla BlaBla

.EXAMPLE

.\is_iscsi_mulitpath.ps1

Running without any parameters will prompt for all necessary values.

.EXAMPLE
    
.\is_iscsi_mulitpath.ps1 -Cluster MyClusterManagementIP -Username admin -Password MyPassword 

These parameters allow the passing of cluster connection information to avoid being prompted while executing the script.

.EXAMPLE
.\83UpgradeCheck.ps1 -ShowVersion

Displays current version of the script and download link

.LINK
www.borisaelen.nl

#>
	
#region Parameters and Variables
[CmdletBinding(PositionalBinding=$False)]
Param(
  [Parameter(Mandatory=$False)]
   [string]$Cluster,

  [Parameter(Mandatory=$False)]
   [string]$Username,

  [Parameter(Mandatory=$False)]
   [string]$Password,

  [Parameter(Mandatory=$False)]
   [switch]$ShowVersion
)

$CurrentScriptVersion = "2.0"

If ($ShowVersion) {
    Write-Host "Current script version is:" $CurrentScriptVersion -ForegroundColor Magenta
    Exit
}

# Check toolkit version
try {
    if (-Not (Get-Module DataONTAP)){
            Import-Module DataONTAP -EA 'STOP' -Verbose:$false
        }
    if ((Get-NaToolkitVersion).CompareTo([system.version]'3.2.1') -LT 0) { throw }
    }
    catch [Exception]
    {
        Write-Warning "This script requires Data ONTAP PowerShell Toolkit 3.2.1 or higher."
        return;
}
#endregion

#region Functions
Function Get-Properties ($array) {
    $array |ForEach-Object{$_ | Get-Member |?{$_.MemberType -ne "Method"} | Select-Object -ExpandProperty Name} | Sort-Object -Unique
}
#endregion

#region Main Body	
if (!$global:CurrentNcController){
	#Connect to the cluster
	If ($Cluster.Length -eq 0) { $Cluster = Read-host "Enter the cluster management LIF" }
	$Cluster = $Cluster.Trim()
	If ($Username.Length -eq 0) { $Username = Read-Host "Enter username for connecting to the cluster" }
	If ($Password.Length -eq 0) { $SecurePassword = Read-Host "Enter the password for" $Username -AsSecureString} else {
		$SecurePassword = New-Object -TypeName System.Security.SecureString
		$Password.ToCharArray() | ForEach-Object {$SecurePassword.AppendChar($_)}
	}
	$Credentials = new-object -typename System.Management.Automation.PSCredential -argumentlist $Username, $SecurePassword
	Write-Host "Attempting connection to $Cluster"
	$ClusterConnection = Connect-NcController -name $Cluster -Credential $Credentials
	if (!$ClusterConnection) {
		RecordIssue "Warn"
		Write-Host "Unable to connect to NetApp cluster, please ensure all supplied information is correct and try again" -ForegroundColor Yellow
		Exit        
	}	
}

$sessies = get-ncIscsiConnection 
$initiators = get-ncIscsiInitiator
$multipath = @()
foreach($initiator in $initiators){
	$nodename = $initiator.InitiatorNodename -split ":"
	$tpgroup = $initiator.TpgroupName
	$sessie = $sessies | ?{ $_.sessionid -eq $initiator.targetsessionid -and $_.TpgroupName -eq $tpgroup } 
	#Debug command
	#write-host $nodename[1] $tpgroup $sessie.RemoteIpAddress $sessie.LocalIpAddress
	if ( $row = $multipath | ?{ $_.Name -eq $nodename[1]} ){
		if ( $row.$tpgroup ){
			$row.$tpgroup += "," + $sessie.RemoteIpAddress
		}
		else{
			$row | add-member -name $tpgroup -type NoteProperty -Value $sessie.RemoteIpAddress
		}
	}else {
		$obj = new-object psobject
		$obj | add-member -name Name -type NoteProperty -Value $nodename[1] 
		$obj | add-member -name $tpgroup -type NoteProperty -Value $sessie.RemoteIpAddress
		$multipath += $obj
	}
}
$multipath | sort -Property Name | select -Property (get-properties $multipath) | Format-Table -AutoSize