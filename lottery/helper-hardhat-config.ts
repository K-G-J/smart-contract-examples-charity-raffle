export interface networkConfigItem {
    name?: string
    subscriptionId?: string
    gasLane?: string
    keepersUpdateInterval?: string
    charityRaffleDuration?: string
    raffleEntranceFee?: string
    jackpot?: string
    callbackGasLimit?: string
    vrfCoordinatorV2?: string
    charity1?: string
    charity2?: string
    charity3?: string
}

export interface networkConfigInfo {
    [key: number]: networkConfigItem
}

export const networkConfig: networkConfigInfo = {
    31337: {
        name: "localhost",
        subscriptionId: "588",
        gasLane: "0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc", // 30 gwei
        keepersUpdateInterval: "30",
        charityRaffleDuration: "30", // 30 seconds (just for testing)
        raffleEntranceFee: "100000000000000000", // 0.1 ETH
        jackpot: "100000000000000000", // 1 ETH
        callbackGasLimit: "500000", // 500,000 gas
    },
    4: {
        name: "rinkeby",
        subscriptionId: "5864",
        gasLane: "0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc", // 30 gwei
        keepersUpdateInterval: "30",
        charityRaffleDuration: "30", // 30 seconds (just for testing)
        raffleEntranceFee: "100000000000000000", // 0.1 ETH
        jackpot: "200000000000000000", // 0.2 ETH
        callbackGasLimit: "500000", // 500,000 gas
        vrfCoordinatorV2: "0x6168499c0cFfCaCD319c818142124B7A15E857ab",
        charity1: "0x8423f6c5f0895914e0C8A4eF523C0A1d5c8632f6", // use extra wallet accounts to test
        charity2: "0x70185775Ae9767751c218d9baAeffBC9b5fD5b34",
        charity3: "0xa95224aE036279f0f2A07623D94F44fDb03F1C45",
    },
    1: {
        name: "mainnet",
        keepersUpdateInterval: "30",
    },
}

export const developmentChains = ["hardhat", "localhost"]
export const VERIFICATION_BLOCK_CONFIRMATIONS = 6
export const frontEndContractsFile =
    "../nextjs-smartcontract-lottery-fcc/constants/contractAddresses.json"
