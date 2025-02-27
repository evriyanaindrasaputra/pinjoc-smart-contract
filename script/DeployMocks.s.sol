// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {MockToken} from "../src/mocks/MockToken.sol";
import {MockOracle} from "../src/mocks/MockOracle.sol";
import {DeployHelpers} from "./DeployHelpers.s.sol";
import {LendingPoolManager} from "../src/LendingPoolManager.sol";
import {LendingPool} from "../src/LendingPool.sol";
import {MockGTXOrderBook} from "../src/mocks/MockGTXOrderBook.sol";
import {PinjocRouter} from "../src/PinjocRouter.sol";

contract DeployMocks is DeployHelpers {
    struct MonthRate {
        string month;
        uint64[2] rates;
        uint256 year;
    }

    function saveDeployment(
        string memory fileName,
        address usdc,
        MockToken[5] memory collaterals,
        address lendingPoolManager,
        address pinjocRouter,
        address mockGTXOrderBook,
        LendingPool[40] memory lendingPools,
        MonthRate[4] memory monthRates
    ) internal {
        string memory json = "{\n";

        // Simpan Mock USDC Address
        json = string.concat(
            json,
            '  "MockUSDC": "',
            vm.toString(usdc),
            '",\n'
        );

        // Simpan Collateral Token Addresses
        for (uint256 i = 0; i < collaterals.length; i++) {
            json = string.concat(
                json,
                '  "',
                collaterals[i].symbol(),
                '": "',
                vm.toString(address(collaterals[i])),
                '",\n'
            );
        }

        // Simpan LendingPoolManager & Router Addresses
        json = string.concat(
            json,
            '  "LendingPoolManager": "',
            vm.toString(lendingPoolManager),
            '",\n'
        );
        json = string.concat(
            json,
            '  "MockGTXOrderBook": "',
            vm.toString(mockGTXOrderBook),
            '",\n'
        );
        json = string.concat(
            json,
            '  "PinjocRouter": "',
            vm.toString(pinjocRouter),
            '",\n'
        );

        // Simpan Semua Lending Pools
        json = string.concat(json, '  "LendingPools": [\n');
        for (uint256 i = 0; i < collaterals.length; i++) {
            for (uint256 j = 0; j < monthRates.length; j++) {
                for (uint256 k = 0; k < 2; k++) {
                    uint256 poolIndex = (i * monthRates.length * 2) +
                        (j * 2) +
                        k;

                    json = string.concat(
                        json,
                        "    {\n",
                        '      "Collateral": "',
                        collaterals[i].symbol(),
                        '",\n',
                        '      "Month": "',
                        monthRates[j].month,
                        '",\n',
                        '      "Rate": "',
                        vm.toString(monthRates[j].rates[k]),
                        '",\n',
                        '      "Address": "',
                        vm.toString(address(lendingPools[poolIndex])),
                        '"\n',
                        "    },\n"
                    );
                }
            }
        }
        // Hapus koma terakhir untuk JSON valid
        json = string.concat(json, "  ]\n}");

        // Simpan ke file JSON
        vm.writeFile(fileName, json);
    }

    function run() public {
        uint256 deployerKey = getDeployerKey();
        address owner = vm.addr(deployerKey);
        vm.startBroadcast(deployerKey);

        console.log(unicode"\n🚀 DEPLOYMENT STARTED 🚀");

        // Deploy Mock Tokens
        console.log(unicode"🪙 Deploying Mock Tokens...");
        MockToken musdc = new MockToken("Mock USDC", "MUSDC", 6);
        console.log(unicode"✅ Mock USDC deployed at: %s", address(musdc));

        MockToken[5] memory collaterals = [
            new MockToken("Mock WETH", "MWETH", 18),
            new MockToken("Mock WBTC", "MWBTC", 8),
            new MockToken("Mock SOL", "MSOL", 18),
            new MockToken("Mock Chainlink", "MLINK", 18),
            new MockToken("Mock AAVE", "MAAVE", 18)
        ];
        // hallo

        for (uint256 i = 0; i < collaterals.length; i++) {
            console.log(
                unicode"✅ %s deployed at: %s",
                collaterals[i].symbol(),
                address(collaterals[i])
            );
        }

        // Mint Tokens to Owner (Tambahkan Likuiditas Lebih Banyak)
        console.log(unicode"\n💰 Minting Tokens to Owner...");
        musdc.mint(owner, 1_000_000_000e6);
        console.log(unicode"✅ Minted 1B MUSDC");

        uint88[5] memory mintAmounts = [
            50_000_000e18, // MWETH
            50_000_000e8, // MWBTC
            50_000_000e18, // MSOL
            50_000_000e18, // MLINK
            50_000_000e18 // MAAVE
        ];

        for (uint256 i = 0; i < collaterals.length; i++) {
            collaterals[i].mint(owner, mintAmounts[i]);
            console.log(
                unicode"✅ Minted %s: %s",
                collaterals[i].symbol(),
                mintAmounts[i]
            );
        }

        // Deploy Mock Oracles
        console.log(unicode"\n📊 Deploying Mock Oracles...");
        MockOracle[5] memory oracles;
        uint40[5] memory prices = [2500e6, 90000e6, 200e6, 15e6, 200e6];

        for (uint256 i = 0; i < collaterals.length; i++) {
            oracles[i] = new MockOracle(
                address(collaterals[i]),
                address(musdc)
            );
            oracles[i].setPrice(prices[i]);
            console.log(
                unicode"✅ MockOracle for %s deployed at: %s",
                collaterals[i].symbol(),
                address(oracles[i])
            );
        }

        // Deploy LendingPoolManager
        console.log(unicode"\n🏦 Deploying LendingPoolManager...");
        LendingPoolManager lendingPoolManager = new LendingPoolManager();
        lendingPoolManager.setLtv(90e16);
        console.log(
            unicode"✅ LendingPoolManager deployed at: %s",
            address(lendingPoolManager)
        );

        // Deploy Lending Pools
        console.log(unicode"\n📌 Deploying Lending Pools...");
        LendingPool[40] memory lendingPools;

        MonthRate[4] memory monthRates = [
            MonthRate("MAY", [6e16, 8e16], 2025),
            MonthRate("AUG", [10e16, 12e16], 2025),
            MonthRate("NOV", [19e16, 21e16], 2025),
            MonthRate("FEB", [22e16, 24e16], 2026)
        ];

        for (uint256 i = 0; i < collaterals.length; i++) {
            for (uint256 j = 0; j < monthRates.length; j++) {
                for (uint256 k = 0; k < 2; k++) {
                    uint256 poolIndex = (i * monthRates.length * 2) +
                        (j * 2) +
                        k;

                    lendingPools[poolIndex] = LendingPool(
                        lendingPoolManager.createLendingPool(
                            address(musdc),
                            address(collaterals[i]),
                            monthRates[j].rates[k],
                            block.timestamp + ((i + 1) * 30 days),
                            monthRates[j].month,
                            monthRates[j].year,
                            address(oracles[i])
                        )
                    );
                    console.log(unicode"✅ LendingPool deployed:");
                    console.log("Collateral:", collaterals[i].symbol());
                    console.log("Month:", monthRates[j].month);
                    console.log("Rate:", monthRates[j].rates[k]);
                    console.log("Address:", address(lendingPools[poolIndex]));

                    uint256 usdcSupply = 250_000e6;
                    uint256 collateralSupply = mintAmounts[i] / 40; // Dibagi 40 agar cukup

                    // Supply USDC ke LendingPool
                    musdc.approve(address(lendingPools[poolIndex]), usdcSupply);
                    lendingPools[poolIndex].supply(owner, usdcSupply);
                    console.log(
                        unicode"✅ SUPPLY %s USDC to LendingPool %s-%d",
                        usdcSupply,
                        monthRates[j].month,
                        monthRates[j].rates[k]
                    );

                    // Supply Collateral ke LendingPool
                    collaterals[i].approve(
                        address(lendingPools[poolIndex]),
                        collateralSupply
                    );
                    lendingPools[poolIndex].supplyCollateral(collateralSupply);
                    console.log(
                        unicode"✅ SUPPLY_COLLATERAL %s to LendingPool %s-%d",
                        collaterals[i].symbol(),
                        monthRates[j].month,
                        monthRates[j].rates[k]
                    );
                }
            }
        }

        console.log(unicode"\n🏦 Deploying MockGTXOrderBook...");
        MockGTXOrderBook mockGTXOrderBook = new MockGTXOrderBook();
        console.log(
            unicode"✅ MockGTXOrderBook deployed at: %s",
            address(mockGTXOrderBook)
        );

        console.log(unicode"\n🏦 Deploying PinjocRouter...");
        PinjocRouter pinjocRouter = new PinjocRouter(
            address(mockGTXOrderBook),
            address(lendingPoolManager)
        );
        console.log(
            unicode"✅ PinjocRouter deployed at: %s",
            address(pinjocRouter)
        );

        console.log(unicode"\n🎉 DEPLOYMENT COMPLETED 🎉");
        saveDeployment(
            "./deployments.json",
            address(musdc),
            collaterals,
            address(lendingPoolManager),
            address(pinjocRouter),
            address(mockGTXOrderBook),
            lendingPools,
            monthRates
        );

        vm.stopBroadcast();
    }
}
