#!/usr/bin/env bash
#  puppet-discovery.sh
INSTALLER_VERSION=0.1.0
MINIKUBE_VERSION=0.22.3
MINIKUBE_KUBERNETES_VERSION="v1.7.5"
KUBECTL_VERSION=v1.7.6
KUBETAIL_VERSION=1.4.1
KUBECONFIG_FILE=.kubeconfig
TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%S%z)
HEAP_APP_ID="2653197683"

function debug-mode() {
    [[ -n $DEBUG ]]
}

# Add overrides for development environment
if [ -f pd-dev.sh ]; then
    source pd-dev.sh
fi

function install-path() {
    local _install_path=${INSTALL_PATH:-$HOME/opt/puppet/discovery}
    echo "${_install_path}"
}

# Assumes script stays in /script directory
function project-root() {
    local _dir=
    local _root=
    _dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

    pushd "${_dir}/../" > /dev/null
    _root=$(pwd)
    popd > /dev/null

    echo "$_root"
}

function os-str() {
    uname | tr '[:upper:]' '[:lower:]'
}


function arch-str() {
    echo "amd64"
}

function minikube-cmd() {
    local _install_path=
    _install_path=$(install-path)

    if debug-mode; then
      KUBECONFIG="${_install_path}/${KUBECONFIG_FILE}" \
        MINIKUBE_HOME="${_install_path}" \
        "${_install_path}"/minikube \
        --profile puppet-discovery-minikube \
        --loglevel 0 \
        --logtostderr \
        --stderrthreshold 0 \
        --v 0 \
        "${@}"
    else
      KUBECONFIG="${_install_path}/${KUBECONFIG_FILE}" \
        MINIKUBE_HOME="${_install_path}" \
        "${_install_path}"/minikube \
        --profile puppet-discovery-minikube \
        "${@}"
    fi
}

function minikube-url() {
    local _minikube_url=
    _minikube_url="https://storage.googleapis.com/minikube/releases/v${MINIKUBE_VERSION}/minikube-$(os-str)-$(arch-str)"

    echo "${_minikube_url}"
}

function minikube-logs() {
    local _pod=
    local _install_path=
    _install_path=$(install-path)
    _pod=$1

    KUBECONFIG="${_install_path}/${KUBECONFIG_FILE}" \
    PATH=${_install_path}:${PATH} \
    "${_install_path}"/kubetail \
                      --context puppet-discovery-minikube \
                      "${_pod}"
}

function kubectl-cmd() {
    local _install_path=
    _install_path="$(install-path)"

    "${_install_path}"/kubectl \
                    --kubeconfig="${_install_path}/${KUBECONFIG_FILE}" \
                    --context=puppet-discovery-minikube \
                    "${@}"
}

function kubectl-url() {
    local _kubectl_url=
    _kubectl_url="https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/$(os-str)/$(arch-str)/kubectl"

    echo "${_kubectl_url}"
}

function kubetail-url() {
    local _kubetail_url="https://raw.githubusercontent.com/johanhaleby/kubetail/${KUBETAIL_VERSION}/kubetail"
    echo "${_kubetail_url}"
}

function download-file() {
    local _url=$1
    local _destination=$2

    if ! curl --progress-bar -Lo "${_destination}" "${_url}"; then
        echo "curl failed to download ${_url}, retrying using wget"
        wget -q --show-progress -O "${_destination}" "${_url}"
    fi
    if [[ ! -a "$_destination" ]]; then
        echo "ERROR: file $_destination was not created successfully, aborting install"
        exit 1
    fi
}

function binary-exists() {
    local _r=
    local _command=$1

    command -v "${_command}" >/dev/null && _r=0 || _r=1

    return $_r
}

function skip-virtualbox-install() {
    [[ ! -z $PUPPET_DISCOVERY_SKIP_VBOX ]]
}

function ensure-virtualbox() {
    if ! binary-exists VBoxManage && ! skip-virtualbox-install;
    then
        echo "VirtualBox is currently missing from your system."
        echo "Visit https://www.virtualbox.org/wiki/Downloads and"
        echo "follow directions to install for your platform"

        exit 1
    fi
}

function ensure-eula() {
    echo "By installing this software, you agree to the End User License Agreement"
    echo "found at https://puppet.app.box.com/v/puppet-discovery-eula"
    echo ""
    if [[ -z ${RUN_FULL_DEPLOY} ]]; then
      read -r -p "Press [Enter] key to start installation..."
    fi
}

function remove-install-directory() {
    local _install_path=
    _install_path="$(install-path)"

    if [ -d "${_install_path}" ]; then
        echo "Removing installation directory..."
        # TODO: add validations, this makes me nervous
        rm -rf "${_install_path}"
    fi
}

function ensure-install-directory() {
    local _install_path=
    _install_path="$(install-path)"

    if [ ! -d "${_install_path}" ]; then
        echo "Setting up installation directory..."
        mkdir -p "${_install_path}"
    fi
}

function ensure-minikube() {
    local _install_path=
    local _minikube_url=
    _install_path=$(install-path)
    _minikube_url="$(minikube-url)"

    if ! binary-exists "${_install_path}/minikube";
    then
        echo "Downloading minikube..."
        download-file "${_minikube_url}" "${_install_path}/minikube"
        chmod +x "${_install_path}"/minikube
    fi
}

function ensure-kubectl() {
    local _install_path=
    local _kubectl_url=
    _install_path="$(install-path)"
    _kubectl_url="$(kubectl-url)"

    if ! binary-exists "${_install_path}/kubectl";
    then
        echo "Downloading kubectl..."
        download-file "${_kubectl_url}" "${_install_path}/kubectl"
        chmod +x "${_install_path}/kubectl"
    fi
}

function ensure-kubeconfig {
  local _install_path=
  _install_path="$(install-path)"

  echo "Generating kubeconfig..."
  if [ ! -f "${_install_path}/${KUBECONFIG_FILE}" ];
  then
      kubectl-cmd config set-context puppet > /dev/null 2>&1
      kubectl-cmd config delete-context puppet > /dev/null 2>&1
  fi
}

function ensure-kubetail() {
    local _install_path=
    local _kubetail_url=
    _install_path="$(install-path)"
    _kubetail_url="$(kubetail-url)"

    if ! binary-exists "${_install_path}/kubetail";
    then
        echo "Downloading kubetail..."
        download-file "${_kubetail_url}" "${_install_path}/kubetail"
        chmod +x "${_install_path}/kubetail"
    fi
}

function configure-minikube() {
    local _install_path=
    local _minikube_config_dir=
    _install_path=$(install-path)

    _minikube_config_dir=${_install_path}/.minikube/config

    if [ ! -d "${_minikube_config_dir}" ]; then
      echo "Generating minikube config directory"
      mkdir -p "${_minikube_config_dir}"
    fi

    echo "Setting up minikube config..."

    cat > "${_minikube_config_dir}"/config.json <<EOF
{
  "WantKubectlDownloadMsg": false,
  "default-storageclass": false
}
EOF
}

function minikube-start() {
    if [[ ! -z "${MINIKUBE_VM_DRIVER}" ]];
    then
        vm_driver="--vm-driver=${MINIKUBE_VM_DRIVER}"
    fi

    echo "Starting minikube..."
    if ! minikube-cmd start \
                  --kubernetes-version $MINIKUBE_KUBERNETES_VERSION \
                  --cpus "$(minikube-cpus)" \
                  --memory "$(minikube-memory)" \
                  $vm_driver
    then
        echo "ERROR: minikube failed to start, aborting install"
        exit 1
    fi

    printf "Waiting for minikube to finish starting..."
    (block-on kubectl-cmd get nodes | grep Ready) &
    spinner $!

    echo ""
}

function minikube-cpus() {
    local _cpus=
    _cpus=${MINIKUBE_CPUS:-1}

    echo "$_cpus"
}

function minikube-memory() {
    local _memory=
    _memory=${MINIKUBE_MEMORY:-4096}

    echo "$_memory"
}

function minikube-stop() {
    echo "Stopping minikube..."
    minikube-cmd stop
}

function minikube-delete() {
    echo "Deleting minikube..."
    minikube-cmd delete
}

function minikube-status() {
    minikube-cmd status --format "{{.MinikubeStatus}}"
}

function puppet-it-managed() {
    [ -d /opt/puppet-it ] && echo "true" || echo "false"
}

function post-measurement() {
    local _action=
    local _payload=
    local _identity=
    _action="${*}"
    _identity=$(unique-system-id)

    _payload=$(cat <<EOF
{
    "app_id": "${HEAP_APP_ID}",
    "identity": "${_identity}",
    "event": "${_action}",
    "timestamp": "${TIMESTAMP}",
    "properties": {
        "category": "cli",
        "platform": "$(os-str)",
        "puppet-employee": "$(puppet-it-managed)"
    }
}
EOF
)

    # Do not send analytics if DISABLE_ANALYTICS flag is set
    if [[ -z "${DISABLE_ANALYTICS}" ]]; then
        curl \
            -X POST \
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            -d "${_payload}" \
            https://heapanalytics.com/api/track > /dev/null 2>&1 &
    fi

}

function generate-uuid() {
    if [[ -a /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    elif binary-exists uuidgen; then
        uuidgen
    elif binary-exists python; then
        python  -c 'import uuid; print uuid.uuid1()'
    elif binary-exists od && binary-exists awk; then
        od -x /dev/urandom | head -1 | awk '{OFS="-"; print $2$3,$4,$5,$6,$7$8$9}'
    fi
}

function unique-system-id() {
    local _uuid=
    _uuid="$(install-path)/.uuid"

    if [[ ! -f "${_uuid}" ]];
    then
        generate-uuid | tee "${_uuid}" > /dev/null
    fi
    cat "${_uuid}"
}

function generate-log-tarball() {
    local _log_dir=
    local _debug_dir=
    local _archive_file=
    _log_dir=$(mktemp -d)
    _debug_dir="$(project-root)/debug"
    _archive_file="${_debug_dir}/puppet-discovery-log-${TIMESTAMP}.tar.gz"

    mkdir -p "${_log_dir}/puppet-discovery-minikube"
    mkdir -p "${_debug_dir}"

    echo "Grabbing Minikube cluster dump..."
    kubectl-cmd cluster-info dump --all-namespaces --output-directory="${_log_dir}"
    echo ""

    echo "Grabbing Puppet Discovery Deployment info..."
    kubectl-cmd get pd -o yaml > "${_log_dir}/puppet-discovery-minikube/pd-info.yaml"

    echo "Grabbing StatefulSet info..."
    kubectl-cmd get sts -o yaml > "${_log_dir}/puppet-discovery-minikube/sts-info.yaml"

    echo "Grabbing Minikube cluster info..."
    kubectl-cmd get all -o yaml > "${_log_dir}/cluster-all.yaml"

    echo "Creating debug archive..."
    tar \
        -czf \
        "${_archive_file}" \
        -C "${_log_dir}" \
        .

    echo "Cleaning up..."
    rm -rf "${_log_dir}"

    echo ""
    echo "A debug archive file can be found at ${_archive_file}"
}

function spinner() {
    local pid=$1
    local delay=0.75
    local spinstr="|/-\\"

    trap 'kill $pid' INT

    while ps a | awk '{print $1}' | grep -q "${pid}"; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"

    trap - INT
}

function getting-started() {
    cmd-open
    echo
    echo "To get started with Puppet Discovery, run:"
    echo "./puppet-discovey.sh open"
}

function cmd-deploy() {
    local _analytics_args=
    local _unique_system_id=
    _unique_system_id="$(unique-system-id)"

    echo "Deploying Puppet Discovery..."
    echo "Depending on your system resources, this may take a couple of minutes."
    echo ""

    if [ -z "${DISABLE_ANALYTICS+x}" ]; then
        _analytics_args="--unique-id=${_unique_system_id}"
    else
        _analytics_args="--disable-analytics=true"
    fi

    if [ -n "$(type -t deploy-operator)" ] && [ "$(type -t deploy-operator)" = function ]; then
      deploy-operator
    else
      kubectl-cmd run \
                  operator \
                  --image=gcr.io/puppet-discovery/puppet-discovery-operator:latest -- \
                  $_analytics_args
    fi

    printf "Waiting for Puppet Discovery to finish starting..."
    (block-on puppet-discovery-status) &
    spinner $!

    kubectl-cmd get pd > /dev/null 2>&1; # hydrate model alias for future queries

    echo ""
    puppet-discovery-status
}

function cmd-version() {
    echo "Puppet Discovery"
    echo ""
    echo "Installer: ${INSTALLER_VERSION}"
    echo "Discovery: $(puppet-discovery-version)"

    exit 0
}

function welcome() {
    echo '================================================================================='
    echo '                               _         _ _                                    '
    echo '                              | |       | (_)                                   '
    echo '  _ __  _   _ _ __  _ __   ___| |_    __| |_ ___  ___ _____   _____ _ __ _   _  '
    echo ' |  _ \| | | |  _ \|  _ \ / _ \ __|  / _` | / __|/ __/ _ \ \ / / _ \  __| | | | '
    echo ' | |_) | |_| | |_) | |_) |  __/ |_  | (_| | \__ \ (_| (_) \ V /  __/ |  | |_| | '
    echo ' | .__/ \__,_| .__/| .__/ \___|\__|  \__,_|_|___/\___\___/ \_/ \___|_|   \__, | '
    echo ' | |         | |   | |                                                    __/ | '
    echo ' |_|         |_|   |_|                                                   |___/  '
    echo '================================================================================='
    echo ""
    echo ""
    echo "Thank you for downloading Puppet Discovery Tech Preview."
    echo ""
    echo ""
}

function cmd-install() {

    welcome

    ensure-eula

    echo ""
    echo "Installing Puppet Discovery..."

    ensure-install-directory

    post-measurement "cmd-install"

    ensure-virtualbox
    ensure-kubectl
    ensure-kubeconfig
    ensure-minikube
    ensure-kubetail

    configure-minikube

    cmd-start

    if [ -n "$(type -t select-channel)" ] && [ "$(type -t select-channel)" = function ]; then
      select-channel
    fi

    if puppet-discovery-private; then
        warning-and-google-auth
    fi

    if [[ -z ${RUN_FULL_DEPLOY} ]]; then
      if [[ ${REQUIRE_AUTH} == true ]]; then
        echo
        read -r -p "Press [Enter] key to load gcloud service account into minikube..."
        echo
        mount-gcr-auth
      fi

      echo
      read -r -p "Press [Enter] key to start installation..."
      echo
      if cmd-deploy; then
        getting-started
      fi
    fi
}

function cmd-uninstall() {
    echo "Uninstalling Puppet Discovery..."

    post-measurement "cmd-uninstall"
    cmd-stop
    minikube-delete
    remove-install-directory
}

function cmd-start() {
    echo "Starting Puppet Discovery..."

    post-measurement "cmd-start"
    minikube-start
}

function cmd-stop() {
    echo "Stopping Puppet Discovery..."

    post-measurement "cmd-stop"
    minikube-stop
}

function cmd-status() {
    echo "Checking Puppet Discovery status..."

    puppet-discovery-status
    echo ""
}

function cmd-info() {
    echo "Retrieving Puppet Discovery info..."

    printf "Waiting for Puppet Discovery to finish starting..."
    (block-on puppet-discovery-status) &
    spinner $!

    puppet-discovery-info
}

function cmd-open() {
    echo "Opening Puppet Discovery..."

    post-measurement "cmd-open"

    printf "Waiting for Puppet Discovery to finish starting..."
    (block-on puppet-discovery-status) &
    spinner $!

    echo ""
    minikube-cmd service ingress --https
}

function cmd-logs() {
    echo "Retrieving Puppet Discovery logs..."

    post-measurement "cmd-logs"
    ensure-kubetail
    minikube-logs "$@"
}

function cmd-logs-help() {
    echo "Usage: $0 logs (pod)"
    echo ""
    echo "Available pods:"
    echo "  (no argument)          - Retrieve all logs in cluster"
    echo "  agent                  - Disco agent logs"
    echo "  elasticsearch          - elasticsearch logs"
    echo "  cmd-controller         - Disco cmd-controller logs"
    echo "  ingest                 - PDP ingest logs"
    echo "  ingress                - Ingress logs"
    echo "  mosquitto              - MQTT logs"
    echo "  operator               - Discovery operator logs"
    echo "  query                  - PDP query logs"
    echo "  ui                     - UI logs"
}

function cmd-mayday() {
    echo "Generating Puppet Discovery troubleshooting tarball..."
    generate-log-tarball
}

function cmd-help() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Available Commands:"
    echo "  install   - Install the puppet-discovery control-plane and services"
    echo "  uninstall - Remove the puppet-discovery control-plane and services"
    echo "  start     - Start the puppet-discovery services"
    echo "  stop      - Stop the puppet-discovery services"
    echo "  status    - Show puppet-discovery service status"
    echo "  info      - List all puppet-discovery service endpoints"
    echo "  logs      - Tail output logs from puppet-discovery"
    echo "  open      - Open puppet-discovery dashboard inside browser"
    echo "  version   - Query the control-plane for the installed version"
    echo "  mayday    - Generate a troubleshooting archive to send to Puppet"
    if [ -n "$(type -t cmd-channel)" ] && [ "$(type -t cmd-channel)" = function ]; then
      echo "  channel   - Switch to a different release channel for puppet-discovery"
    fi
    echo "  help      - This help screen"

    exit 1
}

function puppet-discovery-status() {
    local pod=
    local _exit=
    _exit=0

    for pod in cmd-controller ingest ingress-controller mosquitto operator query ui;
    do
        printf "  %s: " "${pod}"

        if kubectl-cmd rollout status deploy/"$pod" --watch=false 2> /dev/null | grep -q "successfully rolled out";
        then
            printf "✓\n"
        else
            _exit=$(( _exit + 1 ))
            printf "✗\n"
        fi
    done

    if [[ _exit -gt 0 ]]; then return 1; else return 0; fi
}

function block-on() {
    local _max_retries=120 # this effectively gives us a 10 minute timeout
    until "$@" > /dev/null 2>&1 || [ $_max_retries -eq 1 ];
    do
        _max_retries=$(( _max_retries - 1 ))
        sleep 5
    done
    if [ $_max_retries -eq 1 ]; then
      echo "We timed out waiting for the operation to finish. Please check the logs. This can be accomplished via the 'logs' command. "
    fi
}

function puppet-discovery-version() {
    local _version=


    if kubectl-cmd get pd > /dev/null;
    then
        _version="$(kubectl-cmd get pd -o jsonpath='{..spec.releaseChannel}')"@"$(kubectl-cmd get pd -o jsonpath='{..spec.versionTag}')"
    else
        _version="Unknown version. Check status"
    fi

    echo "$_version"
}

function puppet-discovery-info() {
    local _ns=
    local _miniurl=

    _ns=${MINIKUBE_NS:-default}
    _miniurl=$(minikube-cmd service -n "${_ns}" ingress --url --https)

    echo "---------------------------------------------"
    echo "open ${_miniurl}/ to access the ui."
    echo "open ${_miniurl}/pdp/query/index.html for query."
    echo "Open ${_miniurl}/pdp/ingest for ingest."
    echo "Open ${_miniurl}/cmd/graphiql to hit the GraphiQL service for commands."
    echo "Open ${_miniurl}/cmd/graphql for the commands graphql api."
    echo "Open ${_miniurl}/ws for the cmd-controller web sockets api."
    echo "Open ${_miniurl}/command for the cmd-controller command api."
    echo "---------------------------------------------"
}

function puppet-discovery-private() {
    [[ ! -z $PUPPET_DISCOVERY_PRIVATE ]] && [[ ${PUPPET_DISCOVERY_PRIVATE} == true ]]
}

function puppet-discovery() {
    local _os=
    local _command=
    _command="${1}"
    _os=$(os-str)
    shift;


    # Attempt to call command-specific help if defined
    if [[ "${*: -1}" = "help" ]];
    then
        eval "declare -F cmd-${_command}-help &>/dev/null && cmd-${_command}-help || cmd-help"
        exit 1
    fi

    # Call OS command if defined
    eval "declare -F cmd-${_command}-${_os} &>/dev/null && cmd-${_command}-${_os} $*"

    # Call global command
    eval "declare -F cmd-${_command} &>/dev/null && cmd-${_command} $* || cmd-help"
}

# Main Entry Point
if [[ $EUID -eq 0 && "$ALLOW_ROOT" != "true" ]]; then
    echo "**************************************************************"
    echo "This script must not be run as root, or else some minikube"
    echo "files in your home directory may become owned by root."
    echo "**************************************************************"
    echo ""
    cmd-help
    exit 1
fi

if [[ $# -eq 0 ]]; then cmd-help; fi

puppet-discovery "$@"
