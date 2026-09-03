// Writes per-company opencode auth.json homes from Paperclip company secrets.
// Runs as an initContainer (node image = paperclip app image). Decrypts
// local_encrypted_v1 material directly from the DB (the HTTP API never
// exposes secret values to board operators).
const { createDecipheriv } = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

// pnpm virtual store: pg is not hoisted, resolve it from .pnpm
function loadPg() {
  const candidates = ["/app/node_modules/pg", "/app/server/node_modules/pg"];
  for (const c of candidates) {
    if (fs.existsSync(c)) return require(c);
  }
  const pnpmDir = "/app/node_modules/.pnpm";
  const hit = fs.readdirSync(pnpmDir).find((d) => /^pg@/.test(d));
  if (!hit) throw new Error("pg module not found in pnpm store");
  return require(path.join(pnpmDir, hit, "node_modules", "pg"));
}
const { Client } = loadPg();

const HOME_BASE = process.env.COMPANY_HOMES_BASE || "/paperclip/.company-homes";
const MASTER_KEY_FILE =
  process.env.PAPERCLIP_SECRETS_MASTER_KEY_FILE ||
  "/paperclip/instances/default/secrets/master.key";
const AUTH_UID = parseInt(process.env.AUTH_UID || "1000", 10);
const AUTH_GID = parseInt(process.env.AUTH_GID || "1000", 10);

const PADDLE_SKILLS = [
  "paddle-billing-history", "paddle-catalog-setup", "paddle-checkout-web",
  "paddle-customer-portal", "paddle-pricing-pages", "paddle-sandbox-testing",
  "paddle-subscription-cancel", "paddle-subscription-sync",
  "paddle-subscription-update", "paddle-webhooks",
];
const PADDLE_SKILLS_BASE = "https://developer.paddle.com/.well-known/skills";

function decodeMasterKey(raw) {
  const trimmed = raw.trim();
  if (/^[A-Fa-f0-9]{64}$/.test(trimmed)) return Buffer.from(trimmed, "hex");
  const b64 = Buffer.from(trimmed, "base64");
  if (b64.length === 32) return b64;
  if (Buffer.byteLength(trimmed, "utf8") === 32) return Buffer.from(trimmed, "utf8");
  throw new Error("invalid master key encoding");
}

function decrypt(masterKey, material) {
  const decipher = createDecipheriv("aes-256-gcm", masterKey, Buffer.from(material.iv, "base64"));
  decipher.setAuthTag(Buffer.from(material.tag, "base64"));
  return Buffer.concat([decipher.update(Buffer.from(material.ciphertext, "base64")), decipher.final()]).toString("utf8");
}

function chownSafe(p) {
  try { fs.chownSync(p, AUTH_UID, AUTH_GID); } catch (_) {}
}

async function main() {
  const client = new Client({ connectionString: process.env.DATABASE_URL });
  await client.connect();
  const masterKey = decodeMasterKey(fs.readFileSync(MASTER_KEY_FILE, "utf8"));

  const res = await client.query(
    `SELECT cs.company_id, cs.key, csv.material
     FROM company_secrets cs
     JOIN company_secret_versions csv
       ON csv.secret_id = cs.id AND csv.status = 'current'
     WHERE cs.key IN ('opencode_go_api_key', 'paddle_sandbox_api_key', 'paddle-sandbox-api-key')
       AND cs.deleted_at IS NULL`,
  );

  const byCompany = {};
  let globalAuthWritten = false;
  for (const row of res.rows) {
    const value = decrypt(masterKey, row.material);
    byCompany[row.company_id] = byCompany[row.company_id] || {};
    byCompany[row.company_id][row.key.replace(/-/g, "_")] = value;
    if (row.key.startsWith("opencode_go")) {
      const home = path.join(HOME_BASE, row.company_id);
      const authDir = path.join(home, ".local", "share", "opencode");
      fs.mkdirSync(authDir, { recursive: true });
      const authPath = path.join(authDir, "auth.json");
      fs.writeFileSync(authPath + ".tmp", JSON.stringify({ "opencode-go": { type: "api", key: value } }, null, 2));
      fs.renameSync(authPath + ".tmp", authPath);
      chownSafe(home); chownSafe(path.join(home, ".local")); chownSafe(authDir); chownSafe(authPath);
      console.log(`[company-auth] wrote ${authPath}`);
      // Server-level auth.json for UI model-catalog discovery only; agent
      // runs always override HOME per company via secret bindings.
      if (!globalAuthWritten) {
        const gDir = "/paperclip/.local/share/opencode";
        fs.mkdirSync(gDir, { recursive: true });
        fs.writeFileSync(gDir + "/auth.json.tmp", JSON.stringify({ "opencode-go": { type: "api", key: value } }, null, 2));
        fs.renameSync(gDir + "/auth.json.tmp", gDir + "/auth.json");
        chownSafe(gDir); chownSafe(gDir + "/auth.json");
        globalAuthWritten = true;
        console.log(`[company-auth] wrote global ${gDir}/auth.json (model discovery)`);
      }
    }
  }

  // Per-company opencode.json (Paddle MCP servers) + official Paddle skills.
  for (const [companyId, secrets] of Object.entries(byCompany)) {
    const home = path.join(HOME_BASE, companyId);
    const cfgDir = path.join(home, ".config", "opencode");
    fs.mkdirSync(cfgDir, { recursive: true });
    const cfgPath = path.join(cfgDir, "opencode.json");
    let cfg = {};
    try { cfg = JSON.parse(fs.readFileSync(cfgPath, "utf8")); } catch (_) {}
    cfg.mcp = cfg.mcp || {};
    if (secrets.paddle_sandbox_api_key) {
      cfg.mcp["paddle-sandbox"] = {
        type: "remote",
        url: "https://sandbox-mcp.paddle.com/mcp",
        headers: { Authorization: `Bearer ${secrets.paddle_sandbox_api_key}` },
      };
      cfg.mcp["paddle-docs"] = { type: "remote", url: "https://paddlehq.mcp.kapa.ai" };
      const skillsDir = path.join(cfgDir, "skills");
      for (const slug of PADDLE_SKILLS) {
        try {
          const r = await fetch(`${PADDLE_SKILLS_BASE}/${slug}/SKILL.md`);
          if (!r.ok) { console.log(`[company-auth] skill ${slug}: HTTP ${r.status}`); continue; }
          const dir = path.join(skillsDir, slug);
          fs.mkdirSync(dir, { recursive: true });
          fs.writeFileSync(path.join(dir, "SKILL.md"), await r.text());
        } catch (e) {
          console.log(`[company-auth] skill ${slug}: ${e.message}`);
        }
      }
      chownSafe(home);
      console.log(`[company-auth] wrote ${cfgPath} (paddle MCP + skills)`);
    }
    fs.writeFileSync(cfgPath + ".tmp", JSON.stringify(cfg, null, 2));
    fs.renameSync(cfgPath + ".tmp", cfgPath);
    chownSafe(cfgDir); chownSafe(cfgPath);
  }

  // Ensure a home dir exists for every company (HOME target must exist).
  const companies = await client.query("SELECT id FROM companies");
  for (const c of companies.rows) {
    const home = path.join(HOME_BASE, c.id);
    fs.mkdirSync(home, { recursive: true });
    chownSafe(home);
    if (!byCompany[c.id]) console.log(`[company-auth] empty home for ${c.id}`);
  }
  await client.end();
}

main().catch((err) => { console.error("[company-auth] fatal:", err.message); process.exit(1); });
