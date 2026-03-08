// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "../lib/openzeppelin-contracts/contracts/interfaces/IERC20Metadata.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../src/Presale.sol";
import "../src/PresaleToken.sol";
import "../src/SecureChainlinkOracle.sol";

contract PresaleTest is Test {
    using SafeERC20 for IERC20;

    Presale presale;
    PresaleToken presaleToken;
    SecureChainlinkOracle chainlinkOracle;

    address deployer = 0x048ef1062cbb39B338Ac2685dA72adf104b4cEF5;
    address fundsReceiverAddress;
    address chainLinkOracleAddress;
    address etherPriceFeedAddress = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;

    address usdcTokenAddress = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address usdbcTokenAddress = 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA;
    address cbBTCTokenAddress = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;

    uint256 maxSellingAmount;
    uint256 startingTime = block.timestamp;
    uint256 endingTime = block.timestamp + 1 days;
    uint256 etherPriceFeedTheshold = 1 hours;
    uint256[][3] phases;

    function setUp() public {
        fundsReceiverAddress = deployer;

        vm.startPrank(deployer);

        presaleToken = new PresaleToken("Sale Token", "ST");
        uint256 tokenDecimals = IERC20Metadata(address(presaleToken)).decimals();
        maxSellingAmount = 9_000_000 * 10 ** tokenDecimals;

        presaleToken.mint(maxSellingAmount);

        chainlinkOracle = new SecureChainlinkOracle();
        chainLinkOracleAddress = address(chainlinkOracle);

        phases[0] = [3_000_000 * 10 ** tokenDecimals, 5000, block.timestamp + 6 hours];
        phases[1] = [2_000_000 * 10 ** tokenDecimals, 500, block.timestamp + 6 hours];
        phases[2] = [4_000_000 * 10 ** tokenDecimals, 200, block.timestamp + 12 hours];

        presale = new Presale(
            fundsReceiverAddress,
            maxSellingAmount,
            address(presaleToken),
            phases,
            startingTime,
            endingTime,
            chainLinkOracleAddress,
            etherPriceFeedAddress,
            etherPriceFeedTheshold
        );

        IERC20(address(presaleToken)).approve(address(this), maxSellingAmount);

        vm.stopPrank();
        IERC20(address(presaleToken)).safeTransferFrom(deployer, address(presale), maxSellingAmount);
        vm.startPrank(deployer);
        _addPermitedTokens();
        vm.stopPrank();
    }

    function testDeploy() public view {
        assert(address(presaleToken) != address(0));
        assert(address(chainlinkOracle) != address(0));
        assert(address(presaleToken) != address(0));
        assert(address(presale) != address(0));
    }

    function testAddWhitelistedTokenRevertTokenAdded() public {
        vm.startPrank(deployer);
        vm.expectRevert("TokenAddress already added");
        presale.addWhitelistedToken(usdbcTokenAddress, 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B, 3 days);
        vm.stopPrank();
    }

    function testAddWhitelistedTokenRevertTokenInvalid() public {
        vm.startPrank(deployer);
        vm.expectRevert("Token Address cannot be Zero");
        presale.addWhitelistedToken(address(0), 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B, 3 days);
        vm.stopPrank();
    }

    function testAddWhitelistedTokenRevertPriceFeedInvalidd() public {
        vm.startPrank(deployer);
        vm.expectRevert("PriceFeed Address cannot be Zero");
        presale.addWhitelistedToken(usdbcTokenAddress, address(0), 3 days);
        vm.stopPrank();
    }

    function testAddWhitelistedTokenRevertNotOwner() public {
        vm.expectRevert();
        presale.addWhitelistedToken(usdbcTokenAddress, 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B, 3 days);
    }

    function testRemoveWhitelistedToken() public {
        vm.startPrank(deployer);
        presale.removeWhitelistedToken(cbBTCTokenAddress);
        (bool whitelisted1,,) = presale.getWhitelistedToken(cbBTCTokenAddress);
        assert(!whitelisted1);
        vm.stopPrank();
    }

    function testRemoveWhitelistedTokenRevertInvalidtoken() public {
        vm.startPrank(deployer);
        vm.expectRevert("TokenAddress not added");
        presale.removeWhitelistedToken(0x3055913c90Fcc1A6CE9a358911721eEb942013A1);
        vm.stopPrank();
    }

    function testRemoveWhitelistedTokenRevertInvalAddress() public {
        vm.startPrank(deployer);
        vm.expectRevert("Token Address cannot be Zero");
        presale.removeWhitelistedToken(address(0));
        vm.stopPrank();
    }

    function testRemoveWhitelistedTokenRevertNotOwner() public {
        vm.expectRevert();
        presale.removeWhitelistedToken(cbBTCTokenAddress);
    }

    function testBlacklist() public {
        vm.startPrank(deployer);
        presale.blacklist(address(vm.addr(2)));

        assert(presale.blacklistedUsers(address(vm.addr(2))));
        vm.stopPrank();
    }

    function testBlacklistRevertNotOwner() public {
        vm.expectRevert();
        presale.blacklist(address(vm.addr(2)));
    }

    function testBlacklistRevertInvalidAddress() public {
        vm.expectRevert();
        presale.blacklist(address(0));
    }

    function testRemoveBlacklist() public {
        vm.startPrank(deployer);
        presale.blacklist(address(vm.addr(2)));
        assert(presale.blacklistedUsers(address(vm.addr(2))));

        presale.removeBlacklist(address(vm.addr(2)));
        assert(!presale.blacklistedUsers(address(vm.addr(2))));
        vm.stopPrank();
    }

    function testRemoveBlacklistRevertInvalidAddress() public {
        vm.expectRevert();
        presale.removeBlacklist(address(0));
    }

    function testRemoveBlacklistRevertNotOwner() public {
        vm.expectRevert();
        presale.removeBlacklist(address(vm.addr(2)));
    }

    function testBuyWithEtherCorrectly() public {
        uint256 buyAmount = 1 ether;
        address buyer = vm.addr(2);

        vm.deal(buyer, 2 ether);
        _sellWithEth(buyAmount, buyer);
    }

    function testBuyWithEtherExceededCorrectly() public {
        uint256 buyAmount = 15 ether;

        address buyer = makeAddr("buyer");
        vm.deal(buyer, 100 ether);

        uint256 initialPhase = presale.currentPhase();
        _sellWithEth(buyAmount, buyer);
        assert(presale.currentPhase() == initialPhase + 1);
    }

    function testBuyWithEtherRevertMaxSellingAmount() public {
        uint256 buyAmount = 15 ether;
        address buyer = makeAddr("buyer");
        vm.deal(buyer, 1000 ether);

        _sellWithEth(buyAmount, buyer);
        _sellWithEth(buyAmount, buyer);
        _sellWithEth(buyAmount, buyer);

        vm.startPrank(buyer);

        vm.expectRevert("Sold out");
        presale.buyWithEther{value: buyAmount}();

        assert(presale.currentPhase() == 3);
        vm.stopPrank();
    }

    function testBuyWithERC20AmountExceededCorrectly() public {
        uint256 buyAmount = 20000 * (10 ** ERC20(usdcTokenAddress).decimals());
        address buyer = vm.addr(2);
        uint256 initialPhase = presale.currentPhase();
        vm.deal(buyer, 1 ether);

        vm.prank(buyer);
        deal(address(usdcTokenAddress), buyer, 100000 * (10 ** ERC20(usdcTokenAddress).decimals()));
        _sellWithToken(usdcTokenAddress, buyAmount, buyer);

        assert(presale.userTokenBalance(address(buyer)) == phases[0][0]);
        assert(presale.currentPhase() == initialPhase + 1);
    }

    function testBuyWithERC20AmountExceededTwoPhasesCorrectly() public {
        uint256 buyAmount = 20000 * (10 ** ERC20(usdcTokenAddress).decimals());
        address buyer = vm.addr(2);
        uint256 initialPhase = presale.currentPhase();
        vm.deal(buyer, 1 ether);

        vm.prank(buyer);
        deal(address(usdcTokenAddress), buyer, 100000 * (10 ** ERC20(usdcTokenAddress).decimals()));
        _sellWithToken(usdcTokenAddress, buyAmount, buyer);
        _sellWithToken(usdcTokenAddress, buyAmount * 5, buyer);

        _sellWithToken(usdcTokenAddress, buyAmount * 5, buyer);

        assert(presale.currentPhase() == initialPhase + 3);
    }

    function testBuyWithERC20RevertMaxSellingAmount() public {
        uint256 buyAmount = 20000 * (10 ** ERC20(usdcTokenAddress).decimals());
        address buyer = vm.addr(2);
        uint256 initialPhase = presale.currentPhase();
        vm.deal(buyer, 1 ether);

        vm.prank(buyer);
        deal(address(usdcTokenAddress), buyer, 100000 * (10 ** ERC20(usdcTokenAddress).decimals()));
        _sellWithToken(usdcTokenAddress, buyAmount, buyer);
        _sellWithToken(usdcTokenAddress, buyAmount * 5, buyer);
        assert(presale.currentPhase() == initialPhase + 2);

        _sellWithToken(usdcTokenAddress, buyAmount * 5, buyer);
        assert(presale.currentPhase() == initialPhase + 3);

        vm.startPrank(buyer);
        IERC20(usdcTokenAddress).approve(address(presale), buyAmount);

        vm.expectRevert("Sold out");
        presale.buyWithERC20(usdcTokenAddress, buyAmount);

        vm.stopPrank();
    }

    function testBuyWithERC20Correctly() public {
        uint256 buyAmount = 100 * (10 ** ERC20(usdcTokenAddress).decimals());
        address buyer = vm.addr(2);
        vm.deal(buyer, 1 ether);

        vm.prank(buyer);
        deal(address(usdcTokenAddress), buyer, 100000 * (10 ** ERC20(usdcTokenAddress).decimals()));

        _sellWithToken(usdcTokenAddress, buyAmount, buyer);
    }

    function testBuyWithMultipleERC20Correctly() public {
        uint256 usdcBuyAmount = 100 * (10 ** ERC20(usdcTokenAddress).decimals());
        uint256 usdbcBuyAmount = 100 * (10 ** ERC20(usdbcTokenAddress).decimals());
        address buyer = vm.addr(2);
        vm.deal(buyer, 1 ether);

        vm.prank(buyer);
        deal(address(usdcTokenAddress), buyer, 100000 * (10 ** ERC20(usdcTokenAddress).decimals()));
        _sellWithToken(usdcTokenAddress, usdcBuyAmount, buyer);

        deal(address(usdbcTokenAddress), buyer, 100000 * (10 ** ERC20(usdbcTokenAddress).decimals()));
        _sellWithToken(usdbcTokenAddress, usdbcBuyAmount, buyer);

        assert(IERC20(usdcTokenAddress).balanceOf(address(fundsReceiverAddress)) >= usdcBuyAmount);
        assert(IERC20(usdbcTokenAddress).balanceOf(address(fundsReceiverAddress)) >= usdbcBuyAmount);
    }

    function testEmergencyEtherWithdrawCorrectly() public {
        address randomAddress = vm.addr(3);

        vm.deal(randomAddress, 10 ether);
        vm.prank(randomAddress);
        (bool success,) = address(presale).call{value: 1 ether}("");
        require(success, "Transfer failed");

        assert(address(presale).balance == 1 ether);

        vm.startPrank(deployer);
        presale.emergencyEtherWithdraw();

        assert(address(presale).balance == 0);
        vm.stopPrank();
    }

    function testEmergencyEtherWithdrawRevertNoEther() public {
        vm.startPrank(deployer);

        vm.expectRevert("No pending balance to withdraw");
        presale.emergencyEtherWithdraw();

        vm.stopPrank();
    }

    function testEmergencyERC20WithdrawCorrectly() public {
        address randomAddress = vm.addr(2);
        uint256 transferredTokenAmount = 100 * (10 ** ERC20(usdcTokenAddress).decimals());

        assert(IERC20(usdcTokenAddress).balanceOf(address(presale)) == 0);

        deal(address(usdcTokenAddress), randomAddress, 100000 * (10 ** ERC20(usdcTokenAddress).decimals()));

        vm.prank(randomAddress);
        IERC20(usdcTokenAddress).approve(address(this), transferredTokenAmount * 2);
        IERC20(usdcTokenAddress).safeTransferFrom(randomAddress, address(presale), transferredTokenAmount);

        assert(IERC20(usdcTokenAddress).balanceOf(address(presale)) == transferredTokenAmount);

        vm.startPrank(deployer);
        presale.emergencyERC20Withdraw(usdcTokenAddress);

        assert(IERC20(usdcTokenAddress).balanceOf(address(presale)) == 0);
        vm.stopPrank();
    }

    function testClaimCorrectly() public {
        uint256 buyAmount = 1 ether;
        address buyer = vm.addr(2);

        vm.deal(buyer, 2 ether);
        _sellWithEth(buyAmount, buyer);

        vm.warp(endingTime);

        vm.startPrank(buyer);
        presale.claim();

        vm.stopPrank();
    }

    function testClaimRevertPresaleActive() public {
        uint256 buyAmount = 1 ether;
        address buyer = vm.addr(2);

        vm.deal(buyer, 2 ether);
        _sellWithEth(buyAmount, buyer);
        vm.expectRevert("Presale not ended");
        vm.prank(buyer);
        presale.claim();
    }

    function testClaimRevertNoTokensAllocated() public {
        address buyer = vm.addr(2);

        vm.warp(endingTime);
        vm.prank(buyer);
        vm.expectRevert("Zero tokens allocated");

        presale.claim();
    }

    function testClaimRevertNotEnoughTokens() public {
        uint256 buyAmount = 1 ether;
        address buyer = vm.addr(2);

        vm.deal(buyer, 2 ether);
        _sellWithEth(buyAmount, buyer);

        vm.startPrank(address(presale));
        ERC20(address(presaleToken)).transfer(vm.addr(1), maxSellingAmount);
        vm.stopPrank();

        vm.warp(endingTime);

        vm.startPrank(buyer);
        vm.expectRevert("Not enough tokens");
        presale.claim();

        vm.stopPrank();
    }

    // Helpers
    function _sellWithEth(uint256 buyAmount_, address buyer_) internal {
        uint256 receiverInitialBalance = address(fundsReceiverAddress).balance;
        uint256 presaleInitialBalance = address(presale).balance;
        uint256 totalSoldBefore = presale.totalSold();
        uint256 tokenBalanceBefore = presale.userTokenBalance(address(buyer_));
        uint256 buyerEtherBefore = address(buyer_).balance;

        vm.startPrank(buyer_);
        presale.buyWithEther{value: buyAmount_}();
        uint256 buyerEtherAfter = address(buyer_).balance;

        uint256 tokenBalanceAfter = presale.userTokenBalance(address(buyer_));
        uint256 tokenAmountToReceive = tokenBalanceAfter - tokenBalanceBefore;
        uint256 amountSellingWei = buyerEtherBefore - buyerEtherAfter;

        assert(address(presale).balance == presaleInitialBalance);
        assert(address(fundsReceiverAddress).balance == (amountSellingWei + receiverInitialBalance));
        assert(tokenBalanceAfter > tokenBalanceBefore);
        assert(presale.totalSold() == totalSoldBefore + tokenAmountToReceive);
        vm.stopPrank();
    }

    function _sellWithToken(address token_, uint256 buyAmount_, address buyer_) internal {
        uint256 receiverInitialBalance = IERC20(token_).balanceOf(address(fundsReceiverAddress));
        uint256 presaleInitialBalance = IERC20(token_).balanceOf(address(presale));
        uint256 totalSoldBefore = presale.totalSold();
        uint256 tokenBalanceBefore = presale.userTokenBalance(address(buyer_));
        uint256 buyerTokensBefore = IERC20(token_).balanceOf(address(buyer_));

        vm.startPrank(buyer_);
        IERC20(token_).approve(address(presale), buyAmount_);

        presale.buyWithERC20(token_, buyAmount_);
        uint256 buyerTokensAfter = IERC20(token_).balanceOf(address(buyer_));

        uint256 tokenBalanceAfter = presale.userTokenBalance(address(buyer_));
        uint256 tokenAmountToReceive = tokenBalanceAfter - tokenBalanceBefore;
        uint256 amountSellingWei = buyerTokensBefore - buyerTokensAfter;

        assert(IERC20(token_).balanceOf(address(presale)) == presaleInitialBalance);
        assert(IERC20(token_).balanceOf(address(fundsReceiverAddress)) == (amountSellingWei + receiverInitialBalance));
        assert(tokenBalanceAfter > tokenBalanceBefore);
        assert(presale.totalSold() == totalSoldBefore + tokenAmountToReceive);
        vm.stopPrank();
    }

    function _addPermitedTokens() internal {
        // Add cbBTC
        presale.addWhitelistedToken(cbBTCTokenAddress, 0x64c911996D3c6aC71f9b455B1E8E7266BcbD848F, 1 hours);

        // Add USDC
        presale.addWhitelistedToken(usdcTokenAddress, 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B, 3 days);

        // Add usdbcTokenAddress
        presale.addWhitelistedToken(usdbcTokenAddress, 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B, 3 days);

        (bool whitelisted1, address priceFeed1, uint256 threshold1) = presale.getWhitelistedToken(cbBTCTokenAddress);
        assert(whitelisted1);
        assert(priceFeed1 == 0x64c911996D3c6aC71f9b455B1E8E7266BcbD848F);
        assert(threshold1 == 1 hours);

        (bool whitelisted2, address priceFeed2, uint256 threshold2) = presale.getWhitelistedToken(usdcTokenAddress);
        assert(whitelisted2);
        assert(priceFeed2 == 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B);
        assert(threshold2 == 3 days);

        (bool whitelisted3, address priceFeed3, uint256 threshold3) = presale.getWhitelistedToken(usdbcTokenAddress);
        assert(whitelisted3);
        assert(priceFeed3 == 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B);
        assert(threshold3 == 3 days);
    }
}
