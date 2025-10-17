const { readdirSync, readFileSync, writeFileSync, mkdirSync } = require('node:fs')
const { join } = require('node:path')

const root = join(__dirname, '..', '..')
const deploymentsDir = join(root, 'deployments')
const out = join(__dirname, '..', 'public', 'registry.json')

try { mkdirSync(join(__dirname, '..', 'public'), { recursive: true }) } catch {}

let list = []
try {
  const files = readdirSync(deploymentsDir).filter(f => f.endsWith('.json'))
  list = files.map(f => JSON.parse(readFileSync(join(deploymentsDir, f), 'utf8')))
} catch {}
writeFileSync(out, JSON.stringify(list, null, 2))
console.log(`Wrote ${out} with ${list.length} deployments`)

