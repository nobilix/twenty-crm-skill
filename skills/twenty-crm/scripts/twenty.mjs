#!/usr/bin/env node
// twenty-crm skill CLI — connect, check, and refresh a Twenty instance via ocli.
//
//   node twenty.mjs setup [--non-interactive --url <url> --token <key> [--with-metadata]]
//   node twenty.mjs preflight
//   node twenty.mjs refresh
//
// ocli owns the token, base URL, and resolved-spec cache under ~/.ocli. We keep
// only a pointer (the profile name[s]) in ~/.config/twenty-cli/config.json.

import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync, mkdirSync, chmodSync, rmSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';

process.removeAllListeners('warning'); // hush Node 18-20 fetch ExperimentalWarning

const HOME = homedir();
const CONFIG_DIR = process.env.TW_CONFIG_DIR ||
  join(process.env.XDG_CONFIG_HOME || join(HOME, '.config'), 'twenty-cli');
const CONFIG_FILE = join(CONFIG_DIR, 'config.json');
const OCLI_HOME = join(HOME, '.ocli');
const OCLI_INI = join(OCLI_HOME, 'profiles.ini');
const OCLI_PKG = 'openapi-to-cli@0.1.15'; // pinned; bump deliberately after re-testing the round-trip
const SCRIPT = fileURLToPath(import.meta.url);
const GUIDE = join(dirname(SCRIPT), '..', 'references', 'setup-guide.md');

const die = (msg) => { console.error(`twenty-cli: ${msg}`); process.exit(1); };

// Is <cmd> on PATH? (macOS/Linux; we don't target Windows.)
const onPath = (cmd) =>
  (process.env.PATH || '').split(':').some((d) => d && existsSync(join(d, cmd)));

// Run ocli from $HOME so its config resolves to ~/.ocli — ocli defaults to
// $PWD/.ocli when no profiles.ini exists yet. Throws ocli's stderr on failure
// (so callers' `finally` cleanup runs; main() turns it into a clean exit).
function ocli(args) {
  try {
    execFileSync('ocli', args, { cwd: HOME, stdio: ['ignore', 'ignore', 'pipe'] });
  } catch (e) {
    throw new Error(`ocli ${args.join(' ')} failed${e.stderr ? `: ${String(e.stderr).trim()}` : ''}`);
  }
}

// Profile names ocli resolves from <cwd> (empty on any error). Capturing the
// full list avoids the `ocli | grep -q` SIGPIPE trap the bash version hit.
function profilesFrom(cwd) {
  try {
    const out = execFileSync('ocli', ['profiles', 'list'], { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
    return out.split('\n').map((s) => s.trim()).filter(Boolean);
  } catch { return []; }
}

const readConfig = () => existsSync(CONFIG_FILE) ? JSON.parse(readFileSync(CONFIG_FILE, 'utf8')) : {};

// Value of <key> in [<section>] of ocli's INI (empty if absent). ocli writes
// plain `key=value` lines; the value is kept verbatim.
function iniGet(section, key) {
  if (!existsSync(OCLI_INI)) return '';
  let inSection = false;
  for (const line of readFileSync(OCLI_INI, 'utf8').split('\n')) {
    const sec = line.match(/^\[(.+)\]\s*$/);
    if (sec) { inSection = sec[1] === section; continue; }
    const eq = line.indexOf('=');
    if (inSection && eq > 0 && line.slice(0, eq).trim() === key) return line.slice(eq + 1).trim();
  }
  return '';
}

// Download an OpenAPI spec with the bearer token (ocli does not auth spec
// fetches itself). Validates HTTP 200 + an `openapi` field; returns the parsed doc.
async function fetchSpec(url, token) {
  let res;
  try { res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } }); }
  catch (e) { die(`fetch failed: ${url} (${e.message})`); }
  if (res.status !== 200) die(`HTTP ${res.status} from ${url} (token wrong/expired, or bad URL?)`);
  let spec;
  try { spec = await res.json(); } catch { die(`not valid JSON: ${url}`); }
  if (!spec || !spec.openapi) die(`not valid OpenAPI JSON: ${url}`);
  return spec;
}

// Download <specUrl> and (re)create the ocli profile <name> pointing at <base>.
async function addProfile(name, base, specUrl, token) {
  const spec = await fetchSpec(specUrl, token);
  const tmp = join(tmpdir(), `tw-spec-${randomUUID()}.json`);
  writeFileSync(tmp, JSON.stringify(spec));
  try {
    ocli(['profiles', 'add', name, '--api-base-url', base, '--openapi-spec', tmp, '--api-bearer-token', token]);
  } finally {
    rmSync(tmp, { force: true });
  }
  console.log(`✓ ${name}: ${Object.keys(spec.paths || {}).length} paths`);
}

// Local time as `2026-06-04T10:00:00+0400` (matches `date +%Y-%m-%dT%H:%M:%S%z`).
function localNow() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  const off = -d.getTimezoneOffset();
  const sign = off >= 0 ? '+' : '-';
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}` +
    `T${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}` +
    `${sign}${p(Math.floor(Math.abs(off) / 60))}${p(Math.abs(off) % 60)}`;
}

// Read one line from a TTY in raw mode, echoing input unless `secret` (the API
// key). readline isn't used: when its echo is muted, its line-refresh still
// erases a printed prompt via direct cursor writes, leaving a blank prompt.
function readLine(q, { secret = false } = {}) {
  return new Promise((resolve) => {
    const stdin = process.stdin;
    process.stdout.write(q);
    stdin.setRawMode(true);
    stdin.resume();
    let buf = '';
    const onData = (d) => {
      for (const ch of d.toString('utf8')) {
        if (ch === '\r' || ch === '\n') {
          stdin.setRawMode(false); stdin.pause(); stdin.off('data', onData);
          process.stdout.write('\n'); return resolve(buf);
        }
        if (ch === '\u0003') { process.stdout.write('\n'); process.exit(130); }  // Ctrl-C
        if (ch === '\u007f' || ch === '\b') {  // Backspace
          if (buf) { buf = buf.slice(0, -1); if (!secret) process.stdout.write('\b \b'); }
        } else {
          buf += ch;
          if (!secret) process.stdout.write(ch);
        }
      }
    };
    stdin.on('data', onData);
  });
}

// Fill in any missing values. Non-TTY stdin (piped/redirected) → take them as
// lines. A real terminal → prompt, reading the API key hidden.
async function askMissing(url, token) {
  if (!process.stdin.isTTY) {
    const lines = readFileSync(0, 'utf8').split('\n');
    if (!url) url = (lines.shift() || '').trim();
    if (!token) token = (lines.shift() || '').trim();
    return { url, token };
  }
  if (!url) url = (await readLine('Twenty URL — the address you open Twenty at (cloud: https://your-workspace.twenty.com, self-hosted: https://crm.your-company.com): ')).trim();
  if (!token) token = (await readLine('API key (Settings → APIs & Webhooks → + Create key): ', { secret: true })).trim();
  return { url, token };
}

// ── setup ────────────────────────────────────────────────────────────────────
async function cmdSetup(args) {
  let interactive = true, url = '', token = '', withMeta = false;
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--non-interactive') interactive = false;
    else if (a === '--url') url = args[++i];
    else if (a === '--token') token = args[++i];
    else if (a === '--with-metadata') withMeta = true;
    else if (a === '-h' || a === '--help') { console.log(SETUP_HELP); return; }
    else die(`unknown flag: ${a}`);
  }

  if (interactive && (!url || !token)) ({ url, token } = await askMissing(url, token));
  if (!url) die('missing --url');
  if (!token) die('missing --token');
  url = url.replace(/\/+$/, '');

  // Reuse the recorded profile (idempotent re-setup); else `twenty`; else, if
  // another ocli tool already owns `twenty`, pick a non-colliding name.
  let profile = readConfig().profile;
  if (!profile) {
    const taken = profilesFrom(HOME);
    profile = 'twenty';
    if (taken.includes(profile)) { profile = 'twenty-crm'; for (let i = 2; taken.includes(profile); i++) profile = `twenty-${i}`; }
  }
  const metaProfile = `${profile}-meta`;

  process.umask(0o077); // ~/.ocli files born 0600/0700 (chmod below is a fallback)
  mkdirSync(OCLI_HOME, { recursive: true });

  console.log(`→ validating token against ${url} ...`);
  await addProfile(profile, `${url}/rest`, `${url}/rest/open-api/core`, token);
  if (withMeta) {
    await addProfile(metaProfile, `${url}/rest/metadata`, `${url}/rest/open-api/metadata`, token);
    ocli(['use', profile]); // leave the core profile active
  }
  try { chmodSync(OCLI_INI, 0o600); } catch { /* fallback only */ }

  mkdirSync(CONFIG_DIR, { recursive: true });
  const cfg = withMeta ? { profile, metadata_profile: metaProfile } : { profile };
  writeFileSync(CONFIG_FILE, `${JSON.stringify(cfg, null, 2)}\n`);

  console.log(`\n✓ Setup complete — '${profile}' is connected.\n\n` +
    'Now just ask your agent in plain language, e.g.:\n' +
    '  • "How many people are in my CRM?"\n' +
    '  • "Find the most recently added company."\n' +
    '  • "List my open opportunities in the PROPOSAL stage."');
}

// ── preflight ────────────────────────────────────────────────────────────────
function cmdPreflight() {
  const errors = [];
  for (const [cmd, hint] of [
    ['node', 'Node.js ≥18 — https://nodejs.org'],
    ['ocli', `install: npm i -g ${OCLI_PKG}`],
    ['jq', 'install: brew install jq'],
  ]) if (!onPath(cmd)) errors.push(`missing dependency: ${cmd} (${hint})`);

  let profile = '';
  if (!errors.length) {
    if (!existsSync(CONFIG_FILE)) errors.push(`not configured (no ${CONFIG_FILE})`);
    else {
      try { profile = (JSON.parse(readFileSync(CONFIG_FILE, 'utf8')).profile) || ''; }
      catch { errors.push(`${CONFIG_FILE} is not valid JSON`); }
      if (existsSync(CONFIG_FILE) && !profile && !errors.length) errors.push(`config file has no 'profile': ${CONFIG_FILE}`);
    }
  }

  // Does `ocli` resolve our profile from the agent's cwd? Mirrors what a bare
  // `ocli <cmd>` sees, so it catches a $PWD/.ocli that shadows ~/.ocli.
  if (!errors.length && !profilesFrom(process.cwd()).includes(profile)) {
    errors.push(profilesFrom(HOME).includes(profile)
      ? `profile '${profile}' exists in ~/.ocli but is hidden by a local ${join(process.cwd(), '.ocli')} — remove it or run the skill from another directory`
      : `ocli profile '${profile}' not found — (re)run setup`);
  }

  if (!errors.length) {
    const cfg = readConfig();
    const out = [
      'STATUS=ready',
      `PROFILE=${profile}`,
      `URL=${iniGet(profile, 'api_base_url').replace(/\/rest$/, '')}`,
    ];
    if (cfg.metadata_profile) out.push(`METADATA=${cfg.metadata_profile}`);
    // The user's local timezone + current local time. Twenty stores datetimes in
    // UTC and renders them in the user's zone, so a wall-clock date ("10am",
    // "tomorrow") must be read in this zone and converted to UTC before writing.
    out.push(`TZ=${Intl.DateTimeFormat().resolvedOptions().timeZone}`, `NOW=${localNow()}`);
    console.log(out.join('\n'));
    if (existsSync(join(process.cwd(), '.ocli')))
      console.error(`WARN=a local ${join(process.cwd(), '.ocli')} is present and overrides ~/.ocli for commands run here`);
    return;
  }

  console.error('STATUS=not_ready');
  for (const e of errors) console.error(`ERROR=${e}`);
  console.error(`
This skill isn't configured yet. Recommend the user run setup in their own
terminal — the API key is typed as hidden input, so it never enters the chat:

    node ${SCRIPT} setup

It asks for two things: the URL they open Twenty at (cloud:
https://your-workspace.twenty.com, self-hosted: https://crm.your-company.com —
not api.twenty.com; setup appends /rest) and an API key (Settings → APIs &
Webhooks → Create API Key → copy, shown once).

Full step-by-step: ${GUIDE}`);
  process.exit(1);
}

// ── refresh ──────────────────────────────────────────────────────────────────
async function cmdRefresh() {
  const { profile, metadata_profile: metaProfile } = readConfig();
  if (!profile) die('not configured — run setup first');
  const base = iniGet(profile, 'api_base_url');     // <url>/rest
  const token = iniGet(profile, 'api_bearer_token');
  if (!base) die(`no api_base_url for profile '${profile}' in ${OCLI_INI}`);
  if (!token) die(`no api_bearer_token for profile '${profile}' in ${OCLI_INI}`);

  process.umask(0o077);
  await addProfile(profile, base, `${base}/open-api/core`, token);
  if (metaProfile) {
    await addProfile(metaProfile, `${base}/metadata`, `${base}/open-api/metadata`, token);
    ocli(['use', profile]); // leave the core profile active
  }
  try { chmodSync(OCLI_INI, 0o600); } catch { /* fallback only */ }
  console.log('✓ schema refreshed');
}

const SETUP_HELP = `Connect a Twenty CRM instance via ocli.

  node twenty.mjs setup                                  # interactive (key never enters chat)
  node twenty.mjs setup --non-interactive --url <url> --token <key> [--with-metadata]

--with-metadata also creates the schema-admin profile (<name>-meta; rarely needed).`;

async function main() {
  const [cmd, ...rest] = process.argv.slice(2);
  if (cmd === 'setup') return cmdSetup(rest);
  if (cmd === 'preflight') return cmdPreflight();
  if (cmd === 'refresh') return cmdRefresh();
  if (cmd === '-h' || cmd === '--help' || cmd === undefined)
    return console.log('Usage: node twenty.mjs <setup|preflight|refresh> [options]');
  die(`unknown command: ${cmd}`);
}

main().catch((e) => die(e?.message || String(e)));
