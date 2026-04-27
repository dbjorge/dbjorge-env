#!/usr/bin/env node
/* eslint-disable no-console */

/**
 * Analyzes GitHub Actions usage from a CSV exported from
 *   https://github.com/orgs/<org>/actions/metrics/usage
 *
 * Per GitHub docs, that page reports wall-clock job minutes — it does NOT
 * apply billing multipliers. This script sums those wall-clock minutes and,
 * for a rough cost estimate, multiplies them by a per-runner USD/minute rate
 * (pattern-matched against the "Runner labels" column).
 *
 * Usage:
 *   node gh-actions-usage.js <csv-path> [options]
 *     --top <N>               Top N entries per table (default: 10)
 *     --cost-per-minute <N>   Force a single USD/min rate for all rows
 *                             (overrides the per-runner rate table)
 *     --rates <path>          JSON file overriding the default rate table:
 *                             [{"pattern": "macos", "rate": 0.08, "label": "..."}]
 *     --json                  Emit JSON summary instead of tables
 */

const fs = require('node:fs')

// Best-effort USD/min rates keyed by regex patterns on the "Runner labels"
// field. First match wins, so order from most specific to least specific.
// These reflect published GitHub-hosted runner pricing as of mid-2025 and
// will drift — override with --rates for precision.
const DEFAULT_RATES = [
  { pattern: /xlarge/i, rate: 0.16, label: 'macOS xlarge (Apple Silicon, 12-core)' },
  { pattern: /^macos.*intel/i, rate: 0.08, label: 'macOS Intel 3-core' },
  { pattern: /^macos/i, rate: 0.08, label: 'macOS standard 3-core' },
  { pattern: /windows.*64.?core/i, rate: 0.512, label: 'Windows 64-core larger' },
  { pattern: /windows.*32.?core/i, rate: 0.256, label: 'Windows 32-core larger' },
  { pattern: /windows.*16.?core/i, rate: 0.128, label: 'Windows 16-core larger' },
  { pattern: /windows.*8.?core/i, rate: 0.064, label: 'Windows 8-core larger' },
  { pattern: /windows.*4.?core/i, rate: 0.032, label: 'Windows 4-core larger' },
  { pattern: /^windows/i, rate: 0.016, label: 'Windows standard 2-core' },
  { pattern: /64.?core/i, rate: 0.256, label: 'Linux 64-core larger' },
  { pattern: /32.?core/i, rate: 0.128, label: 'Linux 32-core larger' },
  { pattern: /16.?core/i, rate: 0.064, label: 'Linux 16-core larger' },
  { pattern: /8.?core/i, rate: 0.032, label: 'Linux 8-core larger' },
  { pattern: /4.?core/i, rate: 0.016, label: 'Linux 4-core larger' },
  { pattern: /arm/i, rate: 0.005, label: 'Linux ARM 2-core' },
  { pattern: /ubuntu|linux/i, rate: 0.008, label: 'Linux standard 2-core' }
]

function lookupRate(runnerLabel, rates) {
  for (const r of rates) {
    if (r.pattern.test(runnerLabel)) return r
  }
  return { pattern: null, rate: 0, label: 'UNKNOWN (counted at $0)' }
}

function parseCsv(text) {
  const rows = []
  let row = []
  let field = ''
  let inQuotes = false
  for (let i = 0; i < text.length; i++) {
    const c = text[i]
    if (inQuotes) {
      if (c === '"') {
        if (text[i + 1] === '"') {
          field += '"'
          i++
        } else {
          inQuotes = false
        }
      } else {
        field += c
      }
    } else {
      if (c === '"') inQuotes = true
      else if (c === ',') { row.push(field); field = '' }
      else if (c === '\n') { row.push(field); rows.push(row); row = []; field = '' }
      else if (c === '\r') { /* ignore */ }
      else field += c
    }
  }
  if (field !== '' || row.length > 0) { row.push(field); rows.push(row) }
  return rows
}

// GitHub's CSV export armors text fields by wrapping each value so that after
// CSV unquoting it still contains a literal leading `"'` and trailing `"`
// (prevents spreadsheet formula injection). Strip that.
function unarmor(s) {
  if (typeof s !== 'string') return s
  if (s.startsWith('"\'') && s.endsWith('"')) return s.slice(2, -1)
  if (s.startsWith("'")) return s.slice(1)
  return s
}

function parseArgs(argv) {
  const opts = {
    csvPath: null,
    top: 10,
    costPerMinute: null,
    ratesPath: null,
    json: false
  }
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]
    const next = () => {
      if (i + 1 >= argv.length) {
        console.error(`Error: ${a} requires a value`)
        process.exit(1)
      }
      return argv[++i]
    }
    if (a === '--top') opts.top = Number(next())
    else if (a === '--cost-per-minute') opts.costPerMinute = Number(next())
    else if (a === '--rates') opts.ratesPath = next()
    else if (a === '--json') opts.json = true
    else if (a === '--help' || a === '-h') {
      console.log(`Usage: node gh-actions-usage.js <csv-path> [options]
  --top <N>               Top N entries per table (default: 10)
  --cost-per-minute <N>   Force a single USD/min rate for all rows
                          (overrides per-runner rate table)
  --rates <path>          JSON file of [{pattern, rate, label}] overriding defaults
  --json                  Emit JSON summary instead of tables

The CSV is downloaded from:
  https://github.com/orgs/<org>/actions/metrics/usage
`)
      process.exit(0)
    } else if (!a.startsWith('--')) {
      if (opts.csvPath) {
        console.error('Error: multiple CSV paths provided')
        process.exit(1)
      }
      opts.csvPath = a
    } else {
      console.error(`Error: unknown option ${a}`)
      process.exit(1)
    }
  }
  if (!opts.csvPath) {
    console.error('Error: CSV path required. See --help.')
    process.exit(1)
  }
  if (!Number.isFinite(opts.top) || opts.top <= 0) {
    console.error('Error: --top must be a positive number')
    process.exit(1)
  }
  if (opts.costPerMinute !== null && (!Number.isFinite(opts.costPerMinute) || opts.costPerMinute < 0)) {
    console.error('Error: --cost-per-minute must be a non-negative number')
    process.exit(1)
  }
  return opts
}

function loadRates(ratesPath) {
  if (!ratesPath) return DEFAULT_RATES
  const parsed = JSON.parse(fs.readFileSync(ratesPath, 'utf8'))
  return parsed.map(r => ({
    pattern: new RegExp(r.pattern, r.flags || 'i'),
    rate: r.rate,
    label: r.label || r.pattern
  }))
}

function bump(bucket, key, minutes, cost, runs, runnerKey) {
  const e = bucket.get(key) || { key, minutes: 0, cost: 0, runs: 0, byRunner: {} }
  e.minutes += minutes
  e.cost += cost
  e.runs += runs
  e.byRunner[runnerKey] = (e.byRunner[runnerKey] || 0) + minutes
  bucket.set(key, e)
}

function topList(bucket, n) {
  return Array.from(bucket.values())
    .sort((a, b) => b.minutes - a.minutes)
    .slice(0, n)
}

function pad(s, n, right = false) {
  s = String(s)
  if (s.length >= n) return s
  const fill = ' '.repeat(n - s.length)
  return right ? fill + s : s + fill
}

function truncate(s, n) {
  if (s.length <= n) return s
  return s.slice(0, n - 1) + '…'
}

function fmtUsd(n) {
  return `$${n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
}

function printTable(title, rows) {
  console.log(title)
  console.log('='.repeat(title.length))
  if (rows.length === 0) {
    console.log('(no data)\n')
    return
  }
  const nameWidth = Math.min(90, Math.max(4, ...rows.map(r => r.key.length)))
  const header =
    `${pad('name', nameWidth)}  ` +
    `${pad('wall min', 12, true)}  ` +
    `${pad('~cost', 10, true)}  ` +
    `${pad('runs', 8, true)}  runners`
  console.log(header)
  console.log('-'.repeat(header.length))
  for (const r of rows) {
    const runners = Object.entries(r.byRunner)
      .sort((a, b) => b[1] - a[1])
      .map(([k, v]) => `${k}:${Math.round(v).toLocaleString()}`)
      .join(' ')
    console.log(
      `${pad(truncate(r.key, nameWidth), nameWidth)}  ` +
      `${pad(Math.round(r.minutes).toLocaleString(), 12, true)}  ` +
      `${pad(fmtUsd(r.cost), 10, true)}  ` +
      `${pad(r.runs.toLocaleString(), 8, true)}  ${runners}`
    )
  }
  console.log('')
}

function findColumn(headers, candidates) {
  const normalized = headers.map(h => unarmor(h).trim().toLowerCase())
  for (const c of candidates) {
    const idx = normalized.indexOf(c.toLowerCase())
    if (idx !== -1) return idx
  }
  return -1
}

function main() {
  const opts = parseArgs(process.argv.slice(2))
  const rates = loadRates(opts.ratesPath)
  const text = fs.readFileSync(opts.csvPath, 'utf8')
  const rows = parseCsv(text).filter(r => r.length > 1 || (r.length === 1 && r[0] !== ''))
  if (rows.length < 2) {
    console.error('Error: CSV has no data rows')
    process.exit(1)
  }
  const headers = rows[0]

  const idx = {
    job: findColumn(headers, ['Job']),
    workflow: findColumn(headers, ['Workflow']),
    repo: findColumn(headers, ['Source repository', 'Repository']),
    minutes: findColumn(headers, ['Total minutes', 'Minutes']),
    runs: findColumn(headers, ['Job runs', 'Runs']),
    runnerType: findColumn(headers, ['Runner type']),
    runnerLabels: findColumn(headers, ['Runner labels'])
  }
  for (const [k, v] of Object.entries(idx)) {
    if (v === -1 && k !== 'runnerType' && k !== 'runnerLabels') {
      console.error(`Error: required column not found in CSV: ${k}`)
      console.error(`Headers seen: ${headers.map(unarmor).join(', ')}`)
      process.exit(1)
    }
  }

  const byRepo = new Map()
  const byWorkflow = new Map()
  const byJob = new Map()
  const byRunnerLabel = new Map()
  let totalMinutes = 0
  let totalCost = 0
  let totalRuns = 0

  for (let r = 1; r < rows.length; r++) {
    const row = rows[r]
    if (row.length < headers.length) continue
    const job = unarmor(row[idx.job])
    const workflow = unarmor(row[idx.workflow])
    const repo = unarmor(row[idx.repo])
    const minutes = Number(row[idx.minutes]) || 0
    const runs = Number(row[idx.runs]) || 0
    const runnerType = idx.runnerType >= 0 ? unarmor(row[idx.runnerType]) : ''
    const runnerLabels = idx.runnerLabels >= 0 ? unarmor(row[idx.runnerLabels]) : ''

    const runnerKey = runnerLabels || runnerType || 'unknown'
    const matched = opts.costPerMinute !== null
      ? { rate: opts.costPerMinute, label: `flat ${fmtUsd(opts.costPerMinute)}/min` }
      : lookupRate(runnerKey, rates)
    const cost = minutes * matched.rate

    totalMinutes += minutes
    totalCost += cost
    totalRuns += runs

    bump(byRepo, repo, minutes, cost, runs, runnerKey)
    bump(byWorkflow, `${repo} :: ${workflow}`, minutes, cost, runs, runnerKey)
    bump(byJob, `${repo} :: ${workflow} :: ${job}`, minutes, cost, runs, runnerKey)

    const e = byRunnerLabel.get(runnerKey) || {
      key: runnerKey,
      minutes: 0,
      cost: 0,
      runs: 0,
      rate: matched.rate,
      rateLabel: matched.label
    }
    e.minutes += minutes
    e.cost += cost
    e.runs += runs
    byRunnerLabel.set(runnerKey, e)
  }

  const summary = {
    csv: opts.csvPath,
    costOverridePerMinute: opts.costPerMinute,
    totals: {
      wallMinutes: totalMinutes,
      estimatedCostUsd: totalCost,
      runs: totalRuns,
      distinctRepos: byRepo.size,
      distinctWorkflows: byWorkflow.size,
      distinctJobs: byJob.size
    },
    byRunnerLabel: Array.from(byRunnerLabel.values()).sort((a, b) => b.minutes - a.minutes),
    topRepos: topList(byRepo, opts.top),
    topWorkflows: topList(byWorkflow, opts.top),
    topJobs: topList(byJob, opts.top)
  }

  if (opts.json) {
    console.log(JSON.stringify(summary, null, 2))
    return
  }

  console.log('')
  console.log(`GitHub Actions usage — ${opts.csvPath}`)
  console.log('')
  console.log(`Total wall-clock minutes: ${Math.round(totalMinutes).toLocaleString()}`)
  console.log(`Estimated cost:           ${fmtUsd(totalCost)}`)
  console.log(`Total job runs:           ${totalRuns.toLocaleString()}`)
  console.log(`Distinct repos:           ${byRepo.size.toLocaleString()}`)
  console.log(`Distinct workflows:       ${byWorkflow.size.toLocaleString()}`)
  console.log(`Distinct jobs:            ${byJob.size.toLocaleString()}`)
  console.log('')
  console.log('By runner label (rate × minutes):')
  const runnerNameW = Math.max(6, ...summary.byRunnerLabel.map(r => r.key.length))
  for (const r of summary.byRunnerLabel) {
    console.log(
      `  ${pad(r.key, runnerNameW)}  ` +
      `${pad(Math.round(r.minutes).toLocaleString(), 10, true)} min  ` +
      `@ ${pad(fmtUsd(r.rate), 7, true)}/min  = ${pad(fmtUsd(r.cost), 10, true)}  ` +
      `(${r.runs.toLocaleString()} runs; ${r.rateLabel})`
    )
  }
  console.log('')
  console.log('Notes:')
  console.log('  - Minutes are WALL-CLOCK (per GitHub: /actions/metrics/usage does not')
  console.log('    apply billing multipliers).')
  console.log('  - Cost is estimated by matching runner labels against a built-in rate')
  console.log('    table; rates drift, so for authoritative billing use GitHub\'s billing page.')
  console.log('  - Self-hosted runners are not included in the metrics CSV.')
  console.log('')

  printTable(`Top ${opts.top} repos`, summary.topRepos)
  printTable(`Top ${opts.top} workflows`, summary.topWorkflows)
  printTable(`Top ${opts.top} jobs`, summary.topJobs)
}

main()
