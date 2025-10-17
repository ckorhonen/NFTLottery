export const lotteryAbi = [
  { type: 'function', name: 'deposit', stateMutability: 'payable', inputs: [], outputs: [] },
  { type: 'function', name: 'ticketPrice', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
  { type: 'function', name: 'purchaseWindow', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
  { type: 'function', name: 'currentRoundId', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
  { type: 'function', name: 'owner', stateMutability: 'view', inputs: [], outputs: [{ type: 'address' }] },
  { type: 'function', name: 'rounds', stateMutability: 'view', inputs: [{ type: 'uint256' }], outputs: [
    { type: 'uint64' }, // start
    { type: 'uint64' }, // end
    { type: 'uint256' }, // deposited
    { type: 'uint256' }, // purchaseBudget
    { type: 'uint256' }, // ownerAmount
    { type: 'bool' },    // closed
    { type: 'bool' },    // finalized
    { type: 'uint256' }  // winnersDrawn
  ]},
  { type: 'function', name: 'ticketsOf', stateMutability: 'view', inputs: [{ type: 'uint256' }, { type: 'address' }], outputs: [{ type: 'uint256' }] },
  { type: 'function', name: 'finalizeRound', stateMutability: 'nonpayable', inputs: [{ type: 'uint256' }], outputs: [] },
  { type: 'function', name: 'drawWinners', stateMutability: 'nonpayable', inputs: [{ type: 'uint256' }, { type: 'uint256' }], outputs: [] },
  { type: 'function', name: 'startNextRound', stateMutability: 'nonpayable', inputs: [], outputs: [] },
  { type: 'function', name: 'executeUniV3SwapNative', stateMutability: 'payable', inputs: [{ type: 'uint256' }, { type: 'bytes' }, { type: 'uint256' }], outputs: [] },
  { type: 'function', name: 'executeSeaportBasicERC721', stateMutability: 'payable', inputs: [{ type: 'uint256' }, { type: 'bytes' }, { type: 'uint256' }], outputs: [] },
]

export const prizeAbi = [
  { type: 'function', name: 'prizes', stateMutability: 'view', inputs: [{ type: 'uint256' }], outputs: [
    { type: 'uint8' }, { type: 'address' }, { type: 'uint256' }, { type: 'uint256' }, { type: 'uint256' }, { type: 'bool' }, { type: 'address' }
  ] },
  { type: 'function', name: 'prizesLength', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
  { type: 'function', name: 'roundPrizeCount', stateMutability: 'view', inputs: [{ type: 'uint256' }], outputs: [{ type: 'uint256' }] },
  { type: 'function', name: 'prizeIndexAt', stateMutability: 'view', inputs: [{ type: 'uint256' }, { type: 'uint256' }], outputs: [{ type: 'uint256' }] },
  { type: 'function', name: 'claim', stateMutability: 'nonpayable', inputs: [{ type: 'uint256' }], outputs: [] }
]

export const tokenAllowlistAbi = [
  { type: 'function', name: 'set', stateMutability: 'nonpayable', inputs: [{ type: 'address' }, { type: 'bool' }], outputs: [] },
  { type: 'function', name: 'isTokenAllowed', stateMutability: 'view', inputs: [{ type: 'address' }], outputs: [{ type: 'bool' }] },
]
export const collectionAllowlistAbi = [
  { type: 'function', name: 'set', stateMutability: 'nonpayable', inputs: [{ type: 'address' }, { type: 'bool' }], outputs: [] },
  { type: 'function', name: 'isCollectionAllowed', stateMutability: 'view', inputs: [{ type: 'address' }], outputs: [{ type: 'bool' }] },
]

export const uniswapExecutorAbi = [
  { type: 'function', name: 'swapExactInputSingle', stateMutability: 'payable', inputs: [
    { type: 'uint256' },
    { type: 'tuple', components: [
      { type: 'address', name: 'tokenIn' },
      { type: 'address', name: 'tokenOut' },
      { type: 'uint24', name: 'fee' },
      { type: 'address', name: 'recipient' },
      { type: 'uint256', name: 'deadline' },
      { type: 'uint256', name: 'amountIn' },
      { type: 'uint256', name: 'amountOutMinimum' },
      { type: 'uint160', name: 'sqrtPriceLimitX96' }
    ] }
  ], outputs: [{ type: 'uint256' }] }
]

