#!/usr/bin/env node
// Runs directly under Node 24 type stripping, so only erasable TypeScript
// syntax is allowed here (no enums, namespaces, or parameter properties).

import { execFile } from 'node:child_process'
import { readdir, stat } from 'node:fs/promises'
import { homedir } from 'node:os'
import { join } from 'node:path'
import { promisify } from 'node:util'

const execFileAsync = promisify(execFile)

const REPOS_DIR = process.env.REPOS_DIR ?? join(homedir(), 'repos')
const CONCURRENCY = 16
const NETWORK_CONCURRENCY = 8

const NOT_GIT = '<not-git>'
const LOCAL = '<local>'

const useColor = process.stdout.isTTY === true && !process.env.NO_COLOR
const color = (code: string, s: string) => (useColor ? `\x1b[${code}m${s}\x1b[0m` : s)
const dim = (s: string) => color('2', s)
const red = (s: string) => color('31', s)
const green = (s: string) => color('32', s)
const yellow = (s: string) => color('33', s)
const cyan = (s: string) => color('36', s)

interface RepoStatus {
  name: string
  org: string
  remote: string | null
  branch: string
  defaultBranch: string | null
  onDefaultBranch: boolean
  dirty: boolean
}

async function git(cwd: string, args: string[]): Promise<string | null> {
  try {
    const { stdout } = await execFileAsync('git', args, { cwd, maxBuffer: 32 * 1024 * 1024 })
    return stdout
  } catch {
    return null
  }
}

async function isDir(path: string): Promise<boolean> {
  try {
    return (await stat(path)).isDirectory()
  } catch {
    return false
  }
}

function orgFromUrl(url: string): string {
  const trimmed = url.trim().replace(/\.git$/, '')
  const scp = /^[^/]+@[^:]+:(.+)$/.exec(trimmed)
  const path = scp ? scp[1] : trimmed.replace(/^[a-z+]+:\/\/[^/]+\//i, '')
  const parts = path.split('/').filter(Boolean)
  return parts.length >= 2 ? parts[parts.length - 2] : LOCAL
}

// Prefers a remote literally named "upstream", then "origin"; anything else
// counts as having no upstream.
async function resolveRemote(dir: string): Promise<{ remote: string | null; org: string }> {
  const out = await git(dir, ['config', '--get-regexp', '^remote\\..*\\.url'])
  if (out === null) return { remote: null, org: LOCAL }
  const urls = new Map<string, string>()
  for (const line of out.split('\n')) {
    const match = /^remote\.(.+)\.url (.+)$/.exec(line.trim())
    if (match) urls.set(match[1], match[2])
  }
  for (const name of ['upstream', 'origin']) {
    const url = urls.get(name)
    if (url) return { remote: name, org: orgFromUrl(url) }
  }
  return { remote: null, org: LOCAL }
}

async function defaultBranch(dir: string, remote: string | null): Promise<string | null> {
  if (remote === null) {
    for (const candidate of ['main', 'master', 'develop']) {
      if (await git(dir, ['rev-parse', '--verify', '--quiet', `refs/heads/${candidate}`])) {
        return candidate
      }
    }
    return null
  }
  const head = await git(dir, ['symbolic-ref', '--short', `refs/remotes/${remote}/HEAD`])
  if (head) return head.trim().replace(`${remote}/`, '')
  for (const candidate of ['main', 'master', 'develop']) {
    if (await git(dir, ['rev-parse', '--verify', '--quiet', `refs/remotes/${remote}/${candidate}`])) {
      return candidate
    }
  }
  return null
}

async function inspect(name: string): Promise<RepoStatus> {
  const dir = join(REPOS_DIR, name)
  const status = await git(dir, ['status', '--porcelain=v2', '--branch'])
  if (status === null) {
    return {
      name,
      org: NOT_GIT,
      remote: null,
      branch: '-',
      defaultBranch: null,
      onDefaultBranch: true,
      dirty: false,
    }
  }

  let branch = '-'
  let dirty = false
  for (const line of status.split('\n')) {
    if (line.startsWith('# branch.head ')) {
      branch = line.slice('# branch.head '.length)
    } else if (line.length > 0 && !line.startsWith('#')) {
      dirty = true
    }
  }
  if (branch === '(detached)') {
    const sha = await git(dir, ['rev-parse', '--short', 'HEAD'])
    branch = `(detached ${sha ? sha.trim() : '?'})`
  }

  const { remote, org } = await resolveRemote(dir)
  const def = await defaultBranch(dir, remote)

  return {
    name,
    org,
    remote,
    branch,
    defaultBranch: def,
    onDefaultBranch: def !== null && branch === def,
    dirty,
  }
}

async function mapLimit<T, R>(items: T[], limit: number, fn: (item: T) => Promise<R>): Promise<R[]> {
  const results = new Array<R>(items.length)
  let next = 0
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length) {
      const index = next++
      results[index] = await fn(items[index])
    }
  })
  await Promise.all(workers)
  return results
}

async function collect(orgFilter: string | null): Promise<RepoStatus[]> {
  const entries = await readdir(REPOS_DIR, { withFileTypes: true })
  const names = entries
    .filter((e) => e.isDirectory() || e.isSymbolicLink())
    .map((e) => e.name)
    .filter((n) => !n.startsWith('.'))
    .sort()

  const dirs = await mapLimit(names, CONCURRENCY, async (n) =>
    (await isDir(join(REPOS_DIR, n))) ? n : null,
  )
  const repos = await mapLimit(
    dirs.filter((n) => n !== null),
    CONCURRENCY,
    inspect,
  )

  return orgFilter === null ? repos : repos.filter((r) => r.org === orgFilter)
}

async function statusCommand(orgFilter: string | null): Promise<number> {
  const shown = await collect(orgFilter)
  if (shown.length === 0) {
    console.log(dim('No repos matched.'))
    return 0
  }

  const width = (pick: (r: RepoStatus) => string) =>
    Math.max(...shown.map((r) => pick(r).length))
  const nameWidth = width((r) => r.name)
  const orgWidth = width((r) => r.org)
  const branchWidth = width((r) => r.branch)

  for (const r of shown) {
    const branch = r.onDefaultBranch ? dim(r.branch) : cyan(r.branch)
    const state = r.org === NOT_GIT ? dim('-') : r.dirty ? yellow('dirty') : green('clean')
    console.log(
      `${r.name.padEnd(nameWidth)}  ${dim(r.org.padEnd(orgWidth))}  ` +
        `${branch}${' '.repeat(branchWidth - r.branch.length)}  ${state}`,
    )
  }
  return 0
}

async function gitRun(cwd: string, args: string[]): Promise<{ ok: boolean; output: string }> {
  try {
    const { stdout, stderr } = await execFileAsync('git', args, {
      cwd,
      maxBuffer: 32 * 1024 * 1024,
    })
    return { ok: true, output: (stdout + stderr).trim() }
  } catch (err) {
    const e = err as { stdout?: string; stderr?: string; message?: string }
    return { ok: false, output: ((e.stdout ?? '') + (e.stderr ?? e.message ?? '')).trim() }
  }
}

function firstLine(text: string): string {
  const line = text.split('\n').find((l) => l.trim().length > 0)
  return line === undefined ? '' : line.trim()
}

async function networkCommand(
  label: string,
  orgFilter: string | null,
  plan: (r: RepoStatus) => { skip: string } | { args: string[] },
): Promise<number> {
  const repos = await collect(orgFilter)
  if (repos.length === 0) {
    console.log(dim('No repos matched.'))
    return 0
  }
  const nameWidth = Math.max(...repos.map((r) => r.name.length))

  let ok = 0
  let skipped = 0
  let failed = 0

  await mapLimit(repos, NETWORK_CONCURRENCY, async (r) => {
    const decision = plan(r)
    const prefix = r.name.padEnd(nameWidth)
    if ('skip' in decision) {
      skipped++
      console.log(`${prefix}  ${yellow('skip')}  ${dim(decision.skip)}`)
      return
    }
    const result = await gitRun(join(REPOS_DIR, r.name), decision.args)
    const detail = firstLine(result.output)
    if (result.ok) {
      ok++
      console.log(`${prefix}  ${green(label)}  ${dim(detail)}`)
    } else {
      failed++
      console.log(`${prefix}  ${red('failed')}  ${detail}`)
    }
  })

  console.log(dim(`\n${ok} ${label}, ${skipped} skipped, ${failed} failed`))
  return failed > 0 ? 1 : 0
}

function fetchCommand(orgFilter: string | null): Promise<number> {
  return networkCommand('fetched', orgFilter, (r) => {
    if (r.org === NOT_GIT) return { skip: 'not a git repo' }
    if (r.remote === null) return { skip: 'no upstream remote' }
    return { args: ['fetch', '--prune', r.remote] }
  })
}

// Pull is deliberately conservative: anything `status` would flag as dirty or
// off its default branch is left alone rather than risking a messy merge.
function pullCommand(orgFilter: string | null): Promise<number> {
  return networkCommand('pulled', orgFilter, (r) => {
    if (r.org === NOT_GIT) return { skip: 'not a git repo' }
    if (r.remote === null) return { skip: 'no upstream remote' }
    if (r.dirty) return { skip: 'dirty working directory' }
    if (r.defaultBranch === null) return { skip: 'could not determine default branch' }
    if (!r.onDefaultBranch) {
      return { skip: `on non-default branch "${r.branch}" (default: ${r.defaultBranch})` }
    }
    return { args: ['pull', '--ff-only', r.remote, r.branch] }
  })
}

function usage(): void {
  console.log(`Usage: repos.ts [-o|--org <org>] <command>

Commands:
  status, s    List each repo's upstream org, branch, and working-dir state
  fetch, f     Fetch (with --prune) from each repo's upstream remote
  pull, p      Fast-forward pull; skips dirty repos and non-default branches

Options:
  -o, --org    Only show repos whose upstream org matches (${LOCAL}, ${NOT_GIT} allowed)
  -h, --help   Show this help

Repos directory: ${REPOS_DIR} (override with REPOS_DIR)`)
}

async function main(argv: string[]): Promise<number> {
  let orgFilter: string | null = null
  let command: string | null = null

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg === '-o' || arg === '--org') {
      orgFilter = argv[++i] ?? null
      if (orgFilter === null) {
        console.error(red('Error: -o/--org needs a value'))
        return 2
      }
    } else if (arg.startsWith('--org=')) {
      orgFilter = arg.slice('--org='.length)
    } else if (arg === '-h' || arg === '--help') {
      usage()
      return 0
    } else if (command === null) {
      command = arg
    } else {
      console.error(red(`Error: unexpected argument "${arg}"`))
      return 2
    }
  }

  if (command === null) {
    usage()
    return 2
  }
  if (command === 'status' || command === 's') {
    return await statusCommand(orgFilter)
  }
  if (command === 'fetch' || command === 'f') {
    return await fetchCommand(orgFilter)
  }
  if (command === 'pull' || command === 'p') {
    return await pullCommand(orgFilter)
  }
  console.error(red(`Error: unknown command "${command}"`))
  usage()
  return 2
}

process.exitCode = await main(process.argv.slice(2))
