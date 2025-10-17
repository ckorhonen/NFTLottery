// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {Lottery} from "src/Lottery.sol";
import {Ticket1155} from "src/Ticket1155.sol";
import {PrizeVault} from "src/PrizeVault.sol";
import {IRandomSource} from "src/interfaces/IRandomSource.sol";
import {PseudoRandomSource} from "src/random/PseudoRandomSource.sol";
import {VRFv2Adapter} from "src/random/VRFv2Adapter.sol";
import {SeaportExecutor} from "src/executors/SeaportExecutor.sol";
import {UniswapV3Executor} from "src/executors/UniswapV3Executor.sol";
import {LotteryAutomation} from "src/automation/LotteryAutomation.sol";
import {CollectionAllowlist, TokenAllowlist} from "src/Allowlists.sol";

contract DeployLottery is Script {
    struct Params {
        uint256 ticketPrice;
        uint256 roundDuration;
        uint256 purchaseWindow;
        uint256 purchaseShareBps;
        uint256 ownerShareBps;
        uint256 thresholdCap;
        bool allowMultipleWins;
        string uriTemplate;
    }

    function run() external {
        vm.startBroadcast();

        address owner = vm.envOr("OWNER", msg.sender);
        address feeRecipient = vm.envOr("FEE_RECIPIENT", owner);

        Params memory p;
        p.ticketPrice = vm.envOr("TICKET_PRICE_WEI", uint256(0.01 ether));
        p.roundDuration = vm.envOr("ROUND_DURATION", uint256(7 days));
        p.purchaseWindow = vm.envOr("PURCHASE_WINDOW", uint256(2 days));
        p.purchaseShareBps = vm.envOr("PURCHASE_BPS", uint256(5000));
        p.ownerShareBps = vm.envOr("OWNER_BPS", uint256(5000));
        p.thresholdCap = vm.envOr("THRESHOLD_CAP", uint256(0));
        p.allowMultipleWins = vm.envOr("ALLOW_MULTIPLE_WINS", bool(true));
        p.uriTemplate = vm.envOr("TICKET_URI", string("ipfs://template/{id}.json"));

        // Deploy helpers
        Ticket1155 tix = new Ticket1155(p.uriTemplate, owner);
        PrizeVault vault = new PrizeVault(owner);
        // Random source: VRF if configured, else pseudo
        address vrfCoord = vm.envOr("VRF_COORDINATOR", address(0));
        bytes32 vrfKeyHash = vm.envOr("VRF_KEYHASH", bytes32(0));
        uint64 vrfSub = uint64(vm.envOr("VRF_SUB_ID", uint256(0)));
        uint16 vrfMinConf = uint16(uint256(vm.envOr("VRF_MIN_CONFIRMATIONS", uint256(3))));
        uint32 vrfGas = uint32(uint256(vm.envOr("VRF_CALLBACK_GAS", uint256(400000))));

        IRandomSource rnd;
        if (vrfCoord != address(0) && vrfKeyHash != bytes32(0) && vrfSub != 0) {
            rnd = IRandomSource(address(new VRFv2Adapter(vrfCoord, vrfKeyHash, vrfSub, vrfMinConf, vrfGas, owner)));
        } else {
            rnd = IRandomSource(address(new PseudoRandomSource()));
        }

        Lottery lot = new Lottery(
            owner,
            feeRecipient,
            p.ticketPrice,
            p.roundDuration,
            p.purchaseWindow,
            p.purchaseShareBps,
            p.ownerShareBps,
            p.thresholdCap,
            p.allowMultipleWins,
            tix,
            vault,
            rnd
        );

        vault.setController(address(lot));
        tix.setMinter(address(lot));

        // Allowlist scaffolds (empty initially)
        CollectionAllowlist collAllow = new CollectionAllowlist(owner);
        TokenAllowlist tokAllow = new TokenAllowlist(owner);

        // Known protocol addresses (override with env if needed)
        address seaport = vm.envOr("SEAPORT", _defaultSeaport(block.chainid));
        address uniV3 = vm.envOr("UNISWAP_V3_ROUTER", _defaultUniswapV3(block.chainid));

        SeaportExecutor se = new SeaportExecutor(seaport, owner);
        UniswapV3Executor ue = new UniswapV3Executor(uniV3, owner);
        se.setAllowlist(address(collAllow));
        se.setBudgeter(address(lot));
        ue.setAllowlist(address(tokAllow));
        ue.setBudgeter(address(lot));

        lot.setSeaportExecutor(address(se), true);
        lot.setUniswapV3Executor(address(ue), true);

        // Optional: Automation deploy
        bool enableAutomation = vm.envOr("ENABLE_AUTOMATION", bool(true));
        address automationAddr = address(0);
        if (enableAutomation) {
            automationAddr = address(new LotteryAutomation(address(lot), address(vault), owner));
            // default draw chunk 5
        }
        // serialize to JSON for front-end/ops
        string memory root = "../deployments";
        string memory obj = "lottery";
        vm.serializeUint(obj, "chainId", block.chainid);
        vm.serializeAddress(obj, "lottery", address(lot));
        vm.serializeAddress(obj, "ticket1155", address(tix));
        vm.serializeAddress(obj, "prizeVault", address(vault));
        vm.serializeAddress(obj, "seaportExecutor", address(se));
        vm.serializeAddress(obj, "uniswapV3Executor", address(ue));
        vm.serializeAddress(obj, "collectionAllowlist", address(collAllow));
        vm.serializeAddress(obj, "tokenAllowlist", address(tokAllow));
        vm.serializeAddress(obj, "automation", automationAddr);
        string memory json = vm.serializeString(obj, "version", "v1");
        string memory file = string.concat(root, "/", vm.toString(block.chainid), ".json");
        vm.writeJson(json, file);
        vm.stopBroadcast();
    }

    function _defaultSeaport(uint256) internal pure returns (address a) {
        // Canonical Seaport 1.6 address (cross-chain)
        return 0x0000000000000068F116a894984e2DB1123eB395;
    }

    function _defaultUniswapV3(uint256 cid) internal pure returns (address a) {
        if (cid == 1) return 0xE592427A0AEce92De3Edee1F18E0157C05861564; // mainnet
        if (cid == 8453) return 0x2626664c2603336E57B271c5C0b26F421741e481; // base
        if (cid == 137) return 0xE592427A0AEce92De3Edee1F18E0157C05861564; // polygon
        if (cid == 42161) return 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45; // uni v3 swapping via UniversalRouter/SwapRouter02
        return address(0);
    }
}
