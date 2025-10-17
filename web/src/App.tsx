import { useEffect, useMemo, useState } from 'react'
import registry from '../public/registry.json'
import { createConfig, http, readContract } from '@wagmi/core'
import { formatEther, parseEther, encodeFunctionData } from 'viem'
import { injected } from '@wagmi/connectors'
import { mainnet, base, polygon, arbitrum } from 'viem/chains'
import { createWalletClient, custom } from 'viem'
import { lotteryAbi, prizeAbi, tokenAllowlistAbi, collectionAllowlistAbi, uniswapExecutorAbi } from './abi'

const chainsMap: Record<number, any> = { 1: mainnet, 8453: base, 137: polygon, 42161: arbitrum }

type Deployment = { chainId: number, lottery: `0x${string}`, ticket1155: `0x${string}`, prizeVault: `0x${string}`, collectionAllowlist?: `0x${string}`, tokenAllowlist?: `0x${string}`, uniswapV3Executor?: `0x${string}`, seaportExecutor?: `0x${string}` }

export default function App() {
  const deployments = (registry as Deployment[])
  const [account, setAccount] = useState<`0x${string}` | null>(null)
  const [chainId, setChainId] = useState<number>(deployments[0]?.chainId ?? 1)
  const [selected, setSelected] = useState<number>(0)
  const chainDeployments = useMemo(()=>deployments.filter(d => d.chainId === chainId), [chainId])
  const dep = chainDeployments[selected]

  useEffect(() => { (async () => { try { const provider = (window as any).ethereum; if (!provider) return; const client = createWalletClient({ chain: chainsMap[chainId], transport: custom(provider) }); const [acc] = await provider.request({ method: 'eth_requestAccounts' }); setAccount(acc) } catch {} })() }, [chainId])

  const config = useMemo(() => createConfig({ chains: Object.values(chainsMap), connectors: [injected()], transports: { 1: http(), 8453: http(), 137: http(), 42161: http() } }), [])

  const [ticketPrice, setTicketPrice] = useState<string>('0')
  const [owner, setOwner] = useState<`0x${string}` | null>(null)
  const [qty, setQty] = useState<number>(1)
  const [now, setNow] = useState<number>(Math.floor(Date.now() / 1000))
  const [currentRoundId, setCurrentRoundId] = useState<bigint>(1n)
  const [round, setRound] = useState<any | null>(null)
  const [purchaseWindow, setPurchaseWindow] = useState<bigint>(0n)
  useEffect(() => { const t = setInterval(() => setNow(Math.floor(Date.now() / 1000)), 1000); return () => clearInterval(t) }, [])

  useEffect(() => { (async () => { if (!dep) return; try {
      const [price, ownerAddr, rid, pw] = await Promise.all([
        readContract(config, { address: dep.lottery, abi: lotteryAbi, functionName: 'ticketPrice' }) as Promise<bigint>,
        readContract(config, { address: dep.lottery, abi: lotteryAbi, functionName: 'owner' }) as Promise<`0x${string}`>,
        readContract(config, { address: dep.lottery, abi: lotteryAbi, functionName: 'currentRoundId' }) as Promise<bigint>,
        readContract(config, { address: dep.lottery, abi: lotteryAbi, functionName: 'purchaseWindow' }) as Promise<bigint>,
      ])
      setTicketPrice(formatEther(price))
      setOwner(ownerAddr)
      setCurrentRoundId(rid)
      setPurchaseWindow(pw)
      const r = await readContract(config, { address: dep.lottery, abi: lotteryAbi, functionName: 'rounds', args: [rid] })
      setRound(r)
    } catch(e) { console.error(e) } })() }, [dep])

  async function buyTickets() {
    if (!dep) return;
    const provider = (window as any).ethereum; if (!provider) return alert('Install a wallet');
    const client = createWalletClient({ chain: chainsMap[dep.chainId], transport: custom(provider) })
    const value = parseEther((Number(ticketPrice) * qty).toString())
    await client.writeContract({ address: dep.lottery, abi: lottoAbi, functionName: 'deposit', value })
  }

  return (
    <div style={{ fontFamily: 'system-ui, sans-serif', margin: 24 }}>
      <h1>NFTLottery</h1>
      <div style={{display:'flex', gap:16, alignItems:'center'}}>
        <label>Chain:
          <select value={chainId} onChange={e=>{ setChainId(Number(e.target.value)); setSelected(0) }}>
            {[...new Set(deployments.map(d=>d.chainId))].map(cid => <option key={cid} value={cid}>{cid}</option>)}
          </select>
        </label>
        <label>Instance:
          <select value={selected} onChange={e=>setSelected(Number(e.target.value))}>
            {chainDeployments.map((d,i)=>(<option key={d.lottery} value={i}>{d.lottery.slice(0,6)}…{d.lottery.slice(-4)}</option>))}
          </select>
        </label>
      </div>
      <div style={{marginTop:8}}>Lottery: <code>{dep?.lottery}</code></div>

      <RoundStats dep={dep} currentRoundId={currentRoundId} round={round} purchaseWindow={purchaseWindow} ticketPrice={ticketPrice}/>

      <div style={{marginTop:12}}>
        <strong>Buy Tickets</strong>
        <div>Price per ticket: {ticketPrice} native</div>
        <input type="number" min={1} value={qty} onChange={e => setQty(Number(e.target.value))} style={{width:80}} />
        <button onClick={buyTickets} style={{marginLeft:8}}>Buy</button>
      </div>

      {owner && account && dep && owner.toLowerCase()===account.toLowerCase() && (
        <>
          <hr />
          <Admin dep={dep} />
          <AllowlistManager dep={dep} />
          <SwapConsole dep={dep} currentRoundId={currentRoundId} />
          <SeaportConsole dep={dep} currentRoundId={currentRoundId} />
        </>
      )}
      <hr />
      <Rules />
      <MyPrizes dep={dep} />
    </div>
  )
}

function Admin({ dep }: { dep?: Deployment }) {
  const config = useMemo(() => createConfig({ chains: Object.values(chainsMap), connectors: [injected()] }), [])
  const [rid, setRid] = useState<bigint>(1n)
  const [r, setR] = useState<any | null>(null)
  useEffect(()=>{(async()=>{ if(!dep) return; const id = await readContract(config,{address:dep.lottery, abi: lotteryAbi, functionName:'currentRoundId'}) as bigint; setRid(id); const rr = await readContract(config,{address:dep.lottery, abi: lotteryAbi, functionName:'rounds', args:[id]}); setR(rr) })()},[dep])
  if(!dep) return null
  return (
    <div>
      <h3>Admin</h3>
      <div>Round {rid.toString()}: {JSON.stringify(r)}</div>
      <div style={{marginTop:8}}>
        <button onClick={async()=>{ const provider=(window as any).ethereum; const client=createWalletClient({ chain: chainsMap[dep.chainId], transport: custom(provider) }); await client.writeContract({ address: dep.lottery, abi: lotteryAbi, functionName: 'finalizeRound', args: [rid]}); }}>Finalize</button>
        <button onClick={async()=>{ const provider=(window as any).ethereum; const client=createWalletClient({ chain: chainsMap[dep.chainId], transport: custom(provider) }); await client.writeContract({ address: dep.lottery, abi: lotteryAbi, functionName: 'drawWinners', args: [rid, 0n]}); }}>Draw</button>
        <button onClick={async()=>{ const provider=(window as any).ethereum; const client=createWalletClient({ chain: chainsMap[dep.chainId], transport: custom(provider) }); await client.writeContract({ address: dep.lottery, abi: lotteryAbi, functionName: 'startNextRound'}); }}>Start Next</button>
      </div>
    </div>
  )
}

function MyPrizes({ dep }: { dep?: Deployment }){
  const [indices, setIndices] = useState<number[]>([])
  const [addr, setAddr] = useState<`0x${string}` | null>(null)
  const provider = (window as any).ethereum
  const config = useMemo(() => createConfig({ chains: Object.values(chainsMap), connectors: [injected()] }), [])
  useEffect(()=>{(async()=>{ if(!dep||!provider) return; const [acc]=await provider.request({method:'eth_requestAccounts'}); setAddr(acc) })()},[dep])
  useEffect(()=>{ (async()=>{ if(!dep || !addr) return; const count: bigint = await readContract(config, { address: dep.prizeVault, abi: prizeAbi, functionName: 'prizesLength' }) as any; const found:number[]=[]; const len=Number(count); for(let i=0;i<len;i++){ const p:any = await readContract(config, { address: dep.prizeVault, abi: prizeAbi, functionName: 'prizes', args:[BigInt(i)] }); if (p[6]?.toLowerCase?.()===addr.toLowerCase() && !p[5]) found.push(i)} setIndices(found) })() },[dep, addr])
  if(!dep) return null
  return (
    <div>
      <h3>My Prizes</h3>
      {indices.length===0? <div>No unclaimed prizes</div> : indices.map(i=> <div key={i}>Prize #{i} <button onClick={async()=>{ const client=createWalletClient({ chain: chainsMap[dep.chainId], transport: custom((window as any).ethereum) }); await client.writeContract({ address: dep.prizeVault, abi: prizeAbi, functionName: 'claim', args:[BigInt(i)]}); }}>Claim</button></div>)}
    </div>
  )
}

const lottoAbi = [
  { "type":"function","name":"deposit","stateMutability":"payable","inputs":[],"outputs":[] },
  { "type":"function","name":"ticketPrice","stateMutability":"view","inputs":[],"outputs":[{"type":"uint256"}] },
  { "type":"function","name":"rounds","stateMutability":"view","inputs":[{"type":"uint256"}],"outputs":[{"type":"uint64"},{"type":"uint64"},{"type":"uint256"},{"type":"uint256"},{"type":"uint256"},{"type":"bool"},{"type":"bool"},{"type":"uint256"}] },
  { "type":"function","name":"finalizeRound","inputs":[{"type":"uint256"}],"outputs":[],"stateMutability":"nonpayable" },
  { "type":"function","name":"drawWinners","inputs":[{"type":"uint256"},{"type":"uint256"}],"outputs":[],"stateMutability":"nonpayable" },
  { "type":"function","name":"startNextRound","inputs":[],"outputs":[],"stateMutability":"nonpayable" }
]

const prizeAbi = [
  {"type":"function","name":"prizes","stateMutability":"view","inputs":[{"type":"uint256"}],"outputs":[{"type":"uint8"},{"type":"address"},{"type":"uint256"},{"type":"uint256"},{"type":"uint256"},{"type":"bool"},{"type":"address"}]},
  {"type":"function","name":"prizesLength","stateMutability":"view","inputs":[],"outputs":[{"type":"uint256"}]},
  {"type":"function","name":"claim","stateMutability":"nonpayable","inputs":[{"type":"uint256"}],"outputs":[]}
]
