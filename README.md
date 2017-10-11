## How to install Puppet Discovery tech preview
### *Mac/Linux*
1. Get the script
  * ```curl -Lo puppet-discovery https://raw.githubusercontent.com/puppetlabs/puppet-discovery-preview/master/puppet-discovery.sh && chmod +x puppet-discovery```
2. Run ```./puppet-discovery install```
3. Open the ui with ```./puppet-discovery open```
4. For a full list of available commands, run ```./puppet-discovery help```

### *Windows 10+*
1. Open a PowerShell terminal as Administrator
2. Get the script
  * ```Set-ExecutionPolicy Bypass -Scope Process; Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/puppetlabs/puppet-discovery-preview/master/puppet-discovery.ps1' -OutFile .\puppet-discovery.ps1```
3. Run ```.\puppet-discovery.ps1 install```
4. Open the ui with ```.\puppet-discovery.ps1 open```
5. For a full list of available commands, run ```.\puppet-discovery.ps1 help```

### *Installing on a Linux VM*
Direct installation onto a host is possible using localkube and root
privileges. This requires docker and will modify the root user's home
directory. A throwaway VM is assumed.

1. [Install docker-ce](https://docs.docker.com/engine/installation/) if missing.
2. Start docker if it isn't running.
3. Get the script
  * ```curl -Lo puppet-discovery https://raw.githubusercontent.com/puppetlabs/puppet-discovery-preview/master/puppet-discovery.sh && chmod +x puppet-discovery```
4. As root, run ```ALLOW_ROOT=true PUPPET_DISCOVERY_SKIP_VBOX=true MINIKUBE_VM_DRIVER=none ./puppet-discovery install```
5. Open the ui with ```./puppet-discovery open```
6. For a full list of available commands, run ```./puppet-discovery help```

By using this software, you agree to the End User License Agreement found at the URL https://puppet.app.box.com/v/puppet-discovery-eula
