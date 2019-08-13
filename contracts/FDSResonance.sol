pragma solidity ^0.5.0;

import "openzeppelin-solidity/contracts/math/Math.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/SafeERC20.sol";

interface IBNB {
    function balanceOf(address who) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address to, uint256 value) external;
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

contract FDSResonance {
    using Math for uint256;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Total FDS (700 million).
    uint256 constant public TOTAL_FDS = 7*10**26;

    // BNB soft goal (200,000 BNB).
    uint256 constant public BNB_SOFT_GOAL = 2*10**23;

    // BNB hard goal (700,000 BNB).
    uint256 constant public BNB_HARD_GOAL = 7*10**23;

    // Max batch number;
    uint256 constant public MAX_BATCH_NUMBER = 1000;

    IERC20 public fdsToken;         // FDS token.
    IBNB public bnbToken;         // BNB token.
    uint256 public startBlock;
    uint256 public endBlock;
    address public owner;
    address public receiver;
    uint256 public currentBNB;
    uint256 public stockOfFDS;      // All stock of FDS.
    uint256 public batchNumber;     // Exchange batch number.
    uint256 public ramainingStock;  // Ramaining stock of current batch.
    uint256 public totalStock;      // Total stock of current batch.

    bool public closed;
    bool public goalReached;

    struct Record {
        uint256 bnb;
        uint256 fds;
    }

    mapping (address => Record) public records;

    /** 
     * EVENTS
     */
    event Exchange(address indexed sender, uint256 bnb, uint256 fds);
    event Withdrawal(address indexed sender, uint256 bnb, uint256 fds);

    // Initialize the contract
    constructor(address r, address fdsAddress, address bnbAddress, uint256 start, uint256 end) public {
        fdsToken = IERC20(fdsAddress);
        bnbToken = IBNB(bnbAddress);
        startBlock = start;
        endBlock = end;
        owner = msg.sender;
        receiver = r;

        currentBNB = 0;
        stockOfFDS = TOTAL_FDS;
        batchNumber = 1;
        ramainingStock = batchStock(batchNumber);
        totalStock = batchStock(batchNumber);

        closed = false;
        goalReached = false;
    }

    // Get exchange ratio, 1 BNB to n FDS.
    function ratio() public view returns (uint256) {
        (uint256 fds,,,) = _calc(10**18, batchNumber, ramainingStock, totalStock);
        return fds;
    }

    // Get exchange ratio with batch number, 1 BNB to n FDS.
    function ratioWithBatchNumber(uint256 bn) public pure returns (uint256) {
        require(bn <= MAX_BATCH_NUMBER, "The batch number is too large.");
        uint256 stock = _calcBatchStock(bn) * 10**18;
        (uint256 fds,,,) = _calc(10**18, bn, stock, stock);
        return fds;
    }

    // Get batch stock with batch number.
    function batchStock(uint256 bn) public pure returns (uint256) {
        require(bn <= MAX_BATCH_NUMBER, "The batch number is too large.");
        return _calcBatchStock(bn) * 10**18;
    }

    // Exchange BNB for FDS
    function exchange() public returns (bool) {
        require(block.number >= startBlock, "Coming soon.");
        require(block.number <= endBlock, "End of time.");
        require(batchNumber <= MAX_BATCH_NUMBER, "Invalid batch number.");
        require(!closed, "Resonance closed.");

        uint256 bnb = bnbToken
            .balanceOf(msg.sender)
            .min(bnbToken.allowance(msg.sender, address(this)));
        require(bnb > 0, "Lack of allowance or balance.");
        require(bnb <= BNB_HARD_GOAL - currentBNB, "Too much BNB.");
        require(bnb % 10**18 == 0, "BNB must be an integer.");

        uint256 fds;
        uint256 bn;
        uint256 rs;
        uint256 ts;
        (fds, bn, rs, ts) = _calc(bnb, batchNumber, ramainingStock, totalStock);
        require(fdsToken.balanceOf(address(this)) >= fds, "Lack of FDS token.");
        require(bn <= MAX_BATCH_NUMBER + 1, "Invalid batch number.");

        batchNumber = bn;
        ramainingStock = rs;
        totalStock = ts;
        currentBNB = currentBNB.add(bnb); // Add current BNB.
        stockOfFDS = stockOfFDS.sub(fds);

        Record storage record = records[msg.sender];
        record.bnb = record.bnb.add(bnb);
        record.fds = record.fds.add(fds);
        records[msg.sender] = record; // Record the exchange.

        require(bnbToken.transferFrom(msg.sender, address(this), bnb));
        fdsToken.safeTransfer(msg.sender, fds);

        emit Exchange(msg.sender, bnb, fds);
        return true;
    }

    // Close resonance
    function close() public returns (bool) {
        require(msg.sender == owner, "Invalid sender.");
        require(!closed, "Already closed.");

        require(
            block.number > endBlock || batchNumber == MAX_BATCH_NUMBER + 1,
            "Condition unmet."
        );

        if (currentBNB >= BNB_SOFT_GOAL) {
            goalReached = true;
        }
        closed = true;

        return true;
    }

    // Withdraws all BNB and FDS.
    function withdraw() public returns (bool) {
        require(closed, "Is underway.");

        if (goalReached) {
            require(msg.sender == receiver, "Invalid sender.");

            uint256 fds = fdsToken.balanceOf(address(this));
            uint256 bnb = bnbToken.balanceOf(address(this));
            require(fds > 0 || bnb > 0, "The balance is empty.");

            if (fds > 0) fdsToken.safeTransfer(msg.sender, fds);
            if (bnb > 0) bnbToken.transfer(msg.sender, bnb);
            emit Withdrawal(msg.sender, bnb, fds);
            return true;
        } else {
            Record storage record = records[msg.sender];
            require(record.bnb > 0, "The balance is empty.");

            uint256 bnb = record.bnb;
            delete records[msg.sender];
            bnbToken.transfer(msg.sender, bnb);
            emit Withdrawal(msg.sender, bnb, 0);
            return true;
        }
    }

    function _calc(uint256 bnb, uint256 batchNum, uint256 curBatchRemainingStock, uint256 curBatchTotalStock)
        private
        pure 
        returns (uint256, uint256, uint256, uint256) {
        uint256 fds = 0;
        uint256 rBNB = bnb;
        uint256 num = batchNum;
        uint256 rBatchStock = curBatchRemainingStock;
        uint256 tBatchStock = curBatchTotalStock;
        uint256 rBatchBNB = curBatchRemainingStock * 70000 * 10**18 / curBatchTotalStock / 100;

        while (rBNB > 0) {
            if (rBNB == rBatchBNB) {
                fds = fds.add(rBatchStock);
                rBNB = 0;
                num = num.add(1);
                rBatchStock = _calcBatchStock(num) * 10**18;
                tBatchStock = rBatchStock;
            } else if (rBNB > rBatchBNB) {
                fds = fds.add(rBatchStock);
                rBNB = rBNB.sub(rBatchBNB);
                num = num.add(1);
                rBatchStock = _calcBatchStock(num) * 10**18;
                tBatchStock = rBatchStock;
                rBatchBNB = 700 * 10**18;
            } else {
                uint256 t = (rBNB * 100 * tBatchStock) / (70000 * 10**18);
                fds = fds.add(t);
                rBatchStock = rBatchStock.sub(t);
                rBatchBNB = rBatchBNB.sub(rBNB);
                rBNB = 0;
            }
        }
        return (fds, num, rBatchStock, tBatchStock);
    }

    function _calcBatchStock(uint256 n) private pure returns (uint256) {
        uint256 a = 108722;
        uint256 b = 1166736111111111111;
        uint256 c = 70000 * 20;
        if (n == 1) {
            return c * a / 10**5;
        } else {
            uint256 d = 250000 - (n - 1 - 500)**2;
            uint256 e = c - n**2 * b / 10**18;
            return (e * 10 - d * 22) * a / 10 / 10**5;
        }
    }
}

