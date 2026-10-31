```
# 🦙 llama.cpp AI Manager Script

An interactive, distribution-agnostic Bash control center for compiling, managing, and running **`llama.cpp`** on Linux (**MX Linux**, **Debian**, **Ubuntu**) and **Windows (WSL 2)**. 

This utility simplifies multi-backend hardware compilation, system daemon management across both **`sysvinit`** and **`systemd`**, hardware telemetry, and advanced perplexity benchmarking through an intuitive terminal interface.

---

## 🌟 Key Features

* **Multi-Backend Build Engine**: Compile and switch dynamically between **CUDA** (NVIDIA), **Vulkan**, and **ROCm** (AMD RDNA2/RDNA3) backends without manual Makefile edits.
* **Smart Dependency &amp; ROCm Support**: Handles driver toolkits and dependencies smoothly, including automated ROCm installation routines with specialized flags (`--no-dkms`) tailored for non-standard distributions like MX Linux.
* **Dual Init Daemon Support**: One-click background service generation supporting both traditional **`sysvinit`** (`/etc/init.d/`) and modern **`systemd`** (`/etc/systemd/system/`) service architectures.
* **Cross-Sectional Perplexity Engine**: Advanced perplexity evaluation featuring cross-sectional text sampling. Extracts balanced text blocks across test datasets (e.g., `big.txt`) for instant score convergence without context crashes or excessive runtimes.
* **Hardware &amp; Telemetry Inspection**: Integrated GPU detection and telemetry tools for `nvidia-smi`, `vulkaninfo`, and `rocminfo` to monitor compute nodes.
* **WSL 2 &amp; POSIX Compatibility**: Full support for running inside Windows Subsystem for Linux (WSL 2) with automated POSIX path resolution and environment detection.
* **Safe Maintenance &amp; Directory Management**: Includes non-destructive reset options that back up custom configurations and move deleted files safely to a managed trash directory (`~/.ai_manager/trash/`).

---

## 🚀 Quick Start

### 1. Prerequisites
Ensure baseline build tools are installed on your Linux system or WSL 2 environment:

```bash
# Debian / MX Linux / Ubuntu / WSL 2
sudo apt update &amp;&amp; sudo apt install -y git cmake ninja-build ccache build-essential glslc

```

### 2\. Execution

Clone or copy the script to your machine, make it executable, and run:

```
chmod +x ai_manager.sh
./ai_manager.sh

```

---

## 🖥️ Interactive Interface Overview

```
==================================================
        LLAMA.CPP AI MANAGER CONTROL CENTER
==================================================
ACTIVE MODEL:  [Selected .gguf Model]
BACKEND/BUILD: Standard (CUDA / Vulkan / ROCm)
SERVICE INIT:  sysvinit / systemd
--------------------------------------------------
  [M] Select Model
  [L] Launch Server (Foreground / Service)
  [B] Select Backend (CUDA / Vulkan / ROCm)
  [R] Build / Rebuild Options (Ninja + ccache)
  [S] Service Management (sysvinit &amp; systemd)
  [X] Diagnostics &amp; Performance (Perplexity / Bench)
  [I] Install Dependencies &amp; ROCm Toolkits
  [H] Reset &amp; Maintenance (Trash &amp; Cache Clearance)
  [Q] Quit
==================================================

```

---

## 🔧 Core Workflows

### **1\. Backend Selection &amp; Compilation (** **[B]** **&amp;** **[R]** **)**

* Easily toggle your active target backend between **Vulkan**, **ROCm**, or **CUDA**.
* Leverages `ninja` and `ccache` for ultra-fast incremental re-compiles when updating your `llama.cpp` codebase.
* Features clean rebuild options to reset build directories (`build_CUDA`, `build_VULKAN`, `build_ROCM`) whenever upstream dependencies change.

### **2\. Service Management (** **[S]** **)**

* Generates distribution-compliant init scripts for **MX Linux (** **sysvinit** **)** or service unit files for **Ubuntu/Debian (** **systemd** **)**.
* Automatically creates environment defaults in `/etc/default/llama-server` to manage port assignments, layer offloading (`-ngl`), and context sizes.

### **3\. Performance &amp; Perplexity Benchmarking (** **[X]** **)**

* **Cross-Sectional Sampling**: Bypasses the slow convergence of standard sequential perplexity runs by sampling cohesive text blocks across the corpus, giving you an accurate evaluation score in a fraction of the time.
* **Telemetry Diagnostics**: Instant checks for device visibility (`rocminfo`, `vulkaninfo`, `nvidia-smi`).

---

## 📂 System Directory Structure

The script manages configuration state and transient logs under your user home directory:

* `~/.ai_manager/settings.conf` — Active model paths, backend selections, and environment parameters.
* `~/.ai_manager/logs/` — Benchmarking metrics and perplexity run logs.
* `~/.ai_manager/trash/` — Safe destination for purged temporary test files and old configurations.

---

## 📜 License

Distributed under the Open Source **MIT License**.

```

***

💡 Would you like to add a dedicated section outlining step-by-step instructions for setting up 
```
