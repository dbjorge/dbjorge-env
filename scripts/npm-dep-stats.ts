// Step 1: Get package download statistics
const axios = require('axios');

async function getPackageDownloads(packageName, period = 'last-month'): Promise<number> {
  const url = `https://api.npmjs.org/downloads/point/${period}/${packageName}`;
  
  try {
    const response = await axios.get(url);
    return response.data.downloads;
  } catch (error) {
    if (error.response?.status === 404) {
      return 0;
    }
    throw error;
  }
}

// Step 2: Identify package dependents
async function getPackageDependents(packageName, maxOffset = 1000): Promise<string[]> {
  let offset = 0;
  const dependents: string[] = [];
  while (offset < maxOffset) {
    const url = `https://www.npmjs.com/browse/depended/${packageName}?offset=${offset}`;
    const response = await axios.get(url);
    const html = response.data;
    // response will be an html page with links to dependent packages (+ a self link)
    const packageHrefMatches = html.match(/href="\/package\/(.*?)"/g)
    const linkedPackageNames = packageHrefMatches.map(match => match.slice('href="/package/'.length, -1))
    const linkedDependents = linkedPackageNames.filter(name => name !== packageName);
    dependents.push(...linkedDependents);

    const nextPageMatch = /<a href="\/browse\/depended\/(.*?)\?offset=(\d+)">Next Page<\/a>/.exec(html)
    if (!nextPageMatch) {
      break;
    }

    offset = parseInt(nextPageMatch[2]);
  }
  return dependents;
}

// Step 3: Get download statistics for each dependent
async function getDependentDownloads(dependents, period = 'last-month'): Promise<{ [key: string]: number }> {
  const downloads = {};
  for (const dependent of dependents) {
    downloads[dependent] = await getPackageDownloads(dependent, period);
  }
  return downloads;
}

// Step 4: Analyze the data
function analyzeContributions(
  packageDownloads: number,
  dependentDownloads: { [key: string]: number }
): [string, number][] {
  const totalDownloads = packageDownloads;
  const contributions: { [key: string]: number } = {};

  for (const [dependent, downloads] of Object.entries(dependentDownloads)) {
    const contribution = (downloads / totalDownloads) * 100;
    contributions[dependent] = contribution;
  }

  return Object.entries(contributions)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 10);
}

// Main function to run the analysis
async function analyzePackageDependents(packageName) {
  const packageDownloads = await getPackageDownloads(packageName);
  const dependents = await getPackageDependents(packageName);
  const dependentDownloads = await getDependentDownloads(dependents);
  const topContributors = analyzeContributions(packageDownloads, dependentDownloads);

  // Overcounts cases where a project depends on multiple dependents
  const totalDependentDownloads = Object.values(dependentDownloads).reduce((sum, downloads) => sum + downloads, 0);
  const maxLeafDownloads = Math.max(0, packageDownloads - totalDependentDownloads);

  console.log(`${packageName}`)
  console.log(`  Total downloads: ${packageDownloads}`)
  console.log(`  Dependents: ${dependents.length}`)
  console.log(`  Leaf downloads: ${maxLeafDownloads}+`)
  console.log(`\nTop contributors to ${packageName} downloads:`);
  topContributors.forEach(([dependent, contribution]) => {
    console.log(`${dependent}: ${contribution.toFixed(2)}%`);
  });
}

const packageName = process.argv[2];
if (!packageName) {
  console.error('Please provide a package name as an argument.');
  process.exit(1);
}

analyzePackageDependents(packageName);