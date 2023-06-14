// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";

import {ILendPoolAddressesProvider} from "./interfaces/ILendPoolAddressesProvider.sol";
import {ILendPool} from "./interfaces/ILendPool.sol";
import {ILendPoolLoan} from "./interfaces/ILendPoolLoan.sol";
import {IWETH} from "./interfaces/IWETH.sol";

import {IStakedNft} from "../interfaces/IStakedNft.sol";
import {INftPool} from "../interfaces/INftPool.sol";

contract StakeAndBorrowHelper is ReentrancyGuardUpgradeable, OwnableUpgradeable, PausableUpgradeable {
    ILendPoolAddressesProvider public bendAddressesProvider;
    ILendPool public bendLendPool;
    ILendPoolLoan public bendLendLoan;
    IWETH public WETH;

    INftPool public nftPool;
    IStakedNft public stBayc;
    IStakedNft public stMayc;
    IStakedNft public stBakc;

    IERC721Upgradeable public bayc;
    IERC721Upgradeable public mayc;
    IERC721Upgradeable public bakc;

    function initialize(
        address bendAddressesProvider_,
        address WETH_,
        address nftPool_,
        address stBayc_,
        address stMayc_,
        address stBakc_
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        WETH = IWETH(WETH_);
        nftPool = INftPool(nftPool_);
        stBayc = IStakedNft(stBayc_);
        stMayc = IStakedNft(stMayc_);
        stBakc = IStakedNft(stBakc_);

        bayc = IERC721Upgradeable(stBayc.underlyingAsset());
        mayc = IERC721Upgradeable(stMayc.underlyingAsset());
        bakc = IERC721Upgradeable(stBakc.underlyingAsset());

        bendAddressesProvider = ILendPoolAddressesProvider(bendAddressesProvider_);
        bendLendPool = ILendPool(bendAddressesProvider.getLendPool());
        bendLendLoan = ILendPoolLoan(bendAddressesProvider.getLendPoolLoan());

        IERC721Upgradeable(bayc).setApprovalForAll(address(nftPool), true);
        IERC721Upgradeable(mayc).setApprovalForAll(address(nftPool), true);
        IERC721Upgradeable(bakc).setApprovalForAll(address(nftPool), true);

        IERC721Upgradeable(address(stBayc)).setApprovalForAll(address(bendLendPool), true);
        IERC721Upgradeable(address(stMayc)).setApprovalForAll(address(bendLendPool), true);
        IERC721Upgradeable(address(stBakc)).setApprovalForAll(address(bendLendPool), true);
    }

    struct StakeAndBorrowLocalVars {
        address[] nftsForStakingTop;
        uint256[][] nftTokenIdsForStakingTop;
        uint256[] nftTokenIdsForStakingSub;
    }

    function stakeAndBorrow(
        address[] calldata assets,
        uint256[] calldata amounts,
        address[] calldata nftAssets,
        uint256[] calldata nftTokenIds,
        address onBehalfOf,
        uint16 referralCode
    ) public whenNotPaused nonReentrant {
        StakeAndBorrowLocalVars memory vars;

        for (uint256 i = 0; i < nftAssets.length; i++) {
            IERC721Upgradeable(nftAssets[i]).safeTransferFrom(msg.sender, address(this), nftTokenIds[i]);

            // stake original nft to the staking pool
            vars.nftTokenIdsForStakingSub = new uint256[](1);
            vars.nftTokenIdsForStakingSub[0] = nftTokenIds[i];

            vars.nftsForStakingTop = new address[](1);
            vars.nftsForStakingTop[0] = nftAssets[i];
            vars.nftTokenIdsForStakingTop = new uint256[][](1);
            vars.nftTokenIdsForStakingTop[0] = vars.nftTokenIdsForStakingSub;
            nftPool.deposit(vars.nftsForStakingTop, vars.nftTokenIdsForStakingTop);

            // borrow with the staked nft
            IStakedNft stNftAsset = getStakedNFTAsset(nftAssets[i]);
            bendLendPool.borrow(assets[i], amounts[i], address(stNftAsset), nftTokenIds[i], onBehalfOf, referralCode);

            if (assets[i] == address(WETH)) {
                WETH.withdraw(amounts[i]);
                _safeTransferETH(msg.sender, amounts[i]);
            } else {
                IERC20Upgradeable(assets[i]).transfer(msg.sender, amounts[i]);
            }
        }
    }

    struct RepayAndUnstakeLocalVars {
        uint256 loanId;
        address debtReserve;
        uint256 debtTotalAmount;
        address borrower;
        address[] nftsForStakingTop;
        uint256[][] nftTokenIdsForStakingTop;
        uint256[] nftTokenIdsForStakingSub;
    }

    function repayAndUnstake(
        address[] calldata nftAssets,
        uint256[] calldata nftTokenIds
    ) public payable whenNotPaused nonReentrant {
        RepayAndUnstakeLocalVars memory vars;

        if (msg.value > 0) {
            WETH.deposit{value: msg.value}();
            WETH.transferFrom(address(this), msg.sender, msg.value);
        }

        for (uint256 i = 0; i < nftAssets.length; i++) {
            (vars.loanId, vars.debtReserve, , vars.debtTotalAmount, , ) = bendLendPool.getNftDebtData(
                nftAssets[i],
                nftTokenIds[i]
            );

            vars.borrower = bendLendLoan.borrowerOf(vars.loanId);
            require(vars.borrower == msg.sender, "Migrator: caller not borrower");

            // repay with the staked nft
            IERC20Upgradeable(vars.debtReserve).transferFrom(msg.sender, address(this), vars.debtTotalAmount);
            (, bool isFullRepaid) = bendLendPool.repay(nftAssets[i], nftTokenIds[i], vars.debtTotalAmount);
            require(isFullRepaid, "Migrator: full repay failed");

            IStakedNft stNftAsset = getStakedNFTAsset(nftAssets[i]);
            IERC721Upgradeable(address(stNftAsset)).safeTransferFrom(vars.borrower, address(this), nftTokenIds[i]);

            // unstake from the staking pool
            vars.nftTokenIdsForStakingSub = new uint256[](1);
            vars.nftTokenIdsForStakingSub[0] = nftTokenIds[i];

            vars.nftsForStakingTop = new address[](1);
            vars.nftsForStakingTop[0] = nftAssets[i];
            vars.nftTokenIdsForStakingTop = new uint256[][](1);
            vars.nftTokenIdsForStakingTop[0] = vars.nftTokenIdsForStakingSub;
            nftPool.withdraw(vars.nftsForStakingTop, vars.nftTokenIdsForStakingTop);

            IERC721Upgradeable(nftAssets[i]).safeTransferFrom(address(this), vars.borrower, nftTokenIds[i]);
        }
    }

    function setPause(bool flag) public onlyOwner {
        if (flag) {
            _pause();
        } else {
            _unpause();
        }
    }

    function getStakedNFTAsset(address nftAsset) internal view returns (IStakedNft) {
        if (nftAsset == address(bayc)) {
            return stBayc;
        } else if (nftAsset == address(mayc)) {
            return stMayc;
        } else if (nftAsset == address(bakc)) {
            return stBakc;
        } else {
            revert("Migrator: invalid nft asset");
        }
    }

    function _safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, "ETH_TRANSFER_FAILED");
    }

    /**
     * @dev Only WETH contract is allowed to transfer ETH here. Prevent other addresses to send Ether to this contract.
     */
    receive() external payable {
        require(msg.sender == address(WETH), "Receive not allowed");
    }
}
