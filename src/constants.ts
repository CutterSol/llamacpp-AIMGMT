export const SERVER_FLAGS = {
  ngl: 99,
  fa: "on",
  ctx_size: 42768,
  context_shift: true,
  ctx_checkpoints: 8,
  tools: "all",
  cram: 1024,
  cache_reuse: 128,
  kv_unified: true,
  cache_type_k: "q8_0",
  cache_type_v: "q8_0",
  np: 1,
  batch_size: 1024,
  ubatch_size: 256,
  t: 1,
  reasoning: "off",
  ui_mcp_proxy: true,
  cont_batching: true,
  ui_config_file: "~/ai_tools/webui-config.json",
};

export const BACKENDS = ["CUDA", "Vulkan", "RoCM"] as const;
export type Backend = typeof BACKENDS[number];

export const MODELS = [
  { id: "1", name: "DeepSeek-R1-Distill-Llama-70B.gguf", type: "GGUF" },
  { id: "2", name: "Llama-3.1-8B-Instruct-Q8_0.gguf", type: "GGUF" },
  { id: "3", name: "Mistral-7B-Instruct-v0.3.gguf", type: "GGUF" },
];
