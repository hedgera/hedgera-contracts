// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IIndexToken.sol";

/**
 * @title IndexToken
 * @notice ERC-20 token representing shares in a Hedgera index
 * @dev Only the associated vault can mint and burn tokens
 */
contract IndexToken is ERC20, Ownable, ReentrancyGuard, IIndexToken {
    /// @notice The vault contract that can mint/burn these tokens
    address public vault;
    
    /// @notice The index ID this token represents
    uint256 public indexId;
    
    /// @notice Whether the token has been initialized
    bool private _initialized;

    /**
     * @notice Constructor
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param indexId_ The index ID this token represents
     * @param owner_ Owner of the contract (typically IndexFactory)
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 indexId_,
        address owner_
    ) ERC20(name_, symbol_) Ownable(owner_) {
        indexId = indexId_;
        _initialized = false;
    }

    /**
     * @notice Initializes the token with its vault address
     * @param vault_ Address of the vault contract
     * @dev Can only be called once by the owner
     */
    function initialize(address vault_) external onlyOwner {
        require(!_initialized, "IndexToken: already initialized");
        require(vault_ != address(0), "IndexToken: vault cannot be zero address");
        
        vault = vault_;
        _initialized = true;
        
        emit VaultUpdated(address(0), vault_);
    }

    /**
     * @notice Mints new tokens (only callable by the vault)
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external override onlyVault nonReentrant {
        require(to != address(0), "IndexToken: mint to zero address");
        require(amount > 0, "IndexToken: mint amount must be positive");
        
        _mint(to, amount);
    }

    /**
     * @notice Burns tokens (only callable by the vault)
     * @param from Address to burn tokens from
     * @param amount Amount of tokens to burn
     */
    function burn(address from, uint256 amount) external override onlyVault nonReentrant {
        require(from != address(0), "IndexToken: burn from zero address");
        require(amount > 0, "IndexToken: burn amount must be positive");
        require(balanceOf(from) >= amount, "IndexToken: burn amount exceeds balance");
        
        _burn(from, amount);
    }

    /**
     * @notice Gets the associated vault address
     * @return vault Address of the vault
     */
    function getVault() external view override returns (address) {
        return vault;
    }

    /**
     * @notice Gets the index ID this token represents
     * @return indexId The index ID
     */
    function getIndexId() external view override returns (uint256) {
        return indexId;
    }

    /**
     * @notice Gets token metadata
     * @return name Token name
     * @return symbol Token symbol
     * @return decimals Token decimals (always 18)
     */
    function getMetadata() external view override returns (string memory, string memory, uint8) {
        return (name(), symbol(), decimals());
    }

    /**
     * @notice Updates the vault address (only owner)
     * @param newVault New vault address
     * @dev Emergency function to update vault if needed
     */
    function updateVault(address newVault) external onlyOwner {
        require(newVault != address(0), "IndexToken: vault cannot be zero address");
        require(newVault != vault, "IndexToken: same vault address");
        
        address oldVault = vault;
        vault = newVault;
        
        emit VaultUpdated(oldVault, newVault);
    }

    /**
     * @notice Checks if the token is initialized
     * @return initialized Whether the token is initialized
     */
    function isInitialized() external view returns (bool) {
        return _initialized;
    }

    /**
     * @notice Modifier to restrict access to vault only
     */
    modifier onlyVault() {
        require(_initialized, "IndexToken: not initialized");
        require(msg.sender == vault, "IndexToken: caller is not the vault");
        _;
    }

    /**
     * @notice Override transfer to add basic validation
     * @param to Recipient address
     * @param value Amount to transfer
     * @return success Whether transfer succeeded
     */
    function transfer(address to, uint256 value) public override(ERC20, IERC20) returns (bool) {
        require(to != address(0), "IndexToken: transfer to zero address");
        require(to != address(this), "IndexToken: transfer to token contract");
        return super.transfer(to, value);
    }

    /**
     * @notice Override transferFrom to add basic validation
     * @param from Sender address
     * @param to Recipient address
     * @param value Amount to transfer
     * @return success Whether transfer succeeded
     */
    function transferFrom(address from, address to, uint256 value) public override(ERC20, IERC20) returns (bool) {
        require(to != address(0), "IndexToken: transfer to zero address");
        require(to != address(this), "IndexToken: transfer to token contract");
        require(from != address(0), "IndexToken: transfer from zero address");
        return super.transferFrom(from, to, value);
    }
} 