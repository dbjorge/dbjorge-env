#!/usr/bin/env node
/* eslint-disable no-console */

/**
 * Fetches npm download statistics for a package and groups by major version
 * Usage: node npm-downloads-by-version.js <package-name> [--include-prerelease] [--since-major <major-version>]
 */

async function fetchJSON(url) {
  const response = await fetch(url)
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}: ${response.statusText}`)
  }
  return response.json()
}

function getMajorVersion(version) {
  const match = version.match(/^(\d+)\./)
  return match ? parseInt(match[1], 10) : null
}

function getMajorMinor(version) {
  const match = version.match(/^(\d+)\.(\d+)\./)
  return match ? `${match[1]}.${match[2]}` : null
}

function isPrereleaseVersion(version) {
  return !/^(\d+)\.(\d+)\.(\d+)$/.test(version)
}

async function getDownloadsByMajorVersion(packageName, options) {
  const {
    includePrerelease = false,
    sinceMajor = null,
    lastNMinorsPerMajor = 4
  } = options || {}

  console.log(`Fetching data for ${packageName}...\n`)

  // Get all versions with metadata
  const packageData = await fetchJSON(
    `https://registry.npmjs.org/${packageName}`
  )
  let versions = Object.keys(packageData.versions || {})

  if (versions.length === 0) {
    throw new Error(`No versions found for package ${packageName}`)
  }

  versions = versions.filter(version => {
    if (!includePrerelease && isPrereleaseVersion(version)) {
      return false
    }
    if (sinceMajor !== null && getMajorVersion(version) < sinceMajor) {
      return false
    }
    return true
  })

  // Group versions by major version
  const versionsByMajor = new Map()
  versions.forEach(version => {
    const major = getMajorVersion(version)
    if (major !== null) {
      if (!versionsByMajor.has(major)) {
        versionsByMajor.set(major, [])
      }
      versionsByMajor.get(major).push(version)
    }
  })

  // Sort versions in each major group (newest first)
  versionsByMajor.forEach(versionsWithinMajor => {
    versionsWithinMajor.sort((a, b) => {
      const aParts = a.split('.').map(Number)
      const bParts = b.split('.').map(Number)
      for (let i = 0; i < Math.max(aParts.length, bParts.length); i++) {
        const aPart = aParts[i] || 0
        const bPart = bParts[i] || 0
        if (aPart !== bPart) return bPart - aPart
      }
      return 0
    })
  })

  // Group versions by major.minor within each major version
  const minorLinesByMajor = new Map()
  versionsByMajor.forEach((versionsInMajor, major) => {
    const minorLines = new Map()
    versionsInMajor.forEach(version => {
      const majorMinor = getMajorMinor(version)
      if (majorMinor) {
        if (!minorLines.has(majorMinor)) {
          minorLines.set(majorMinor, [])
        }
        minorLines.get(majorMinor).push(version)
      }
    })
    // Sort minor lines (newest first)
    const sortedMinorLines = Array.from(minorLines.entries()).sort((a, b) => {
      const [aMajorMinor] = a
      const [bMajorMinor] = b
      const aParts = aMajorMinor.split('.').map(Number)
      const bParts = bMajorMinor.split('.').map(Number)
      for (let i = 0; i < Math.max(aParts.length, bParts.length); i++) {
        const aPart = aParts[i] || 0
        const bPart = bParts[i] || 0
        if (aPart !== bPart) return bPart - aPart
      }
      return 0
    })
    minorLinesByMajor.set(major, sortedMinorLines)
  })

  // see https://github.com/npm/registry/blob/main/docs/download-counts.md#point-values
  const downloadPeriod = 'last-week'

  // Fetch downloads for all versions at once using the versions API
  const versionsDownloadsData = await fetchJSON(
    `https://api.npmjs.org/versions/${encodeURIComponent(packageName)}/${downloadPeriod}`
  )

  // Fetch total downloads
  const downloadsData = await fetchJSON(
    `https://api.npmjs.org/downloads/point/${downloadPeriod}/${encodeURIComponent(packageName)}`
  )

  // Build a map of version downloads
  const versionDownloads = new Map()
  for (const version of versions) {
    versionDownloads.set(version, versionsDownloadsData.downloads[version] || 0)
  }

  // Calculate statistics by major version
  const results = []
  const sortedMajors = Array.from(versionsByMajor.keys()).sort((a, b) => b - a)

  for (const major of sortedMajors) {
    const versionsInMajor = versionsByMajor.get(major)
    const minorLines = minorLinesByMajor.get(major)

    const totalDownloads = versionsInMajor.reduce(
      (sum, ver) => sum + (versionDownloads.get(ver) || 0),
      0
    )

    // Calculate downloads for each individual minor line (up to 3 latest)
    const minorLineStats = []
    const latestMinorLines = minorLines.slice(0, lastNMinorsPerMajor)

    latestMinorLines.forEach(([majorMinor, versionsWithinMinor]) => {
      const downloads = versionsWithinMinor.reduce(
        (sum, ver) => sum + (versionDownloads.get(ver) || 0),
        0
      )

      // Get the most recent version from this minor line
      const mostRecentVersion = versionsWithinMinor[0]
      const releaseDate = mostRecentVersion
        ? packageData.time[mostRecentVersion]
        : null

      minorLineStats.push({
        minorLine: majorMinor,
        downloads,
        releaseDate,
        versionCount: versionsWithinMinor.length
      })
    })

    // Get release date for the most recent version in the entire major line
    const mostRecentVersionInMajor = versionsInMajor[0]
    const majorLineReleaseDate = packageData.time[mostRecentVersionInMajor]

    results.push({
      major,
      totalDownloads,
      majorLineReleaseDate,
      versionCount: versionsInMajor.length,
      minorLineCount: minorLines.length,
      minorLineStats
    })
  }

  return {
    packageName,
    dateRange: downloadPeriod,
    allDownloads: downloadsData.downloads,
    filteredDownloads: results.reduce(
      (sum, result) => sum + result.totalDownloads,
      0
    ),
    results
  }
}

function parseArgs(args) {
  let packageName = null
  const options = {}

  for (let i = 0; i < args.length; i++) {
    const arg = args[i]

    if (arg === '--include-prerelease') {
      options.includePrerelease = true
    } else if (arg === '--since-major') {
      if (i + 1 >= args.length) {
        console.error('Error: --since-major requires a major version number')
        process.exit(1)
      }
      const majorVersion = parseInt(args[i + 1], 10)
      if (isNaN(majorVersion)) {
        console.error('Error: --since-major must be followed by a valid number')
        process.exit(1)
      }
      options.sinceMajor = majorVersion
      i++ // Skip next argument since we consumed it
    } else if (arg === '--last-n-minors-per-major') {
      if (i + 1 >= args.length) {
        console.error('Error: --last-n-minors-per-major requires a number')
        process.exit(1)
      }
      const lastNMinorsPerMajor = parseInt(args[i + 1], 10)
      if (isNaN(lastNMinorsPerMajor)) {
        console.error(
          'Error: --last-n-minors-per-major must be followed by a valid number'
        )
        process.exit(1)
      }
      options.lastNMinorsPerMajor = lastNMinorsPerMajor
      i++ // Skip next argument since we consumed it
    } else if (!arg.startsWith('--')) {
      if (packageName) {
        console.error('Error: Multiple package names provided')
        process.exit(1)
      }
      packageName = arg
    } else {
      console.error(`Error: Unknown option ${arg}`)
      process.exit(1)
    }
  }

  if (!packageName) {
    console.error(
      'Usage: node npm-downloads-by-version.js <package-name> [--include-prerelease] [--since-major <major-version>] [--last-n-minors-per-major <number>]'
    )
    process.exit(1)
  }

  return { packageName, options }
}

async function main() {
  const args = process.argv.slice(2)
  const { packageName, options } = parseArgs(args)

  try {
    const data = await getDownloadsByMajorVersion(packageName, options)

    console.log(`Package: ${data.packageName}`)
    console.log(`Date Range: ${data.dateRange} (last 7 days)`)
    console.log(
      `Total Downloads (all versions): ${data.allDownloads.toLocaleString()}`
    )
    console.log(
      `Filtered Downloads (${options.sinceMajor ? `since ${options.sinceMajor}.x` : 'all versions'}, ${options.includePrerelease ? 'including' : 'excluding'} prereleases${options.maxMinorLinesPerMajor > 1 ? ` (up to ${options.maxMinorLinesPerMajor} minor lines)` : ''}): ${data.filteredDownloads.toLocaleString()}\n`
    )
    console.log('Filtered Downloads by Major Version:')
    console.log('='.repeat(80))

    data.results.forEach(result => {
      console.log(`\nMajor Version ${result.major}.x:`)

      const releaseDate = result.majorLineReleaseDate
        ? new Date(result.majorLineReleaseDate).toISOString().split('T')[0]
        : 'unknown'
      console.log(
        `  Downloads (${result.major}.x): ${result.totalDownloads.toLocaleString()} [${result.versionCount} version${result.versionCount > 1 ? 's' : ''}, last: ${releaseDate}]`
      )

      result.minorLineStats.forEach(stat => {
        const date = stat.releaseDate
          ? new Date(stat.releaseDate).toISOString().split('T')[0]
          : 'unknown'
        console.log(
          `  Downloads (${stat.minorLine}.x): ${stat.downloads.toLocaleString()} [${stat.versionCount} version${stat.versionCount > 1 ? 's' : ''}, last: ${date}]`
        )
      })
    })

    console.log('\n' + '='.repeat(80))
  } catch (error) {
    console.error(`Error: ${error.message}`)
    process.exit(1)
  }
}

if (require.main === module) {
  main()
}

module.exports = { getDownloadsByMajorVersion }
