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
    Help      - This help screen

  .PARAMETER Force
    Specify this parameter to skip confirmation checks, enabling you to run in CI if needed.

  .PARAMETER MinikubeVersion
    Specify this parameter to override the default minikube version for install.
    We suggest you only use this if you're already familiar with minikube and are troubleshooting.

  .PARAMETER MinikubeKubernetesVersion
    Specify this parameter to override the default Kubernetes API version used by minikube.
    We suggest you only use this if you're already familiar with minikube and are troubleshooting.

  .PARAMETER MinikubeCpus
    Specify this parameter to override the default number of CPUs assigned to the VM created by minikube.
    By default, 1 cpu is assigned.

  .PARAMETER MinikubeMemory
    Specify this parameter to override the default amount of RAM (in MB) assigned to the VM created by minikube.
    By default, 4GB is assigned.

  .PARAMETER KubectlVersion
    Specify this parameter to override the version of kubectl downloaded and used in the installation.
    We suggest you only use this if you're already familiar with kubectl and are troubleshooting.

  .PARAMETER PuppetDiscoveryVersion
    Specify this parameter to override the version of Puppet Discovery you download and run.
    By default, this script will download and run the latest released version.

  .EXAMPLE
    .\Puppet-Discovery.ps1 Install

    This command will install Puppet Discovery to your local machine using the default settings.

    NOTE: This can take several minutes to come fully online.

  .EXAMPLE
    .\Puppet-Discovery.ps1 Uninstall

    This command will uninstall Puppet Discovery from your local machine entirely.

  .EXAMPLE
    .\Puppet-Discovery.ps1 Start

    This command will start Puppet Discovery on your local machine using the default settings.
    You must have installed Puppet Discovery for this to work.

    NOTE: This can take several minutes to come fully online.

  .EXAMPLE
    .\Puppet-Discovery.ps1 Stop

    This command will stop Puppet Discovery on your local machine.

  .EXAMPLE
    .\Puppet-Discovery.ps1 Open

    This command will open Puppet Discovery in your default browser.
    You must have installed Puppet Discovery for this to work.

    NOTE: If you do not have a browser window already open prior to running this command, your prompt _may_
    hang until you close the browser window.

#>
[cmdletbinding()]
param (
  [ValidateSet('Install', 'Uninstall', 'Start', 'Stop', 'Status', 'Info', 'Open', 'Help', 'Mayday')]
  [String]$Command                   = 'Help',
  [string]$MinikubeVersion           = '0.22.3',
  [string]$MinikubeKubernetesVersion = '1.7.5',
  [string]$MinikubeCpus              = 1,
  [string]$MinikubeMemory            = 4096,
  [string]$KubectlVersion            = '1.7.6',
  [string]$PuppetDiscoveryVersion    = 'latest',
  [switch]$Force
)

Begin {
  # Check for runas Admin and error out if not elevated.
  If (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Throw "This script must be executed in an elevated administrative shell"
    Return
  }
  # Check for Windows 10 and error out if on another OS.
  If ((Get-WmiObject -Class Win32_OperatingSystem).Version -notmatch '^10.') {
    Throw 'Puppet Discovery is only supported on Windows 10.'
    Return
  }
  # Check for Hyper-V Install and error out if not available.
  If ((Get-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V -Online).State -ne 'Enabled') {
    Throw 'Puppet Discovery requires Hyper-V to be installed.'
    Return
  }
  # Get the current time for logging and analytics.
  $TimeStamp = Get-Date -Format FileDateTimeUniversal
  # Initialize the variables for necessary paths.
  $PuppetDiscoveryPath = "$env:ProgramData\puppet-discovery"
  $DebugDirectory      = "$PuppetDiscoveryPath\debug"
  $MiniKubeUrl         = "https://storage.googleapis.com/minikube/releases/v${MinikubeVersion}/minikube-windows-amd64.exe"
  $MiniKubePath        = "$PuppetDiscoveryPath\minikube.exe"
  $KubeCtlUrl          = "https://storage.googleapis.com/kubernetes-release/release/v${KubectlVersion}/bin/windows/amd64/kubectl.exe"
  $KubeCtlPath         = "$PuppetDiscoveryPath\kubectl.exe"
  # Add the PuppetDiscovery folder to the path for minikube/kubectl
  $env:Path += ";$PuppetDiscoveryPath"
  # Set environment variables for sandboxing
  $KubeConfigPath      = "$PuppetDiscoveryPath\.kubeconfig"
  If ([string]::IsNullOrEmpty($env:KUBECONFIG)) {
    $env:KUBECONFIG    = $KubeConfigPath
  } ElseIf ($env:KUBECONFIG -notmatch $KubeConfigPath.Replace('\','\\').Replace('.','\.')) {
    $env:KUBECONFIG   += ";$KubeConfigPath"
  }
  $env:MINIKUBE_HOME = $PuppetDiscoveryPath
  # List the pods we'll deploy for use in checking status.
  $Pods = 'cmd-controller','ingest','ingress-controller','mosquitto','operator','query','ui'

  # Define a private function for calling minikube and kubectl.
  # This allows us to capture output and/or ignore errors, which we can't do by default.
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
    ForEach ($File in (($OutputFile, $ErrorFile) | Where-Object {-not [string]::IsNullOrEmpty($_)})) {
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

  Function Invoke-Minikube {
    [cmdletbinding()]
    Param (
    [string]$ArgumentList,
    [switch]$PassThru
    )
    $PSBoundParameters.ArgumentList = "$ArgumentList --profile puppet-discovery-minikube"
    Invoke-Binary -Path $MiniKubePath @PSBoundParameters
  }

  Function Start-PuppetDiscovery {
    Invoke-Kubectl -ArgumentList 'run operator --image=gcr.io/puppet-discovery/puppet-discovery-operator:latest -- --release-channel=preview'
  }

  Function Start-Minikube {
    # This script will _always_ use the Hyper-V driver.
    # However, we need to retrieve an _external_ virtual switch for use.
    $VMDriverString = "--vm-driver=hyperv"
    Write-Host "Kubernetes requires at least one available external virtual switch."
    If (@(Get-VMSwitch -SwitchType External).Count -lt 1) {
      # If the force parameter is specified, don't confirm at prompt - useful for CI.
        New-VMSwitch -Name vExternal -NetAdapterName (Get-NetAdapter -Physical | Where-Object -FilterScript {$_.Status -eq 'Up'})[0].Name -Confirm:$(-not $Force)
    }
    Write-Host "Using external virtual switch [$((Get-VMSwitch -SwitchType External).Name)]"
    $VMDriverString += " --hyperv-virtual-switch=$((Get-VMSwitch -SwitchType External).Name)"
    Invoke-Minikube -ArgumentList "start --kubernetes-version v$MinikubeKubernetesVersion --cpus $MinikubeCpus --memory $MinikubeMemory $VMDriverString"
    # Verify that the vm actually comes up and is usable, or error if too much time passes.
    $i = 0
    While ((Invoke-Kubectl -ArgumentList 'get nodes' -PassThru | Where-Object {$_ -match 'ready'}).Count -eq $null) {
      $i++
      Start-Sleep -Seconds 5
      If ($i -gt 120) {
        Throw "We timed out waiting for the operation to finish."
        Return
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
    New-Item -Path "$DebugDirectory\puppet-discovery-minikube" -ItemType Directory -Force | Out-Null
    If (-not (Test-Path $DebugDirectory)) {
      New-Item -Path $DebugDirectory -Force -ItemType Directory | Out-Null
    }
    Write-Host "Grabbing Minikube cluster dump..."
    Invoke-Kubectl -ArgumentList "cluster-info dump --all-namespaces --output-directory=`"$LogsDirectory`""

    Write-Host "`nGrabbing Puppet Discovery Deployment info..."
    Invoke-Kubectl -PassThru -ArgumentList 'get pd -o yaml'  | Out-File -FilePath "$LogsDirectory\puppet-discovery-minikube\pd-info.yaml" -Force

    Write-Host "Grabbing StatefulSet info..."
    Invoke-Kubectl -PassThru -ArgumentList 'get sts -o yaml' | Out-File -FilePath  "$LogsDirectory\puppet-discovery-minikube\sts-info.yaml" -Force

    Write-Host "Grabbing Minikube cluster info..."
    Invoke-Kubectl -PassThru -ArgumentList 'get all -o yaml' | Out-File -FilePath "$LogsDirectory\cluster-all.yaml" -Force

    Write-Host "Creating debug archive..."
    Compress-Archive -Path $LogsDirectory -DestinationPath $ArchivePath -CompressionLevel Optimal -Force | Out-Null

    Write-Host "Cleaning up..."
    Remove-Item -Path $LogsDirectory -Recurse -Force

    Write-Host "A debug archive file can be found at $ArchivePath"
  }
}

Process {
  Switch ($Command) {
    "Install" {
      # Welcome message and EULA display
      Write-Host '================================================================================='
      Write-Host '                               _         _ _                                    '
      Write-Host '                              | |       | (_)                                   '
      Write-Host '  _ __  _   _ _ __  _ __   ___| |_    __| |_ ___  ___ _____   _____ _ __ _   _  '
      Write-Host ' |  _ \| | | |  _ \|  _ \ / _ \ __|  / _` | / __|/ __/ _ \ \ / / _ \  __| | | | '
      Write-Host ' | |_) | |_| | |_) | |_) |  __/ |_  | (_| | \__ \ (_| (_) \ V /  __/ |  | |_| | '
      Write-Host ' | .__/ \__,_| .__/| .__/ \___|\__|  \__,_|_|___/\___\___/ \_/ \___|_|   \__, | '
      Write-Host ' | |         | |   | |                                                    __/ | '
      Write-Host ' |_|         |_|   |_|                                                   |___/  '
      Write-Host '================================================================================='
      Write-Host ""
      Write-Host ""
      Write-Host "Thank you for downloading Puppet Discovery Tech Preview."
      Write-Host ""
      Write-Host ""
      Write-Host "By installing this software, you agree to the End User License Agreement"
      Write-Host "found at https://puppet.app.box.com/v/puppet-discovery-eula"
      Write-Host ""
      Read-Host -Prompt "Press [Enter] key to start installation"

      If (-not (Test-Path -Path $PuppetDiscoveryPath)) {
        mkdir $PuppetDiscoveryPath -Force | Out-Null
      }

      If (-not (Test-Path $MiniKubePath)) {
        Write-Host 'downloading minikube...'
        (New-Object System.Net.WebClient).DownloadFile($MiniKubeUrl, $MiniKubePath)
      }

      If (-not (Test-Path $KubeCtlPath)) {
        Write-Host 'downloading kubectl...'
        (New-Object System.Net.WebClient).DownloadFile($KubeCtlUrl, $KubeCtlPath)
      }

      Write-Host 'start minikube cluster...'
      Start-Minikube

      Write-Host 'wait till cluster is in Running state...'
      $i = 1
      While ((Invoke-Minikube -ArgumentList 'status --format "{{.MinikubeStatus}}"' -PassThru) -ne 'Running') {
        Start-Sleep -Seconds $i
        $i++
        If ($i -ge 10) {
          Throw "Status retrieval timed out"
          Return
        }
      }

      Write-Host 'reconfigure minikube vm...'
      Invoke-Minikube -ArgumentList 'ssh "sudo sysctl -w  vm.max_map_count=262144"'

      Write-Host 'deploy services...'
      Start-PuppetDiscovery

      Write-Host 'waiting for services...'
      $i = 1
      While ((Get-PuppetDiscoveryStatus -ErrorAction SilentlyContinue -OutVariable Status | Where-Object {$_ -match 'success'}).Count -ne $Pods.Count) {
        Start-Sleep -Seconds 10
        $i++
        If ($i -ge 60) {
          Throw "We timed out waiting for the operation to finish."
          Return
        }
      }
      $Status
    }
    "Uninstall" {
      Write-Host 'puppet-discovery uninstall'
      If (Test-Path $MiniKubePath) {
        Invoke-Minikube -ArgumentList 'stop'
        Invoke-Minikube -ArgumentList 'delete'
      }
      If (Test-Path  $PuppetDiscoveryPath -Type Container) {
        Write-Host 'cleanup puppet-discovery installation location...'
        Remove-Item -Path $PuppetDiscoveryPath -Recurse -Force
      }
    }
    "Start" {
      Write-Host 'puppet-discovery start'
      Start-Minikube
    }
    "Stop" {
      Write-Host 'puppet-discovery stop'
      Invoke-Minikube -ArgumentList 'stop'
    }
    "Status" {
      Write-Host 'puppet-discovery status'
      Get-PuppetDiscoveryStatus
    }
    "Info" {
      Write-Host 'puppet-discovery info'
      $UrlPrefix = Invoke-Minikube -ArgumentList 'service ingress --url --https' -PassThru
      Write-Host "---------------------------------------------"
      Write-Host "open '$UrlPrefix/' to access the ui."
      Write-Host "open '$UrlPrefix/pdp/query/index.html' for query."
      Write-Host "Open '$UrlPrefix/pdp/ingest' for ingest."
      Write-Host "Open '$UrlPrefix/cmd/graphiql' to hit the GraphiQL service for commands."
      Write-Host "Open '$UrlPrefix/cmd/graphql' for the commands graphql api."
      Write-Host "Open '$UrlPrefix/ws' for the cmd-controller web sockets api."
      Write-Host "Open '$UrlPrefix/command' for the cmd-controller command api."
      Write-Host "---------------------------------------------"
    }
    "Open" {
      Write-Host 'puppet-discovery open'
      # Note: If the browser is not already open, this will cause the CLI to hang until the browser is closed.
      # Possibly because the browser is a child process of this call to minikube.
      Invoke-Minikube -ArgumentList 'service ingress --https'
    }
    "Help" {
      Get-Help $MyInvocation.MyCommand.Source -Full
    }
    "Mayday" {
      Write-Host 'puppet-discovery mayday'
      New-PuppetDiscoveryLogArchive
    }
  }
}
