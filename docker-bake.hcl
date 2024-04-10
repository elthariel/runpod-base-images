variable "USERNAME" {
    default = "ashleykza"
}

variable "APP" {
    default = "runpod-base"
}

variable "CU_VERSION" {
    default = "118"
}

variable "RELEASE" {
    default = "1.0.0"
}

target "default" {
    dockerfile = "Dockerfile"
    tags = ["${USERNAME}/${APP}-cu${CU_VERSION}}:${RELEASE}"]
    args = {
        RELEASE = "${RELEASE}"
        INDEX_URL = "https://download.pytorch.org/whl/cu${CU_VERSION}"
        TORCH_VERSION = "2.1.2+cu${CU_VERSION}"
        XFORMERS_VERSION = "0.0.23.post1+cu${CU_VERSION}"
        RUNPODCTL_VERSION = "v1.14.2"
    }
}
