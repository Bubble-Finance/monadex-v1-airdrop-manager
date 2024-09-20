// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {MonadexV1AirdropManager} from "../src/MonadexV1AirdropManager.sol";
import {Script} from "../lib/forge-std/src/Script.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
contract deployOlaAirdrop is Script{
    MonadexV1AirdropManager public MDXAirdrop;
    address public supportedToken; //set your supported token
    IERC20 public IMDX = IERC20(supportedToken);
    bytes32 public root = 0x56d421160b35433b3742992cc6e7d5644882450964a20adeacbb899f833ace1e;
    uint public totalMDXAirdropFund = 100 * 1e18;


    function run() external {
        deployDrops();
    }

    function deployDrops() public returns (MonadexV1AirdropManager) {
        vm.startBroadcast();
        MDXAirdrop = new MonadexV1AirdropManager(100,root);
        MDXAirdrop.addToken(supportedToken);
        MDXAirdrop.addAirdropFund(supportedToken, totalMDXAirdropFund);
        vm.stopBroadcast();

        return (MDXAirdrop);

    }
}