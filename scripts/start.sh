#!/usr/bin/env bash
# ---------------------------------------------------------------------------- #
#                          Function Definitions                                #
# ---------------------------------------------------------------------------- #

setup_nginx_auth() {
    local htpasswd_file="/etc/nginx/htpasswd"

    if [[ -n "$HTTP_AUTH_USERNAME" && -n "$HTTP_AUTH_PASSWORD" ]]; then
        echo "Setting up Nginx authentication..."

        local md5_password=$(openssl passwd -apr1 "$HTTP_AUTH_PASSWORD")
        local htpasswd="${HTTP_AUTH_USERNAME}:${md5_password}"

        echo "${htpasswd}" > "$htpasswd_file"
        sed -i 's/auth_basic off/auth_basic "StableDiffusion Web UI"/' /etc/nginx/nginx.conf
    else
        echo "Nginx authentication disabled..."

        touch "$htpasswd_file"
    fi
}

start_nginx() {
    echo "Starting Nginx service..."
    service nginx start
}


# Check CUDA version using nvidia-smi
check_cuda_version() {
    echo "Checking CUDA version using nvidia-smi..."

    CURRENT_CUDA_VERSION=$(nvidia-smi | grep -oP "CUDA Version: \K[0-9.]+")

    # Check if the CUDA version was successfully extracted
    if [[ -z "${CURRENT_CUDA_VERSION}" ]];
    then
        echo "CUDA version not found. Make sure that CUDA is properly installed and 'nvidia-smi' is available."
        exit 1
    fi

    echo "Detected CUDA version using nvidia-smi: ${CURRENT_CUDA_VERSION}"

    # Split the version into major and minor for comparison
    IFS='.' read -r -a CURRENT_CUDA_VERSION_ARRAY <<< "${CURRENT_CUDA_VERSION}"
    CURRENT_CUDA_VERSION_MAJOR="${CURRENT_CUDA_VERSION_ARRAY[0]}"
    CURRENT_CUDA_VERSION_MINOR="${CURRENT_CUDA_VERSION_ARRAY[1]}"

    IFS='.' read -r -a REQUIRED_CUDA_VERSION_ARRAY <<< "${REQUIRED_CUDA_VERSION}"
    REQUIRED_CUDA_VERSION_MAJOR="${REQUIRED_CUDA_VERSION_ARRAY[0]}"
    REQUIRED_CUDA_VERSION_MINOR="${REQUIRED_CUDA_VERSION_ARRAY[1]}"

    # Compare the CUDA version with the required version
    if [[ "${CURRENT_CUDA_VERSION_MAJOR}" -lt "${REQUIRED_CUDA_VERSION_MAJOR}" ||
          ( "${CURRENT_CUDA_VERSION_MAJOR}" -eq "${REQUIRED_CUDA_VERSION_MAJOR}" && "${CURRENT_CUDA_VERSION_MINOR}" -lt "${REQUIRED_CUDA_VERSION_MINOR}" ) ]];
    then
        echo "Current CUDA version (${CURRENT_CUDA_VERSION}) is older than required (${REQUIRED_CUDA_VERSION})."
        echo "Please switch to a pod with CUDA version ${REQUIRED_CUDA_VERSION} or higher by selecting the appropriate filter on Pod deploy."
        exit 1
    else
        echo "CUDA version from nvidia-smi seems sufficient: ${CURRENT_CUDA_VERSION}"
    fi
}

# Simple CUDA functionality test using PyTorch
test_pytorch_cuda() {
    echo "Performing a simple CUDA functionality test using PyTorch..."

    python3 - <<END
import sys
import torch

try:
    # Check if CUDA is available
    if not torch.cuda.is_available():
        print("CUDA is not available on this system.")
        sys.exit(1)

    # Get the CUDA version
    cuda_version = torch.version.cuda
    if cuda_version is None:
        print("Could not determine CUDA version using PyTorch.")
        sys.exit(1)

    print(f"From PyTorch test, your CUDA version meets the requirement: {cuda_version}")

    # Test CUDA by getting device count
    num_gpus = torch.cuda.device_count()
    print(f"Number of CUDA-capable devices: {num_gpus}")

    # List CUDA-capable devices
    for i in range(num_gpus):
        print(f"Device {i}: {torch.cuda.get_device_name(i)}")

except RuntimeError as e:
    print(f"Runtime error: {e}")
    sys.exit(2)
except Exception as e:
    print(f"An unexpected error occurred: {e}")
    sys.exit(1)
END

    if [[ $? -ne 0 ]]; then
        echo "PyTorch CUDA test failed. Please switch to a pod with a proper CUDA setup."
        exit 1
    else
        echo "CUDA version is sufficient and functional."
    fi
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
    local hashed_password=""
    if [[ -n "$JUPYTER_PASSWORD" ]]; then
        echo "Enabling Jupyter Lab autentication..."
        local imports="import os; from jupyter_server.auth import passwd;"
        local passwd_cmd="print(passwd(os.environ['JUPYTER_PASSWORD']))"
        hashed_password=$(python -c "${imports} ${passwd_cmd}")
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
      --ServerApp.token="" \
      --ServerApp.password="'$hashed_password'" \
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
setup_nginx_auth
start_nginx
setup_ssh
start_cron
start_jupyter
check_cuda_version
test_pytorch_cuda
start_runpod_uploader
execute_script "/pre_start.sh" "Running pre-start script..."
configure_filezilla
update_rclone
export_env_vars
execute_script "/post_start.sh" "Running post-start script..."
echo "Container is READY!"
sleep infinity
