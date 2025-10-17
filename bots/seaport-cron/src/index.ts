import { createWalletClient, http, encodeFunctionData, parseEther } from 'viem'
import { privateKeyToAccount } from 'viem/accounts'

// Minimal ABI for Lottery.executeSeaportBasicERC721
const lotteryAbi = [
  { type:'function', name:'currentRoundId', inputs:[], outputs:[{type:'uint256'}], stateMutability:'view'},
  { type:'function', name:'rounds', inputs:[{type:'uint256'}], outputs:[{type:'uint64'},{type:'uint64'},{type:'uint256'},{type:'uint256'},{type:'uint256'},{type:'bool'},{type:'bool'},{type:'uint256'}], stateMutability:'view'},
  { type:'function', name:'executeSeaportBasicERC721', inputs:[{type:'uint256'},{type:'bytes'},{type:'uint256'},{type:'uint256'}], outputs:[], stateMutability:'payable' },
  { type:'function', name:'purchaseWindow', inputs:[], outputs:[{type:'uint256'}], stateMutability:'view' },
]

// Minimal ABI for SeaportExecutor.buyBasicERC721 (we pass calldata directly)
// const seaportExecAbi = [...]

type Deployment = {
  chainId: number
  lottery: `0x${string}`
  prizeVault: `0x${string}`
  collectionAllowlist?: `0x${string}`
  tokenAllowlist?: `0x${string}`
}

export default {
  async scheduled(event: ScheduledEvent, env: any, ctx: ExecutionContext) {
    const chains = (env.DEPLOYMENTS as string || '').split(/\s+/).filter(Boolean)
    for (const chain of chains) {
      const url = new URL(`../../deployments/${chain}.json`, import.meta.url)
      let dep: Deployment
      try {
        const res = await fetch(url)
        if (!res.ok) continue
        dep = await res.json()
      } catch { continue }

      const rpc = env[`RPC_${dep.chainId}`]
      const pk = env[`PK_${dep.chainId}`]
      if (!rpc || !pk) continue
      const account = privateKeyToAccount(pk as `0x${string}`)
      const client = createWalletClient({ account, transport: http(rpc) })

      // Read round and window
      const rid = await client.readContract({ address: dep.lottery, abi: lotteryAbi as any, functionName:'currentRoundId' }) as bigint
      const [ , end, deposited, purchaseBudget ] = (await client.readContract({ address: dep.lottery, abi: lotteryAbi as any, functionName:'rounds', args:[rid] })) as any
      const pw = await client.readContract({ address: dep.lottery, abi: lotteryAbi as any, functionName:'purchaseWindow' }) as bigint
      const now = Math.floor(Date.now()/1000)
      // Skip if not in purchase window
      if (now < Number(end) || now > Number(end + pw)) continue

      // TODO: Fetch tasks from KV or an API; for now, no-op
      // Example task
      const task = env.NEXT_TASK ? JSON.parse(env.NEXT_TASK) : null
      if (!task) continue

      const calldata = task.calldata as `0x${string}` // encoded SeaportExecutor.buyBasicERC721(roundId, params)
      const nativePrice = parseEther(task.nativePrice || '0.01')
      const cap = parseEther(task.maxNativeSpend || '0.02')

      try {
        await client.writeContract({ address: dep.lottery, abi: lotteryAbi as any, functionName:'executeSeaportBasicERC721', args:[rid, calldata, nativePrice, cap], value: nativePrice })
      } catch(e) {
        // log and continue
        console.error('seaport exec failed', e)
      }
    }
  }
}

