<#
  .SYNOPSIS
    A script for bootstrapping and using Puppet Discovery.

  .DESCRIPTION
    A script for bootstrapping and using Puppet Discovery.

    NOTE: Puppet Discovery requires Hyper-V to run. Please install Hyper-V before running Puppet Discovery.

  .PARAMETER Command
    Specify the command to pass to Puppet Discovery (by default, this help screen will show):

    Install   - Install the puppet-discovery control-plane and services
    Uninstall - Remove the puppet-discovery control-plane and services (removes all collected !!!)
    Start     - Start the puppet-discovery services
    Stop      - Stop the puppet-discovery services
    Status    - Show puppet-discovery service status
    Info      - List all puppet-discovery service endpoints
    Open      - Open puppet-discovery dashboard inside browser
    Upgrade   - Upgrade puppet-discovery to new latest version
    Help      - This help screen

  .PARAMETER Force
    Specify this parameter to skip confirmation checks, enabling you to run in CI if needed.

#>
[cmdletbinding()]
param (
  [ValidateNotNullOrEmpty()]
  [ValidateSet('Install', 'Uninstall', 'Start', 'Stop', 'Status', 'Info', 'Open', 'Deploy', 'Upgrade', 'Help', 'Mayday')]
  [String]$Command = 'Help',
  [string]$MinikubeVersion = '0.22.0',
  [string]$MinikubeKubernetesVersion = '1.7.5',
  [string]$MinikubeCpus = 1,
  [string]$MinikubeMemory = 4096,
  [string]$KubectlVersion = '1.7.6',
  [string]$PuppetDiscoveryVersion = 'latest',
  [switch]$Force
)

Begin {
  # welcome
  if ($Command -eq 'Install') {
    Write-Output '================================================================================='
    Write-Output '                               _         _ _                                    '
    Write-Output '                              | |       | (_)                                   '
    Write-Output '  _ __  _   _ _ __  _ __   ___| |_    __| |_ ___  ___ _____   _____ _ __ _   _  '
    Write-Output ' |  _ \| | | |  _ \|  _ \ / _ \ __|  / _` | / __|/ __/ _ \ \ / / _ \  __| | | | '
    Write-Output ' | |_) | |_| | |_) | |_) |  __/ |_  | (_| | \__ \ (_| (_) \ V /  __/ |  | |_| | '
    Write-Output ' | .__/ \__,_| .__/| .__/ \___|\__|  \__,_|_|___/\___\___/ \_/ \___|_|   \__, | '
    Write-Output ' | |         | |   | |                                                    __/ | '
    Write-Output ' |_|         |_|   |_|                                                   |___/  '
    Write-Output '================================================================================='
    Write-Output ""
    Write-Output ""
    Write-Output "Thank you for downloading Puppet Discovery Tech Preview."
    Write-Output ""
    Write-Output ""
    Write-Output "By using this software, you agree to the End User License Agreement"
    Write-Output "Found at the URL https://puppet.app.box.com/v/puppet-discovery-eula"
    Write-Output ""
    Read-Host -Prompt "Press [Enter] key to start installation"
  }

  # Check for runas Admin and error out if not elevated.
  If (!([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
      Throw "This script must be executed in an elevated administrative shell"
  }
  # Check for Windows 10 and error out if on another OS.
  If ((Get-WmiObject win32_operatingSystem).version -notmatch '^10.') {
    Throw 'Puppet Discovery is only supported on Windows 10.'
  }
  # Check for Hyper-V Install and error out if not available.
  If ((Get-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V -Online).State -ne 'Enabled') {
    Throw 'Puppet Discovery requires Hyper-V to be installed.'
  }
  # Initialize the variables for necessary paths.
  $PuppetDiscoveryPath = "$env:ProgramData\puppet-discovery"
  $DebugDirectory      = "$PuppetDiscoveryPath\debug"
  # Get the current time for logging and analytics.
  $TimeStamp = Get-Date -Format FileDateTimeUniversal
  # We're using a patch of 0.22.2 to address failures to start on Windows.
  # For more information, see: https://github.com/kubernetes/minikube/issues/1981
  $MiniKubeUrl = "https://storage.googleapis.com/minikube-builds/1982/minikube-windows-amd64.exe"
  $MiniKubePath = "$PuppetDiscoveryPath\minikube.exe"
  $KubeCtlUrl = "https://storage.googleapis.com/kubernetes-release/release/v${KubectlVersion}/bin/windows/amd64/kubectl.exe"
  $KubeCtlPath = "$PuppetDiscoveryPath\kubectl.exe"
  # Add the PuppetDiscovery folder to the path for minikube/kubectl
  $env:Path += ";$PuppetDiscoveryPath"
  # Set environment variables for sandboxing
  $KubeConfigPath = "$PuppetDiscoveryPath\.kubeconfig"
  If ([string]::IsNullOrEmpty($env:KUBECONFIG)) {
    $env:KUBECONFIG    = $KubeConfigPath
  } ElseIf ($env:KUBECONFIG -notmatch $KubeConfigPath.replace('\','\\').replace('.','\.')) {
    $env:KUBECONFIG    += ";$KubeConfigPath"
  }
  $env:MINIKUBE_HOME = $PuppetDiscoveryPath
  # List the pods we'll deploy for use in checking status.
  $Pods = 'cmd-controller','ingest','ingress-controller','mosquitto','operator','query','ui'

  Function Invoke-Minikube {
    Param (
    [string]$ArgumentList,
    [switch]$PassThru
    )
    $ArgumentList += " --profile puppet-discovery-minikube"
    If ($PassThru) {
      $TemporaryFile = "$PuppetDiscoveryPath/$(New-Guid).txt"
      Start-Process -FilePath $MiniKubePath -Wait -NoNewWindow -ArgumentList $ArgumentList -RedirectStandardOutput $TemporaryFile
      Get-Content $TemporaryFile
      Remove-Item $TemporaryFile
    } Else {
      Start-Process -FilePath $MiniKubePath -Wait -NoNewWindow -ArgumentList $ArgumentList
    }
  }
  Function Invoke-Binary {
    [cmdletbinding()]
    Param (
      [string]$ArgumentList,
      [string]$Path,
      [switch]$PassThru
    )
    $Parameters = @{
      ArgumentList = $ArgumentList
      Wait         = $true
      NoNewWindow  = $true
      FilePath     = $Path
    }
    If ($PassThru) {
      $OutputFile = "$PuppetDiscoveryPath/$(New-Guid).txt"
      $Parameters.RedirectStandardOutput = $OutputFile
    }
    If ($ErrorActionPreference -eq 'SilentlyContinue' ) {
      $ErrorFile = "$PuppetDiscoveryPath/$(New-Guid).txt"
      $Parameters.RedirectStandardError = $ErrorFile
    }
    Start-Process @Parameters
    If ($PassThru) { Get-Content $OutputFile }
    ForEach ($File in ($OutputFile, $ErrorFile) | Where-Object {![string]::IsNullOrEmpty($_)}) {
      If (Test-Path -Path $File) { Remove-Item -Path $File }
    }
  }

  Function Invoke-Kubectl {
    [cmdletbinding()]
    Param (
      [string]$ArgumentList,
      [switch]$PassThru
    )
      $PSBoundParameters.ArgumentList = "--kubeconfig=$KubeConfigPath --context=puppet-discovery-minikube $ArgumentList"
      Invoke-Binary -Path $KubeCtlPath @PSBoundParameters
  }
  Function Start-PuppetDiscovery {
    Invoke-Kubectl -ArgumentList 'run operator --image=gcr.io/puppet-discovery/puppet-discovery-operator:latest -- --release-channel=preview'
  }

  Function Start-Minikube {
    $VMDriverString = "--vm-driver=hyperv"
    Write-Host "Kubernetes requires at least one available external virtual switch."
    If (@(Get-VMSwitch -SwitchType External).Count -lt 1) {
      # If the force parameter is specified, don't confirm at prompt - useful for CI.
        New-VMSwitch -Name vExternal -NetAdapterName (Get-NetAdapter -Physical | Where-Object -FilterScript {$_.Status -eq 'Up'})[0].Name -Confirm:$(!$Force)
    }
    Write-Host "Using external virtual switch [$((Get-VMSwitch -SwitchType External).Name)]"
    $VMDriverString += " --hyperv-virtual-switch=$((Get-VMSwitch -SwitchType External).Name)"
    Invoke-Minikube -ArgumentList "start --kubernetes-version v$MinikubeKubernetesVersion --cpus $MinikubeCpus --memory $MinikubeMemory $VMDriverString"
    $i = 0
    While ((Invoke-Kubectl -ArgumentList 'get nodes' -PassThru | Where-Object {$_ -match 'ready'}).Count -eq $null) {
      $i++
      Start-Sleep -Seconds 5
      If ($i -gt 120) {
        Throw "We timed out waiting for the operation to finish."
      }
    }
  }

  Function Get-PuppetDiscoveryStatus  {
    [cmdletbinding()]
    Param ()
    ForEach ($Pod in $Pods) {
      Invoke-Kubectl -ArgumentList "rollout status deploy/$Pod --watch=false" -PassThru
    }
  }

  Function New-PuppetDiscoveryLogArchive {
    $LogsDirectory = (New-Item -Path "$env:TEMP\$(new-guid)" -ItemType Directory -Force).FullName
    $ArchivePath   = "$LogsDirectory\puppet-discovery-log-$TimeStamp.zip"
    $null = New-Item -Path "$LogsDirectory\puppet-discovery-minikube" -ItemType Directory -Force
    If (!(Test-Path $DebugDirectory)) {
      New-Item -Path $DebugDirectory -Force -ItemType Directory
    }
    Write-Host "Grabbing Minikube cluster dump..."
    Invoke-Kubectl -ArgumentList "cluster-info dump --all-namespaces --output-directory=`"$LogsDirectory`""

    Write-Host "`nGrabbing Puppet Discovery Deployment info..."
    Invoke-Kubectl -PassThru -ArgumentList 'get pd -o yaml' | Out-File -FilePath "$LogsDirectory\puppet-discovery-minikube/pd-info.yaml" -Force

    Write-Host "Grabbing StatefulSet info..."
    Invoke-Kubectl -PassThru -ArgumentList 'get sts -o yaml' | Out-File -FilePath  "$LogsDirectory\puppet-discovery-minikube/sts-info.yaml" -Force

    Write-Host "Grabbing Minikube cluster info..."
    Invoke-Kubectl -PassThru -ArgumentList 'get all -o yaml' | Out-File -FilePath "$LogsDirectory\cluster-all.yaml" -Force

    Write-Host "Creating debug archive..."
    $null = Compress-Archive -Path $LogsDirectory -DestinationPath $ArchivePath -CompressionLevel Optimal -Force

    Write-Host "Cleaning up..."
    Remove-Item -Path $LogsDirectory -Recurse -Force

    Write-Host "A debug archive file can be found at $ArchivePath"
  }
}

Process {
  switch ($Command) {
    "install" {
      Write-Output 'puppet-discovery install'

      If (-not (Test-Path -Path $PuppetDiscoveryPath)) {
        mkdir $PuppetDiscoveryPath -Force | Out-Null
      }

      if (-Not (Test-Path $MiniKubePath)) {
        Write-Output 'downloading minikube ...'
        (New-Object System.Net.WebClient).DownloadFile($MiniKubeUrl, $MiniKubePath)
      }

      if (-Not (Test-Path $KubeCtlPath)) {
        Write-Output 'downloading kubectl ...'
        (New-Object System.Net.WebClient).DownloadFile($KubeCtlUrl, $KubeCtlPath)
      }

      Write-Output 'start minikube cluster ...'
      Start-Minikube

      Write-Output 'wait till cluster is in Running state ...'
      $i = 1
      while ((Invoke-Minikube -ArgumentList 'status --format "{{.MinikubeStatus}}"' -PassThru) -ne 'Running') {
        Start-Sleep -Seconds $i
        $i++
        if ($i -ge 10) {
          Write-Error -Message "Status retrieval timedout" -Category QuotaExceeded -ErrorId 1001
          break
        }
      }

      Write-Output 'reconfigure minikube vm ...'
      Invoke-Minikube -ArgumentList 'ssh "sudo sysctl -w  vm.max_map_count=262144"'

      Write-Output 'deploy services ...'
      Start-PuppetDiscovery

      Write-Output 'waiting for services...'
      $i = 1
      while ((Get-PuppetDiscoveryStatus -ErrorAction SilentlyContinue -OutVariable Status | Where-Object {$_ -match 'success'}).Count -ne $Pods.Count) {
        Start-Sleep -Seconds 10
        $i++
        if ($i -ge 60) {
          Throw "We timed out waiting for the operation to finish. Please check the logs. This can be accomplished via the 'logs' command."
        }
      }
      $Status
    }
    "uninstall" {
      Write-Output 'puppet-discovery uninstall'
      If (Test-Path $MiniKubePath) {
        Invoke-Minikube -ArgumentList 'stop'
        Invoke-Minikube -ArgumentList 'delete'
      }
      If (Test-Path  $PuppetDiscoveryPath -Type Container) {
        Write-Output 'cleanup puppet-discovery installation location ...'
        Remove-Item -Path $PuppetDiscoveryPath -Recurse -Force
      }
    }
    "start" {
      Write-Output 'puppet-discovery start'
      Start-Minikube
    }
    "stop" {
      Write-Output 'puppet-discovery stop'
      Invoke-Minikube -ArgumentList 'stop'
    }
    "status" {
      Write-Output 'puppet-discovery status'
      Get-PuppetDiscoveryStatus
    }
    "info" {
      Write-Output 'puppet-discovery info'
      ### minikube service mini-nginx-ingress-controller --url --https
    }
    "open" {
      Write-Output 'puppet-discovery open'
      # Note: If the browser is not already open, this will cause the CLI to hang until the browser is closed.
      # Possibly because the browser is a child process of this call to minikube.
      Invoke-Minikube -ArgumentList 'service ingress --https'
    }
    "deploy" {
      Write-Output 'puppet-discovery deploy'
      Start-PuppetDiscovery
    }
    "upgrade" {
      Write-Output 'puppet-discovery upgrade'
      Start-PuppetDiscovery
    }
    "help" {
      Get-Help $MyInvocation.MyCommand.Source -Full
    }
    "mayday" {
      New-PuppetDiscoveryLogArchive     
    }
  }
}
