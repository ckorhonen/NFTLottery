import { execSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

type Chain = { name: string, chainId: number, rpcUrl: string, privateKey: string }

const root = process.cwd()
const cfgPath = process.env.CONFIG || join(root, 'ops', 'config.json')
const cfg = JSON.parse(readFileSync(cfgPath, 'utf8'))

function sh(cmd: string, env: Record<string, string> = {}) {
  console.log(`$ ${cmd}`)
  execSync(cmd, { stdio: 'inherit', env: { ...process.env, ...env } })
}

for (const c of cfg.chains as Chain[]) {
  for (const inst of cfg.instances as any[]) {
    const env = {
      OWNER: process.env.OWNER || '',
      FEE_RECIPIENT: process.env.FEE_RECIPIENT || '',
      TICKET_PRICE_WEI: inst.ticketPriceWei.toString(),
      ROUND_DURATION: inst.roundDurationSec.toString(),
      PURCHASE_WINDOW: inst.purchaseWindowSec.toString(),
      PURCHASE_BPS: inst.purchaseBps.toString(),
      OWNER_BPS: inst.ownerBps.toString(),
      THRESHOLD_CAP: inst.thresholdCapWei.toString(),
      ALLOW_MULTIPLE_WINS: inst.allowMultipleWins ? 'true' : 'false',
      TICKET_URI: inst.ticketUri
    }
    sh(`forge script evm/script/DeployLottery.s.sol:DeployLottery --rpc-url ${c.rpcUrl} --broadcast --ledger false --private-key ${c.privateKey}`, env)
  }
}

// Build and deploy the Cloudflare Worker front-end
sh(`npm install`, { })
sh(`npm --prefix web install`, { })
sh(`npm --prefix web run build`, { })
if (process.env.CF_API_TOKEN) {
  sh(`npm --prefix web run deploy`, { })
} else {
  console.log('Skipping Cloudflare deploy (set CF_API_TOKEN to enable). Built web/dist/.')
}
