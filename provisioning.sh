#!/bin/bash

source /venv/main/bin/activate
COMFYUI_DIR=${WORKSPACE}/ComfyUI

# Packages are installed after nodes so we can fix them...

APT_PACKAGES=(
    #"package-1"
    #"package-2"
)

PIP_PACKAGES=(
    #"package-1"
    #"package-2"
)

NODES=(
    #"https://github.com/ltdrdata/ComfyUI-Manager"
    #"https://github.com/cubiq/ComfyUI_essentials"
)

WORKFLOWS=(
    "https://raw.githubusercontent.com/Comfy-Org/workflow_templates/refs/heads/main/templates/image_qwen_image_layered.json"
    "https://raw.githubusercontent.com/Comfy-Org/workflow_templates/refs/heads/main/templates/image_qwen_image_edit_2511.json"
)

# Qwen workflows use text_encoders, diffusion_models, vae, and loras directories
# We'll download to the appropriate model directories

CHECKPOINT_MODELS=(
    # Not used - Qwen uses diffusion_models instead
)

UNET_MODELS=(
    # Qwen Image Layered diffusion model (bf16 version, ~6GB)
    "https://huggingface.co/Comfy-Org/Qwen-Image-Layered_ComfyUI/resolve/main/split_files/diffusion_models/qwen_image_layered_bf16.safetensors"
    # Qwen Image Edit 2511 diffusion model (bf16 version, ~6GB)
    "https://huggingface.co/Comfy-Org/Qwen-Image-Edit_ComfyUI/resolve/main/split_files/diffusion_models/qwen_image_edit_2511_bf16.safetensors"
)

LORA_MODELS=(
    # Lightning LoRA for 4-step fast inference (~6GB)
    "https://huggingface.co/lightx2v/Qwen-Image-Edit-2511-Lightning/resolve/main/Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors"
)

VAE_MODELS=(
    # Qwen Image Layered VAE (~300MB)
    "https://huggingface.co/Comfy-Org/Qwen-Image-Layered_ComfyUI/resolve/main/split_files/vae/qwen_image_layered_vae.safetensors"
    # Qwen Image VAE (~300MB)
    "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/vae/qwen_image_vae.safetensors"
)

ESRGAN_MODELS=(
)

CONTROLNET_MODELS=(
)

# Text encoders for Qwen (shared by both workflows)
TEXT_ENCODER_MODELS=(
    # Qwen 2.5 VL text encoder (fp8 scaled, ~8.3GB)
    "https://huggingface.co/Comfy-Org/HunyuanVideo_1.5_repackaged/resolve/main/split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors"
)

### DO NOT EDIT BELOW HERE UNLESS YOU KNOW WHAT YOU ARE DOING ###

function provisioning_start() {
    provisioning_print_header
    provisioning_get_apt_packages
    provisioning_get_nodes
    provisioning_get_pip_packages
    provisioning_get_workflows
    provisioning_get_files \
        "${COMFYUI_DIR}/models/checkpoints" \
        "${CHECKPOINT_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/diffusion_models" \
        "${UNET_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/loras" \
        "${LORA_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/controlnet" \
        "${CONTROLNET_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/vae" \
        "${VAE_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/esrgan" \
        "${ESRGAN_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/text_encoders" \
        "${TEXT_ENCODER_MODELS[@]}"
    provisioning_create_readme
    provisioning_fix_supervisor
    provisioning_print_end
}

function provisioning_get_apt_packages() {
    if [[ -n $APT_PACKAGES ]]; then
            sudo $APT_INSTALL ${APT_PACKAGES[@]}
    fi
}

function provisioning_get_pip_packages() {
    if [[ -n $PIP_PACKAGES ]]; then
            pip install --no-cache-dir ${PIP_PACKAGES[@]}
    fi
}

function provisioning_get_nodes() {
    for repo in "${NODES[@]}"; do
        dir="${repo##*/}"
        path="${COMFYUI_DIR}/custom_nodes/${dir}"
        requirements="${path}/requirements.txt"
        if [[ -d $path ]]; then
            if [[ ${AUTO_UPDATE,,} != "false" ]]; then
                printf "Updating node: %s...\n" "${repo}"
                ( cd "$path" && git pull )
                if [[ -e $requirements ]]; then
                   pip install --no-cache-dir -r "$requirements"
                fi
            fi
        else
            printf "Downloading node: %s...\n" "${repo}"
            git clone "${repo}" "${path}" --recursive
            if [[ -e $requirements ]]; then
                pip install --no-cache-dir -r "${requirements}"
            fi
        fi
    done
}

function provisioning_get_workflows() {
    if [[ -z "${WORKFLOWS[@]}" ]]; then return 0; fi
    
    workflows_dir="${COMFYUI_DIR}/workflows"
    mkdir -p "$workflows_dir"
    
    printf "Downloading %s workflow(s) to %s...\n" "${#WORKFLOWS[@]}" "$workflows_dir"
    for url in "${WORKFLOWS[@]}"; do
        printf "Downloading workflow: %s\n" "${url}"
        wget -qnc --content-disposition --show-progress -P "$workflows_dir" "$url"
        printf "\n"
    done
}

function provisioning_get_files() {
    if [[ -z $2 ]]; then return 1; fi
    
    dir="$1"
    mkdir -p "$dir"
    shift
    arr=("$@")
    printf "Downloading %s model(s) to %s...\n" "${#arr[@]}" "$dir"
    for url in "${arr[@]}"; do
        printf "Downloading: %s\n" "${url}"
        provisioning_download "${url}" "${dir}"
        printf "\n"
    done
}

function provisioning_fix_supervisor() {
    # Fix ComfyUI supervisor configuration to use valid arguments
    if [ -f /etc/supervisor/conf.d/comfyui.conf ]; then
        printf "\n"
        printf "Fixing ComfyUI supervisor configuration...\n"
        
        # Backup existing config
        cp /etc/supervisor/conf.d/comfyui.conf /etc/supervisor/conf.d/comfyui.conf.backup 2>/dev/null || true
        
        # Create new config with correct arguments (no --disable-auto-launch or --enable-cors-header)
        cat > /etc/supervisor/conf.d/comfyui.conf << 'EOF'
[program:comfyui]
directory=/workspace/ComfyUI
command=/venv/main/bin/python main.py --listen 0.0.0.0 --port 8188 --multi-user
autostart=true
autorestart=true
stdout_logfile=/var/log/comfyui.log
stderr_logfile=/var/log/comfyui_error.log
redirect_stderr=true
user=root
environment=PYTHONUNBUFFERED=1,PYTHONPATH="/workspace/ComfyUI"
EOF
        
        # Reload supervisor
        supervisorctl reread 2>/dev/null || true
        supervisorctl update 2>/dev/null || true
        
        printf "✓ Supervisor configuration fixed\n"
        printf "  ComfyUI will start with: --listen 0.0.0.0 --port 8188 --multi-user\n"
    fi
}

function provisioning_create_readme() {
    readme_file="${COMFYUI_DIR}/workflows/README.txt"
    
    cat > "$readme_file" << 'EOF'
QWEN COMFYUI WORKFLOWS - VAST.AI DEPLOYMENT
===========================================

This ComfyUI instance has been pre-configured with Qwen image workflows.

INCLUDED WORKFLOWS:
-------------------

1. image_qwen_image_layered.json
   Purpose: Convert images into layered representations or generate from text
   - Input size: 640px recommended (1024px for high-res)
   - Steps: 20 (default/fast) or 50 (better quality)
   - CFG: 2.5 (default) or 4.0 (original quality)
   - Layers: 2 or more
   
   Use cases:
   - Extract foreground/background layers
   - Generate multi-layer compositions
   - Create depth-separated image elements

2. image_qwen_image_edit_2511.json
   Purpose: Advanced image editing with reference images
   - Standard mode: 40 steps, CFG 4.0 (~2-3 minutes)
   - Lightning mode: 4 steps, CFG 1.0 (~30 seconds)
   - Supports up to 3 reference images
   
   Use cases:
   - Texture transfer (e.g., change leather to fur)
   - Style transfer between images
   - Object replacement with reference
   - Multi-image composition

DOWNLOADED MODELS (~27GB total):
---------------------------------

Text Encoders:
  models/text_encoders/
    └── qwen_2.5_vl_7b_fp8_scaled.safetensors (8.3GB)

Diffusion Models:
  models/diffusion_models/
    ├── qwen_image_layered_bf16.safetensors (6GB)
    └── qwen_image_edit_2511_bf16.safetensors (6GB)

VAE Models:
  models/vae/
    ├── qwen_image_layered_vae.safetensors (300MB)
    └── qwen_image_vae.safetensors (300MB)

LoRA Models:
  models/loras/
    └── Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors (6GB)

GETTING STARTED:
----------------

1. ComfyUI is accessible at the URL/port provided by Vast.ai
2. Load a workflow from the workflows/ directory
3. Upload your images or enter your prompts
4. Adjust settings as needed
5. Queue the prompt to generate

SYSTEM REQUIREMENTS:
--------------------

Recommended:
- GPU: RTX 3090, RTX 4090, or A100
- VRAM: 16GB+ (bf16 models)
- RAM: 32GB+
- Storage: 50GB+

For Lower VRAM (12-16GB):
Download FP8 mixed precision models from:
https://huggingface.co/Comfy-Org/Qwen-Image-Layered_ComfyUI/blob/main/split_files/diffusion_models/qwen_image_layered_fp8mixed.safetensors

Then update the workflow to use the FP8 model.

OPTIMIZATION TIPS:
------------------

Speed:
- Use Lightning LoRA for 4-step inference (vs 40 steps)
- Start with 640px resolution, increase to 1024px only if needed
- Use 20 steps instead of 40 for faster iterations

Quality:
- Use 40-50 steps for best results
- Use bf16 models (default)
- Increase resolution to 1024px
- Increase CFG to 4.0

Memory:
- Close other applications
- Reduce batch size to 1
- Use lower resolution inputs
- Enable model offloading in ComfyUI settings

TROUBLESHOOTING:
----------------

If ComfyUI doesn't start:
The supervisor configuration has been fixed to use valid ComfyUI arguments.
If you still have issues, manually start ComfyUI:

  cd /workspace/ComfyUI
  source /venv/main/bin/activate
  python main.py --listen 0.0.0.0 --port 8188 --multi-user

Check supervisor status:
  supervisorctl status comfyui

View logs:
  tail -f /var/log/comfyui.log
  tail -f /var/log/comfyui_error.log

CUDA Out of Memory:
- Restart ComfyUI
- Use FP8 models instead of bf16
- Reduce image resolution
- Close other GPU processes

EXAMPLE PROMPTS:
----------------

Image Layered:
"A cinematic medium shot of a beautiful young woman with fair skin and a 
joyful, radiant smile, looking back over her shoulder."

Image Edit:
"Change the furniture leather in image 1 to the fur material in image 2."
"Replace the background in image 1 with the landscape from image 2."
"Transfer the artistic style from image 2 to the subject in image 1."

RESOURCES:
----------

- ComfyUI: https://github.com/comfyanonymous/ComfyUI
- Qwen Models: https://huggingface.co/Comfy-Org
- Workflow Templates: https://github.com/Comfy-Org/workflow_templates
- Vast.ai Docs: https://vast.ai/docs

Generated by Qwen ComfyUI Provisioning Script (v2)
Includes supervisor configuration fix for Vast.ai compatibility
EOF
    
    printf "Created README at: %s\n" "$readme_file"
}

function provisioning_print_header() {
    printf "\n##############################################\n#                                            #\n#          Provisioning container            #\n#                                            #\n#     Qwen Image Workflows for ComfyUI       #\n#                                            #\n#         This will take some time           #\n#        (~27GB models to download)          #\n#                                            #\n# Your container will be ready on completion #\n#                                            #\n##############################################\n\n"
}

function provisioning_print_end() {
    printf "\n##############################################\n#                                            #\n#        Provisioning complete!              #\n#                                            #\n#  Qwen Image Workflows are ready to use     #\n#                                            #\n#  Models downloaded (~27GB):                #\n#    - Text encoders                         #\n#    - Diffusion models (2x)                 #\n#    - VAE models (2x)                       #\n#    - Lightning LoRA                        #\n#                                            #\n#  Workflows location:                       #\n#    ${COMFYUI_DIR}/workflows/               #\n#                                            #\n#  - image_qwen_image_layered.json           #\n#  - image_qwen_image_edit_2511.json         #\n#                                            #\n#  Read the README.txt for usage guide       #\n#                                            #\n#  ✓ Supervisor config fixed for Vast.ai     #\n#                                            #\n#      Application will start now            #\n#                                            #\n##############################################\n\n"
}

function provisioning_has_valid_hf_token() {
    [[ -n "$HF_TOKEN" ]] || return 1
    url="https://huggingface.co/api/whoami-v2"

    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $HF_TOKEN" \
        -H "Content-Type: application/json")

    # Check if the token is valid
    if [ "$response" -eq 200 ]; then
        return 0
    else
        return 1
    fi
}

function provisioning_has_valid_civitai_token() {
    [[ -n "$CIVITAI_TOKEN" ]] || return 1
    url="https://civitai.com/api/v1/models?hidden=1&limit=1"

    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $CIVITAI_TOKEN" \
        -H "Content-Type: application/json")

    # Check if the token is valid
    if [ "$response" -eq 200 ]; then
        return 0
    else
        return 1
    fi
}

# Download from $1 URL to $2 file path
function provisioning_download() {
    if [[ -n $HF_TOKEN && $1 =~ ^https://([a-zA-Z0-9_-]+\.)?huggingface\.co(/|$|\?) ]]; then
        auth_token="$HF_TOKEN"
    elif 
        [[ -n $CIVITAI_TOKEN && $1 =~ ^https://([a-zA-Z0-9_-]+\.)?civitai\.com(/|$|\?) ]]; then
        auth_token="$CIVITAI_TOKEN"
    fi
    if [[ -n $auth_token ]];then
        wget --header="Authorization: Bearer $auth_token" -qnc --content-disposition --show-progress -e dotbytes="${3:-4M}" -P "$2" "$1"
    else
        wget -qnc --content-disposition --show-progress -e dotbytes="${3:-4M}" -P "$2" "$1"
    fi
}

# Allow user to disable provisioning if they started with a script they didn't want
if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi
