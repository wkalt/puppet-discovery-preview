#requires -runasadministrator
<#
  .SYNOPSIS
    A script for bootstrapping and using Puppet Discovery.

  .DESCRIPTION
    A script for bootstrapping and using Puppet Discovery.

    NOTE: Puppet Discovery requires VirtualBox to run. Please download and install Virtualbox before trying to use
    Puppet Discovery.

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

  .PARAMETER VMDriver
    Specify this parameter to overwrite the hypervisor used for Puppet Discovery. On Windows, you
    can use either Hyper-V or VirtualBox. Puppet Discovery assumes Hyper-V by default.

  .PARAMETER Force
    Specify this parameter to skip confirmation checks, enabling you to run in CI if needed.

#>
[cmdletbinding()]
param (
  [ValidateNotNullOrEmpty()]
  [ValidateSet('Install', 'Uninstall', 'Start', 'Stop', 'Status', 'Info', 'Open', 'Deploy', 'Upgrade', 'Help')]
  [String]$Command = 'Help',
  [string]$MinikubeVersion = '0.22.0',
  [string]$MinikubeKubernetesVersion = '1.7.5',
  [string]$MinikubeCpus = 1,
  [string]$MinikubeMemory = 4096,
  [string]$KubectlVersion = '1.7.6',
  [string]$PuppetDiscoveryVersion = 'latest',
  [ValidateSet('hyperv','virtualbox')]
  [string]$VMDriver = 'hyperv',
  [switch]$Force
)

Begin {
  # Initialize the variables for necessary paths.
  $PuppetDiscoveryPath = "$env:ProgramData\puppet-discovery"
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
  
  # Throw an error, halting execution if any command other than help is run.
  if (-Not (Get-Command VBoxManage.exe -ErrorAction SilentlyContinue) -and ($Command -in @('Install','Start')) -and ($VMDriver -eq 'virtualbox')) {
    Throw "VirtualBox is currently missing from your PATH. Visit https://www.virtualbox.org/wiki/Downloads and follow directions to install for your platform."
  } ElseIf ($VMDriver -eq 'hyperv' -and ((Get-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V -Online).State -ne 'Enabled')) {
    Throw "Hyper-V is not currently enabled and you did not specify VirtualBox as your driver. If you want to use Hyper-V for Puppet Discovery, please install it before using this tool."
  }
  
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
    If (-not ([string]::IsNullOrEmpty($VMDriver))) {
      $VMDriverString = "--vm-driver=$VMDriver"
    }
    If ($VMDriver -eq 'hyperv') {
      Write-Host "Kubernetes requires at least one available external virtual switch."
      If (@(Get-VMSwitch -SwitchType External).Count -lt 1) {
        # If the force parameter is specified, don't confirm at prompt - useful for CI.
          New-VMSwitch -Name vExternal -NetAdapterName (Get-NetAdapter)[0].Name -Confirm:$(!$Force)
      }
      Write-Host "Using external virtual switch [$((Get-VMSwitch -SwitchType External).Name)]"
      $VMDriverString += " --hyperv-virtual-switch=$((Get-VMSwitch -SwitchType External).Name)"
    }
    Invoke-Minikube -ArgumentList "start --kubernetes-version v$MinikubeKubernetesVersion --cpus $MinikubeCpus --memory $MinikubeMemory $VMDriverString"
  }

  Function Get-PuppetDiscoveryStatus  {
    [cmdletbinding()]
    Param ()
    ForEach ($Pod in $Pods) {
      Invoke-Kubectl -ArgumentList "rollout status deploy/$Pod --watch=false" -PassThru
    }
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
  }
}