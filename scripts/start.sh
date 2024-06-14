#!/usr/bin/env bash
# ---------------------------------------------------------------------------- #
#                          Function Definitions                                #
# ---------------------------------------------------------------------------- #

check_cuda_version() {
    # Extract the CUDA version using nvidia-smi
    CURRENT_CUDA_VERSION=$(nvidia-smi | grep "CUDA Version" | awk -F 'CUDA Version: ' '{print $2}' | awk '{print $1}')

    # Check if the CUDA version was successfully extracted
    if [[ -z "${CURRENT_CUDA_VERSION}" ]];
    then
        echo "CUDA version not found. Make sure that CUDA is properly installed."
        exit 1
    fi

    # Compare the CUDA version with the required version
    if [[ $(printf '%s\n' "${REQUIRED_CUDA_VERSION}" "${CURRENT_CUDA_VERSION}" | sort -V | head -n1) != "${REQUIRED_CUDA_VERSION}" ]];
    then
        echo "Current CUDA version (${CURRENT_CUDA_VERSION}) is older than required (${REQUIRED_CUDA_VERSION})."
        echo "Please switch to a pod with CUDA version ${REQUIRED_CUDA_VERSION} or higher by selecting the appropriate filter on Pod deploy."
        exit 1
    else
        echo "CUDA version is sufficient: ${CURRENT_CUDA_VERSION}"
    fi
}

start_nginx() {
    echo "Starting Nginx service..."
    service nginx start
}

execute_script() {
    local script_path=$1
    local script_msg=$2
    if [[ -f ${script_path} ]]; then
        echo "${script_msg}"
        bash ${script_path}
    fi
}

generate_ssh_host_keys() {
    if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
        ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key -q -N ''
    fi

    if [ ! -f /etc/ssh/ssh_host_dsa_key ]; then
        ssh-keygen -t dsa -f /etc/ssh/ssh_host_dsa_key -q -N ''
    fi

    if [ ! -f /etc/ssh/ssh_host_ecdsa_key ]; then
        ssh-keygen -t ecdsa -f /etc/ssh/ssh_host_ecdsa_key -q -N ''
    fi

    if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
        ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -q -N ''
    fi
}

setup_ssh() {
    echo "Setting up SSH..."
    mkdir -p ~/.ssh

    # Add SSH public key from environment variable to ~/.ssh/authorized_keys
    # if the PUBLIC_KEY environment variable is set
    if [[ ${PUBLIC_KEY} ]]; then
        echo -e "${PUBLIC_KEY}\n" >> ~/.ssh/authorized_keys
    fi

    chmod 700 -R ~/.ssh

    # Generate SSH host keys if they don't exist
    generate_ssh_host_keys

    service ssh start

    echo "SSH host keys:"
    cat /etc/ssh/*.pub
}

export_env_vars() {
    echo "Exporting environment variables..."
    printenv | grep -E '^RUNPOD_|^PATH=|^_=' | awk -F = '{ print "export " $1 "=\"" $2 "\"" }' >> /etc/rp_environment
    echo 'source /etc/rp_environment' >> ~/.bashrc
}

start_jupyter() {
    # Default to not using a password
    JUPYTER_PASSWORD=""

    # Allow a password to be set by providing the JUPYTER_PASSWORD environment variable
    if [[ ${JUPYTER_LAB_PASSWORD} ]]; then
        JUPYTER_PASSWORD=${JUPYTER_LAB_PASSWORD}
    fi

    echo "Starting Jupyter Lab..."
    mkdir -p /workspace/logs
    cd / && \
    nohup jupyter lab --allow-root \
      --no-browser \
      --port=8888 \
      --ip=* \
      --FileContentsManager.delete_to_trash=False \
      --ContentsManager.allow_hidden=True \
      --ServerApp.terminado_settings='{"shell_command":["/bin/bash"]}' \
      --ServerApp.token=${JUPYTER_PASSWORD} \
      --ServerApp.allow_origin=* \
      --ServerApp.preferred_dir=/workspace &> /workspace/logs/jupyter.log &
    echo "Jupyter Lab started"
}

start_runpod_uploader() {
    echo "Starting RunPod Uploader..."
    nohup /usr/local/bin/runpod-uploader &> /workspace/logs/runpod-uploader.log &
    echo "RunPod Uploader started"
}

configure_filezilla() {
    # Only proceed if there is a public IP
    if [[ ! -z "${RUNPOD_PUBLIC_IP}" ]]; then
        # Server information
        hostname="${RUNPOD_PUBLIC_IP}"
        port="${RUNPOD_TCP_PORT_22}"

        # Generate a random password
        password=$(openssl rand -base64 12)

        # Set the password for the root user
        echo "root:${password}" | chpasswd

        # Update SSH configuration
        ssh_config="/etc/ssh/sshd_config"

        # Enable PasswordAuthentication
        grep -q "^PasswordAuthentication" ${ssh_config} && \
          sed -i "s/^PasswordAuthentication.*/PasswordAuthentication yes/" ${ssh_config} || \
          echo "PasswordAuthentication yes" >> ${ssh_config}

        # Enable PermitRootLogin
        grep -q "^PermitRootLogin" ${ssh_config} && \
          sed -i "s/^PermitRootLogin.*/PermitRootLogin yes/" ${ssh_config} || \
          echo "PermitRootLogin yes" >> ${ssh_config}

        # Restart the SSH service
        service ssh restart

        # Create FileZilla XML configuration for SFTP
        filezilla_config_file="/workspace/filezilla_sftp_config.xml"
        cat > ${filezilla_config_file} << EOF
<?xml version="1.0" encoding="UTF-8"?>
<FileZilla3 version="3.66.1" platform="linux">
    <Servers>
        <Server>
            <Host>${hostname}</Host>
            <Port>${port}</Port>
            <Protocol>1</Protocol> <!-- 1 for SFTP -->
            <Type>0</Type>
            <User>root</User>
            <Pass encoding="base64">$(echo -n ${password} | base64)</Pass>
            <Logontype>1</Logontype> <!-- 1 for Normal logon type -->
            <EncodingType>Auto</EncodingType>
            <BypassProxy>0</BypassProxy>
            <Name>Generated Server</Name>
            <RemoteDir>/workspace</RemoteDir>
            <SyncBrowsing>0</SyncBrowsing>
            <DirectoryComparison>0</DirectoryComparison>
            <!-- Additional settings can be added here -->
        </Server>
    </Servers>
</FileZilla3>
EOF
        echo "FileZilla SFTP configuration file created at: ${filezilla_config_file}"
    else
        echo "RUNPOD_PUBLIC_IP is not set. Skipping FileZilla configuration."
    fi
}

update_rclone() {
    echo "Updating rclone..."
    rclone selfupdate
}

start_cron() {
    echo "Starting Cron service..."
    service cron start
}

# ---------------------------------------------------------------------------- #
#                               Main Program                                   #
# ---------------------------------------------------------------------------- #

echo "Container Started, configuration in progress..."
start_nginx
setup_ssh
start_cron
start_jupyter
start_runpod_uploader
execute_script "/pre_start.sh" "Running pre-start script..."
configure_filezilla
update_rclone
export_env_vars
execute_script "/post_start.sh" "Running post-start script..."
echo "Container is READY!"
sleep infinity
