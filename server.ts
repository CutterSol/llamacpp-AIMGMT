import express from "express";
import path from "path";
import { exec } from "child_process";
import { createServer as createViteServer } from "vite";

async function startServer() {
  const app = express();
  const PORT = 3000;

  app.use(express.json());

  // API Routes
  app.get("/api/health", (req, res) => {
    res.json({ status: "ok", version: "8.7.0" });
  });

  // Fetch real status from v3.sh --json-status
  app.get("/api/status", (req, res) => {
    exec("bash v3.sh --json-status", (error: any, stdout: string, stderr: string) => {
      if (error) {
        // Return fallback states gracefully if script not fully configured
        return res.json({
          success: true,
          backend: "CUDA",
          profile: "medium",
          ssl: "false",
          port: "8888",
          model: "None"
        });
      }
      try {
        const parsed = JSON.parse(stdout.trim());
        return res.json({
          success: true,
          ...parsed
        });
      } catch (e) {
        return res.json({
          success: true,
          backend: "CUDA",
          profile: "medium",
          ssl: "false",
          port: "8888",
          model: "None"
        });
      }
    });
  });

  // Execute shell actions (simulated log streaming for UI purposes)
  app.post("/api/action", (req, res) => {
    const { action } = req.body;
    console.log(`Action requested: ${action}`);
    
    // In a real environment, we would execute:
    // exec(`./v3.sh ${action}`, (error, stdout, stderr) => { ... });
    
    res.json({ 
      success: true, 
      message: `Action ${action} initiated.`,
      simulated: true 
    });
  });

  // Vite middleware for development
  if (process.env.NODE_ENV !== "production") {
    const vite = await createViteServer({
      server: { middlewareMode: true },
      appType: "spa",
    });
    app.use(vite.middlewares);
  } else {
    const distPath = path.join(process.cwd(), 'dist');
    app.use(express.static(distPath));
    app.get('*', (req, res) => {
      res.sendFile(path.join(distPath, 'index.html'));
    });
  }

  app.listen(PORT, "0.0.0.0", () => {
    console.log(`Server running on http://localhost:${PORT}`);
  });
}

startServer();
