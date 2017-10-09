## How to install Puppet Discovery tech preview
### *Mac/Linux*
1. Get the script
  * ```curl -Lo puppet-discovery https://raw.githubusercontent.com/puppetlabs/puppet-discovery-preview/master/puppet-discovery.sh && chmod +x puppet-discovery```
2. Run ```./puppet-discovery install```
3. Open the ui with ```./puppet-discovery open```
4. For a full list of available commands, run ```./puppet-discovery help```

### *Windows 10+*
1. Get the script
  * ```Set-ExecutionPolicy Bypass -Scope Process; Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/puppetlabs/puppet-discovery-preview/master/puppet-discovery.ps1' -OutFile .\puppet-discovery.ps1```
2. Run ```.\puppet-discovery.ps1 install```
3. Open the ui with ```.\puppet-discovery.ps1 open```
4. For a full list of available commands, run ```.\puppet-discovery.ps1 help```
