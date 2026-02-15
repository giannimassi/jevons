import { type ChildProcess, execSync, spawn } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import * as net from 'net';

const REPO_ROOT = path.resolve(__dirname, '..', '..');
const BINARY = path.join(REPO_ROOT, 'bin', 'jevons');
const FIXTURE_DIR = path.join(__dirname, 'fixtures');

/** Find a free TCP port. */
export async function getFreePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const srv = net.createServer();
    srv.listen(0, '127.0.0.1', () => {
      const addr = srv.address();
      if (!addr || typeof addr === 'string') {
        srv.close();
        reject(new Error('could not get port'));
        return;
      }
      const port = addr.port;
      srv.close(() => resolve(port));
    });
    srv.on('error', reject);
  });
}

/** Wait until the HTTP server is accepting connections. */
async function waitForServer(port: number, timeoutMs = 10_000): Promise<void> {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      const res = await fetch(`http://127.0.0.1:${port}/dashboard/index.html`);
      if (res.ok) return;
    } catch {
      // not ready yet
    }
    await new Promise((r) => setTimeout(r, 200));
  }
  throw new Error(`Server did not start within ${timeoutMs}ms on port ${port}`);
}

/** Recursively copy a directory. */
function copyDirSync(src: string, dest: string) {
  fs.mkdirSync(dest, { recursive: true });
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);
    if (entry.isDirectory()) {
      copyDirSync(srcPath, destPath);
    } else {
      fs.copyFileSync(srcPath, destPath);
    }
  }
}

export interface ServerHandle {
  port: number;
  baseURL: string;
  process: ChildProcess;
  dataDir: string;
}

/**
 * Start the jevons web server with fixture data.
 *
 * The server runs an initial sync on startup which overwrites the data dir.
 * To preserve our fixtures, we:
 * 1. Create a temp data dir
 * 2. Start the server (sync writes empty data to temp dir)
 * 3. Copy fixture files into the temp dir (overwriting sync output)
 * 4. The dashboard's next poll picks up the fixture data
 */
export async function startServer(): Promise<ServerHandle> {
  // Regenerate fixtures so timestamps are relative to current time
  execSync(`node ${path.join(__dirname, 'generate-fixtures.js')}`, {
    cwd: REPO_ROOT,
    stdio: 'pipe',
  });

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'jevons-e2e-'));
  const port = await getFreePort();

  const proc = spawn(BINARY, ['web', '--port', String(port), '--interval', '9999'], {
    cwd: REPO_ROOT,
    env: {
      ...process.env,
      CLAUDE_USAGE_DATA_DIR: tmpDir,
      CLAUDE_USAGE_SOURCE_DIR: '/tmp/jevons-e2e-nosrc', // nonexistent → empty sync
      HOME: '/tmp/jevons-e2e-nohome', // prevent reading real ~/.claude.json
    },
    stdio: 'pipe',
  });

  proc.stderr?.on('data', (d: Buffer) => {
    if (process.env.DEBUG) process.stderr.write(`[jevons] ${d}`);
  });
  proc.stdout?.on('data', (d: Buffer) => {
    if (process.env.DEBUG) process.stdout.write(`[jevons] ${d}`);
  });

  await waitForServer(port);

  // Now overwrite the sync output with our fixture data
  copyDirSync(FIXTURE_DIR, tmpDir);

  return {
    port,
    baseURL: `http://127.0.0.1:${port}`,
    process: proc,
    dataDir: tmpDir,
  };
}

/** Stop the jevons server and clean up temp dir. */
export function stopServer(handle: ServerHandle): void {
  if (handle.process && !handle.process.killed) {
    handle.process.kill('SIGTERM');
  }
  try {
    fs.rmSync(handle.dataDir, { recursive: true, force: true });
  } catch {
    // best effort cleanup
  }
}

/**
 * Start the server with an empty data dir (no events, no projects).
 */
export async function startEmptyServer(): Promise<ServerHandle> {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'jevons-e2e-empty-'));
  const port = await getFreePort();

  const proc = spawn(BINARY, ['web', '--port', String(port), '--interval', '9999'], {
    cwd: REPO_ROOT,
    env: {
      ...process.env,
      CLAUDE_USAGE_DATA_DIR: tmpDir,
      CLAUDE_USAGE_SOURCE_DIR: '/tmp/jevons-e2e-nosrc',
      HOME: '/tmp/jevons-e2e-nohome',
    },
    stdio: 'pipe',
  });

  await waitForServer(port);

  return {
    port,
    baseURL: `http://127.0.0.1:${port}`,
    process: proc,
    dataDir: tmpDir,
  };
}
