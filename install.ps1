# Pre Script Tasks
if (!
    #current role
    (New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    #is admin?
    )).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
) {
    #elevate script and exit current non-elevated runtime
    Start-Process `
        -FilePath 'powershell' `
        -ArgumentList (
            #flatten to single array
            '-File', $MyInvocation.MyCommand.Source, $args `
            | %{ $_ }
        ) `
        -Verb RunAs
    exit
}


# Functions
function Install-Archive {

    param (
        $ArchivePath,
        $ArchiveInstallPath
    )

    Write-Output $ArchivePath $ArchiveInstallPath 
    Expand-Archive $ArchivePath $ArchiveInstallPath

}

function Get-LastElementOfString {

    param (
        $String,
        $Delimiter
    )

    return $string.split($delimiter)[-1]
}

function Remove-LastElementOfString {

    param (
        $String,
        $Delimiter
    )

    $string = $string.split($Delimiter)
    $string[-1] = $null

    return $string -join $Delimiter
}

# Global Variables
$OSDriveLetter=(Get-WmiObject Win32_OperatingSystem).SystemDrive
$InstallDir="$($OSDriveLetter)\bin"
$ScriptPath=$PSCommandPath
#Results=@()

# Derived Variables
$InstallDirFolderName=Get-LastElementOfString -String $InstallDir -Delimiter "\"
$InstallDirParentFolderPath=Remove-LastElementOfString -String $InstallDir -Delimiter "\"
$ScriptFolderPath=Remove-LastElementOfString -String $ScriptPath -Delimiter "\"
$ScriptName=Get-LastElementOfString -String $ScriptPath -Delimiter "\"


# Main
cd $ScriptFolderPath

if (-Not (Test-Path -Path $InstallDir)) {
    New-Item -Path $InstallDirParentFolderPath -Name "$InstallDirFolderName" -ItemType "directory"
}

elseif (Test-Path -Path $InstallDir) {
    Write-Output "Install Directory Already Exists - Proceeding with install steps"
}

else {
    Write-Error "Unable to create/detect $($InstallDir) "
}

Get-ChildItem -Directory | ForEach-Object {
    $FolderPath="$($ScriptFolderPath)$($_.name)"
    $ManifestFile=Get-ChildItem "$($FolderPath)" | Where-Object { $_ -clike "*.install.json" } | Select Name -ExpandProperty Name
    $ManifestFilePath="$($FolderPath)\$($ManifestFile)"

    if ($ManifestFile.length -gt 0){
        Write-Output "Checking... $ManifestFilePath"

        $manifest = Get-Content "$ManifestFilePath" | Out-String | ConvertFrom-Json
        $manifest.result.name = $manifest.name
        Switch ($manifest.method)
        {
            "extraction" { 
                $ArchivePath="$($FolderPath)\$($manifest.archive)"
                if ($manifest.installPath -eq "bin"){
                    if (Test-Path "$($InstallDir)\$($manifest.mainExePath)"){
                        $manifest.result.install = "Already installed"
                    }

                    else {
                        Install-Archive $ArchivePath $InstallDir
                        $manifest.result.install = "Installed"
                    }
                    
                }

                else {
                    $manifest.result.error = "Please specify install path in manifest (eg. bin, programfiles...)"
                }
                
             }
        }

        $StartUpRegistryPath="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\run"
        Switch ($manifest.startup)
        {
            "login" {
                $RegistryPath=Get-ItemProperty -Path $StartUpRegistryPath -Name $manifest.name
                if(Get-ItemProperty -Path $StartUpRegistryPath -Name $manifest.name){
                    $manifest.result.startup = "Already exists"
                }

                else {
                    New-ItemProperty -Path $StartUpRegistryPath -Name $manifest.name -Value "$($InstallDir)\$($manifest.mainExePath)\$($manifest.mainExe)" -PropertyType "String"
                    $manifest.result.startup = "Added"
                }
                 
            }
        }

        ## TODO ADD TO START MENU


        ## TODO ADD TO PATH

        $manifest.result.notes = $manifest.notes
        $Results += $manifest.result
    }   
}

$Results | Format-Table

pause