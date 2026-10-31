import { useState, useEffect, useRef } from "react";
import { 
  Server, 
  Cpu, 
  Activity, 
  Terminal as TerminalIcon, 
  Settings, 
  Play, 
  Square, 
  RefreshCcw, 
  Database,
  Shield,
  Zap,
  HardDrive,
  GitPullRequest,
  Info,
  Sliders,
  AlertTriangle,
  CheckCircle,
  TrendingUp,
  Download,
  Lock,
  Unlock
} from "lucide-react";
import { motion } from "motion/react";
import { SERVER_FLAGS, BACKENDS, Backend, MODELS } from "./constants";

interface LogEntry {
  timestamp: string;
  message: string;
  type: "info" | "error" | "success" | "command";
}

export default function App() {
  const [activeTab, setActiveTab] = useState<"main" | "options" | "updates" | "maintenance">("main");
  const [advancedMode, setAdvancedMode] = useState<boolean>(() => {
    const saved = localStorage.getItem("advanced_mode");
    return saved === "true";
  });
  const [sslEnabled, setSslEnabled] = useState(false);
  const [sslPort, setSslPort] = useState("8888");
  const [sslCertPath, setSslCertPath] = useState("");
  const [sslKeyPath, setSslKeyPath] = useState("");

  const [backend, setBackend] = useState<Backend>(() => {
    const saved = localStorage.getItem("selected_backend");
    return (saved as Backend) || "CUDA";
  });
  const [selectedVulkanGpus, setSelectedVulkanGpus] = useState<string[]>(() => {
    const saved = localStorage.getItem("vulkan_selected_gpus");
    try {
      return saved ? JSON.parse(saved) : ["NVIDIA GeForce RTX 3060"];
    } catch {
      return ["NVIDIA GeForce RTX 3060"];
    }
  });

  const [activeModel, setActiveModel] = useState<string | null>(null);
  const [isServerRunning, setIsServerRunning] = useState(false);
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [uptime, setUptime] = useState(0);
  const [vramUsage, setVramUsage] = useState({ gpu0: 10, gpu1: 5 });
  const [llamaVersion, setLlamaVersion] = useState("llama-server version 1.2.4-git-0a1b2c3d");
  const [buildProfile, setBuildProfile] = useState<"low" | "medium" | "high">("low");
  const [modelsDir, setModelsDir] = useState<string>("/home/user/Downloads");
  const [dependencies, setDependencies] = useState<Record<string, boolean>>({
    cmake: true,
    ninja: true,
    ccache: true,
    glslc: true,
    glslangValidator: true,
    "spirv-headers": true,
    nvcc: false, // Simulated hardware dependency
    rocminfo: false, // Simulated hardware dependency
  });
  const logEndRef = useRef<HTMLDivElement>(null);

  // Automatically persist backend changes
  useEffect(() => {
    localStorage.setItem("selected_backend", backend);
  }, [backend]);

  // Automatically persist selected Vulkan GPUs changes
  useEffect(() => {
    localStorage.setItem("vulkan_selected_gpus", JSON.stringify(selectedVulkanGpus));
  }, [selectedVulkanGpus]);

  // Fetch real-time status from backend to ensure alignment
  useEffect(() => {
    const fetchStatus = async () => {
      try {
        const response = await fetch("/api/status");
        if (response.ok) {
          const data = await response.json();
          if (data.success) {
            if (data.backend && data.backend !== backend) {
              setBackend(data.backend);
            }
            if (data.profile && data.profile !== buildProfile) {
              setBuildProfile(data.profile as "low" | "medium" | "high");
            }
            if (data.ssl && (data.ssl === "true") !== sslEnabled) {
              setSslEnabled(data.ssl === "true");
            }
            if (data.port && data.port !== sslPort) {
              setSslPort(data.port);
            }
            if (data.model && data.model !== "None" && data.model !== activeModel) {
              setActiveModel(data.model);
            }
          }
        }
      } catch (err) {
        console.warn("Could not reach backend API for real-time status. Operating in standalone mode.", err);
      }
    };

    fetchStatus();
    const interval = setInterval(fetchStatus, 5000);
    return () => clearInterval(interval);
  }, [backend, buildProfile, sslEnabled, sslPort, activeModel]);

  const missingCoreDeps = Object.entries(dependencies)
    .filter(([name, present]) => ["cmake", "ninja", "ccache"].includes(name) && !present)
    .map(([name]) => name);

  const addLog = (message: string, type: LogEntry["type"] = "info") => {
    setLogs(prev => [...prev, {
      timestamp: new Date().toLocaleTimeString(),
      message,
      type
    }].slice(-50));
  };

  useEffect(() => {
    addLog("System initialized. Welcome to AI Node Manager v0.9.4.0", "success");
    addLog("Hardware configuration: Ivy Bridge CPU (No AVX2) | Dual NVIDIA RTX GPUs", "info");
    addLog("Loaded optimizations: Git-Pull trigger and llama-server --version auto-query", "info");
    addLog("Startup Verification: Loaded core dependency tracker.", "success");
    if (missingCoreDeps.length > 0) {
      addLog(`CRITICAL: These base dependencies were missing: ${missingCoreDeps.join(", ")}`, "error");
      addLog("Choose menu option [I] to install dependencies", "info");
    }
  }, []);

  useEffect(() => {
    logEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [logs]);

  useEffect(() => {
    let interval: NodeJS.Timeout;
    if (isServerRunning) {
      interval = setInterval(() => {
        setUptime(prev => prev + 1);
        setVramUsage({
          gpu0: 72 + Math.random() * 3,
          gpu1: 88 + Math.random() * 2
        });
      }, 1000);
    } else {
      setUptime(0);
      setVramUsage({ gpu0: 12, gpu1: 6 });
    }
    return () => clearInterval(interval);
  }, [isServerRunning]);

  const handleAction = async (action: string) => {
    addLog(`Executing: ${action}`, "command");
    
    try {
      const response = await fetch("/api/action", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action })
      });
      const data = await response.json();
      
      if (data.success) {
        if (action === "start") {
          if (!activeModel) {
            addLog("Error: Please select a model first", "error");
            return;
          }
          setIsServerRunning(true);
          addLog("Checking active backend version...", "info");
          addLog(`Version command: llama-server --version`, "command");
          addLog(`Binary stdout: ${llamaVersion}`, "success");
          const actualPort = sslEnabled ? (sslPort === "8888" ? "443" : sslPort) : (sslPort === "443" ? "8888" : sslPort);
          addLog(`Starting llama-server with SSL=${sslEnabled ? 'ON' : 'OFF'} on port ${actualPort}...`, "info");
          let sslArgs = "";
          if (sslEnabled) {
            sslArgs = ` --ssl-key-file "${sslKeyPath || '[Auto-Generated Default]'}" --ssl-cert-file "${sslCertPath || '[Auto-Generated Default]'}"`;
          }
          if (backend === "Vulkan") {
            addLog(`Auto-loading pre-selected Vulkan GPUs: ${selectedVulkanGpus.join(", ") || "None"}`, "info");
            addLog(`Vulkan physical devices initiated automatically without user prompt.`, "success");
          }
          addLog(`Restored server flags: -ngl 99 -fa on --ctx-size 42768 --context-shift --ctx-checkpoints 8 --port ${actualPort}${sslArgs} --batch-size 2048 --ubatch-size 2048 --cram 2048 --cache-reuse 128 -np 2 --reasoning off --ui-mcp-proxy --ui-config-file ...`, "success");
        } else if (action === "toggle_ssl") {
          const nextSsl = !sslEnabled;
          setSslEnabled(nextSsl);
          const nextPort = nextSsl ? "443" : "8888";
          setSslPort(nextPort);
          addLog(`SSL configuration toggled in React -> ${nextSsl ? "ON (HTTPS)" : "OFF (HTTP)"}`, "success");
          addLog(`Default launch port reassigned: ${nextPort}`, "info");
          addLog(`Persisted Settings: SSL_ENABLED=${nextSsl}, PORT=${nextPort}`, "info");
        } else if (action === "save_ssl_settings") {
          addLog(`Saving options custom configuration to settings.conf...`, "info");
          addLog(`Configured details: PORT=${sslPort}, CERT="${sslCertPath || '[Auto-Generated]'}", KEY="${sslKeyPath || '[Auto-Generated]'}"`, "success");
          addLog("Reloaded Settings database environment cleanly.", "success");
        } else if (action === "stop") {
          setIsServerRunning(false);
          addLog("Server shutdown requested.", "info");
          addLog("Server stopped completely.", "success");
        } else if (action === "toggle_profile") {
          let next: "low" | "medium" | "high" = "low";
          if (buildProfile === "low") next = "medium";
          else if (buildProfile === "medium") next = "high";
          setBuildProfile(next);
          addLog(`hardware build profile toggled -> ${next.toUpperCase()}`, "success");
          addLog(`Persisted to Settings: BUILD_PROFILE=${next}`, "info");
          if (next === "high") {
            addLog("Compiler Vectorization settings (AVX-512): AVX=ON, AVX2=ON, AVX512=ON, FMA=ON, F16C=ON, BMI2=ON, NATIVE=ON, -march=native", "info");
          } else if (next === "medium") {
            addLog("Compiler Vectorization settings (AVX2): AVX=ON, AVX2=ON, AVX512=OFF, FMA=ON, F16C=ON, BMI2=ON, NATIVE=ON, -march=native", "info");
          } else {
            addLog("Compiler Vectorization settings (AVX-OFF): AVX=OFF, AVX2=OFF, AVX512=OFF, FMA=OFF, F16C=OFF, BMI2=OFF, NATIVE=OFF", "info");
          }
        } else if (action === "perplexity_check") {
          if (!activeModel) {
            addLog("Error: Select a GGUF model path first", "error");
            return;
          }
          addLog("Checking if sample text corpus exists: ~/.ai_manager/perplexity_test.txt", "info");
          addLog("Generating sample evaluation text corpus at ~/.ai_manager/perplexity_test.txt ...", "success");
          addLog(`Starting llama-perplexity engine validation against: ${activeModel}`, "info");
          addLog(`Command: llama-perplexity -m ${activeModel} -f ~/.ai_manager/perplexity_test.txt -ngl 99 -fa on`, "command");
          setTimeout(() => {
            addLog("Evaluating perplexity logits using Dual GPU hardware offloading...", "info");
            addLog(`Result: Perplexity evaluation completed with steady scale: 5.642 (STABLE)`, "success");
          }, 850);
        } else if (action === "vram_monitor") {
          addLog("Executing action: watch -n 1 nvidia-smi", "command");
          addLog("GPU 0 Allocation: 10.4 GB / 12.0 GB (RTX 3060 Active Mode)", "success");
          addLog("GPU 1 Allocation: 9.6 GB / 12.0 GB (RTX 3060/RX 9060 Active Mode)", "success");
          addLog("Stable memory pool. No memory leakages detected.", "info");
        } else if (action === "vulkan_check") {
          addLog("Querying Vulkan summary: vulkaninfo --summary | grep -E 'GPU|deviceName|deviceType'", "command");
          addLog("Devices: [0] NVIDIA GeForce RTX 3060 (Discrete GPU) | [1] AMD Radeon RX 9060 (Discrete GPU)", "success");
          addLog("Vulkan instance version 1.3.204 verified successfully.", "info");
          addLog(`Active persistent Vulkan GPU selections: [${selectedVulkanGpus.join(", ") || "None"}] will be targeted for next run.`, "success");
        } else if (action === "diagnostic_run") {
          if (!activeModel) {
            addLog("Error: Select a GGUF model path first for stability check", "error");
            return;
          }
          addLog("Spawning separate window Diagnostic Test Run...", "info");
          addLog(`Command: timeout 12 bin/llama-server -m ${activeModel} -ngl 99 --port 9091 --no-mmap > diagnostics.log`, "command");
          addLog("Logging operational stability outputs straight to ~/.ai_manager/diagnostics.log", "success");
          setTimeout(() => {
            addLog("=== Real-time Operational Stability Check Log ===", "success");
            addLog("[INFO] llama-server initialized successfully. Ready state achieved.", "success");
            addLog("[INFO] No segmentation faults or compilation warnings caught.", "success");
            addLog("Diagnostics successfully completed. Window closed out.", "success");
          }, 1200);
        } else if (action.startsWith("service_")) {
          const type = action.replace("service_", "");
          if (type === "status") {
            addLog("Querying systemd service status: systemctl status llama-server", "command");
            addLog("Status: ACTIVE (running) • PID: 14088 (Double-GPU Server Mode)", "success");
          } else if (type === "restart") {
            addLog("Executing action: sudo systemctl restart llama-server", "command");
            addLog("Service daemon restarted successfully.", "success");
          } else if (type === "update") {
            addLog("Synchronizing config flags to service properties...", "info");
            addLog("Writing settings to /etc/default/llama-server using LLAMA_ARG_ environment variables...", "command");
            addLog(`Configured prefix tags: LLAMA_ARG_MODEL="${activeModel || ''}" LLAMA_ARG_PORT="8888"`, "success");
            addLog("Daemon-reload successfully processed.", "success");
          } else if (type === "install") {
            addLog("Prompting architecture init configurations... selected systemd", "info");
            addLog("Deploying service configuration files to /etc/systemd/system/llama-server.service", "command");
            addLog("Registered simple service lifecycle handles.", "success");
          } else if (type === "remove") {
            addLog("Executing: sudo systemctl stop & disable and purge service files", "command");
            addLog("Service removed comfortably. Environment cleaned up.", "success");
          }
        } else if (action === "benchmark") {
          addLog("Initializing LLAMA-BENCHMARK Performance Engine...", "info");
          if (activeModel) {
            addLog(`Benchmarking active model: ${activeModel}`, "info");
            addLog(`Command: llama-bench -m ${activeModel}`, "command");
            setTimeout(() => {
              addLog("==========================================", "success");
              addLog(`Model: ${activeModel.replace(".gguf", "")}`, "success");
              addLog("Metrics: 512 context, batch 512, single prompt evaluation", "info");
              addLog("Performance: Prompt eval 52.8 t/s | generation 11.2 text/s", "success");
              addLog("VRAM footprint: 10.4 GB allocated across dual GPUS", "info");
              addLog("==========================================", "success");
            }, 800);
          } else {
            addLog("No active GGUF model targeted. Running baseline performance matrix...", "info");
            addLog("Command: llama-bench", "command");
            setTimeout(() => {
              addLog("==========================================", "success");
              addLog("Target: Hardware Matrix Performance (Llama-3-8B Equiv)", "success");
              addLog("F16 evaluation: 145.2 t/s", "info");
              addLog("Q8_0 evaluation: 168.4 t/s", "success");
              addLog("Q4_K_M evaluation: 285.3 t/s (Dual RTX optimized)", "success");
              addLog("==========================================", "success");
            }, 800);
          }
        } else if (action === "install_deps_nvidia") {
          addLog("Executing: sudo apt update && sudo apt install -y git cmake ninja-build ccache build-essential nodejs npm glslc spirv-headers nvidia-cuda-toolkit", "command");
          addLog("Preparing safe installation for Nvidia toolkit & SPIR-V headers...", "info");
          setTimeout(() => {
            setDependencies(prev => ({ ...prev, nvcc: true, "spirv-headers": true }));
            addLog("Nvidia Dependency installed and configured: nvcc -> INSTALLED", "success");
            addLog("All CUDA & Vulkan pipelines configured properly.", "success");
          }, 1200);
        } else if (action === "install_deps_amd") {
          addLog("Executing: sudo apt update && sudo apt install -y git cmake ninja-build ccache build-essential nodejs npm glslc spirv-headers", "command");
          addLog("WARNING: Do NOT install ROCm or ROCm tools via native apt repositories (e.g., libamdhip64-dev), as it causes header conflicts.", "error");
          addLog("Switching to official AMD installer package for tools & ROCm instead of native system repositories:", "info");
          addLog("sudo amdgpu-install --usecase=rocm,rocmdevtools --no-dkms", "command");
          addLog("Adding user video and render group permissions: sudo usermod -aG video,render $USER", "command");
          addLog("Preparing safe installation for AMD RoCM and official tools...", "info");
          setTimeout(() => {
            setDependencies(prev => ({ ...prev, rocminfo: true, "spirv-headers": true }));
            addLog("AMD Dependency installed and configured: rocminfo -> INSTALLED (official AMD package)", "success");
            addLog("All RoCM & Vulkan pipelines configured properly.", "success");
          }, 1200);
        } else if (action === "config_reset") {
          addLog("Triggering System configuration reset...", "info");
          addLog("Checking if preexisting backups exist at /settings.conf.old ...", "info");
          addLog("Safely backed up existing settings to /settings.conf.old1", "success");
          addLog("Recreated settings database with standard default variables.", "success");
          addLog("Preferences restored successfully. Closing script context.", "success");
          setTimeout(() => {
            setIsServerRunning(false);
            setActiveModel(null);
            setBuildProfile("low");
            addLog("AI Node Manager reverted back to low out-of-the-box profile.", "info");
          }, 800);
        } else if (action === "cache_reset") {
          addLog("Spawning CMake clean sub-routine...", "info");
          addLog("Moving build folders build, build_VULKAN, and build_ROCM to trash directory ~/.ai_manager/trash/", "command");
          addLog("Success: Cache databases and compiled objects completely purged. Primary directory remains intact.", "success");
          addLog("Tip: Total repository replacement is possible anytime manually.", "info");
        } else if (action.startsWith("build")) {
          addLog(`Initializing git repository check for llama.cpp...`, "info");
          addLog("Directory exists: true. Run: git pull", "command");
          addLog("Fetch stream: Pulling latest commits from ggml-org/llama.cpp", "success");
          addLog("Optimization applied: export CCACHE_SLOPPINESS=include_file_mtime,time_macros", "success");
          addLog(`Configuring CMake args (Ninja + ccache + No-AVX + Compiler cache launcher + UI warning fixes)...`, "info");
          if (action.includes("rocm")) {
            addLog("Injected flags: -DGGML_HIPBLAS=ON -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache", "success");
          } else if (action.includes("vulkan")) {
            addLog("Injected flags: -DGGML_VULKAN=ON -DGGML_VULKAN_BFLOAT16=OFF -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache", "success");
          } else {
            addLog("Injected flags: -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=86 -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache", "success");
          }
          addLog(`Build switches: -DGGML_AVX=${buildProfile !== "low" ? "ON" : "OFF"} -DGGML_AVX2=${buildProfile !== "low" ? "ON" : "OFF"} -DGGML_AVX512=${buildProfile === "high" ? "ON" : "OFF"} -DGGML_NATIVE=${buildProfile !== "low" ? "ON" : "OFF"}`, "info");
          if (buildProfile !== "low") {
            addLog("Injected native optimizations: -DCMAKE_C_FLAGS=-march=native -DCMAKE_CXX_FLAGS=-march=native", "success");
          }
          setTimeout(() => addLog(`${action.toUpperCase()} compilation complete via fast incremental pipeline! Compiled binary ready.`, "success"), 1800);
        }
      }
    } catch (error) {
      addLog(`Action failed: ${error}`, "error");
    }
  };

  return (
    <div className="min-h-screen bg-[#070709] text-slate-300 font-mono p-4 md:p-8 selection:bg-emerald-500/30">
      <div className="max-w-7xl mx-auto space-y-6">
        
        {/* Header */}
        <header className="flex flex-col md:flex-row justify-between items-start md:items-center gap-4 bg-slate-950/60 p-6 rounded-2xl border border-slate-900 backdrop-blur-md">
          <div className="flex items-center gap-4">
            <div className="p-3 bg-emerald-500/10 rounded-xl border border-emerald-500/20">
              <Server className="w-8 h-8 text-emerald-400 animate-pulse" />
            </div>
            <div>
              <h1 className="text-2xl font-bold text-white tracking-tight">AI NODE MANAGER <span className="text-emerald-500 text-sm font-mono ml-2">v0.9.4.0</span></h1>
              <p className="text-sm text-slate-500 flex items-center gap-2">
                <Activity className="w-3 h-3 text-emerald-500" /> Ivy Bridge Dual-GPU Platform • Xeon-Ready Optimized
              </p>
            </div>
          </div>
          <div className="flex flex-wrap items-center gap-3">
            <label id="toggle-advanced-mode" className={`flex items-center gap-2 cursor-pointer px-4 py-2 rounded-xl border transition-all select-none ${advancedMode ? 'bg-emerald-500/10 border-emerald-500/30 text-emerald-400' : 'bg-slate-900/60 border-slate-800 hover:border-slate-700 text-slate-400 hover:text-slate-200'}`}>
              <input 
                id="checkbox-advanced-mode"
                type="checkbox" 
                checked={advancedMode} 
                onChange={(e) => {
                  const val = e.target.checked;
                  setAdvancedMode(val);
                  localStorage.setItem("advanced_mode", String(val));
                  if (!val) {
                    setActiveTab("main");
                  }
                  addLog(val ? "Advanced Mode Enabled. Advanced tabs (Options, Compiler, Maintenance) are now exposed." : "Simple Beginner Mode Enabled. Advanced settings secured and hidden.", "info");
                }}
                className="rounded border-slate-800 text-emerald-500 focus:ring-emerald-500 focus:ring-offset-slate-950 bg-slate-950 w-4 h-4 cursor-pointer accent-emerald-500"
              />
              <span className="text-xs font-mono font-bold uppercase tracking-wider">Advanced Mode</span>
            </label>
            <div className={`px-3 py-2 rounded-xl text-xs font-bold border transition-colors ${isServerRunning ? 'bg-emerald-500/10 border-emerald-500/50 text-emerald-400 animate-pulse' : 'bg-rose-500/10 border-rose-500/50 text-rose-400'}`}>
              {isServerRunning ? "● SERVER ACTIVE" : "○ SERVER IDLE"}
            </div>
            <div className="px-3 py-2 bg-slate-950 rounded-xl text-xs text-slate-400 border border-slate-800">
              {backend} ACTIVE BACKEND
            </div>
          </div>
        </header>

        {/* Dependency verification banner equivalent */}
        {missingCoreDeps.length > 0 && (
          <motion.div 
            initial={{ opacity: 0, y: -10 }}
            animate={{ opacity: 1, y: 0 }}
            className="bg-rose-500/5 border border-rose-500/35 rounded-2xl p-5 flex flex-col md:flex-row items-start md:items-center justify-between gap-4"
          >
            <div className="flex items-start gap-4">
              <div className="p-2.5 bg-rose-500/10 rounded-xl border border-rose-500/20 text-rose-400 shrink-0">
                <AlertTriangle className="w-5 h-5" />
              </div>
              <div className="space-y-1">
                <h4 className="text-sm font-bold text-white uppercase tracking-wider">dependency verification failed</h4>
                <p className="text-xs text-rose-300">
                  these dependencies were missing: <span className="font-bold text-rose-450">{missingCoreDeps.join(", ")}</span>
                </p>
                <p className="text-[10px] text-slate-500">
                  choose menu option [I] to install dependencies using the installer panel
                </p>
              </div>
            </div>
            <div className="text-xs text-slate-500 italic mt-1 md:mt-0 font-bold shrink-0">
              [Status: Intervention Required]
            </div>
          </motion.div>
        )}

        {/* Tab Selection */}
        {advancedMode && (
          <div className="flex flex-wrap gap-2 border-b border-slate-900 pb-2">
            <button
              onClick={() => setActiveTab("main")}
              className={`px-4 py-2 text-xs font-bold uppercase rounded-lg transition-all border ${activeTab === "main" ? "bg-emerald-500/10 border-emerald-500/30 text-emerald-400" : "bg-transparent border-transparent text-slate-400 hover:text-white"}`}
            >
              ● Main Dashboard
            </button>
            <button
              onClick={() => setActiveTab("options")}
              className={`px-4 py-2 text-xs font-bold uppercase rounded-lg transition-all border ${activeTab === "options" ? "bg-emerald-500/10 border-emerald-500/30 text-emerald-400" : "bg-transparent border-transparent text-slate-400 hover:text-white"}`}
            >
              ⚙ Options & SSL Settings
            </button>
            <button
              onClick={() => setActiveTab("updates")}
              className={`px-4 py-2 text-xs font-bold uppercase rounded-lg transition-all border ${activeTab === "updates" ? "bg-emerald-500/10 border-emerald-500/30 text-emerald-400" : "bg-transparent border-transparent text-slate-400 hover:text-white"}`}
            >
              ⟳ Compiler & Updates
            </button>
            <button
              onClick={() => setActiveTab("maintenance")}
              className={`px-4 py-2 text-xs font-bold uppercase rounded-lg transition-all border ${activeTab === "maintenance" ? "bg-emerald-500/10 border-emerald-500/30 text-emerald-400" : "bg-transparent border-transparent text-slate-400 hover:text-white"}`}
            >
              ⚠ Reset & Maintenance
            </button>
          </div>
        )}

        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          
          {/* Main Controls */}
          <div className="lg:col-span-2 space-y-6">
            {activeTab === "main" && (
              <>
            
            {/* Status Grid */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <StatusCard 
                icon={<Cpu className="w-4 h-4 text-emerald-400" />} 
                label="CPU Optimization" 
                value={buildProfile === "low" ? "Ivy Bridge (NO-AVX)" : buildProfile === "medium" ? "Modern AVX2 Native" : "Advanced AVX-512"} 
                detail={buildProfile === "low" ? "GGML_AVX = OFF" : buildProfile === "medium" ? "AVX2 & Native ON" : "AVX-512 & Native ON"} 
              />
              <StatusCard 
                icon={<Activity className="w-4 h-4 text-emerald-400" />} 
                label="Server Runtime" 
                value={new Date(uptime * 1000).toISOString().substr(11, 8)} 
                detail="Uptime Counter"
              />
              <StatusCard 
                icon={<Database className="w-4 h-4 text-emerald-400" />} 
                label="Selected Model" 
                value={activeModel ? activeModel.replace(".gguf", "") : "None Selected"} 
                detail={activeModel ? "Standard GGUF Format" : "Standby Mode"}
                highlight={!!activeModel}
              />
            </div>

            {/* Version Display and git info */}
            <div className="bg-slate-950/40 p-5 rounded-2xl border border-slate-900 flex flex-col md:flex-row justify-between items-center gap-4">
              <div className="flex items-center gap-3">
                <div className="p-2 bg-blue-500/10 rounded-lg text-blue-400">
                  <Info className="w-4 h-4" />
                </div>
                <div>
                  <h4 className="text-xs text-slate-500 font-bold uppercase tracking-wider">Currently Selected Backend Version</h4>
                  <p className="text-xs text-white leading-relaxed font-semibold">{llamaVersion}</p>
                </div>
              </div>
              <button 
                onClick={() => {
                  setLlamaVersion(`llama-server version 1.2.${Math.floor(Math.random() * 9) + 5}-git-${Math.random().toString(16).substr(2, 8)}`);
                  addLog("Queried backend version successfully: llama-server --version", "success");
                }}
                className="px-4 py-2 bg-slate-900 hover:bg-slate-800 text-xs border border-slate-800 hover:border-slate-700 text-white font-bold rounded-xl flex items-center gap-1.5 transition-all"
              >
                <RefreshCcw className="w-3.5 h-3.5" /> Re-Query version
              </button>
            </div>
            </>
            )}

            {activeTab === "options" && (
              <>
            {/* Persistent Hardware Profiles Setting (Change Build Options Menu equivalent) */}
            <div className="bg-slate-950/40 p-6 rounded-2xl border border-slate-900">
              <div className="flex justify-between items-start mb-4">
                <div>
                  <h3 className="text-sm font-semibold text-slate-200 flex items-center gap-2">
                    <Sliders className="w-4 h-4 text-emerald-400" /> PERSISTENT HARDWARE PROFILE (CMAKE OPTS)
                  </h3>
                  <p className="text-[10px] text-slate-500 mt-1 uppercase">Saves settings to local ~/.ai_manager/settings.conf</p>
                </div>
                <button
                  onClick={() => handleAction("toggle_profile")}
                  className="px-3 py-1.5 bg-emerald-500/10 border border-emerald-500/30 hover:bg-emerald-500/25 text-emerald-400 text-xs font-bold rounded-lg transition-all"
                >
                  Toggle Profile Settings
                </button>
              </div>

              <div className="grid grid-cols-1 lg:grid-cols-3 gap-4 mt-2">
                <div 
                  onClick={() => { setBuildProfile("low"); addLog("Switched build target to LOW profile (AVX OFF)", "success"); }}
                  className={`p-4 rounded-xl border text-left transition-all cursor-pointer hover:border-emerald-500/40 ${buildProfile === "low" ? "bg-emerald-500/5 border-emerald-500/30" : "bg-slate-950 border-slate-900 opacity-60"}`}
                >
                  <div className="flex justify-between items-center mb-1">
                    <span className="text-xs font-bold text-white">Low Profile (AVX OFF)</span>
                    {buildProfile === "low" && <span className="text-[9px] bg-emerald-500/20 text-emerald-300 font-bold px-1.5 py-0.5 rounded">ACTIVE</span>}
                  </div>
                  <p className="text-[10px] text-slate-400 mb-3 leading-normal">Locks building optimization. Disables AVX vector sets for safety.</p>
                  <div className="bg-slate-950/90 text-slate-400 p-2 rounded border border-slate-900 font-mono text-[9px] database-mono">
                    -DGGML_AVX=OFF {"\n"}-DGGML_AVX2=OFF {"\n"}-DGGML_AVX512=OFF
                  </div>
                </div>

                <div 
                  onClick={() => { setBuildProfile("medium"); addLog("Switched build target to MEDIUM profile (AVX2 ON)", "success"); }}
                  className={`p-4 rounded-xl border text-left transition-all cursor-pointer hover:border-emerald-500/40 ${buildProfile === "medium" ? "bg-emerald-500/5 border-emerald-500/30" : "bg-slate-950 border-slate-900 opacity-60"}`}
                >
                  <div className="flex justify-between items-center mb-1">
                    <span className="text-xs font-bold text-white">Medium Profile (AVX2)</span>
                    {buildProfile === "medium" && <span className="text-[9px] bg-emerald-500/20 text-emerald-300 font-bold px-1.5 py-0.5 rounded">ACTIVE</span>}
                  </div>
                  <p className="text-[10px] text-slate-400 mb-3 leading-normal">Optimizes AVX2 on modern engines. Adds native compilation flag.</p>
                  <div className="bg-slate-950/90 text-slate-400 p-2 rounded border border-slate-900 font-mono text-[9px] database-mono">
                    -DGGML_AVX2=ON {"\n"}-DGGML_NATIVE=ON {"\n"}-march=native
                  </div>
                </div>

                <div 
                  onClick={() => { setBuildProfile("high"); addLog("Switched build target to HIGH profile (AVX-512 ON)", "success"); }}
                  className={`p-4 rounded-xl border text-left transition-all cursor-pointer hover:border-emerald-500/40 ${buildProfile === "high" ? "bg-emerald-500/5 border-emerald-500/30" : "bg-slate-950 border-slate-900 opacity-60"}`}
                >
                  <div className="flex justify-between items-center mb-1">
                    <span className="text-xs font-bold text-white">High Profile (AVX-512)</span>
                    {buildProfile === "high" && <span className="text-[9px] bg-emerald-500/20 text-emerald-300 font-bold px-1.5 py-0.5 rounded">ACTIVE</span>}
                  </div>
                  <p className="text-[10px] text-slate-400 mb-3 leading-normal">Targets advanced compute instructions with full AVX-512 vector support.</p>
                  <div className="bg-slate-950/90 text-slate-400 p-2 rounded border border-slate-900 font-mono text-[9px] database-mono">
                    -DGGML_AVX512=ON {"\n"}-DGGML_NATIVE=ON {"\n"}-march=native
                  </div>
                </div>
              </div>
            </div>
            </>
            )}

            {activeTab === "options" && (
              <>
                {/* SSL Configuration Panel */}
                <div id="ssl-config-panel-container" className="bg-slate-950/40 p-6 rounded-2xl border border-slate-900 space-y-5">
                  <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-4 border-b border-slate-900 pb-3">
                    <div>
                      <h3 className="text-sm font-semibold text-slate-200 flex items-center gap-2">
                        <Lock className="w-4 h-4 text-emerald-400" /> SECURE LAUNCH GATEWAY (SSL CONFIGURATION)
                      </h3>
                      <p className="text-[10px] text-slate-500 mt-1 uppercase leading-none">Saves settings to ~/.ai_manager/settings.conf</p>
                    </div>
                    <button
                      id="opt-ssl-toggle-btn"
                      onClick={() => handleAction("toggle_ssl")}
                      className={`px-3 py-1.5 text-xs font-bold rounded-lg border transition-all uppercase ${
                        sslEnabled 
                          ? "bg-emerald-500/10 border-emerald-500/30 text-emerald-400" 
                          : "bg-rose-500/10 border-rose-500/30 text-rose-400"
                      }`}
                    >
                      SSL State: {sslEnabled ? "ENABLED (HTTPS)" : "DISABLED (HTTP)"}
                    </button>
                  </div>

                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div className="space-y-2">
                      <label className="text-[10px] text-slate-500 font-bold uppercase tracking-wider block">Listening Port (PORT)</label>
                      <input
                        id="input-ssl-port"
                        type="text"
                        value={sslPort}
                        onChange={(e) => setSslPort(e.target.value)}
                        className="w-full bg-[#040406] border border-slate-900 hover:border-slate-850 focus:border-emerald-500/40 focus:outline-none px-3.5 py-2.5 text-xs text-white rounded-xl font-mono"
                        placeholder="Default: 8888"
                      />
                    </div>

                    <div className="space-y-2">
                      <label className="text-[10px] text-slate-500 font-bold uppercase tracking-wider block leading-none">Sync Settings Environment</label>
                      <button
                        id="btn-save-ssl-settings"
                        onClick={() => handleAction("save_ssl_settings")}
                        className="w-full bg-emerald-500 hover:bg-emerald-400 text-emerald-950 text-xs font-bold py-2.5 rounded-xl transition-all"
                      >
                        Save Configuration & Sync
                      </button>
                    </div>

                    <div className="space-y-2 col-span-1 md:col-span-2">
                      <label className="text-[10px] text-slate-500 font-bold uppercase tracking-wider block">SSL Certificate File Path</label>
                      <input
                        id="input-ssl-cert"
                        type="text"
                        value={sslCertPath}
                        onChange={(e) => setSslCertPath(e.target.value)}
                        className="w-full bg-[#040406] border border-slate-900 hover:border-slate-850 focus:border-emerald-500/40 focus:outline-none px-3.5 py-2.5 text-xs text-white rounded-xl font-mono"
                        placeholder="e.g., /home/username/.ai_manager/certs/server.crt"
                      />
                    </div>

                    <div className="space-y-2 col-span-1 md:col-span-2">
                      <label className="text-[10px] text-slate-500 font-bold uppercase tracking-wider block">SSL Private Key File Path</label>
                      <input
                        id="input-ssl-key"
                        type="text"
                        value={sslKeyPath}
                        onChange={(e) => setSslKeyPath(e.target.value)}
                        className="w-full bg-[#040406] border border-slate-900 hover:border-slate-850 focus:border-emerald-500/40 focus:outline-none px-3.5 py-2.5 text-xs text-white rounded-xl font-mono"
                        placeholder="e.g., /home/username/.ai_manager/certs/server.key"
                      />
                    </div>
                  </div>

                  <div className="p-3 bg-slate-950 rounded-xl border border-slate-900 text-[10px] leading-relaxed text-slate-400 uppercase font-semibold">
                    🔑 Persistent format: settings.conf binds <span className="text-emerald-400">SSL_ENABLED</span>, <span className="text-emerald-400">PORT</span>, <span className="text-emerald-400">SSL_CERT_PATH</span>, and <span className="text-emerald-400">SSL_KEY_PATH</span> dynamically.
                  </div>
                </div>
              </>
            )}

            {activeTab === "main" && (
              <>
                         {/* Diagnostics and System Stability Matrix */}
             <div className="bg-slate-950/40 p-6 rounded-2xl border border-slate-900 space-y-4">
               <div>
                 <h3 className="text-sm font-semibold text-slate-200 flex items-center gap-2">
                   <TrendingUp className="w-4 h-4 text-cyan-400" /> DIAGNOSTICS & SYSTEM STABILITY MATRIX
                 </h3>
                 <p className="text-[10px] text-slate-500 uppercase tracking-wider mt-1">Option [b] • Verification utilities running live diagnostic benchmarks</p>
               </div>

               <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
                 <button
                   onClick={() => handleAction("benchmark")}
                   className="p-3 bg-cyan-950/10 hover:bg-cyan-950/30 border border-cyan-500/20 text-cyan-400 text-xs font-bold rounded-xl transition-all flex flex-col items-center text-center justify-between min-h-[90px] group"
                 >
                   <TrendingUp className="w-4 h-4 text-cyan-400 mb-1 group-hover:scale-110 transition-transform" />
                   <span>1) Run Benchmarks</span>
                   <span className="text-[8px] text-slate-500 font-normal uppercase mt-1">Evaluates t/s execution</span>
                 </button>

                 <button
                   onClick={() => handleAction("perplexity_check")}
                   className="p-3 bg-blue-950/10 hover:bg-blue-950/30 border border-blue-500/20 text-blue-400 text-xs font-bold rounded-xl transition-all flex flex-col items-center text-center justify-between min-h-[90px] group"
                 >
                   <Activity className="w-4 h-4 text-blue-400 mb-1 group-hover:scale-110 transition-transform" />
                   <span>2) Perplexity Check</span>
                   <span className="text-[8px] text-slate-500 font-normal uppercase mt-1">Runs logits validation</span>
                 </button>

                 <button
                   onClick={() => handleAction("diagnostic_run")}
                   className="p-3 bg-emerald-950/10 hover:bg-emerald-950/30 border border-emerald-500/20 text-emerald-400 text-xs font-bold rounded-xl transition-all flex flex-col items-center text-center justify-between min-h-[90px] group"
                 >
                   <TerminalIcon className="w-4 h-4 text-emerald-400 mb-1 group-hover:scale-110 transition-transform" />
                   <span>3) Operational Test</span>
                   <span className="text-[8px] text-slate-500 font-normal uppercase mt-1">Spawns test runtime</span>
                 </button>

                 <button
                   onClick={() => handleAction("vram_monitor")}
                   className="p-3 bg-amber-950/10 hover:bg-amber-950/30 border border-amber-500/20 text-amber-500 text-xs font-bold rounded-xl transition-all flex flex-col items-center text-center justify-between min-h-[90px] group font-semibold"
                 >
                   <Zap className="w-4 h-4 text-amber-500 mb-1 group-hover:scale-110 transition-transform" />
                   <span>4) Monitor VRAM</span>
                   <span className="text-[8px] text-slate-500 font-normal uppercase mt-1">Real-time nvidia-smi</span>
                 </button>

                 <button
                   onClick={() => handleAction("vulkan_check")}
                   className="p-3 bg-purple-950/10 hover:bg-purple-950/30 border border-purple-500/20 text-purple-400 text-xs font-bold rounded-xl transition-all flex flex-col items-center text-center justify-between min-h-[90px] group col-span-2 md:col-span-1"
                 >
                   <Shield className="w-4 h-4 text-purple-400 mb-1 group-hover:scale-110 transition-transform" />
                   <span>5) Vulkan Check</span>
                   <span className="text-[8px] text-slate-500 font-normal uppercase mt-1">vulkaninfo summary</span>
                 </button>
               </div>

               <div className="bg-[#050508] border border-slate-900 rounded-xl p-3.5 text-xs text-slate-350 leading-relaxed font-mono">
                 {activeModel ? (
                   <div className="flex justify-between items-center gap-4">
                     <div>
                       Targeting active GGUF model: <span className="text-emerald-400 font-bold">{activeModel}</span>
                     </div>
                     <span className="text-[9px] bg-emerald-500/10 border border-emerald-500/30 text-emerald-300 font-bold px-1.5 py-0.5 rounded shrink-0 uppercase">GGUF loaded</span>
                   </div>
                 ) : (
                   <p className="italic text-slate-500 text-[11px]">
                     Note: Select an active GGUF model file below to unlock comprehensive Perplexity checks and Operational stability tests on custom model files.
                   </p>
                 )}
               </div>
             </div>

            </>
          )}

          {activeTab === "maintenance" && (
            <>
             {/* Reset & Maintenance Sub-Menu / Container */}
             <div className="bg-slate-950/40 p-6 rounded-2xl border border-slate-900 space-y-4">
               <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-2">
                 <div>
                   <h3 className="text-sm font-semibold text-slate-200 flex items-center gap-2">
                     <Sliders className="w-4 h-4 text-amber-500 animate-pulse" /> RESET & MAINTENANCE UTILITIES
                   </h3>
                   <p className="text-[10px] text-slate-500 uppercase tracking-wider mt-1">Option [h] • Backup configurations and clean CMake databases</p>
                 </div>
                 <span className="text-[9px] bg-amber-500/10 border border-amber-500/20 text-amber-400 px-2.5 py-0.5 rounded-full font-bold uppercase shrink-0">
                   Maintenance Mode
                 </span>
               </div>

               <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                 <button
                   onClick={() => handleAction("config_reset")}
                   className="p-4 bg-slate-900 hover:bg-slate-850 border border-slate-800 text-xs rounded-xl font-bold text-slate-300 hover:text-white transition-all flex flex-col items-start gap-1.5"
                 >
                   <div className="flex items-center gap-2 text-rose-400">
                     <AlertTriangle className="w-4 h-4 text-rose-400" />
                     <span className="font-extrabold uppercase">1) Reset System Config</span>
                   </div>
                   <p className="text-[10px] text-slate-400 font-normal text-left leading-normal">
                     Clones configuration settings into sequential backups (.old, .old1) to prevent overwrites, then restores default variables.
                   </p>
                 </button>

                 <button
                   onClick={() => handleAction("cache_reset")}
                   className="p-4 bg-slate-900 hover:bg-slate-850 border border-slate-800 text-xs rounded-xl font-bold text-slate-300 hover:text-white transition-all flex flex-col items-start gap-1.5"
                 >
                   <div className="flex items-center gap-2 text-amber-400">
                     <RefreshCcw className="w-4 h-4 text-amber-400" />
                     <span className="font-extrabold uppercase">2) Reset Build Cache</span>
                   </div>
                   <p className="text-[10px] text-slate-400 font-normal text-left leading-normal">
                     Deletes all CMakeCache.txt files and compiled .o assets in build & build_VULKAN, forcing a clean recompilation.
                   </p>
                 </button>
               </div>
             </div>

             {/* Daemon & Systemd Service Controls */}
             <div className="bg-slate-950/40 p-6 rounded-2xl border border-slate-900 space-y-4">
               <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-2">
                 <div>
                   <h3 className="text-sm font-semibold text-slate-200 flex items-center gap-2">
                     <Server className="w-4 h-4 text-indigo-400" /> DAEMON & SYSTEM SERVICE MANAGER
                   </h3>
                   <p className="text-[10px] text-slate-500 uppercase tracking-wider mt-1">Option [s] • Service lifecycle installer & controller</p>
                 </div>
                 <span className="text-[9px] bg-indigo-500/10 border border-indigo-500/20 text-indigo-300 px-2.5 py-0.5 rounded-full font-bold uppercase shrink-0">
                   Systemd Supported
                 </span>
               </div>

               <div className="grid grid-cols-2 md:grid-cols-5 gap-2.5">
                 <button
                   onClick={() => handleAction("service_status")}
                   className="p-2.5 bg-slate-900 hover:bg-slate-850 border border-slate-800 text-[10px] rounded-xl font-bold text-slate-300 hover:text-white transition-all flex flex-col items-center gap-1.5 justify-center min-h-[64px]"
                 >
                   <Info className="w-3.5 h-3.5 text-slate-400" />
                   <span>Status</span>
                 </button>
                 <button
                   onClick={() => handleAction("service_restart")}
                   className="p-2.5 bg-slate-900 hover:bg-slate-850 border border-slate-800 text-[10px] rounded-xl font-bold text-slate-300 hover:text-white transition-all flex flex-col items-center gap-1.5 justify-center min-h-[64px]"
                 >
                   <RefreshCcw className="w-3.5 h-3.5 text-amber-500" />
                   <span>Restart</span>
                 </button>
                 <button
                   onClick={() => handleAction("service_update")}
                   className="p-2.5 bg-slate-900 hover:bg-slate-850 border border-slate-800 text-[10px] rounded-xl font-bold text-slate-300 hover:text-white transition-all flex flex-col items-center gap-1.5 justify-center min-h-[64px]"
                 >
                   <Sliders className="w-3.5 h-3.5 text-indigo-400" />
                   <span>Sync Config</span>
                 </button>
                 <button
                   onClick={() => handleAction("service_install")}
                   className="p-2.5 bg-slate-900 hover:bg-slate-850 border border-slate-800 text-[10px] rounded-xl font-bold text-slate-300 hover:text-white transition-all flex flex-col items-center gap-1.5 justify-center min-h-[64px]"
                 >
                   <Play className="w-3.5 h-3.5 text-emerald-400" />
                   <span>Install</span>
                 </button>
                 <button
                   onClick={() => handleAction("service_remove")}
                   className="col-span-2 md:col-span-1 p-2.5 bg-slate-900 hover:bg-slate-850 border border-slate-800 text-[10px] rounded-xl font-bold text-slate-300 hover:text-white transition-all flex flex-col items-center gap-1.5 justify-center min-h-[64px]"
                 >
                   <Square className="w-3.5 h-3.5 text-rose-500" />
                   <span>Uninstall</span>
                 </button>
               </div>
             </div>

             {/* Models Workspace Path Directory */}
             <div className="bg-slate-950/40 p-6 rounded-2xl border border-slate-900 space-y-4">
               <div>
                 <h3 className="text-sm font-semibold text-slate-200 flex items-center gap-2">
                   <Database className="w-4 h-4 text-emerald-400" /> GGUF DIRECTORY CONFIGURATION
                 </h3>
                 <p className="text-[10px] text-slate-500 uppercase tracking-wider mt-1">Saves persistent MODELS_DIR workspace variables</p>
               </div>

               <div className="flex flex-col md:flex-row gap-2">
                 <div className="flex-1 min-w-[200px] relative">
                   <div className="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-600 text-xs font-mono font-bold">PATH:</div>
                   <input
                     type="text"
                     placeholder="/path/to/models"
                     value={modelsDir}
                     onChange={(e) => {
                       setModelsDir(e.target.value);
                     }}
                     className="w-full bg-[#040406] border border-slate-850 hover:border-slate-800 focus:border-emerald-500/50 focus:outline-none pl-14 pr-3.5 py-2.5 text-xs text-slate-200 rounded-xl transition-all font-mono"
                   />
                 </div>
                 <button
                   onClick={() => {
                     addLog(`Configured MODELS_DIR pathway successfully: ${modelsDir}`, "success");
                     addLog(`Environment workspace pointing dynamically to path location.`, "info");
                   }}
                   className="px-4 py-2.5 bg-emerald-500 hover:bg-emerald-400 text-emerald-950 text-xs font-bold rounded-xl transition-all shrink-0"
                 >
                   Apply Workspace
                 </button>
               </div>
             </div>

            </>
          )}

          {activeTab === "main" && (
            <>
            {/* VRAM Monitor */}
            <div className="bg-slate-950/40 p-6 rounded-2xl border border-slate-900">
              <h3 className="text-sm font-semibold text-slate-400 mb-6 flex items-center gap-2">
                <Zap className="w-4 h-4 text-amber-500" /> DUAL RTX VRAM ALLOCATION
              </h3>
              <div className="space-y-6">
                <ProgressBar label="GPU 0 (RTX 3060 - 12GB)" percentage={vramUsage.gpu0} color="bg-emerald-500" />
                <ProgressBar label="GPU 1 (RTX 3060/RX 9060)" percentage={vramUsage.gpu1} color="bg-cyan-500" />
              </div>
            </div>

            {/* Model Selection */}
            <div className="bg-slate-950/40 p-6 rounded-2xl border border-slate-900">
              <h3 className="text-sm font-semibold text-slate-400 mb-4 flex items-center gap-2">
                <HardDrive className="w-4 h-4 text-emerald-400" /> GGUF MODEL SELECTOR
              </h3>
              <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
                {MODELS.map(model => (
                  <button
                    key={model.id}
                    onClick={() => {
                        setActiveModel(model.name);
                        addLog(`GGUF Model loaded into buffer: ${model.name}`, "info");
                    }}
                    className={`p-4 rounded-xl border text-left transition-all group ${
                      activeModel === model.name 
                        ? 'bg-emerald-500/10 border-emerald-500/50 text-white' 
                        : 'bg-slate-950 border-slate-900 hover:border-slate-800 hover:bg-slate-900/50'
                    }`}
                  >
                    <div className="flex justify-between items-start mb-1">
                      <span className="text-[10px] font-bold text-slate-500 uppercase tracking-wider">{model.type}</span>
                      {activeModel === model.name && <div className="w-2 h-2 rounded-full bg-emerald-500" />}
                    </div>
                    <div className="font-semibold text-xs break-all group-hover:text-white transition-colors">{model.name}</div>
                  </button>
                ))}
              </div>
            </div>
            </>
          )}
          </div>

          {/* Sidebar Actions & Logs */}
          <div className="space-y-6">
            
            {/* Quick Actions */}
            <div className="bg-slate-950/40 p-6 rounded-2xl border border-slate-900 space-y-3">
              <h3 className="text-sm font-semibold text-slate-400 mb-4 flex items-center gap-2 justify-center text-center">
                <Settings className="w-4 h-4 text-emerald-400" /> SERVER MANAGEMENT
              </h3>
              
              <button 
                onClick={() => handleAction(isServerRunning ? "stop" : "start")}
                disabled={!activeModel}
                className={`w-full py-3 rounded-xl font-bold flex items-center justify-center gap-2 transition-all ${
                  isServerRunning 
                    ? 'bg-rose-500/20 text-rose-400 border border-rose-500/30 hover:bg-rose-500/30 font-bold' 
                    : 'bg-emerald-500 text-emerald-950 border border-emerald-400 hover:bg-emerald-400 font-bold disabled:opacity-40 disabled:cursor-not-allowed'
                }`}
              >
                {isServerRunning ? <><Square className="w-4 h-4 fill-current" /> STOP SERVER</> : <><Play className="w-4 h-4 fill-current" /> START SERVER</>}
              </button>

              <div className="grid grid-cols-3 gap-2">
                <ActionButton 
                  icon={<RefreshCcw className="w-4 h-4 text-emerald-400" />} 
                  label="REBUILD CUDA" 
                  onClick={() => handleAction("build_cuda")} 
                />
                <ActionButton 
                  icon={<RefreshCcw className="w-4 h-4 text-cyan-400" />} 
                  label="REBUILD VULKAN" 
                  onClick={() => handleAction("build_vulkan")} 
                />
                <ActionButton 
                  icon={<RefreshCcw className="w-4 h-4 text-purple-400" />} 
                  label="REBUILD ROCM" 
                  onClick={() => handleAction("build_rocm")} 
                />
              </div>

              <div className="pt-4 border-t border-slate-900">
                <p className="text-[10px] text-slate-500 mb-3 text-center uppercase tracking-[0.2em] font-semibold">Switch Backend</p>
                <div className="flex gap-2">
                  {BACKENDS.map(b => (
                    <button
                      key={b}
                      onClick={() => {
                        setBackend(b);
                        addLog(`Backend targeted: ${b}`, "info");
                        addLog("Retrieving latest version signature...", "info");
                        addLog(`Querying llama-server --version for ${b}`, "command");
                      }}
                      className={`flex-1 py-2 rounded-lg text-xs font-bold border transition-all ${
                        backend === b 
                          ? 'bg-blue-500/10 border-blue-500/50 text-blue-400' 
                          : 'bg-slate-950 border-slate-900 text-slate-550 hover:text-slate-300'
                      }`}
                    >
                      {b}
                    </button>
                  ))}
                </div>

                {backend === "Vulkan" && (
                  <div id="vulkan-gpu-selector" className="mt-4 pt-4 border-t border-slate-900/60 space-y-3">
                    <div className="flex justify-between items-center">
                      <p className="text-[10px] text-slate-400 uppercase tracking-[0.15em] font-bold">
                        Vulkan GPU Targets (Persistent)
                      </p>
                      <span className="text-[9px] text-slate-500 uppercase font-mono bg-slate-950 px-1.5 py-0.5 rounded border border-slate-900">
                        Spacebar/Click to Select
                      </span>
                    </div>
                    
                    <div className="space-y-2">
                      {[
                        { index: 0, name: "NVIDIA GeForce RTX 3060", detail: "Discrete GPU" },
                        { index: 1, name: "AMD Radeon RX 9060", detail: "Discrete GPU" }
                      ].map((gpu) => {
                        const isSelected = selectedVulkanGpus.includes(gpu.name);
                        return (
                          <div
                            key={gpu.name}
                            tabIndex={0}
                            onClick={() => {
                              let next;
                              if (isSelected) {
                                next = selectedVulkanGpus.filter(g => g !== gpu.name);
                              } else {
                                next = [...selectedVulkanGpus, gpu.name];
                              }
                              setSelectedVulkanGpus(next);
                              addLog(`Vulkan GPU Target updated: [${next.join(", ") || "None"}]. Selected persistently.`, "success");
                            }}
                            onKeyDown={(e) => {
                              if (e.key === " " || e.key === "Spacebar") {
                                e.preventDefault();
                                let next;
                                if (isSelected) {
                                  next = selectedVulkanGpus.filter(g => g !== gpu.name);
                                } else {
                                  next = [...selectedVulkanGpus, gpu.name];
                                }
                                setSelectedVulkanGpus(next);
                                addLog(`Vulkan GPU Target updated: [${next.join(", ") || "None"}]. Selected persistently.`, "success");
                              }
                            }}
                            className={`flex items-center justify-between p-2.5 rounded-xl border text-xs font-medium cursor-pointer transition-all focus:outline-none focus:ring-1 focus:ring-cyan-500/50 ${
                              isSelected 
                                ? 'bg-cyan-500/10 border-cyan-500/40 text-cyan-200' 
                                : 'bg-[#040406] border-slate-900 text-slate-400 hover:text-slate-350 hover:bg-[#07070b]'
                            }`}
                          >
                            <div className="flex items-center gap-2">
                              <div className={`w-3.5 h-3.5 rounded border flex items-center justify-center font-bold text-[9px] transition-all ${
                                isSelected ? 'bg-cyan-500 border-cyan-400 text-cyan-950' : 'border-slate-800'
                              }`}>
                                {isSelected ? "✓" : ""}
                              </div>
                              <div className="flex flex-col">
                                <span className="font-semibold text-[11px] leading-tight text-left">
                                  [{gpu.index}] {gpu.name}
                                </span>
                                <span className="text-[9px] text-slate-500 uppercase tracking-wide text-left">
                                  {gpu.detail}
                                </span>
                              </div>
                            </div>

                            <span className="text-[9px] text-slate-500 bg-slate-950/60 px-1.5 py-0.5 rounded border border-slate-900 uppercase font-bold">
                              {isSelected ? "Active" : "Idle"}
                            </span>
                          </div>
                        );
                      })}
                    </div>

                    <p className="text-[9px] text-slate-500 uppercase leading-normal">
                      📁 Configuration persisted dynamically in local node state database. Active selections apply seamlessly on next engine restart without user prompts.
                    </p>
                  </div>
                )}
              </div>
            </div>

            {/* Interactive System Dependency Matrix (Sub-Menu Installer Option I equivalent) */}
            <div className="bg-slate-950/40 p-5 rounded-2xl border border-slate-900 space-y-4">
              <div>
                <h3 className="text-xs font-bold text-slate-300 uppercase tracking-wider flex items-center gap-1.5">
                  <Download className="w-4 h-4 text-emerald-400" /> SYSTEM DEPS MANAGER (OPTION I)
                </h3>
                <p className="text-[10px] text-slate-500 mt-1 uppercase font-semibold">Simulates verification check & custom interactive setups</p>
              </div>

              <div className="space-y-1.5 border border-slate-900/80 bg-slate-950/80 p-3 rounded-lg overflow-hidden shrink-0">
                {Object.entries(dependencies).map(([name, installed]) => (
                  <div key={name} className="flex items-center justify-between text-[10px]">
                    <span className="text-slate-400 font-mono">{name}</span>
                    <span className={`font-bold transition-all ${installed ? 'text-emerald-500' : 'text-rose-500 animate-pulse'}`}>
                      {installed ? "● INSTALLED" : "○ MISSING"}
                    </span>
                  </div>
                ))}
              </div>

              <div className="space-y-2 border-t border-slate-900/60 pt-3">
                <button
                  onClick={() => handleAction("install_deps_nvidia")}
                  disabled={dependencies.nvcc}
                  className="w-full py-2 bg-slate-900 hover:bg-slate-850 disabled:opacity-50 text-[10px] font-bold text-white rounded-lg border border-slate-800 transition-all flex items-center justify-center gap-1.5"
                >
                  <Download className="w-3.5 h-3.5 text-emerald-400" /> [N] Nvidia (CUDA & Vulkan)
                </button>
                <button
                  onClick={() => handleAction("install_deps_amd")}
                  disabled={dependencies.rocminfo}
                  className="w-full py-2 bg-slate-900 hover:bg-slate-850 disabled:opacity-50 text-[10px] font-bold text-white rounded-lg border border-slate-800 transition-all flex items-center justify-center gap-1.5"
                >
                  <Download className="w-3.5 h-3.5 text-purple-400" /> [A] AMD (RoCM & Vulkan)
                </button>
              </div>
            </div>

            {/* Git Pull Actions */}
            <div className="bg-slate-950/40 p-4 rounded-xl border border-slate-900 space-y-2">
              <h4 className="text-[10px] font-bold text-slate-500 uppercase tracking-widest flex items-center gap-1.5">
                <GitPullRequest className="w-3.5 h-3.5 text-blue-400" /> Repository Source Controller
              </h4>
              <p className="text-[10px] text-slate-400 leading-normal">
                Enables official <span className="text-white hover:underline cursor-pointer">llama.cpp repo pull</span> directly before executing build managers. Keeps your local node updated to the latest commits automatically.
              </p>
              <button
                onClick={() => handleAction("build_and_pull")}
                className="w-full py-2 bg-blue-500/10 border border-blue-500/25 hover:bg-blue-500/20 text-blue-400 text-xs font-bold rounded-lg flex items-center justify-center gap-1.5 transition-all mt-1"
              >
                <GitPullRequest className="w-3.5 h-3.5" /> Pull & Compile Latest Updates
              </button>
            </div>

            {/* Terminal */}
            <div className="bg-[#040406] rounded-2xl border border-slate-900 overflow-hidden flex flex-col h-[320px]">
              <div className="bg-slate-950/80 px-4 py-2 border-b border-slate-900 flex justify-between items-center">
                <span className="text-[10px] font-bold text-slate-500 flex items-center gap-2 uppercase tracking-widest leading-none">
                  <TerminalIcon className="w-3 h-3 text-emerald-400" /> SYSTEM MONITOR
                </span>
                <button 
                  onClick={() => setLogs([])}
                  className="text-[10px] text-slate-600 hover:text-white transition-colors uppercase leading-none"
                >
                  Clear logs
                </button>
              </div>
              <div className="flex-1 overflow-y-auto p-4 space-y-1 font-mono text-[10px] scrollbar-thin scrollbar-thumb-slate-900">
                {logs.map((log, i) => (
                  <div key={i} className="flex gap-3 leading-relaxed">
                    <span className="text-slate-700 shrink-0">[{log.timestamp}]</span>
                    <span className={`
                      ${log.type === 'error' ? 'text-rose-500' : ''}
                      ${log.type === 'success' ? 'text-emerald-500 font-bold' : ''}
                      ${log.type === 'command' ? 'text-amber-400 italic opacity-85 font-semibold' : 'text-slate-350'}
                    `}>
                      {log.type === 'command' ? '$ ' : ''}{log.message}
                    </span>
                  </div>
                ))}
                <div ref={logEndRef} />
              </div>
            </div>

          </div>
        </div>

        {/* Footer Info */}
        <footer className="grid grid-cols-1 md:grid-cols-3 gap-6 text-[10px] text-slate-600 border-t border-slate-900 pt-6 px-2">
            <div className="flex items-center gap-2">
                <Shield className="w-3 h-3" />
                <span>Ivy Bridge Compatibility Layer Standardized</span>
            </div>
            <div className="text-center">
                Server Environment Version 8.8.0 (STABLE)
            </div>
            <div className="text-right">
                © 2026 AI NODE MANAGER
            </div>
        </footer>
      </div>
    </div>
  );
}


function StatusCard({ id, icon, label, value, detail, highlight = false }: { id?: string, icon: any, label: string, value: string, detail: string, highlight?: boolean }) {
  return (
    <div id={id} className={`p-5 rounded-2xl border backdrop-blur-sm transition-all duration-300 ${highlight ? 'bg-emerald-500/5 border-emerald-500/30' : 'bg-slate-950/30 border-slate-900 hover:border-slate-850'}`}>
      <div className="flex items-center gap-2 text-slate-500 mb-2">
        {icon}
        <span className="text-[10px] font-bold uppercase tracking-[0.15em]">{label}</span>
      </div>
      <div className={`text-sm font-bold truncate ${highlight ? 'text-emerald-400' : 'text-white'}`}>{value}</div>
      <div className="text-[10px] text-slate-650 mt-1 uppercase tracking-wider">{detail}</div>
    </div>
  );
}

function ProgressBar({ label, percentage, color }: { label: string, percentage: number, color: string }) {
  return (
    <div className="space-y-2">
      <div className="flex justify-between text-[11px] font-bold uppercase tracking-wider">
        <span className="text-slate-500">{label}</span>
        <span className="text-white">{percentage.toFixed(1)}%</span>
      </div>
      <div className="h-1.5 w-full bg-slate-900 rounded-full overflow-hidden">
        <div style={{ width: `${percentage}%` }} className={`h-full ${color} transition-all duration-500 shadow-[0_0_8px_rgba(16,185,129,0.3)]`} />
      </div>
    </div>
  );
}

function ActionButton({ icon, label, onClick }: { icon: any, label: string, onClick: () => void }) {
  return (
    <button 
      onClick={onClick}
      className="flex flex-col items-center justify-center gap-2 p-3 bg-slate-950 border border-slate-900 rounded-xl hover:bg-slate-900 hover:border-slate-800 transition-all text-slate-400 hover:text-white group"
    >
      <div className="p-2 bg-slate-900 rounded-lg group-hover:bg-slate-800 transition-colors">
        {icon}
      </div>
      <span className="text-[9px] font-bold uppercase tracking-tighter">{label}</span>
    </button>
  );
}
