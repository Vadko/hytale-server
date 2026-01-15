const express = require("express");
const http = require("http");
const { Server } = require("socket.io");
const Docker = require("dockerode");
const path = require("path");
const fs = require("fs");

const app = express();
const server = http.createServer(app);
const io = new Server(server);
const docker = new Docker({ socketPath: "/var/run/docker.sock" });

const CONTAINER_NAME = process.env.CONTAINER_NAME || "hytale-server";
const PORT = process.env.PANEL_PORT || 3000;

app.use(express.static(path.join(__dirname, "public")));
app.use(express.json());

let container = null;

async function getContainer() {
  try {
    container = docker.getContainer(CONTAINER_NAME);
    return container;
  } catch (e) {
    return null;
  }
}

async function getContainerStatus() {
  try {
    const c = await getContainer();
    if (!c) return { running: false, status: "not found" };
    const info = await c.inspect();
    return {
      running: info.State.Running,
      status: info.State.Status,
      startedAt: info.State.StartedAt,
      health: info.State.Health?.Status || "unknown",
    };
  } catch (e) {
    return { running: false, status: "not found", error: e.message };
  }
}

async function execCommand(cmd) {
  try {
    const c = await getContainer();
    if (!c) throw new Error("Container not found");

    const exec = await c.exec({
      Cmd: ["sh", "-c", cmd],
      AttachStdout: true,
      AttachStderr: true,
    });

    const stream = await exec.start();
    return new Promise((resolve, reject) => {
      let output = "";
      stream.on("data", (chunk) => {
        output += chunk.slice(8).toString("utf8");
      });
      stream.on("end", () => resolve(output));
      stream.on("error", reject);
    });
  } catch (e) {
    throw e;
  }
}

async function sendServerCommand(cmd) {
  try {
    const c = await getContainer();
    if (!c) throw new Error("Container not found");

    await execCommand(`echo "${cmd}" > /tmp/hytale-console`);
    return { success: true };
  } catch (e) {
    return { success: false, error: e.message };
  }
}

async function checkServerFiles() {
  try {
    const result = await execCommand(
      'ls -la /opt/hytale/*.jar /opt/hytale/*.zip 2>/dev/null || echo "NO_FILES"'
    );
    const hasJar = result.includes("HytaleServer.jar");
    const hasAssets = result.includes("Assets.zip");
    return { hasJar, hasAssets, ready: hasJar && hasAssets };
  } catch (e) {
    return { hasJar: false, hasAssets: false, ready: false };
  }
}

async function downloadServerFiles() {
  try {
    // Run the downloader
    const result = await execCommand(
      "cd /opt/hytale && hytale-downloader --download-path /tmp/hytale-game.zip 2>&1"
    );
    return { success: true, output: result };
  } catch (e) {
    return { success: false, error: e.message };
  }
}

async function restartContainer() {
  try {
    const c = await getContainer();
    if (!c) throw new Error("Container not found");
    await c.restart();
    return { success: true };
  } catch (e) {
    return { success: false, error: e.message };
  }
}

async function stopContainer() {
  try {
    const c = await getContainer();
    if (!c) throw new Error("Container not found");
    await c.stop();
    return { success: true };
  } catch (e) {
    return { success: false, error: e.message };
  }
}

async function startContainer() {
  try {
    const c = await getContainer();
    if (!c) throw new Error("Container not found");
    await c.start();
    return { success: true };
  } catch (e) {
    return { success: false, error: e.message };
  }
}

io.on("connection", async (socket) => {
  console.log("Client connected");

  // Send initial status
  socket.emit("status", await getContainerStatus());
  socket.emit("files", await checkServerFiles());

  // Stream logs
  try {
    const c = await getContainer();
    if (c) {
      const logStream = await c.logs({
        follow: true,
        stdout: true,
        stderr: true,
        tail: 100,
        timestamps: true,
      });

      logStream.on("data", (chunk) => {
        const text = chunk.slice(8).toString("utf8");
        socket.emit("log", text);
      });

      socket.on("disconnect", () => {
        logStream.destroy();
      });
    }
  } catch (e) {
    socket.emit("error", "Failed to connect to container: " + e.message);
  }

  // Handle commands
  socket.on("command", async (cmd) => {
    const result = await sendServerCommand(cmd);
    socket.emit("command-result", { cmd, ...result });
  });

  // Handle download request
  socket.on("download", async () => {
    socket.emit("download-status", {
      status: "starting",
      message: "Starting download...",
    });
    const result = await downloadServerFiles();
    socket.emit("download-status", {
      status: result.success ? "complete" : "error",
      ...result,
    });
    socket.emit("files", await checkServerFiles());
  });

  // Handle container control
  socket.on("restart", async () => {
    socket.emit("action-status", { action: "restart", status: "starting" });
    const result = await restartContainer();
    socket.emit("action-status", { action: "restart", ...result });
  });

  socket.on("stop", async () => {
    socket.emit("action-status", { action: "stop", status: "starting" });
    const result = await stopContainer();
    socket.emit("action-status", { action: "stop", ...result });
  });

  socket.on("start", async () => {
    socket.emit("action-status", { action: "start", status: "starting" });
    const result = await startContainer();
    socket.emit("action-status", { action: "start", ...result });
  });

  // Check files status
  socket.on("check-files", async () => {
    socket.emit("files", await checkServerFiles());
  });

  // Status updates
  const statusInterval = setInterval(async () => {
    socket.emit("status", await getContainerStatus());
  }, 5000);

  socket.on("disconnect", () => {
    clearInterval(statusInterval);
    console.log("Client disconnected");
  });
});

server.listen(PORT, () => {
  console.log(`Hytale Panel running on http://localhost:${PORT}`);
});
