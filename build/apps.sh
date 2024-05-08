#!/usr/bin/env bash
# Install Jupyter, gdown and OhMyRunPod
pip3 install -U --no-cache-dir jupyterlab \
    jupyterlab_widgets \
    ipykernel \
    ipywidgets \
    gdown \
    OhMyRunPod

# Install RunPod File Uploader
curl -sSL https://github.com/kodxana/RunPod-FilleUploader/raw/main/scripts/installer.sh -o installer.sh && \
    chmod +x installer.sh && \
    ./installer.sh

# Install rclone
curl https://rclone.org/install.sh | bash

# Install runpodctl
wget "https://github.com/runpod/runpodctl/releases/download/${RUNPODCTL_VERSION}/runpodctl-linux-amd64" -O runpodctl && \
    chmod a+x runpodctl && \
    mv runpodctl /usr/local/bin

# Install croc
curl https://getcroc.schollz.com | bash

# Install speedtest CLI
curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | bash && \
    apt install -y speedtest
