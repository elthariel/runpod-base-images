variable "USERNAME" {
    default = "ashleykza"
}

variable "RELEASE" {
    default = "1.0.1"
}

variable "RUNPODCTL_VERSION" {
    default = "v1.14.2"
}

group "default" {
    targets = ["cu118-torch212", "cu118-torch222", "cu121-torch221"]
}

target "cu118-torch212" {
    dockerfile = "Dockerfile.with-xformers"
    tags = ["${USERNAME}/runpod-base:${RELEASE}-cuda11.8.0-torch2.1.2"]
    args = {
        BASE_IMAGE = "nvidia/cuda:11.8.0-cudnn8-devel-ubuntu22.04"
        RELEASE = "${RELEASE}"
        INDEX_URL = "https://download.pytorch.org/whl/cu118"
        TORCH_VERSION = "2.1.2+cu118"
        XFORMERS_VERSION = "0.0.23.post1+cu118"
        RUNPODCTL_VERSION = "${RUNPODCTL_VERSION}"
    }
}

target "cu118-torch222" {
    dockerfile = "Dockerfile.with-xformers"
    tags = ["${USERNAME}/runpod-base:${RELEASE}-cuda11.8.0-torch2.2.2"]
    args = {
        BASE_IMAGE = "nvidia/cuda:11.8.0-cudnn8-devel-ubuntu22.04"
        RELEASE = "${RELEASE}"
        INDEX_URL = "https://download.pytorch.org/whl/cu118"
        TORCH_VERSION = "2.2.2+cu118"
        XFORMERS_VERSION = "0.0.25.post1+cu118"
        RUNPODCTL_VERSION = "${RUNPODCTL_VERSION}"
    }
}

target "cu121-torch221" {
    dockerfile = "Dockerfile.without-xformers"
    tags = ["${USERNAME}/runpod-base:${RELEASE}-cuda12.1.1-torch2.2.1"]
    args = {
        BASE_IMAGE = "nvidia/cuda:12.1.1-cudnn8-devel-ubuntu22.04"
        RELEASE = "${RELEASE}"
        INDEX_URL = "https://download.pytorch.org/whl/cu121"
        TORCH_VERSION = "2.2.1+cu121"
        RUNPODCTL_VERSION = "${RUNPODCTL_VERSION}"
    }
}
