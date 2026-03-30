// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {PQSignatureRouter} from "../src/PQSignatureRouter.sol";
import {PQValidator} from "../src/PQValidator.sol";
import {EcdsaVerifier} from "../src/adapters/EcdsaVerifier.sol";
import {EthFalconAdapter} from "../src/adapters/EthFalconAdapter.sol";
import {EthMldsaAdapter} from "../src/adapters/EthMldsaAdapter.sol";
import {ComposedVerifier} from "../src/adapters/ComposedVerifier.sol";
import {IPQVerifier} from "../src/adapters/IPQVerifier.sol";
import {ZKNOX_ethfalcon} from "../src/vendor/zknox/ZKNOX_ethfalcon.sol";
import {ZKNOX_ethdilithium} from "../src/vendor/zknox/ZKNOX_ethdilithium.sol";
import {
    ETHFALCON_SCHEME,
    MLDSAETH_SCHEME,
    ECDSA_ETHFALCON_SCHEME,
    ECDSA_MLDSAETH_SCHEME
} from "../src/libraries/SchemeIds.sol";

/// @title Deploy
/// @notice Deploys the full PQ Wallet contract stack in the correct order.
///
/// Deployment order:
///   1. ZKNOX verifiers (ETHFALCON, MLDSAETH)
///   2. PQSignatureRouter (owned by deployer)
///   3. PQValidator (references the router)
///   4. Router.setValidator (one-time wiring)
///   5. EcdsaVerifier (stateless, no auth needed)
///   6. EthFalconAdapter + EthMldsaAdapter (authorized by ComposedVerifier addresses)
///   7. ComposedVerifier instances for hybrid schemes
///   8. Register all verifiers on the router
///
/// Usage:
///   forge script script/Deploy.s.sol:Deploy --rpc-url $RPC_URL --broadcast --verify
///
/// Environment variables:
///   DEPLOYER_PRIVATE_KEY — private key of the deployer (becomes router owner)
contract Deploy is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerKey);

        // --- Step 1: ZKNOX verifiers ---
        ZKNOX_ethfalcon zknoxEthfalcon = new ZKNOX_ethfalcon();
        console.log("ZKNOX_ethfalcon:", address(zknoxEthfalcon));

        ZKNOX_ethdilithium zknoxMldsaeth = new ZKNOX_ethdilithium();
        console.log("ZKNOX_ethdilithium:", address(zknoxMldsaeth));

        // --- Step 2: Core contracts ---
        PQSignatureRouter router = new PQSignatureRouter(deployer);
        console.log("PQSignatureRouter:", address(router));

        PQValidator validator = new PQValidator(router);
        console.log("PQValidator:", address(validator));

        // --- Step 3: Wire validator to router (one-time, immutable) ---
        router.setValidator(address(validator));

        // --- Step 4: Stateless adapters ---
        EcdsaVerifier ecdsaVerifier = new EcdsaVerifier();
        console.log("EcdsaVerifier:", address(ecdsaVerifier));

        // --- Step 5: PQ adapters ---
        // Standalone adapters are authorized by the router for direct PQ-only schemes.
        EthFalconAdapter ethfalconStandalone = new EthFalconAdapter(address(zknoxEthfalcon), address(router));
        console.log("EthFalconAdapter (standalone):", address(ethfalconStandalone));

        EthMldsaAdapter mldsaStandalone = new EthMldsaAdapter(address(zknoxMldsaeth), address(router));
        console.log("EthMldsaAdapter (standalone):", address(mldsaStandalone));

        // --- Step 6: Hybrid adapters ---
        // ComposedVerifier calls sub-adapter registerKey directly, so sub-adapters
        // must authorize the ComposedVerifier address. We predict it using CREATE nonce.

        // ECDSA + ETHFALCON hybrid
        uint256 nonce = vm.getNonce(deployer);
        // nonce → ethfalconForHybrid, nonce+1 → hybridEthfalcon
        address predictedHybridEthfalcon = vm.computeCreateAddress(deployer, nonce + 1);
        EthFalconAdapter ethfalconForHybrid = new EthFalconAdapter(address(zknoxEthfalcon), predictedHybridEthfalcon);
        ComposedVerifier hybridEthfalcon = new ComposedVerifier(
            IPQVerifier(address(ecdsaVerifier)), IPQVerifier(address(ethfalconForHybrid)), address(router)
        );
        require(address(hybridEthfalcon) == predictedHybridEthfalcon, "ETHFALCON hybrid address mismatch");
        console.log("ComposedVerifier (ECDSA+ETHFALCON):", address(hybridEthfalcon));

        // ECDSA + MLDSAETH hybrid
        nonce = vm.getNonce(deployer);
        address predictedHybridMldsa = vm.computeCreateAddress(deployer, nonce + 1);
        EthMldsaAdapter mldsaForHybrid = new EthMldsaAdapter(address(zknoxMldsaeth), predictedHybridMldsa);
        ComposedVerifier hybridMldsa = new ComposedVerifier(
            IPQVerifier(address(ecdsaVerifier)), IPQVerifier(address(mldsaForHybrid)), address(router)
        );
        require(address(hybridMldsa) == predictedHybridMldsa, "MLDSA hybrid address mismatch");
        console.log("ComposedVerifier (ECDSA+MLDSAETH):", address(hybridMldsa));

        // --- Step 7: Register all verifiers on the router ---
        router.registerVerifier(ETHFALCON_SCHEME, IPQVerifier(address(ethfalconStandalone)));
        router.registerVerifier(MLDSAETH_SCHEME, IPQVerifier(address(mldsaStandalone)));
        router.registerVerifier(ECDSA_ETHFALCON_SCHEME, IPQVerifier(address(hybridEthfalcon)));
        router.registerVerifier(ECDSA_MLDSAETH_SCHEME, IPQVerifier(address(hybridMldsa)));

        vm.stopBroadcast();

        console.log("--- Deployment complete ---");
    }
}
