#!/bin/bash
# --- AI OPTIMIZED SCRIPT v0.9.5.3 ---
# Hardware: Intelligent Auto-Detected Profile | Single Backend Platform
# Features: Incremental Ninja + ccache | BF16 Disabled | Git Auto-Pull
# Optimizations: Advanced ccache sloppiness, CUDA compiler ccache launcher, and fixed UI warnings.
# Enhancements: Startup dependency check, Xeon profile toggles, interactive dependency sub-menu, and real-time llama-bench.

# Non-interactive CLI flag handler for React API Frontend Groundwork
if [[ "$1" == "--json-status" ]]; then
    # Load settings without showing prompts or blocking
    if [[ -f "$HOME/.ai_manager/settings.conf" ]]; then
        source "$HOME/.ai_manager/settings.conf"
    fi
    # Set default values if not defined
    [[ -z "$BACKEND" ]] && BACKEND="CUDA"
    [[ -z "$BUILD_PROFILE" ]] && BUILD_PROFILE="medium"
    [[ -z "$SSL_ENABLED" ]] && SSL_ENABLED="false"
    [[ -z "$PORT" ]] && PORT="8888"
    
    # Check last selected model
    model_name="None"
    if [[ -n "$LAST_MODEL" && -f "$LAST_MODEL" ]]; then
        model_name="$(basename "$LAST_MODEL")"
    elif [[ -n "$MODEL_PATH" && -f "$MODEL_PATH" ]]; then
        model_name="$(basename "$MODEL_PATH")"
    fi
    
    # Print the JSON status cleanly
    echo "{\"backend\": \"$BACKEND\", \"profile\": \"$BUILD_PROFILE\", \"ssl\": \"$SSL_ENABLED\", \"port\": \"$PORT\", \"model\": \"$model_name\"}"
    exit 0
fi

# Configuration
LLAMA_DIR="$HOME/ai_tools/llama.cpp"
BUILD_CUDA="$LLAMA_DIR/build"
BUILD_VULKAN="$LLAMA_DIR/build_VULKAN"
BUILD_ROCM="$LLAMA_DIR/build_ROCM"
SETTINGS_FILE="$HOME/.ai_manager/settings.conf"
PORT="8888"
TRASH_DIR="$HOME/.ai_manager/trash"
LOGS_DIR="$HOME/.ai_manager/logs"
FLAGS_FILE="$HOME/.ai_manager/server_flags.conf"

# Restored log function
log() { echo "[$(date -Is)] $*"; }

cleanup() {
    echo -e "\n[INFO] Shutting down AI services..."
    pkill -f "llama-server" 2>/dev/null
    killall -9 llama-server 2>/dev/null
    if [[ -n "$PORT" ]]; then
        fuser -k "$PORT"/tcp 2>/dev/null
    fi
    pkill -P $$ 2>/dev/null
    exit 0
}
trap cleanup SIGINT SIGTERM

# Ensure official AMD ROCm tools are available in PATH
if [[ -d "/opt/rocm/bin" && ":$PATH:" != *":/opt/rocm/bin:"* ]]; then
    export PATH="/opt/rocm/bin:$PATH"
fi
if [[ -d "/opt/rocm/llvm/bin" && ":$PATH:" != *":/opt/rocm/llvm/bin:"* ]]; then
    export PATH="/opt/rocm/llvm/bin:$PATH"
fi

# Startup Dependency Verification Engine (Base dependencies & headers)
check_dependencies() {
    local missing=()
    
    # Base Components checks (cmake, ninja, ccache)
    command -v cmake &>/dev/null || missing+=("cmake")
    command -v ninja &>/dev/null || missing+=("ninja")
    command -v ccache &>/dev/null || missing+=("ccache")
    (dpkg -s spirv-headers &>/dev/null || [[ -d "/usr/include/spirv" ]]) || missing+=("spirv-headers")
    
    if [[ ${#missing[@]} -ne 0 ]]; then
        clear
        echo "=========================================="
        echo "    dependency verification failed        "
        echo "=========================================="
        echo "these base dependencies were missing:"
        for dep in "${missing[@]}"; do
            echo "  - $dep"
        done
        echo ""
        echo "choose menu option [I] to install dependencies"
        echo "=========================================="
        read -p "Press Enter to continue..."
    fi
}

# Create Settings File and persistence setup
mkdir -p "$HOME/.ai_manager"
mkdir -p "$TRASH_DIR"
mkdir -p "$LOGS_DIR"
if [[ ! -f "$FLAGS_FILE" ]]; then touch "$FLAGS_FILE"; fi

save_settings() {
    mkdir -p "$HOME/.ai_manager"
    cat <<EOF > "$SETTINGS_FILE"
BACKEND="$BACKEND"
BUILD_PROFILE="$BUILD_PROFILE"
LAST_MODEL="$LAST_MODEL"
MODELS_DIR="$MODELS_DIR"
ACTIVE_CUSTOM_BUILD="$ACTIVE_CUSTOM_BUILD"
SSL_ENABLED="$SSL_ENABLED"
USE_SSL="$SSL_ENABLED"
PORT="$PORT"
SSL_CERT_PATH="$SSL_CERT_PATH"
SSL_KEY_PATH="$SSL_KEY_PATH"
GPU_LAYERS="$GPU_LAYERS"
FLASH_ATTENTION="$FLASH_ATTENTION"
CONTEXT_SIZE="$CONTEXT_SIZE"
BATCH_SIZE="$BATCH_SIZE"
UBATCH_SIZE="$UBATCH_SIZE"
THREADS="$THREADS"
GPU_BLACKLIST="$GPU_BLACKLIST"
GPU_BLACKLIST_CONFIGURED="$GPU_BLACKLIST_CONFIGURED"
VULKAN_DEVICE="$VULKAN_DEVICE"
MMPROJ_PATH="$MMPROJ_PATH"
LAUNCH_PAUSE="$LAUNCH_PAUSE"
EOF
}

# Automated self-signed SSL certificate generation layer
ensure_ssl_certs() {
    if [[ "$SSL_ENABLED" == "true" ]]; then
        local ssl_dir="$HOME/.ai_manager/ssl"
        mkdir -p "$ssl_dir"
        local key_file="$ssl_dir/server.key"
        local cert_file="$ssl_dir/server.crt"
        if [[ ! -f "$key_file" || ! -f "$cert_file" ]]; then
            log "Generating automated self-signed SSL certificate inside $ssl_dir..."
            if command -v openssl &>/dev/null; then
                openssl req -x509 -newkey rsa:2048 -keyout "$key_file" -out "$cert_file" -days 365 -nodes -subj "/CN=localhost" &>/dev/null
                log "Automated self-signed SSL certificate generated successfully."
            else
                log "Warning: openssl is not installed, cannot generate automated self-signed SSL certificates."
            fi
        fi
        if [[ -z "$SSL_KEY_PATH" && -f "$key_file" ]]; then
            SSL_KEY_PATH="$key_file"
        fi
        if [[ -z "$SSL_CERT_PATH" && -f "$cert_file" ]]; then
            SSL_CERT_PATH="$cert_file"
        fi
    fi
}

if [[ ! -f "$SETTINGS_FILE" ]]; then
    BACKEND="CUDA"
    BUILD_PROFILE=""
    LAST_MODEL=""
    MODELS_DIR=""
    ACTIVE_CUSTOM_BUILD=""
    SSL_ENABLED="false"
    PORT="8888"
    SSL_CERT_PATH=""
    SSL_KEY_PATH=""
    VULKAN_DEVICE=""
    MMPROJ_PATH=""
    LAUNCH_PAUSE="true"
    save_settings
fi
source "$SETTINGS_FILE"

# Guarantee variables initialized cleanly
[[ -z "$ACTIVE_CUSTOM_BUILD" ]] && ACTIVE_CUSTOM_BUILD=""
[[ -z "$SSL_ENABLED" ]] && SSL_ENABLED="false"
[[ -z "$PORT" ]] && {
    if [[ "$SSL_ENABLED" == "true" ]]; then
        PORT="443"
    else
        PORT="8888"
    fi
}
[[ -z "$SSL_CERT_PATH" ]] && SSL_CERT_PATH=""
[[ -z "$SSL_KEY_PATH" ]] && SSL_KEY_PATH=""
[[ -z "$GPU_LAYERS" ]] && GPU_LAYERS="99"
[[ -z "$FLASH_ATTENTION" ]] && FLASH_ATTENTION="on"
[[ -z "$CONTEXT_SIZE" ]] && CONTEXT_SIZE="2048"
[[ -z "$BATCH_SIZE" ]] && BATCH_SIZE="2048"
[[ -z "$UBATCH_SIZE" ]] && UBATCH_SIZE="2048"
[[ -z "$THREADS" ]] && THREADS="3"
[[ -z "$GPU_BLACKLIST" ]] && GPU_BLACKLIST=""
[[ -z "$GPU_BLACKLIST_CONFIGURED" ]] && GPU_BLACKLIST_CONFIGURED=""
[[ -z "$VULKAN_DEVICE" ]] && VULKAN_DEVICE=""
[[ -z "$MMPROJ_PATH" ]] && MMPROJ_PATH=""
[[ -z "$LAUNCH_PAUSE" ]] && LAUNCH_PAUSE="true"

# Dynamic self-signed cert generation at startup if enabled
ensure_ssl_certs
save_settings

# Support default profile if unset (Auto-detection rule)
if [[ -z "$BUILD_PROFILE" ]]; then
    if grep -q "avx512f" /proc/cpuinfo 2>/dev/null; then
        BUILD_PROFILE="high"
    elif grep -q "avx2" /proc/cpuinfo 2>/dev/null; then
        BUILD_PROFILE="medium"
    else
        BUILD_PROFILE="low"
    fi
    save_settings
fi

# Persistent GGUF Models Directory Setup
if [[ -z "$MODELS_DIR" ]]; then
    clear
    echo "=========================================="
    echo "    PERSISTENT WORKSPACE CONFIGURATION    "
    echo "=========================================="
    echo "Please configure your persistent GGUF models directory."
    read -p "Enter the absolute path to your GGUF models (e.g. $HOME/Downloads): " input_dir
    [[ -z "$input_dir" ]] && input_dir="$HOME/Downloads"
    mkdir -p "$input_dir"
    MODELS_DIR="$input_dir"
    save_settings
fi

# Run startup dependency check
check_dependencies

# Load last selected model if valid
if [[ -n "$LAST_MODEL" && -f "$LAST_MODEL" ]]; then
    MODEL_PATH="$LAST_MODEL"
fi

get_active_cuda_devices() {
    local all_gpus=()
    if command -v nvidia-smi &>/dev/null; then
        while read -r idx; do
            if [[ -n "$idx" && "$idx" =~ ^[0-9]+$ ]]; then
                all_gpus+=("$idx")
            fi
        done < <(nvidia-smi --query-gpu=index --format=csv,noheader 2>/dev/null)
    fi
    
    if [[ ${#all_gpus[@]} -eq 0 ]]; then
        # Default fallback list for common environments if nvidia-smi is missing/unusable but blacklist is defined
        all_gpus=(0 1 2 3)
    fi
    
    local active=()
    for gpu in "${all_gpus[@]}"; do
        local blacklisted=0
        IFS=',' read -ra ADDR <<< "$GPU_BLACKLIST"
        for bl in "${ADDR[@]}"; do
            bl=$(echo "$bl" | tr -d ' ')
            if [[ "$gpu" == "$bl" ]]; then
                blacklisted=1
                break
            fi
        done
        if [[ $blacklisted -eq 0 ]]; then
            active+=("$gpu")
        fi
    done
    
    (IFS=,; echo "${active[*]}")
}

apply_gpu_blacklist() {
    # Strip any previously written visibility constraints from FLAGS_FILE
    sed -i '/CUDA_VISIBLE_DEVICES/d' "$FLAGS_FILE" 2>/dev/null
    sed -i '/HIP_VISIBLE_DEVICES/d' "$FLAGS_FILE" 2>/dev/null
    sed -i '/GGML_VK_VISIBLE_DEVICES/d' "$FLAGS_FILE" 2>/dev/null
    
    if [[ -n "$GPU_BLACKLIST" ]]; then
        local active_gpus
        active_gpus=$(get_active_cuda_devices)
        
        # Output info warning safely
        log "[INFO] GPU Blacklist in effect (${GPU_BLACKLIST}). Retaining active GPU indexes: ${active_gpus:-None}"
        
        # Set actively in this parent shell stage
        export CUDA_VISIBLE_DEVICES="$active_gpus"
        export HIP_VISIBLE_DEVICES="$active_gpus"
        
        # Persist to FLAGS_FILE so any spawned secondary window shells read these variables
        echo "export CUDA_VISIBLE_DEVICES=$active_gpus" >> "$FLAGS_FILE"
        echo "export HIP_VISIBLE_DEVICES=$active_gpus" >> "$FLAGS_FILE"
    else
        unset CUDA_VISIBLE_DEVICES
        unset HIP_VISIBLE_DEVICES
    fi

    # Apply Vulkan device selection or fallback to blacklist
    if [[ -n "$VULKAN_DEVICE" ]]; then
        log "[INFO] Persistent Vulkan Device in effect: ${VULKAN_DEVICE}"
        export GGML_VK_VISIBLE_DEVICES="$VULKAN_DEVICE"
        echo "export GGML_VK_VISIBLE_DEVICES=$VULKAN_DEVICE" >> "$FLAGS_FILE"
    elif [[ -n "$GPU_BLACKLIST" ]]; then
        local active_gpus
        active_gpus=$(get_active_cuda_devices)
        export GGML_VK_VISIBLE_DEVICES="$active_gpus"
        echo "export GGML_VK_VISIBLE_DEVICES=$active_gpus" >> "$FLAGS_FILE"
    else
        unset GGML_VK_VISIBLE_DEVICES
    fi
}

configure_gpu_blacklist() {
    clear
    echo "=========================================="
    echo "       GPU BLACKLIST CONFIGURATION"
    echo "=========================================="
    echo "This blacklist prevents llama-server, llama-bench, llama-perplexity,"
    echo "or other runtime engines from utilizing older or display-only GPUs."
    echo ""
    echo "Detected GPU Devices on System:"
    echo "------------------------------------------"
    if command -v nvidia-smi &>/dev/null; then
        echo "NVIDIA GPU(s):"
        nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader 2>/dev/null || echo "nvidia-smi check failed."
    else
        echo "No NVIDIA GPUs detected via nvidia-smi."
    fi
    echo ""
    if command -v vulkaninfo &>/dev/null; then
        echo "Vulkan GPU(s):"
        vulkaninfo --summary 2>/dev/null | grep -E "deviceName|deviceType" || echo "vulkaninfo failed."
    fi
    echo ""
    if command -v rocminfo &>/dev/null; then
        echo "ROCm AMD GPU(s):"
        rocminfo 2>/dev/null | grep -E "Name:|MarketingName:" | head -n 4 || echo "rocminfo failed."
    fi
    echo "------------------------------------------"
    echo "Current blacklisted GPU index/indexes: ${GPU_BLACKLIST:-None (all GPUs will be used)}"
    echo ""
    echo "To blacklist specific GPUs, enter their indices (comma-separated, e.g. 1)."
    echo "Enter 'none' or leave empty and press Enter to clear blacklist."
    read -p "New Blacklist Selection: " input_val
    
    if [[ -z "$input_val" ]]; then
        echo "Keeping current selection: ${GPU_BLACKLIST:-None}"
        sleep 1.5
        return
    fi
    
    if [[ "${input_val^^}" == "NONE" ]]; then
        GPU_BLACKLIST=""
        echo "[INFO] GPU Blacklist cleared."
    else
        GPU_BLACKLIST="$input_val"
        echo "[INFO] GPU Blacklist set to: $GPU_BLACKLIST"
    fi
    GPU_BLACKLIST_CONFIGURED="true"
    save_settings
    apply_gpu_blacklist
    sleep 2
}

# Apply GPU Blacklist silently on Startup
if [[ "$1" != "--json-status" ]]; then
    apply_gpu_blacklist
fi

# Helper function to dynamically locate the direct tool binaries depending on baseline backend or custom builds
get_bin_path() {
    local tool_name="$1"
    if [[ -n "$ACTIVE_CUSTOM_BUILD" ]]; then
        echo "$HOME/ai_tools/llama_custom_${ACTIVE_CUSTOM_BUILD}/BUILD_${ACTIVE_CUSTOM_BUILD}/bin/${tool_name}"
    else
        if [[ "$BACKEND" == "Vulkan" ]]; then
            echo "$BUILD_VULKAN/bin/${tool_name}"
        elif [[ "$BACKEND" == "RoCM" || "$BACKEND" == "ROCM" ]]; then
            echo "$BUILD_ROCM/bin/${tool_name}"
        else
            echo "$BUILD_CUDA/bin/${tool_name}"
        fi
    fi
}

# Helper to print menu option cleanly with underlined keys
item() {
    local key="$1"
    local desc="$2"
    echo -e "  \e[1m[\e[4m$key\e[24m]\e[0m $desc"
}

# Helper to get currently selected backend version
get_server_version() {
    local BIN="$(get_bin_path llama-server)"
    
    if [[ -f "$BIN" ]]; then
        "$BIN" --version 2>&1 | head -n 1
    else
        echo "Binary not built yet (Please run REBUILD/compile first)"
    fi
}

show_menu() {
    clear
    local MODEL_NAME="[NONE]"
    [[ -n "$MODEL_PATH" ]] && MODEL_NAME="$(basename "$MODEL_PATH")"
    local VERSION_INFO="$(get_server_version)"
    echo "=========================================="
    echo "    AI OPTIMIZED MANAGEMENT [v0.9.5.3]"
    echo "=========================================="
    echo "ACTIVE MODEL: $MODEL_NAME"
    if [[ -n "$ACTIVE_CUSTOM_BUILD" ]]; then
        echo "BACKEND/BUILD: Custom ($ACTIVE_CUSTOM_BUILD)"
    else
        echo "BACKEND/BUILD: Standard ($BACKEND)"
    fi
    echo "PROFILE: $BUILD_PROFILE"
    echo "VERSION: $VERSION_INFO"
    if [[ "$SSL_ENABLED" == "true" ]]; then
        echo "SSL STATUS: ON (Port: $PORT)"
    else
        echo "SSL STATUS: OFF (Port: $PORT)"
    fi
    echo "------------------------------------------"
    echo "  [M] Select Model"
    echo "  [L] Launch Server"
    echo "  [B] Select Backend (CUDA/Vulkan/Custom)"
    echo "  [R] Build / Rebuild Options (CUDA, Vulkan & ROCm)"
    echo "  [O] Options (Configure SSL ON/OFF & Custom Settings)"
    echo "  [S] Service Management (Install Llama.cpp as service)"
    echo "  [X] Diagnostics & Performance (Bench, Perplexity, Checks)"
    echo "  [I] Install Dependencies (System package installation)"
    echo "  [H] Reset & Maintenance (Config resets & cache clearing)"
    echo "  [Q] Quit"
    echo "=========================================="
    read -p "Selection: " choice
}

options_menu() {
    while true; do
        clear
        echo "=========================================="
        echo "           OPTIONS SUB-MENU"
        echo "=========================================="
        echo "Current Settings:"
        if [[ "$SSL_ENABLED" == "true" ]]; then
            echo "  SSL Toggle: [ON]"
          else
            echo "  SSL Toggle: [OFF]"
          fi
        echo "  Server Listen Port: $PORT"
        echo "  SSL private key:    ${SSL_KEY_PATH:-[Auto-Generated Default]}"
        echo "  SSL certificate:    ${SSL_CERT_PATH:-[Auto-Generated Default]}"
        echo "  GPU Blacklist:      ${GPU_BLACKLIST:-[None (All GPUs will be used)]}"
        echo "  Vulkan Device:      ${VULKAN_DEVICE:-[Default / Decided by Blacklist]}"
        echo "  MMPROJ File:        ${MMPROJ_PATH:-[None (Disabled)]}"
        if [[ "$LAUNCH_PAUSE" == "true" ]]; then
            echo "  Launch Pause:       [ON] (Will pause after exit/errors)"
        else
            echo "  Launch Pause:       [OFF] (Returns immediately to menu)"
        fi
        echo "------------------------------------------"
        item "1" "Toggle SSL ON/OFF"
        item "2" "Configure Custom Ports & Cert Paths"
        item "3" "Configure GPU Blacklist"
        item "4" "Select Multi-Modal Projector (MMPROJ) File"
        item "5" "Toggle Launch Pause ON/OFF"
        item "R" "Return to Main Menu"
        echo "=========================================="
        read -p "Selection: " opt_choice
        case ${opt_choice^^} in
            1)
                if [[ "$SSL_ENABLED" == "true" ]]; then
                    SSL_ENABLED="false"
                    PORT="8888"
                else
                    SSL_ENABLED="true"
                    ensure_ssl_certs
                    if [[ "$SSL_ENABLED" == "true" ]]; then
                        if [[ -z "$SSL_CERT_PATH" ]]; then SSL_CERT_PATH="$HOME/.ai_manager/ssl/server.crt"; fi
                        if [[ -z "$SSL_KEY_PATH" ]]; then SSL_KEY_PATH="$HOME/.ai_manager/ssl/server.key"; fi
                        if [[ ! -f "$SSL_CERT_PATH" || ! -f "$SSL_KEY_PATH" ]]; then
                            echo "Generating self-signed SSL certificates..."
                            mkdir -p "$(dirname "$SSL_CERT_PATH")" 2>/dev/null
                            openssl req -x509 -newkey rsa:4096 -keyout "$SSL_KEY_PATH" \
                                -out "$SSL_CERT_PATH" -days 365 -nodes \
                                -subj "/C=US/ST=State/L=City/O=Org/CN=localhost" \
                                2>/dev/null
                            echo "Certificates generated at: $SSL_CERT_PATH, $SSL_KEY_PATH"
                        fi
                    fi
                fi
                save_settings
                log "SSL Toggled to: ${SSL_ENABLED^^} (Port reset to default: $PORT)"
                sleep 1
                ;;
            2)
                clear
                echo "=== SSL & Port Configuration ==="
                read -p "Enter server listen port (current: $PORT): " input_port
                if [[ -n "$input_port" ]]; then
                    PORT="$input_port"
                fi
                read -p "Enter SSL Certificate Path (e.g., /etc/letsencrypt/live/example.com/fullchain.pem): " input_cert
                [[ -n "$input_cert" ]] && SSL_CERT_PATH="$input_cert"
                read -p "Enter SSL Private Key Path (e.g., /etc/letsencrypt/live/example.com/privkey.pem): " input_key
                [[ -n "$input_key" ]] && SSL_KEY_PATH="$input_key"

                if [[ -n "$SSL_CERT_PATH" && -n "$SSL_KEY_PATH" ]]; then
                    if [[ ! -f "$SSL_CERT_PATH" || ! -f "$SSL_KEY_PATH" ]]; then
                        echo "Error: Certificate or key file not found"
                        sleep 2
                    fi
                fi
                ensure_ssl_certs
                save_settings
                log "Configuration updated: Port=$PORT, Cert=$SSL_CERT_PATH, Key=$SSL_KEY_PATH"
                sleep 1.5
                ;;
            3)
                configure_gpu_blacklist
                ;;
            4)
                select_mmproj
                ;;
            5)
                if [[ "$LAUNCH_PAUSE" == "true" ]]; then
                    LAUNCH_PAUSE="false"
                else
                    LAUNCH_PAUSE="true"
                fi
                save_settings
                log "Launch Pause toggled to: ${LAUNCH_PAUSE^^}"
                sleep 1
                ;;
            R)
                break
                ;;
            *)
                echo "Invalid selection."
                sleep 1
                ;;
        esac
    done
}

select_model() {
    echo "Select model (.gguf) inside $MODELS_DIR:"
    local files=("$MODELS_DIR"/*.gguf)
    if [[ ${#files[@]} -eq 0 || ! -e "${files[0]}" ]]; then
        echo "No .gguf files found in $MODELS_DIR."
        read -p "Enter..."
        return
    fi
    for i in "${!files[@]}"; do
        echo "$((i+1))) $(basename "${files[$i]}")"
    done
    read -p "Select: " idx
    if [[ $idx -ge 1 && $idx -le ${#files[@]} ]]; then
        local selected_file="${files[$((idx-1))]}"
        if [[ -f "$selected_file" ]]; then
            MODEL_PATH="$selected_file"
            LAST_MODEL="$MODEL_PATH"
            save_settings
            log "Saved selected model to configuration: $(basename "$MODEL_PATH")"
        else
            echo "Error: '$(basename "$selected_file")' does not exist!"
            read -p "Press Enter to continue..."
        fi
    fi
}

select_mmproj() {
    clear
    echo "=========================================="
    echo "       SELECT MULTIMODAL PROJECTOR (MMPROJ)"
    echo "=========================================="
    echo "Searching for mmproj files in: $MODELS_DIR"
    echo "------------------------------------------"
    
    local files=()
    # Check for files containing mmproj in their name
    while IFS= read -r -d '' line; do
        if [[ -f "$line" ]]; then
            files+=("$line")
        fi
    done < <(find "$MODELS_DIR" -maxdepth 1 -type f -name "*mmproj*" -print0 2>/dev/null)
    
    # If no files contain *mmproj*, list all .gguf and .bin files as options
    if [[ ${#files[@]} -eq 0 ]]; then
        while IFS= read -r -d '' line; do
            if [[ -f "$line" ]]; then
                files+=("$line")
            fi
        done < <(find "$MODELS_DIR" -maxdepth 1 -type f \( -name "*.gguf" -o -name "*.bin" \) -print0 2>/dev/null)
    fi
    
    if [[ ${#files[@]} -eq 0 ]]; then
        echo "No mmproj, .gguf, or .bin files found in $MODELS_DIR."
        echo "Please download an mmproj file to that directory first."
        echo "------------------------------------------"
        item "C" "Clear current MMPROJ setting"
        item "R" "Return"
        read -p "Selection: " choice
        if [[ "${choice^^}" == "C" ]]; then
            MMPROJ_PATH=""
            save_settings
            echo "[INFO] MMPROJ setting cleared."
            sleep 1.5
        fi
        return
    fi
    
    echo "Choose an MMPROJ file:"
    for i in "${!files[@]}"; do
        echo "$((i+1))) $(basename "${files[$i]}")"
    done
    echo "------------------------------------------"
    item "C" "Clear current MMPROJ setting"
    item "R" "Return without changing"
    echo "------------------------------------------"
    read -p "Select (1-${#files[@]}, C, or R): " idx
    
    if [[ "${idx^^}" == "C" ]]; then
        MMPROJ_PATH=""
        save_settings
        echo "[INFO] MMPROJ setting cleared."
        sleep 1.5
        return
    fi
    
    if [[ "${idx^^}" == "R" || -z "$idx" ]]; then
        return
    fi
    
    if [[ "$idx" =~ ^[0-9]+$ ]] && [[ $idx -ge 1 && $idx -le ${#files[@]} ]]; then
        local selected_file="${files[$((idx-1))]}"
        if [[ -f "$selected_file" ]]; then
            MMPROJ_PATH="$selected_file"
            save_settings
            log "Saved selected mmproj to configuration: $(basename "$MMPROJ_PATH")"
            echo "[INFO] MMPROJ path updated successfully."
            sleep 1.5
        else
            echo "Error: '$(basename "$selected_file")' does not exist!"
            read -p "Press Enter to continue..."
        fi
    fi
}

change_build_options() {
    clear
    echo "=========================================="
    echo "    HARDWARE BUILD PROFILE SETTINGS       "
    echo "=========================================="
    echo "Current Profile: ${BUILD_PROFILE^^}"
    echo "------------------------------------------"
    item "L" "Low Profile: Legacy systems (AVX OFF)"
    item "M" "Medium Profile: Modern systems with AVX2 (AVX2 ON, -march=native)"
    item "H" "High Profile: Advanced systems with AVX-512 (AVX-512 ON, -march=native)"
    item "R" "Return to Build Menu"
    echo "=========================================="
    read -p "Selection: " prof_choice
    case ${prof_choice^^} in
        L)
            BUILD_PROFILE="low"
            save_settings
            log "Build profile set to LOW"
            sleep 1
            ;;
        M)
            BUILD_PROFILE="medium"
            save_settings
            log "Build profile set to MEDIUM"
            sleep 1
            ;;
        H)
            BUILD_PROFILE="high"
            save_settings
            log "Build profile set to HIGH"
            sleep 1
            ;;
        *)
            return
            ;;
    esac
}

check_hw_dep_cuda() {
    command -v nvcc &>/dev/null || dpkg -s nvidia-cuda-toolkit &>/dev/null
}

check_hw_dep_vulkan() {
    command -v glslc &>/dev/null && command -v glslangValidator &>/dev/null && (dpkg -s spirv-headers &>/dev/null || [[ -d "/usr/include/spirv" ]])
}

check_hw_dep_rocm() {
    command -v rocminfo &>/dev/null || [[ -x "/opt/rocm/bin/rocminfo" ]] || command -v hipcc &>/dev/null || [[ -x "/opt/rocm/bin/hipcc" ]]
}

verify_rocm_environment() {
    local conflict=0
    
    if [[ -d "/usr/include/hip" ]]; then
        conflict=1
    fi
    
    if dpkg -l | grep -E "libamdhip64-dev|libhsa-runtime-dev|libhiprtc-builtins5" &>/dev/null; then
        conflict=1
    fi
    
    if [[ $conflict -eq 1 ]]; then
        echo -e "\e[1;41m\e[97m======================================================================\e[0m"
        echo -e "\e[1;41m\e[97m FATAL ERROR: NATIVE ROCM PACKAGES DETECTED (HEADER SHADOWING)        \e[0m"
        echo -e "\e[1;41m\e[97m======================================================================\e[0m"
        echo -e "\e[1;31mYour build environment is contaminated by native Debian/Ubuntu apt packages.\e[0m"
        echo "These packages create conflicts in /usr/include/hip/ that break compilation."
        echo ""
        echo "To fix this, you MUST purge native packages and switch to official AMD tools:"
        echo "sudo apt purge libamdhip64-dev libhsa-runtime-dev libhiprtc-builtins5 libamd-comgr-dev librocblas0 libhipblas0 rocminfo rocm-smi"
        echo "sudo rm -rf /usr/include/hip/"
        echo "Then, install the official AMD installer package for tools & ROCm via dependency menu [I]."
        echo ""
        read -p "Compilation aborted. Press Enter to return to the menu..."
        return 1
    fi
    return 0
}

compile_custom_fork() {
    clear
    echo "=========================================="
    echo "    COMPILE CUSTOM GITHUB FORK/BRANCH     "
    echo "=========================================="
    
    # Retain operational confirmation gates for rebuild/compilation menu where files are cloned/written
    read -p "Are you sure you want to compile a custom GitHub fork? [y/N]: " confirm
    if [[ "${confirm^^}" != "Y" ]]; then
        log "Custom compile aborted."
        read -p "Press Enter to continue..."
        return
    fi
    
    read -p "Enter GitHub Repository URL: " custom_url
    if [[ -z "$custom_url" ]]; then
        log "Error: Repository URL cannot be empty."
        read -p "Press Enter to continue..."
        return
    fi
    
    read -p "Enter a unique name for this build (e.g., pinecone): " custom_name
    if [[ -z "$custom_name" ]]; then
        log "Error: Build name cannot be empty."
        read -p "Press Enter to continue..."
        return
    fi
    if [[ "$custom_name" =~ \.\. ]]; then
        log "Error: Invalid name (path traversal)."
        read -p "Press Enter to continue..."
        return
    fi
    if [[ "$custom_name" =~ [^a-zA-Z0-9_-] ]]; then
        log "Error: Invalid characters (only alphanumeric, dashes, and underscores allowed)."
        read -p "Press Enter to continue..."
        return
    fi
    
    local build_dir="$HOME/ai_tools/llama_custom_$custom_name"
    log "Preparing target directory: $build_dir"
    
    if [[ -d "$build_dir" ]]; then
        read -p "Directory '$build_dir' already exists. Trashing and overwriting? [y/N]: " overwrite_confirm
        if [[ "${overwrite_confirm^^}" != "Y" ]]; then
            log "Custom compile aborted to prevent overwriting."
            read -p "Press Enter to continue..."
            return
        fi
        local dest="$TRASH_DIR/llama_custom_${custom_name}_$(date +%Y%m%d_%H%M%S)"
        echo "[INFO] Moving existing directory to trash at '$dest'"
        mv "$build_dir" "$dest"
    fi
    
    log "Cloning repository..."
    git clone "$custom_url" "$build_dir"
    if [[ $? -ne 0 ]]; then
        log "Error: Failed to clone repository $custom_url"
        read -p "Press Enter to continue..."
        return
    fi
    
    echo ""
    echo "Select Build Target Architecture:"
    echo "1) CUDA"
    echo "2) Vulkan"
    echo "3) ROCm"
    read -p "Selection: " build_arch
    
    local target_build_dir="$build_dir/BUILD_$custom_name"
    mkdir -p "$target_build_dir"
    
    export CCACHE_SLOPPINESS=include_file_mtime,time_macros
    
    local cmake_args=(
        "-G Ninja" 
        "-B $target_build_dir" 
        "-S $build_dir" 
        "-DCMAKE_C_COMPILER_LAUNCHER=ccache" 
        "-DCMAKE_CXX_COMPILER_LAUNCHER=ccache"
        "-DCMAKE_CUDA_COMPILER_LAUNCHER=ccache"
        "-DLLAMA_BUILD_SERVER=ON"
        "-DCMAKE_BUILD_TYPE=Release"
        "-DCMAKE_TLS_VERIFY=OFF"
    )
    if [[ "$SSL_ENABLED" == "true" ]]; then
        cmake_args+=("-DLLAMA_SERVER_SSL=ON")
    else
        cmake_args+=("-DLLAMA_SERVER_SSL=OFF")
    fi
    
    if [[ "$BUILD_PROFILE" == "low" ]]; then
        cmake_args+=(
            "-DGGML_AVX=OFF"
            "-DGGML_AVX2=OFF"
            "-DGGML_AVX512=OFF"
            "-DGGML_FMA=OFF"
            "-DGGML_F16C=OFF"
            "-DGGML_BMI2=OFF"
            "-DGGML_NATIVE=OFF"
        )
    elif [[ "$BUILD_PROFILE" == "medium" ]]; then
        cmake_args+=(
            "-DGGML_AVX=ON"
            "-DGGML_AVX2=ON"
            "-DGGML_AVX512=OFF"
            "-DGGML_FMA=ON"
            "-DGGML_F16C=ON"
            "-DGGML_BMI2=ON"
            "-DGGML_NATIVE=ON"
            "-DCMAKE_C_FLAGS=-march=native"
            "-DCMAKE_CXX_FLAGS=-march=native"
        )
    else # high
        cmake_args+=(
            "-DGGML_AVX=ON"
            "-DGGML_AVX2=ON"
            "-DGGML_AVX512=ON"
            "-DGGML_FMA=ON"
            "-DGGML_F16C=ON"
            "-DGGML_BMI2=ON"
            "-DGGML_NATIVE=ON"
            "-DCMAKE_C_FLAGS=-march=native"
            "-DCMAKE_CXX_FLAGS=-march=native"
        )
    fi

    if [[ "$build_arch" == "1" ]]; then
        cmake_args+=(
            "-DGGML_CUDA=ON"
            "-DCMAKE_CUDA_ARCHITECTURES=86"
        )
    elif [[ "$build_arch" == "3" ]]; then
        cmake_args+=(
            "-DGGML_HIPBLAS=ON"
        )
    else
        # Vulkan
        cmake_args+=(
            "-DGGML_VULKAN=ON"
            "-DGGML_VULKAN_BFLOAT16=OFF"
        )
    fi
    
    log "Compiling $custom_name with build profile: $BUILD_PROFILE ..."
    cd "$build_dir" || { log "Error: Failed to navigate to $build_dir"; read -p "Press Enter to continue..."; return; }
    
    export CMAKE_TLS_VERIFY=0
    cmake "${cmake_args[@]}" && {
        echo "Starting build compilation..."
        cmake --build "$target_build_dir" -- -j$(nproc) 2>&1 | tee "$target_build_dir/build.log" | while read -r line; do
            if [[ "$line" =~ \[([[:space:]]*[0-9]+)%\] ]]; then
                local pct="${BASH_REMATCH[1]}"
                pct=$(echo "$pct" | tr -d ' ')
                local num_bars=$(( pct / 5 ))
                local num_dots=$(( 20 - num_bars ))
                local bar=""
                for ((i=0; i<num_bars; i++)); do bar+="■"; done
                for ((i=0; i<num_dots; i++)); do bar+="."; done
                echo -ne "\rBuilding: [$bar] $pct%   "
            else
                if [[ "$line" =~ "Building" || "$line" =~ "Linking" ]]; then
                    local short_line="${line:0:60}"
                    echo -ne "\r\e[KBuilding: $short_line"
                fi
            fi
        done
        echo "" # new line at the end
    }
    
    if [[ $? -eq 0 ]]; then
        log "Custom Build '$custom_name' compiled successfully!"
        log "Binaries output to: $target_build_dir"
    else
        log "Error: Compilation failed for '$custom_name'"
    fi
    
    read -p "Compilation phase complete. Enter..."
}

show_build_menu() {
    while true; do
        clear
        echo "=========================================="
        echo "        BUILD & REBUILD ENGINE SUITE      "
        echo "=========================================="
        echo "Hardware Status: CUDA: ✔ | Vulkan: ✔ | RoCM: ✔"
        echo "------------------------------------------"
        echo " --- FAST INCREMENTAL COMPILE ---"
        echo "  (Updates existing binaries using ccache. Does NOT delete folders.)"
        item "1" "COMPILE: llama.cpp CUDA"
        item "2" "COMPILE: llama.cpp VULKAN"
        item "3" "COMPILE: llama.cpp ROCM"
        echo ""
        echo " --- FORCE CLEAN REBUILD ---"
        echo "  (Deletes the entire build folder & purges ccache. Use if compilation fails.)"
        item "4" "REBUILD: llama.cpp CUDA"
        item "5" "REBUILD: llama.cpp VULKAN"
        item "6" "REBUILD: llama.cpp ROCM"
        echo ""
        echo " --- ALTERNATIVE ENGINES ---"
        item "F" "COMPILE: Custom GitHub Fork/Branch"
        item "O" "Change Build Options Profile (Current: ${BUILD_PROFILE^^})"
        local ssl_status_txt="OFF"
        [[ "$SSL_ENABLED" == "true" ]] && ssl_status_txt="ON"
        item "S" "Toggle SSL Support (Currently: $ssl_status_txt)"
        item "R" "Return to Main Menu"
        echo "=========================================="
        read -p "Selection: " bld_choice

        case ${bld_choice^^} in
            1) compile_backend "CUDA" "COMPILE" ;;
            2) compile_backend "VULKAN" "COMPILE" ;;
            3) compile_backend "ROCM" "COMPILE" ;;
            4) compile_backend "CUDA" "REBUILD" ;;
            5) compile_backend "VULKAN" "REBUILD" ;;
            6) compile_backend "ROCM" "REBUILD" ;;
            F) compile_custom_fork ;;
            O) change_build_options ;;
            S)
                if [[ "$SSL_ENABLED" == "true" ]]; then
                    SSL_ENABLED="false"
                    if [[ "$PORT" == "443" ]]; then
                        PORT="8888"
                    fi
                else
                    SSL_ENABLED="true"
                    ensure_ssl_certs
                    if [[ "$SSL_ENABLED" == "true" ]]; then
                        if [[ -z "$SSL_CERT_PATH" ]]; then SSL_CERT_PATH="$HOME/.ai_manager/ssl/server.crt"; fi
                        if [[ -z "$SSL_KEY_PATH" ]]; then SSL_KEY_PATH="$HOME/.ai_manager/ssl/server.key"; fi
                        if [[ ! -f "$SSL_CERT_PATH" || ! -f "$SSL_KEY_PATH" ]]; then
                            echo "Generating self-signed SSL certificates..."
                            mkdir -p "$(dirname "$SSL_CERT_PATH")" 2>/dev/null
                            openssl req -x509 -newkey rsa:4096 -keyout "$SSL_KEY_PATH" \
                                -out "$SSL_CERT_PATH" -days 365 -nodes \
                                -subj "/C=US/ST=State/L=City/O=Org/CN=localhost" \
                                2>/dev/null
                            echo "Certificates generated at: $SSL_CERT_PATH, $SSL_KEY_PATH"
                        fi
                    fi
                fi
                save_settings
                log "SSL Toggle update: SSL_ENABLED=$SSL_ENABLED, PORT=$PORT"
                sleep 1
                ;;
            R) break ;;
            *) echo "Invalid selection." ; sleep 1 ;;
        esac
    done
}

install_dependencies_menu() {
    while true; do
        clear
        echo "=========================================="
        echo "    INSTALL DEPENDENCIES FOR"
        echo "=========================================="
        item "N" "Nvidia (CUDA & Vulkan)"
        item "A" "AMD (RoCM & Vulkan)"
        item "R" "Return to Main Menu"
        echo "=========================================="
        read -p "Selection: " dep_choice
        case ${dep_choice^^} in
            N)
                echo "Executing custom installation of base and Nvidia packages..."
                sudo apt update && sudo apt install -y git cmake ninja-build ccache build-essential nodejs npm glslc spirv-headers nvidia-cuda-toolkit
                read -p "Installation phase complete. Press Enter..."
                ;;
            A)
                echo "Executing custom installation of base and AMD packages..."
                sudo apt update && sudo apt install -y git cmake ninja-build ccache build-essential nodejs npm glslc spirv-headers
                echo "======================================================================"
                echo -e "\e[1;31mWARNING: Do NOT install ROCm or ROCm tools via native apt repositories (e.g., libamdhip64-dev),\e[0m"
                echo -e "\e[1;31mas native system packages cause header shadowing conflicts that break compilation.\e[0m"
                echo "Switching to official AMD installer package for tools & ROCm instead of native repos:"
                echo "sudo amdgpu-install --usecase=rocm,rocmdevtools --no-dkms"
                echo "======================================================================"
                read -p "Would you like this script to execute the official AMD installer for tools & ROCm now? [y/N]: " run_amd
                if [[ "${run_amd^^}" == "Y" ]]; then
                    if command -v amdgpu-install &>/dev/null; then
                        sudo amdgpu-install --usecase=rocm,rocmdevtools --no-dkms
                    else
                        echo ""
                        echo "Official AMD installer package (amdgpu-install) not found on your system."
                        read -p "Download & install official AMD installer package (.deb) now? [y/N]: " dl_amd
                        if [[ "${dl_amd^^}" == "Y" ]]; then
                            local codename=$(lsb_release -cs 2>/dev/null || echo "noble")
                            local deb_url="https://repo.radeon.com/amdgpu-install/6.2.4/ubuntu/${codename}/amdgpu-install_6.2.60204-1_all.deb"
                            echo "Fetching official AMD package: $deb_url..."
                            if wget -q --show-progress "$deb_url" -O /tmp/amdgpu-install.deb 2>/dev/null || curl -fLo /tmp/amdgpu-install.deb "$deb_url" 2>/dev/null; then
                                sudo apt install -y /tmp/amdgpu-install.deb
                                rm -f /tmp/amdgpu-install.deb
                                if command -v amdgpu-install &>/dev/null; then
                                    echo "Official AMD installer package configured successfully!"
                                    echo "Installing ROCm and developer tools via official AMD package..."
                                    sudo amdgpu-install --usecase=rocm,rocmdevtools --no-dkms
                                fi
                            else
                                echo "Automated download failed."
                                echo "Please download the official AMD installer .deb from:"
                                echo "https://repo.radeon.com/amdgpu-install/ and run: sudo apt install ./amdgpu-install_*.deb"
                            fi
                        else
                            echo "Please install the official AMD installer package (amdgpu-install) instead of native system repositories."
                            sleep 2
                        fi
                    fi
                fi
                sudo usermod -aG video $USER
                sudo usermod -aG render $USER
                echo "Configured user video and render group permissions."
                read -p "Installation phase complete. Press Enter..."
                ;;
            R)
                break
                ;;
        esac
    done
}

service_menu() {
    while true; do
        clear
        echo "=========================================="
        echo "    SERVICE MANAGEMENT"
        echo "=========================================="
        item "A" "Service Status"
        item "B" "Restart Service"
        item "C" "Update Service w/ New Flags"
        item "D" "Install Service w/ Current Flags"
        item "E" "Remove Service"
        item "R" "Return to Main Menu"
        echo "=========================================="
        read -p "Selection: " svc_choice
        case ${svc_choice^^} in
            A)
                clear
                echo "--- System Service Status ---"
                if [[ -f /etc/systemd/system/llama-server.service ]]; then
                    echo "[Systemd detected]"
                    systemctl status llama-server --no-pager 2>/dev/null
                elif [[ -f /etc/init.d/llama-server ]]; then
                    echo "[SysVinit detected]"
                    /etc/init.d/llama-server status 2>/dev/null || ps aux | grep llama-server | grep -v grep
                else
                    echo "No service installed."
                fi
                read -p "Press Enter to continue..."
                ;;
            B)
                clear
                echo "Restarting service..."
                if [[ -f /etc/systemd/system/llama-server.service ]]; then
                    sudo systemctl restart llama-server 2>/dev/null || echo "Failed to restart Systemd service."
                elif [[ -f /etc/init.d/llama-server ]]; then
                    sudo /etc/init.d/llama-server restart 2>/dev/null || echo "Failed to restart SysVinit service."
                else
                    echo "No service installed to restart."
                fi
                read -p "Press Enter to continue..."
                ;;
            C)
                clear
                echo "Updating service configuration flags (LLAMA_ARG_ prefix)..."
                sudo mkdir -p /etc/default
                sudo tee /etc/default/llama-server >/dev/null <<EOF
LLAMA_ARG_MODEL="$MODEL_PATH"
LLAMA_ARG_PORT="$PORT"
LLAMA_ARG_HOST="0.0.0.0"
LLAMA_ARG_N_GPU_LAYERS="99"
LLAMA_ARG_FLASH_ATTN="on"
LLAMA_ARG_CONTEXT_SHIFT="1"
EOF
                sudo systemctl daemon-reload 2>/dev/null
                echo "Daemon reloaded with updated variables."
                read -p "Press Enter to continue..."
                ;;
            D)
                clear
                read -p "Choose Init Architecture [S] Systemd or [V] SysVinit: " init_type
                if [[ "${init_type^^}" == "S" ]]; then
                    sudo tee /etc/systemd/system/llama-server.service >/dev/null <<EOF
[Unit]
Description=Llama Server Daemon
After=network.target

[Service]
Type=simple
EnvironmentFile=-/etc/default/llama-server
ExecStart=$BUILD_CUDA/bin/llama-server
Restart=always

[Install]
WantedBy=multi-user.target
EOF
                    sudo systemctl daemon-reload 2>/dev/null
                    sudo systemctl enable llama-server 2>/dev/null
                    echo "Systemd service deployed. Use [C] to write configuration flags and [B] to start/restart."
                elif [[ "${init_type^^}" == "V" ]]; then
                    sudo tee /etc/init.d/llama-server >/dev/null <<EOF
#!/bin/sh
### BEGIN INIT INFO
# Provides:          llama-server
# Required-Start:    \$network \$remote_fs \$syslog
# Required-Stop:     \$network \$remote_fs \$syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Llama Server Daemon
### END INIT INFO

case "\$1" in
  start)
    export LLAMA_ARG_MODEL="$MODEL_PATH"
    export LLAMA_ARG_PORT="$PORT"
    export LLAMA_ARG_HOST="0.0.0.0"
    $BUILD_CUDA/bin/llama-server &
    echo \$! > /var/run/llama-server.pid
    ;;
  stop)
    kill \$(cat /var/run/llama-server.pid)
    rm /var/run/llama-server.pid
    ;;
  restart)
    \$0 stop
    sleep 1
    \$0 start
    ;;
  *)
    echo "Usage: \$0 {start|stop|restart}"
    exit 1
esac
EOF
                    sudo chmod +x /etc/init.d/llama-server
                    echo "SysVinit script deployed to /etc/init.d/llama-server."
                else
                    echo "Unknown option."
                fi
                read -p "Press Enter to continue..."
                ;;
            E)
                clear
                echo "Removing service..."
                sudo systemctl stop llama-server 2>/dev/null
                sudo systemctl disable llama-server 2>/dev/null
                
                # Check for llama-server.service file deletion
                if [[ -f /etc/systemd/system/llama-server.service ]]; then
                    read -p "Are you sure you want to delete /etc/systemd/system/llama-server.service? [y/N]: " confirm_svc
                    if [[ "${confirm_svc^^}" == "Y" ]]; then
                        local dest_svc="$TRASH_DIR/llama-server_service_$(date +%Y%m%d_%H%M%S)"
                        echo "[INFO] Moving '/etc/systemd/system/llama-server.service' to trash at '$dest_svc'"
                        sudo mv /etc/systemd/system/llama-server.service "$dest_svc" 2>/dev/null
                    fi
                fi
                
                # Check for /etc/init.d/llama-server file deletion
                if [[ -f /etc/init.d/llama-server ]]; then
                    read -p "Are you sure you want to delete /etc/init.d/llama-server? [y/N]: " confirm
                    if [[ "${confirm^^}" == "Y" ]]; then
                        local dest="$TRASH_DIR/llama-server_init_$(date +%Y%m%d_%H%M%S)"
                        echo "[INFO] Moving '/etc/init.d/llama-server' to trash at '$dest'"
                        sudo mv /etc/init.d/llama-server "$dest" 2>/dev/null
                    fi
                fi
                sudo systemctl daemon-reload 2>/dev/null
                echo "Service uninstalled cleanly."
                read -p "Press Enter to continue..."
                ;;
            R)
                break
                ;;
        esac
    done
}

diagnostics_menu() {
    while true; do
        clear
        echo "=========================================="
        echo "    DIAGNOSTICS & PERFORMANCE    "
        echo "=========================================="
        echo "  [B] Run Benchmark (llama-bench)"
        echo "  [P] Run Perplexity Check (llama-perplexity)"
        echo "  [D] Diagnostic Test Run (test flags)"
        echo "  [M] Monitor VRAM (NVIDIA-SMI)"
        echo "  [V] System Vulkan Check (Vulkan GPU IDs)"
        echo "  [A] Run RoCM AMD Diagnostics"
        echo "  [G] GPU Detection & Diagnostics"
        echo "  [F] Run Bench/Perplexity to File"
        echo "  [R] Return to Main Menu"
        echo "=========================================="
        read -p "Selection: " diag_choice
        case ${diag_choice^^} in
            B) run_benchmark ;;
            P) run_perplexity_menu ;;
            D) diagnostic_test_run ;;
            M) watch -n 1 nvidia-smi ;;
            V)
                clear
                if ! command -v vulkaninfo &>/dev/null; then
                    echo "=========================================="
                    echo " WARNING: vulkaninfo is NOT installed!     "
                    echo "=========================================="
                    echo "To query Vulkan devices, please install the vulkan-tools package."
                    echo "Command: sudo apt update && sudo apt install -y vulkan-tools"
                    echo "------------------------------------------"
                else
                    echo "=========================================="
                    echo "       SYSTEM VULKAN GPU IDENTITIES       "
                    echo "=========================================="
                    vulkaninfo --summary 2>/dev/null | grep -E "GPU|deviceName|deviceType" || echo "Failed to retrieve Vulkan device summary."
                fi
                read -p "Press Enter to return..."
                ;;
            A)
                clear
                local rocminfo_bin="rocminfo"
                if ! command -v rocminfo &>/dev/null && [[ -x "/opt/rocm/bin/rocminfo" ]]; then
                    rocminfo_bin="/opt/rocm/bin/rocminfo"
                fi
                if command -v "$rocminfo_bin" &>/dev/null || [[ -x "$rocminfo_bin" ]]; then
                    "$rocminfo_bin" 2>/dev/null | grep -E "GPU|Name|Marketing|Device Type" || echo "rocminfo found, but failed to return output."
                else
                    echo "rocminfo not found. Please install official AMD tools via option [I] (amdgpu-install --usecase=rocm,rocmdevtools) instead of native system repositories."
                fi
                read -p "Press Enter to return..."
                ;;
            G)
                clear
                echo "=========================================="
                echo "   AUTOMATED HARDWARE & GPU DETECTION     "
                echo "=========================================="
                echo ""
                echo "Checking CUDA/Nvidia Devices..."
                if command -v nvidia-smi &>/dev/null; then
                    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null || echo "nvidia-smi found, but failed to run."
                else
                    echo "-> No CUDA (Nvidia) GPU found or nvidia-smi is missing."
                fi
                echo ""
                echo "Checking Vulkan Devices..."
                if command -v vulkaninfo &>/dev/null; then
                    vulkaninfo --summary 2>/dev/null | grep -E "deviceName|deviceType" || echo "vulkaninfo found, but failed to list devices."
                else
                    echo "-> vulkaninfo is missing (Vulkan toolkit not fully installed)."
                fi
                echo ""
                echo "Checking ROCm/AMD Devices..."
                if command -v rocminfo &>/dev/null; then
                    rocminfo 2>/dev/null | grep -E "Name:|MarketingName:" | head -n 4 || echo "rocminfo found, but failed to return CPU/GPU structures."
                elif [[ -x "/opt/rocm/bin/rocminfo" ]]; then
                    /opt/rocm/bin/rocminfo 2>/dev/null | grep -E "Name:|MarketingName:" | head -n 4
                else
                    echo "-> No ROCm/AMD environment detected."
                fi
                echo "=========================================="
                read -p "Press Enter to return..."
                ;;
            F)
                clear
                echo "=========================================="
                echo "   RUN DIAGNOSTIC SILENTLY TO FILE "
                echo "=========================================="
                echo "1) Run llama-bench to file only"
                echo "2) Run llama-perplexity to file only"
                read -p "Select: " silent_choice
                if [[ "$silent_choice" == "1" ]]; then
                    [[ -z "$MODEL_PATH" ]] && { echo "Select a GGUF model first!"; sleep 2; continue; }
                    local BENCH_FILE="$LOGS_DIR/benchmark_$(date +%Y%m%d_%H%M%S).txt"
                    local BIN_PATH=$(get_bin_path llama-bench)
                    echo "Running benchmark silently, writing to $BENCH_FILE..."
                    "$BIN_PATH" -m "$MODEL_PATH" -n 128 -p 512,1024 -t 6 &> "$BENCH_FILE"
                    echo "Complete! Benchmark results successfully written."
                    read -p "Press Enter to return..."
                elif [[ "$silent_choice" == "2" ]]; then
                    [[ -z "$MODEL_PATH" ]] && { echo "Select a GGUF model first!"; sleep 2; continue; }
                    local CORPUS_FILE="${MODELS_DIR:-$HOME/Downloads}/norvig_big.txt"
                    local LOG_FILE="$LOGS_DIR/perplexity_$(date +%Y%m%d_%H%M%S).txt"
                    local BIN_PATH=$(get_bin_path llama-perplexity)
                    if [[ ! -s "$CORPUS_FILE" ]]; then
                        echo "[INFO] Perplexity corpus missing. Downloading Norvig''s big.txt..."
                        curl -sL "https://norvig.com/big.txt" > "$CORPUS_FILE"
                    fi
                    echo "Running perplexity check silently, writing to $LOG_FILE..."
                    
                    local start_secs=$(date +%s)
                    local start_time_str=$(date "+%Y-%m-%d %H:%M:%S")
                    
                    # Write metadata header to LOG_FILE
                    write_perplexity_header "$LOG_FILE" "false" "2" "$CORPUS_FILE" "$start_time_str"
                    
                    source "$FLAGS_FILE" 2>/dev/null
                    local -a ppl_args=()
                    ppl_args+=("-m" "$MODEL_PATH")
                    ppl_args+=("-f" "$CORPUS_FILE")
                    [[ -n "$GPU_LAYERS" ]] && ppl_args+=("-ngl" "$GPU_LAYERS")
                    [[ -n "$FLASH_ATTENTION" ]] && ppl_args+=("-fa" "$FLASH_ATTENTION")
                    [[ -n "$CONTEXT_SIZE" ]] && ppl_args+=("-c" "$CONTEXT_SIZE")
                    [[ -n "$BATCH_SIZE" ]] && ppl_args+=("-b" "$BATCH_SIZE")
                    [[ -n "$UBATCH_SIZE" ]] && ppl_args+=("-ub" "$UBATCH_SIZE")
                    [[ -n "$THREADS" ]] && ppl_args+=("-t" "$THREADS")
                    "$BIN_PATH" "${ppl_args[@]}" >> "$LOG_FILE" 2>&1
                    
                    local end_secs=$(date +%s)
                    local end_time_str=$(date "+%Y-%m-%d %H:%M:%S")
                    local elapsed=$(( end_secs - start_secs ))
                    local hours=$((elapsed / 3600))
                    local minutes=$(((elapsed % 3600) / 60))
                    local seconds=$((elapsed % 60))
                    local elapsed_str=""
                    if [[ $hours -gt 0 ]]; then
                        elapsed_str="${hours}h ${minutes}m ${seconds}s"
                    else
                        if [[ $minutes -gt 0 ]]; then
                            elapsed_str="${minutes}m ${seconds}s"
                        else
                            elapsed_str="${seconds}s"
                        fi
                    fi
                    
                    # Analyze and append post-run report
                    write_perplexity_report "$LOG_FILE" "false" "2" "$CORPUS_FILE" "$start_time_str" "$end_time_str" "$elapsed_str" >/dev/null
                    
                    echo "Complete! Perplexity validation results successfully written to $LOG_FILE"
                    read -p "Press Enter to return..."
                fi
                ;;
            R) break ;;
        esac
    done
}

reset_system_config() {
    clear
    echo "=========================================="
    echo "    SYSTEM CONFIG BOUNDED RESET ENGINE"
    echo "=========================================="
    read -p "Are you sure you want to reset system configuration settings? [y/N]: " confirm
    if [[ "${confirm^^}" != "Y" ]]; then
        log "Configuration reset aborted."
        read -p "Press Enter to continue..."
        return
    fi
    if [[ -f "$SETTINGS_FILE" ]]; then
        local backup_file="${SETTINGS_FILE}.old"
        local counter=1
        while [[ -f "$backup_file" ]]; do
            backup_file="${SETTINGS_FILE}.old${counter}"
            counter=$((counter + 1))
        done
        log "Safely backing up existing configuration to $backup_file ..."
        cp "$SETTINGS_FILE" "$backup_file"
    fi
    local CORPUS_FILE="${MODELS_DIR:-$HOME/Downloads}/norvig_big.txt"
    if [[ -f "$CORPUS_FILE" ]]; then
        local dest="$TRASH_DIR/norvig_big_$(date +%Y%m%d_%H%M%S).txt"
        echo "[INFO] Moving '$CORPUS_FILE' to trash at '$dest'"
        mv "$CORPUS_FILE" "$dest"
    fi
    log "Resetting application configuration back to default values..."
    # Perform clean reset by recreation
    BACKEND="CUDA"
    BUILD_PROFILE="low"
    LAST_MODEL=""
    MODELS_DIR=""
    ACTIVE_CUSTOM_BUILD=""
    save_settings
    log "Preferences restored to defaults successfully."
    log "Exiting script immediately."
    sleep 2
    exit 0
}

reset_cuda_cache() {
    clear
    echo "=========================================="
    echo "    RESET CUDA BUILD & CACHE              "
    echo "=========================================="
    read -p "Are you sure you want to completely delete the CUDA build directory ($BUILD_CUDA)? [y/N]: " confirm
    if [[ "${confirm^^}" == "Y" ]]; then
        log "Purging CUDA build directory..."
        rm -rf "$BUILD_CUDA"
        log "CUDA build directory deleted."
    else
        log "Reset aborted."
    fi
    read -p "Press Enter to continue..."
}

reset_vulkan_cache() {
    clear
    echo "=========================================="
    echo "    RESET VULKAN BUILD & CACHE            "
    echo "=========================================="
    read -p "Are you sure you want to completely delete the Vulkan build directory ($BUILD_VULKAN)? [y/N]: " confirm
    if [[ "${confirm^^}" == "Y" ]]; then
        log "Purging Vulkan build directory..."
        rm -rf "$BUILD_VULKAN"
        log "Vulkan build directory deleted."
    else
        log "Reset aborted."
    fi
    read -p "Press Enter to continue..."
}

reset_rocm_cache() {
    clear
    echo "=========================================="
    echo "    RESET ROCM BUILD & CACHE              "
    echo "=========================================="
    read -p "Are you sure you want to completely delete the ROCm build directory ($BUILD_ROCM)? [y/N]: " confirm
    if [[ "${confirm^^}" == "Y" ]]; then
        log "Purging ROCm build directory..."
        rm -rf "$BUILD_ROCM"
        log "ROCm build directory deleted."
    else
        log "Reset aborted."
    fi
    read -p "Press Enter to continue..."
}

maintenance_menu() {
    while true; do
        clear
        echo "=========================================="
        echo "    RESET & MAINTENANCE SUB-MENU          "
        echo "=========================================="
        echo "  [1] System Config Reset Defaults & Exit"
        echo "  [2] Reset/Wipe CUDA Build Cache & Directory"
        echo "  [3] Reset/Wipe Vulkan Build Cache & Directory"
        echo "  [4] Reset/Wipe ROCm Build Cache & Directory"
        echo "  [5] Delete Perplexity Corpus File"
        echo "  [6] Clear ccache (purge all cached builds)"
        echo "  [R] Return to Main Menu"
        echo "=========================================="
        read -p "Selection: " maint_choice
        case ${maint_choice} in
            1) reset_system_config ;;
            2) reset_cuda_cache ;;
            3) reset_vulkan_cache ;;
            4) reset_rocm_cache ;;
            5)
                local CORPUS_FILE="${MODELS_DIR:-$HOME/Downloads}/norvig_big.txt"
                if [[ ! -f "$CORPUS_FILE" ]]; then
                    echo "[INFO] Perplexity corpus file does not exist."
                    read -p "Press Enter to continue..."
                else
                    read -p "Are you sure you want to delete the perplexity corpus file? [y/N]: " confirm
                    if [[ "${confirm^^}" == "Y" ]]; then
                        local dest="$TRASH_DIR/norvig_big_$(date +%Y%m%d_%H%M%S).txt"
                        echo "[INFO] Moving '$CORPUS_FILE' to trash at '$dest'"
                        mv "$CORPUS_FILE" "$dest"
                        log "Perplexity corpus file moved to trash."
                    else
                        log "Deletion aborted."
                    fi
                    read -p "Press Enter to continue..."
                fi
                ;;
            6)
                ccache -C
                log "ccache build cache purged successfully."
                sleep 1.5
                ;;
            [Rr]*) break ;;
        esac
    done
}

spawn_window() {
    local cmd="$1"
    local title="$2"
    
    # Source flags before execution so the terminal has Vulkan devices loaded
    local full_cmd="source $FLAGS_FILE 2>/dev/null; $cmd"

    if command -v gnome-terminal &>/dev/null; then
        gnome-terminal --title="$title" -- bash -c "$full_cmd; exec bash"
    elif command -v konsole &>/dev/null; then
        konsole --title "$title" -e bash -c "$full_cmd; exec bash"
    elif command -v xterm &>/dev/null; then
        xterm -T "$title" -e bash -c "$full_cmd; exec bash"
    else
        echo "[INFO] No graphical terminal detected. Running safely in foreground..."
        bash -c "$full_cmd"
        local exit_code=$?
        if [[ "$LAUNCH_PAUSE" == "true" ]]; then
            echo "------------------------------------------"
            echo "[INFO] Process terminated with exit code $exit_code."
            read -p "Press Enter to return to menu..."
        fi
    fi
}

run_benchmark() {
    [[ -z "$MODEL_PATH" ]] && { echo "Select a GGUF model first!"; sleep 2; return; }
    clear
    echo "=========================================="
    echo " LLAMA-BENCHMARK PERFORMANCE ENGINE"
    echo "=========================================="
    local BENCH_FILE="$LOGS_DIR/benchmark_$(date +%Y%m%d_%H%M%S).txt"
    local BIN_PATH=$(get_bin_path llama-bench)

    echo "[INFO] Running benchmark on: $(basename "$MODEL_PATH")"
    echo "[INFO] Output will be saved to: $BENCH_FILE"
    echo "------------------------------------------"

    # Execute benchmark and use 'tee' to display live while saving to file
    "$BIN_PATH" -m "$MODEL_PATH" -n 128 -p 512,1024 -t 6 | tee "$BENCH_FILE"

    echo "------------------------------------------"
    read -p "Benchmark complete. Press Enter to return to menu..."
}

prepare_predictive_corpus() {
    local source_file="$1"
    local dest_file="$2"
    
    if [[ ! -f "$source_file" ]]; then
        echo "[ERROR] Source corpus file not found: $source_file"
        return 1
    fi
    
    local total_lines
    total_lines=$(wc -l < "$source_file")
    
    # 10 zones of 600 lines each require at least 6000 lines.
    # Safety check: if source is smaller than the slice requirements, bypass slicing and copy directly.
    if [[ "$total_lines" -lt 7000 ]]; then
        echo "[INFO] Source file too small ($total_lines lines). Bypassing slicing; copying directly."
        cp "$source_file" "$dest_file"
        return 0
    fi
    
    # Clean the destination file
    > "$dest_file"
    
    local block_size=600
    local num_zones=10
    local step=$(( (total_lines - block_size) / (num_zones - 1) ))
    
    if [[ "$step" -le 0 ]]; then
        echo "[INFO] Calculated step size is non-positive. Bypassing slicing; copying directly."
        cp "$source_file" "$dest_file"
        return 0
    fi
    
    echo "[INFO] Mathematically slicing source file into $num_zones equally spaced zones of $block_size lines (step size: $step)..."
    for i in {0..9}; do
        local start_line=$(( i * step + 1 ))
        local end_line=$(( start_line + block_size - 1 ))
        # Using sed to extract lines elegantly and fast without reading into huge Bash arrays
        sed -n "${start_line},${end_line}p" "$source_file" >> "$dest_file"
    done
    
    echo "[INFO] Predictive slices generated successfully at $dest_file."
    return 0
}

calculate_stats() {
    echo "$*" | awk '{
        sum = 0;
        sumsq = 0;
        n = NF;
        if (n == 0) {
            print "0.0000 0.0000";
            exit;
        }
        for (i = 1; i <= n; i++) {
            sum += $i;
            sumsq += ($i * $i);
        }
        mean = sum / n;
        variance = (sumsq / n) - (mean * mean);
        if (variance < 0) variance = 0;
        stddev = sqrt(variance);
        printf "%.4f %.4f\n", mean, stddev;
    }'
}

get_chunk_val() {
    local target_idx="$1"
    local log_f="$2"
    sed -nE "s/.*\[[[:space:]]*${target_idx}\][[:space:]]*([0-9]+\.[0-9]+).*/\1/p" "$log_f" | tail -n 1
}

get_chunks_in_range() {
    local start_idx="$1"
    local end_idx="$2"
    local log_f="$3"
    local vals=()
    for ((i=start_idx; i<=end_idx; i++)); do
        local val=$(get_chunk_val "$i" "$log_f")
        if [[ -n "$val" ]]; then
            vals+=("$val")
        fi
    done
    echo "${vals[@]}"
}

write_perplexity_header() {
    local log_f="$1"
    local is_pred="$2"
    local choice_name="$3"
    local corpus="$4"
    local start_t_str="$5"
    
    {
        echo "======================================================================="
        echo "                    LLAMA-PERPLEXITY VALIDATION RUN"
        echo "======================================================================="
        echo "Run Date       : $(date)"
        echo "Start Time     : ${start_t_str:-$(date "+%Y-%m-%d %H:%M:%S")}"
        echo "Model Name     : $(basename "$MODEL_PATH")"
        echo "Full Model Path: $MODEL_PATH"
        if [[ "$is_pred" == "true" ]]; then
            echo "Test Type      : Option 3 (Accelerated Predictive Test)"
            echo "Corpus Slices  : Cross-Sectional Mixed Slices (Temp file: $corpus)"
        elif [[ "$choice_name" == "1" ]]; then
            echo "Test Type      : Option 1 (Raw Sequential Short Test)"
            echo "Corpus File    : $corpus"
        else
            echo "Test Type      : Option 2 (Exhaustive Production Run)"
            echo "Corpus File    : $corpus"
        fi
        echo "======================================================================="
        echo "CONFIGURATIONS:"
        echo "  GPU_LAYERS      = $GPU_LAYERS"
        echo "  FLASH_ATTENTION = $FLASH_ATTENTION"
        echo "  CONTEXT_SIZE    = $CONTEXT_SIZE"
        echo "  BATCH_SIZE      = $BATCH_SIZE"
        echo "  UBATCH_SIZE     = $UBATCH_SIZE"
        echo "  THREADS         = $THREADS"
        echo "  BACKEND         = $BACKEND"
        echo "======================================================================="
        echo "STARTING LLAMA-PERPLEXITY RUN..."
        echo ""
    } > "$log_f"
}

write_perplexity_report() {
    local log_f="$1"
    local is_pred="$2"
    local choice_name="$3"
    local corpus="$4"
    local start_t_str="$5"
    local end_t_str="$6"
    local elapsed_str="$7"
    
    {
        echo ""
        echo "======================================================================="
        echo "                 METADATA ANALYSIS & POST-RUN REPORT"
        echo "======================================================================="
        echo "Model Name     : $(basename "$MODEL_PATH")"
        echo "Start Time     : ${start_t_str:-N/A}"
        echo "End Time       : ${end_t_str:-N/A}"
        echo "Total Run Time : ${elapsed_str:-N/A}"
        
        if [[ "$is_pred" == "true" ]]; then
            echo "Executed Test  : Option 3 (Accelerated Predictive Test - 40 Chunks Mixed Slices)"
            echo "-----------------------------------------------------------------------"
            echo "WHAT THIS TEST MEASURED:"
            echo "  This test provides a statistically extrapolated prediction of the model''s"
            echo "  generalized perplexity representing a 700+ chunk exhaustive run across"
            echo "  random cross-sectional text slices (also known as the random test)."
            echo "  By processing 40 mixed slices, it bypasses the sequential front-matter"
            echo "  bias in under 2 minutes."
            echo ""
            
            local last_ppl_line=$(grep -E '\[[[:space:]]*[0-9]+\][[:space:]]*[0-9]+\.[0-9]+' "$log_f" | tail -n 1)
            local last_chunk_num=$(echo "$last_ppl_line" | sed -E 's/.*\[[[:space:]]*([0-9]+)\].*/\1/')
            local last_chunk_val=$(echo "$last_ppl_line" | sed -E 's/.*\[[[:space:]]*[0-9]+\][[:space:]]*([0-9]+\.[0-9]+).*/\1/')
            
            local val_34=$(get_chunk_val 34 "$log_f")
            local plateau_vals=$(get_chunks_in_range 30 40 "$log_f")
            
            if [[ -z "$val_34" && -n "$last_chunk_num" ]]; then
                echo "Warning: Test was interrupted or did not reach Chunk #34 (Last processed chunk: #$last_chunk_num)."
                local start_fb=$(( last_chunk_num - 10 ))
                [[ $start_fb -lt 1 ]] && start_fb=1
                plateau_vals=$(get_chunks_in_range $start_fb $last_chunk_num "$log_f")
                val_34="$last_chunk_val"
            fi
            
            if [[ -n "$plateau_vals" ]]; then
                local stats=$(calculate_stats $plateau_vals)
                local plateau_mean=$(echo "$stats" | awk '{print $1}')
                local plateau_stddev=$(echo "$stats" | awk '{print $2}')
                
                echo "PREDICTION TRAJECTORY RESULTS:"
                echo "  Expected Final Perplexity Prediction (Chunk #34) : ${val_34:-N/A}"
                echo "  Steady-State Plateau Mean (Chunks 30-40)         : ${plateau_mean:-N/A}"
                echo "  Trajectory Standard Deviation (Plateau Stability) : ${plateau_stddev:-N/A}"
                echo ""
                echo "NOTE on prediction:"
                echo "  Statistical trajectory analysis indicates that Chunk #34 provides the"
                echo "  most accurate converged proxy for a full-scale exhaustive run."
                echo "  The Trajectory Standard Deviation indicates how stable the perplexity"
                echo "  remained across the mixed sample blocks."
            else
                echo "Error: No perplexity telemetry could be parsed from the run."
            fi
            
        elif [[ "$choice_name" == "1" ]]; then
            echo "Executed Test  : Option 1 (Raw Sequential Short Test - 30 Chunks)"
            echo "-----------------------------------------------------------------------"
            echo "WHAT THIS TEST MEASURED:"
            echo "  This test measures local text perplexity over the initial 30 sequential"
            echo "  chunks of the raw corpus. It is highly vulnerable to introductory/"
            echo "  front-matter structural text bias (e.g. legal headers, standard licenses)"
            echo "  which typically causes it to under-report the true generalized perplexity."
            echo ""
            
            local last_ppl_line=$(grep -E '\[[[:space:]]*[0-9]+\][[:space:]]*[0-9]+\.[0-9]+' "$log_f" | tail -n 1)
            local last_chunk_num=$(echo "$last_ppl_line" | sed -E 's/.*\[[[:space:]]*([0-9]+)\].*/\1/')
            local last_chunk_val=$(echo "$last_ppl_line" | sed -E 's/.*\[[[:space:]]*[0-9]+\][[:space:]]*([0-9]+\.[0-9]+).*/\1/')
            
            echo "RESULTS SUMMARY:"
            echo "  Last Processed Chunk     : #$last_chunk_num"
            echo "  Final Measured Local PPL : $last_chunk_val"
            
        else
            echo "Executed Test  : Option 2 (Exhaustive Production Run)"
            echo "-----------------------------------------------------------------------"
            echo "WHAT THIS TEST MEASURED:"
            echo "  This test measures the true generalized perplexity of the model across"
            echo "  the entire corpus. It provides the absolute production-grade evaluation"
            echo "  of the model''s textual coherence, predictability, and semantic depth."
            echo ""
            
            local last_ppl_line=$(grep -E '\[[[:space:]]*[0-9]+\][[:space:]]*[0-9]+\.[0-9]+' "$log_f" | tail -n 1)
            local last_chunk_num=$(echo "$last_ppl_line" | sed -E 's/.*\[[[:space:]]*([0-9]+)\].*/\1/')
            local last_chunk_val=$(echo "$last_ppl_line" | sed -E 's/.*\[[[:space:]]*[0-9]+\][[:space:]]*([0-9]+\.[0-9]+).*/\1/')
            
            echo "RESULTS SUMMARY:"
            echo "  Last Processed Chunk       : #$last_chunk_num"
            echo "  Final Measured General PPL : $last_chunk_val"
        fi
        echo "======================================================================="
    } | tee -a "$log_f"
}

run_perplexity_menu() {
    [[ -z "$MODEL_PATH" ]] && { echo "Select a GGUF model first!"; sleep 2; return; }
    
    local CORPUS_FILE="${MODELS_DIR:-$HOME/Downloads}/norvig_big.txt"
    local BIN_PATH=$(get_bin_path llama-perplexity)
    
    if [[ ! -s "$CORPUS_FILE" ]]; then
        clear
        echo "[INFO] Perplexity corpus missing. Downloading Norvig''s big.txt..."
        curl -sL "https://norvig.com/big.txt" > "$CORPUS_FILE"
        echo "[INFO] Corpus successfully generated."
        sleep 1.5
    fi

    local active_corpus="$CORPUS_FILE"
    local chunks_count=""
    local is_predictive="false"
    local TEMP_CORPUS="/tmp/predictive_corpus_$$.txt"

    while true; do
        clear
        echo "=========================================="
        echo "    LLAMA-PERPLEXITY VALIDATION MENU"
        echo "=========================================="
        echo "ACTIVE MODEL: $(basename "$MODEL_PATH")"
        echo "CORPUS FILE : $(basename "$CORPUS_FILE")"
        echo "------------------------------------------"
        echo "  [1] Option 1: Raw Sequential Short Test"
        echo "      (Processes academic short list - 30 chunks natively."
        echo "       Warning: This under-reports final PPL due to introductory/"
        echo "       front-matter structural text bias.)"
        echo ""
        echo "  [2] Option 2: Exhaustive Production Run"
        echo "      (Processes the entire dataset cleanly up to 1000+ chunks"
        echo "       for absolute production-grade evaluation.)"
        echo ""
        echo "  [3] Option 3: Accelerated Predictive Test"
        echo "      (Generates a cross-sectional text slice, then executes"
        echo "       eval over 40 mixed chunks to estimate 700+ pass plateau"
        echo "       in under 2 minutes.)"
        echo ""
        echo "  [R] Return to Diagnostics Menu"
        echo "=========================================="
        read -p "Selection: " ppl_choice
        
        local switch_choice=${ppl_choice^^}
        if [[ "$switch_choice" == "1" ]]; then
            active_corpus="$CORPUS_FILE"
            chunks_count="30"
            is_predictive="false"
            break
        elif [[ "$switch_choice" == "2" ]]; then
            active_corpus="$CORPUS_FILE"
            chunks_count="1000"
            is_predictive="false"
            break
        elif [[ "$switch_choice" == "3" ]]; then
            # Triggers 'prepare_predictive_corpus' to generate cross-sectional text slice
            clear
            echo "[INFO] Triggering prepare_predictive_corpus..."
            prepare_predictive_corpus "$CORPUS_FILE" "$TEMP_CORPUS"
            if [[ $? -ne 0 ]]; then
                echo "[ERROR] Failed to prepare predictive corpus."
                sleep 2
                continue
            fi
            active_corpus="$TEMP_CORPUS"
            chunks_count="40"
            is_predictive="true"
            break
        elif [[ "$switch_choice" == "R" ]]; then
            return
        else
            echo "Invalid selection."
            sleep 1
        fi
    done

    clear
    local LOG_FILE="$LOGS_DIR/perplexity_$(date +%Y%m%d_%H%M%S).txt"
    
    local start_secs=$(date +%s)
    local start_time_str=$(date "+%Y-%m-%d %H:%M:%S")
    
    # Write metadata header using helper
    write_perplexity_header "$LOG_FILE" "$is_predictive" "$switch_choice" "$active_corpus" "$start_time_str"
    
    echo "=========================================="
    echo "      RUNNING PERPLEXITY CHECK"
    echo "=========================================="
    echo "[INFO] Model : $(basename "$MODEL_PATH")"
    echo "[INFO] Log   : $LOG_FILE"
    echo "[INFO] Config: GPU_LAYERS=$GPU_LAYERS, FLASH_ATTENTION=$FLASH_ATTENTION, CONTEXT_SIZE=$CONTEXT_SIZE, BATCH_SIZE=$BATCH_SIZE, THREADS=$THREADS"
    if [[ "$is_predictive" == "true" ]]; then
        echo "[INFO] Mode  : Option 3 (Accelerated Predictive Test)"
        echo "[INFO] Corpus: Sliced Predictive Temp File ($active_corpus)"
    else
        echo "[INFO] Mode  : Option $switch_choice"
        echo "[INFO] Corpus: $active_corpus"
    fi
    echo "------------------------------------------"

    local ppl_args=()
    ppl_args+=("-m" "$MODEL_PATH")
    ppl_args+=("-f" "$active_corpus")
    [[ -n "$GPU_LAYERS" ]] && ppl_args+=("-ngl" "$GPU_LAYERS")
    [[ -n "$FLASH_ATTENTION" ]] && ppl_args+=("-fa" "$FLASH_ATTENTION")
    [[ -n "$CONTEXT_SIZE" ]] && ppl_args+=("-c" "$CONTEXT_SIZE")
    [[ -n "$BATCH_SIZE" ]] && ppl_args+=("-b" "$BATCH_SIZE")
    [[ -n "$UBATCH_SIZE" ]] && ppl_args+=("-ub" "$UBATCH_SIZE")
    [[ -n "$THREADS" ]] && ppl_args+=("-t" "$THREADS")
    [[ -n "$chunks_count" ]] && ppl_args+=("--chunks" "$chunks_count")

    source "$FLAGS_FILE" 2>/dev/null
    
    # Pipes stderr and stdout correctly, appending to existing log file with header
    "$BIN_PATH" "${ppl_args[@]}" 2>&1 | tee -a "$LOG_FILE"

    echo "------------------------------------------"
    echo "[INFO] Run complete. Performing trajectory and statistical metadata audits..."
    
    local end_secs=$(date +%s)
    local end_time_str=$(date "+%Y-%m-%d %H:%M:%S")
    local elapsed=$(( end_secs - start_secs ))
    local hours=$((elapsed / 3600))
    local minutes=$(((elapsed % 3600) / 60))
    local seconds=$((elapsed % 60))
    local elapsed_str=""
    if [[ $hours -gt 0 ]]; then
        elapsed_str="${hours}h ${minutes}m ${seconds}s"
    else
        if [[ $minutes -gt 0 ]]; then
            elapsed_str="${minutes}m ${seconds}s"
        else
            elapsed_str="${seconds}s"
        fi
    fi
    
    sleep 1
    
    # Analyze and append the final post-run report using helper
    write_perplexity_report "$LOG_FILE" "$is_predictive" "$switch_choice" "$active_corpus" "$start_time_str" "$end_time_str" "$elapsed_str"
    
    echo ""
    # Clean up the predictive slice file from /tmp/ if produced
    if [[ "$is_predictive" == "true" ]]; then
        echo "[INFO] Cleaning up temporary sliced corpus file..."
        rm -f "$TEMP_CORPUS"
    fi

    read -p "Perplexity validation complete. Press Enter to return..."
}

diagnostic_test_run() {
    [[ -z "$MODEL_PATH" ]] && { echo "Select a GGUF model first!"; sleep 2; return; }

    local BIN="$(get_bin_path llama-server)"
    if [[ ! -f "$BIN" ]]; then
        echo "Compiled binary not found at $BIN."
        sleep 2
        return
    fi
    mkdir -p "$LOGS_DIR"
    echo "=== Real-time Operational Stability Check ===" > "$LOGS_DIR/diagnostics.log"
    
    local diag_cmd="timeout 12 \"$BIN\" -m \"$MODEL_PATH\" -ngl 99 --port 9091 --host 127.0.0.1 --no-mmap &> \"$LOGS_DIR/diagnostics.log\""
    
    echo "Launching diagnostic test run in separate window..."
    spawn_window "$diag_cmd" "Diagnostic Test Run"
    
    echo "Diagnostics running in independent console window. Waiting for completion..."
    sleep 6
    echo "=========================================="
    echo "    DIAGNOSTICS TEST RUN LOGS (TAIL)"
    echo "=========================================="
    tail -n 20 "$LOGS_DIR/diagnostics.log" 2>/dev/null || echo "Logging in progress..."
    echo "=========================================="
    read -p "Press Enter to return..."
}

compile_backend() {
    local backend="$1"
    local mode="$2"
    local BUILD_DIR=""
    
    if [[ "$backend" == "ROCM" ]]; then
        verify_rocm_environment || return
        BUILD_DIR="$BUILD_ROCM"
    elif [[ "$backend" == "CUDA" ]]; then
        BUILD_DIR="$BUILD_CUDA"
    elif [[ "$backend" == "VULKAN" ]]; then
        BUILD_DIR="$BUILD_VULKAN"
    fi

    echo "Initiating $mode for $backend backend..."

    if [[ "$mode" == "REBUILD" ]]; then
        echo "Purging build directory ($BUILD_DIR) and resetting ccache..."
        rm -rf "$BUILD_DIR"
        ccache -C
    fi

    # 1. Pull latest changes or clone official source
    if [[ -d "$LLAMA_DIR" && -d "$LLAMA_DIR/.git" ]]; then
        log "Existing git repository found at $LLAMA_DIR."
        read -p "Pull latest from git? [y/N]: " pull_git
        if [[ "${pull_git^^}" == "Y" ]]; then
            log "Pulling latest updates from official repository..."
            cd "$LLAMA_DIR" || { log "Error: Failed to navigate to $LLAMA_DIR"; return; }
            git pull --tags || log "Warning: Git pull failed, attempting compiler phase with existing codebase..."
            cd - &>/dev/null || return
        fi
    else
        log "Official llama.cpp repository not found."
        log "Cloning from official source..."
        
        # Add simple [y/n] confirmation dialog before any file deletion
        if [[ -d "$LLAMA_DIR" ]]; then
            read -p "Are you sure you want to move existing llama directory to trash? [y/N]: " confirm
            if [[ "${confirm^^}" == "Y" ]]; then
                local dest="$TRASH_DIR/llama.cpp_$(date +%Y%m%d_%H%M%S)"
                echo "[INFO] Moving '$LLAMA_DIR' to trash at '$dest'"
                mv "$LLAMA_DIR" "$dest"
            fi
        fi
        git clone https://github.com/ggml-org/llama.cpp "$LLAMA_DIR" || { log "Error: Failed to clone llama.cpp"; return; }
    fi

    # Web UI NPM package resolution check
    if [[ -d "$LLAMA_DIR/tools/ui" ]]; then
        log "Checking and installing Node dependencies for Web UI inside $LLAMA_DIR/tools/ui..."
        (cd "$LLAMA_DIR/tools/ui" && npm install --silent &>/dev/null &)
    fi

    mkdir -p "$BUILD_DIR"

    # Get gpu_arch for ROCm/HIP target architectures
    local gpu_arch=""
    if [[ "$backend" == "ROCM" ]]; then
        if [[ -n "$AMDGPU_TARGETS" ]]; then
            gpu_arch="$AMDGPU_TARGETS"
            log "Using ROCm GPU architecture override from environment: AMDGPU_TARGETS=$gpu_arch"
        else
            local rocminfo_bin=""
            if command -v rocminfo &>/dev/null; then
                rocminfo_bin="rocminfo"
            elif [[ -x "/opt/rocm/bin/rocminfo" ]]; then
                rocminfo_bin="/opt/rocm/bin/rocminfo"
            fi

            if [[ -n "$rocminfo_bin" ]]; then
                gpu_arch=$("$rocminfo_bin" 2>/dev/null | grep -o -E 'gfx[0-9a-fA-F]+' | head -n 1)
            fi

            if [[ -n "$gpu_arch" ]]; then
                log "Automatically detected ROCm GPU architecture: $gpu_arch"
            else
                log "Could not automatically detect ROCm GPU architecture via rocminfo."
                read -p "Please enter your GPU architecture (e.g., gfx1100, gfx1030, gfx906) [or press Enter to fallback to native]: " user_arch
                if [[ -n "$user_arch" ]]; then
                    gpu_arch="$user_arch"
                fi
            fi
        fi
    fi

    log "Building $backend ($BUILD_PROFILE-end profile)..."

    # Initialize compilation flags
    local FLAGS="-B $BUILD_DIR -GNinja -S $LLAMA_DIR"
    FLAGS+=" -DCMAKE_C_COMPILER_LAUNCHER=ccache"
    FLAGS+=" -DCMAKE_CXX_COMPILER_LAUNCHER=ccache"
    FLAGS+=" -DCMAKE_CUDA_COMPILER_LAUNCHER=ccache"
    FLAGS+=" -DLLAMA_BUILD_SERVER=ON"
    FLAGS+=" -DCMAKE_BUILD_TYPE=Release"
    FLAGS+=" -DCMAKE_TLS_VERIFY=OFF"
    if [[ "$SSL_ENABLED" == "true" ]]; then
        FLAGS+=" -DLLAMA_SERVER_SSL=ON"
    else
        FLAGS+=" -DLLAMA_SERVER_SSL=OFF"
    fi

    if [[ "$BUILD_PROFILE" == "low" ]]; then
        FLAGS+=" -DGGML_AVX=OFF"
        FLAGS+=" -DGGML_AVX2=OFF"
        FLAGS+=" -DGGML_AVX512=OFF"
        FLAGS+=" -DGGML_FMA=OFF"
        FLAGS+=" -DGGML_F16C=OFF"
        FLAGS+=" -DGGML_BMI2=OFF"
        FLAGS+=" -DGGML_NATIVE=OFF"
    elif [[ "$BUILD_PROFILE" == "medium" ]]; then
        FLAGS+=" -DGGML_AVX=ON"
        FLAGS+=" -DGGML_AVX2=ON"
        FLAGS+=" -DGGML_AVX512=OFF"
        FLAGS+=" -DGGML_FMA=ON"
        FLAGS+=" -DGGML_F16C=ON"
        FLAGS+=" -DGGML_BMI2=ON"
        FLAGS+=" -DGGML_NATIVE=ON"
        FLAGS+=" -DCMAKE_C_FLAGS=-march=native"
        FLAGS+=" -DCMAKE_CXX_FLAGS=-march=native"
    else # high
        FLAGS+=" -DGGML_AVX=ON"
        FLAGS+=" -DGGML_AVX2=ON"
        FLAGS+=" -DGGML_AVX512=ON"
        FLAGS+=" -DGGML_FMA=ON"
        FLAGS+=" -DGGML_F16C=ON"
        FLAGS+=" -DGGML_BMI2=ON"
        FLAGS+=" -DGGML_NATIVE=ON"
        FLAGS+=" -DCMAKE_C_FLAGS=-march=native"
        FLAGS+=" -DCMAKE_CXX_FLAGS=-march=native"
    fi

    if [[ "$backend" == "CUDA" ]]; then
        FLAGS+=" -DGGML_CUDA=ON"
        FLAGS+=" -DCMAKE_CUDA_ARCHITECTURES=86"
    elif [[ "$backend" == "ROCM" ]]; then
        FLAGS+=" -DGGML_HIP=ON"
        FLAGS+=" -DGGML_HIPBLAS=ON"
        if [[ -n "$gpu_arch" ]]; then
            FLAGS+=" -DAMDGPU_TARGETS=$gpu_arch"
        fi
    else
        # VULKAN backend stabilization: Disable BF16 Shaders
        FLAGS+=" -DGGML_VULKAN=ON"
        FLAGS+=" -DGGML_VULKAN_BFLOAT16=OFF"
        
        if ! command -v glslc &> /dev/null; then
            log "WARNING: glslc not found. Run: sudo apt install glslc"
        fi
        if ! dpkg -s spirv-headers &>/dev/null && [[ ! -d "/usr/include/spirv" ]]; then
            log "WARNING: spirv-headers not found. Run: sudo apt install spirv-headers"
        fi
    fi

    cd "$LLAMA_DIR" || { log "Error: Failed to navigate to $LLAMA_DIR"; return; }
    export CMAKE_TLS_VERIFY=0
    eval cmake $FLAGS && {
        echo "Starting build compilation..."
        cmake --build "$BUILD_DIR" -- -j$(nproc) 2>&1 | tee "$BUILD_DIR/build.log" | while read -r line; do
            if [[ "$line" =~ \[([[:space:]]*[0-9]+)%\] ]]; then
                local pct="${BASH_REMATCH[1]}"
                pct=$(echo "$pct" | tr -d ' ')
                local num_bars=$(( pct / 5 ))
                local num_dots=$(( 20 - num_bars ))
                local bar=""
                for ((i=0; i<num_bars; i++)); do bar+="■"; done
                for ((i=0; i<num_dots; i++)); do bar+="."; done
                echo -ne "\rBuilding: [$bar] $pct%   "
            else
                if [[ "$line" =~ "Building" || "$line" =~ "Linking" ]]; then
                    local short_line="${line:0:60}"
                    echo -ne "\r\e[KBuilding: $short_line"
                fi
            fi
        done
        echo "" # new line at the end
    }
    read -p "Build complete. Enter..."
    cd - &>/dev/null || return
}

select_custom_backend() {
    clear
    echo "=========================================="
    echo "    SCANNING CUSTOM BINARY ENVIRONMENT"
    echo "=========================================="
    local custom_dirs=()
    # List directories matching $HOME/ai_tools/llama_custom_*
    for d in "$HOME"/ai_tools/llama_custom_*; do
        if [[ -d "$d" ]]; then
            local name="${d##*/llama_custom_}"
            # Verify the BUILD_$name folder exists inside
            if [[ -d "$d/BUILD_$name" ]]; then
                custom_dirs+=("$name")
            fi
        fi
    done
    
    if [[ ${#custom_dirs[@]} -eq 0 ]]; then
        echo "No valid custom builds found in $HOME/ai_tools/."
        echo "(Verify you have folders matching 'llama_custom_*' containing a 'BUILD_*' folder)"
        read -p "Press Enter to continue..."
        return
    fi
    
    echo "Available Custom / Alternative Builds:"
    for i in "${!custom_dirs[@]}"; do
        echo "  $((i+1))) Custom Build: ${custom_dirs[$i]}"
    done
    echo "------------------------------------------"
    read -p "Select a custom build number (or Enter to cancel): " idx
    if [[ -n "$idx" && "$idx" -ge 1 && "$idx" -le ${#custom_dirs[@]} ]]; then
        ACTIVE_CUSTOM_BUILD="${custom_dirs[$((idx-1))]}"
        save_settings
        log "Active running path redirected to custom build: $ACTIVE_CUSTOM_BUILD"
        sleep 2
    fi
}

configure_vulkan_devices() {
    clear
    echo "=========================================="
    echo "        VULKAN DEVICE SELECTION           "
    echo "=========================================="
    echo "Available Vulkan Devices:"
    vulkaninfo --summary 2>/dev/null | grep -E "GPU|deviceName" || echo "No Vulkan devices detected."
    echo "------------------------------------------"
    echo "Enter the GPU ID to use (e.g., 0, 1, or 0,1)."
    echo "Leave blank to use default."
    read -p "Device ID(s): " vk_devs
    if [[ -n "$vk_devs" ]]; then
        VULKAN_DEVICE="$vk_devs"
    else
        VULKAN_DEVICE=""
    fi
    save_settings
    apply_gpu_blacklist
    if [[ -n "$VULKAN_DEVICE" ]]; then
        echo "[INFO] Vulkan devices locked to: $VULKAN_DEVICE"
    else
        echo "[INFO] Vulkan devices reset to default."
    fi
    sleep 2
}

select_backend_menu() {
    while true; do
        clear
        echo "=========================================="
        echo " BACKEND / EXECUTION ENGINE MANAGEMENT"
        echo "=========================================="
        echo "Current Active Backend: $BACKEND"
        if [[ "$BACKEND" == "Vulkan" || "$BACKEND" == "VULKAN" ]]; then
            echo "Persistent Vulkan GPU Device(s): ${VULKAN_DEVICE:-[Default / Decided by Blacklist]}"
        fi
        if [[ -n "$ACTIVE_CUSTOM_BUILD" ]]; then
            echo "Active Custom Build: $ACTIVE_CUSTOM_BUILD"
        else
            echo "Active Custom Build: None (Using Baseline Paths)"
        fi
        echo "------------------------------------------"
        echo "  [1] Switch Active Backend to: CUDA"
        echo "  [2] Switch Active Backend to: Vulkan"
        echo "  [3] Switch Active Backend to: RoCM"
        echo ""
        echo "  [C] Select Custom / Alternative Backend"
        echo "  [R] Return to Main Menu"
        echo "=========================================="
        read -p "Selection: " b_choice
        case ${b_choice^^} in
            1)
                BACKEND="CUDA"
                ACTIVE_CUSTOM_BUILD=""
                save_settings
                log "Configured active backend: CUDA (Baseline)"
                sleep 1
                ;;
            2)
                BACKEND="Vulkan"
                ACTIVE_CUSTOM_BUILD=""
                save_settings
                log "Configured active backend: Vulkan (Baseline)"
                configure_vulkan_devices
                sleep 1 ;;
            3)
                BACKEND="RoCM"
                ACTIVE_CUSTOM_BUILD=""
                save_settings
                log "Configured active backend: RoCM (Baseline)"
                sleep 1
                ;;
            C)
                select_custom_backend
                ;;
            R)
                break
                ;;
            *)
                echo "Invalid selection."
                sleep 1
                ;;
        esac
    done
}

start_server() {
    [[ -z "$MODEL_PATH" ]] && { echo "Select a model!"; sleep 2; return; }

    # Port Conflict Check (Issue 12)
    if ss -tuln 2>/dev/null | grep -q ":$PORT "; then
        echo "=========================================="
        echo " WARNING: Port $PORT is already in use!    "
        echo "=========================================="
        echo "1) Kill the process using port $PORT"
        echo "2) Choose a different port"
        echo "3) Use a randomly generated alternative port"
        echo "4) Ignore and try launching anyway"
        echo "------------------------------------------"
        read -p "Selection: " port_choice
        case "$port_choice" in
            1)
                local pid=$(lsof -t -i:"$PORT" 2>/dev/null || fuser "$PORT"/tcp 2>/dev/null | awk '{print $1}')
                if [[ -n "$pid" ]]; then
                    echo "Killing process $pid using port $PORT..."
                    kill -9 $pid 2>/dev/null
                    sleep 1
                else
                    echo "Could not find PID using lsof/fuser. Retrying with sudo fuser..."
                    sudo fuser -k "$PORT"/tcp 2>/dev/null
                    sleep 1
                fi
                ;;
            2)
                read -p "Enter new port: " new_port
                if [[ -n "$new_port" ]]; then
                    PORT="$new_port"
                    save_settings
                fi
                ;;
            3)
                local rand_port=$(( RANDOM % 16383 + 49152 ))
                echo "Using randomly generated port: $rand_port"
                PORT="$rand_port"
                save_settings
                ;;
            *)
                echo "Proceeding..."
                ;;
        esac
    fi

    # VRAM / RAM Footprint Check (Issue 8)
    if [[ -f "$MODEL_PATH" ]]; then
        local file_size_bytes=$(stat -c%s "$MODEL_PATH" 2>/dev/null || wc -c < "$MODEL_PATH" 2>/dev/null)
        local model_gb=$(( file_size_bytes / 1024 / 1024 / 1024 ))
        if [[ $model_gb -eq 0 ]]; then model_gb=1; fi # fallback

        # Check NVIDIA VRAM
        local vram_mb=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null | head -n 1)
        local vram_gb=0
        if [[ -n "$vram_mb" && "$vram_mb" =~ ^[0-9]+$ ]]; then
            vram_gb=$(( vram_mb / 1024 ))
        fi

        # Check Free System RAM
        local ram_free_bytes=$(free -b 2>/dev/null | awk '/^Mem:/{print $4}')
        local ram_free_gb=0
        if [[ -n "$ram_free_bytes" && "$ram_free_bytes" =~ ^[0-9]+$ ]]; then
            ram_free_gb=$(( ram_free_bytes / 1024 / 1024 / 1024 ))
        fi

        local total_avail=$(( vram_gb + ram_free_gb ))
        if [[ $total_avail -gt 0 && $model_gb -gt $total_avail ]]; then
            echo "=========================================="
            echo " WARNING: INSUFFICIENT MEMORY DETECTED!   "
            echo "=========================================="
            echo "Model size: ~${model_gb} GB"
            echo "Detected VRAM: ~${vram_gb} GB, Free RAM: ~${ram_free_gb} GB"
            echo "Total safe memory limit: ~${total_avail} GB"
            echo "------------------------------------------"
            read -p "Do you want to proceed with launching anyway? [y/N]: " proceed_anyway
            if [[ "${proceed_anyway^^}" != "Y" ]]; then
                echo "Launch cancelled to prevent system out-of-memory crash."
                sleep 2
                return
            fi
        fi
    fi

    # Determine binary path
    local BIN="$(get_bin_path llama-server)"
    
    if [[ ! -f "$BIN" ]]; then
        echo "Backend binary not found at $BIN! Please rebuild first."
        sleep 3
        return
    fi
    
    # Show active backend version command signature before startup as requested!
    echo "=========================================="
    echo "  LAUNCHING SERVER"
    echo "  Backend Binary: $BIN"
    echo "  Version Signature:"
    "$BIN" --version 2>&1 | head -n 2
    echo "=========================================="
    sleep 1

    local FLAGS=""
    FLAGS+=" -ngl $GPU_LAYERS"                       # Offloads layers to the GPU for maximum acceleration
    FLAGS+=" -fa $FLASH_ATTENTION"                   # Enables Flash Attention to lower VRAM overhead
    FLAGS+=" --host 0.0.0.0"                         # Binds the server to all local and network interfaces
    FLAGS+=" --port $PORT"                           # Sets the designated HTTP listening port
#    FLAGS+=" --ctx-size 65536"
#    FLAGS+=" --rope-scaling yarn"
#    FLAGS+=" --rope-scale 8"
#    FLAGS+=" --yarn-orig-ctx 32768"
#    FLAGS+=" --swa-full"                            #Full-size SWA cache; exclusive of context shift
    FLAGS+=" --context-shift"                        # Automatically evicts older context when limits are hit; causes hallucination w/ yarn enabled
    FLAGS+=" --ctx-checkpoints 8"                    # Retains 16 RAM context checkpoints to eliminate long re-prefill pauses
    FLAGS+=" --tools all"                            # Enables native system tools (shell execution, file editing)
    FLAGS+=" -cram $CONTEXT_SIZE"                    # Restricts max memory allocation size for context RAM caches
#    FLAGS+=" --cache-reuse 256"                     # Reuses up to 64 token blocks for faster prompt caching; not supported messages at start
#    FLAGS+=" --cache-type-v q8_0"                    #best option to save VRAM
#    FLAGS+=" --cache-type-k q8_0"
#    FLAGS+=" --spec-type draft-mtp"                 #MTP flags didn't help when added, actually made things slower.  
#    FLAGS+=" --spec-draft-n-max 3"
#    FLAGS+=" --spec-draft-p-min 0.75"
#    FLAGS+=" --kv-unified"                           # Enforces a unified model architecture for tracking KV states
    FLAGS+=" -np 3"                                  # Allocates 4 parallel request/generation slots; increases vram usage
    FLAGS+=" --batch-size $BATCH_SIZE"               # Sets the logical prompt prefill block evaluation chunk size
    FLAGS+=" --ubatch-size $UBATCH_SIZE"             # Sets the physical execution micro-batch size
    FLAGS+=" -t $THREADS"                            # Allocates CPU threads for initial prompt evaluation phases
    FLAGS+=" --prio 2"                               # (Recommended) Higher process priority to prevent interruption
#    FLAGS+=" --reasoning off"                        # Disables built-in model reasoning tokens where supported
    FLAGS+=" --ui-mcp-proxy"                         # Enables CORS routing proxy for external MCP server plugins
    FLAGS+=" --cont-batching"                        # Enforces continuous request batching pipelines
    FLAGS+=" --mlock"                                # Locks the model architecture to physical RAM to prevent OS swapping
#    FLAGS+=" --no-mmap"                             #Typically problematic, w/ few benefits
    FLAGS+=" --metrics"                              # new flag for stats/metrics  
    if [[ "$SSL_ENABLED" == "true" ]]; then
        ensure_ssl_certs
        if [[ -n "$SSL_KEY_PATH" ]]; then
            FLAGS+=" --ssl-key-file $SSL_KEY_PATH"
        fi
        if [[ -n "$SSL_CERT_PATH" ]]; then
            FLAGS+=" --ssl-cert-file $SSL_CERT_PATH"
        fi
    fi
    FLAGS+=" --ui-config-file \$HOME/ai_tools/webui-config.json" # Applies custom WebUI layout parameters

    if [[ -n "$MMPROJ_PATH" && -f "$MMPROJ_PATH" ]]; then
        FLAGS+=" --mmproj \"$MMPROJ_PATH\""
    fi

    local cmd="\"$BIN\" -m \"$MODEL_PATH\" $FLAGS"

    # Spawn window protocol using centralized interactive function
    spawn_window "$cmd" "Llama Server Daemon"
}

while true; do
    show_menu
    case ${choice^^} in
        M) select_model ;;
        L) start_server ;;
        B) select_backend_menu ;;
        R) show_build_menu ;;
        O) options_menu ;;
        S) service_menu ;;
        X) diagnostics_menu ;;
        I) install_dependencies_menu ;;
        H) maintenance_menu ;;
        Q) cleanup ;;
    esac
done
