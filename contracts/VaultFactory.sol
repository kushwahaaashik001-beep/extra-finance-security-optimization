// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./external/openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IAddressRegistry.sol";
import "./interfaces/IVaultFactory.sol";
import "./interfaces/IVeloVault.sol";
import "./libraries/helpers/Errors.sol";

contract VaultFactory is Ownable, IVaultFactory {
    mapping(uint256 => address) public vaults;
    uint256 public nextVaultID;

    // global address provider
    address public immutable addressRegistry;

    constructor(address _addressRegistry) {
        require(_addressRegistry != address(0), Errors.VL_ADDRESS_CANNOT_ZERO);
        addressRegistry = _addressRegistry;
        nextVaultID = 1;
    }

    /// @notice  New a Vault which contains the amm pool's info and the debt positions
    /// Each vault has a debt position that is shared by all the vault positions of this vault
    /// @return vaultId The ID of vault
    function newVault(
        bytes calldata params
    ) external onlyOwner returns (uint256 vaultId) {
        vaultId = nextVaultID;
        nextVaultID = nextVaultID + 1;

        address libraryAddress = IAddressRegistry(addressRegistry).getAddress(
            AddressId.ADDRESS_ID_VAULT_DEPLOYER_SELECTOR
        );
        require(libraryAddress != address(0), "Library address is not set");

        // Move #3: Gas Optimized Delegatecall with Yul
        // We save gas by avoiding abi.encode overhead and manual result copying
        address vaultAddress;
        bytes4 selector = 0x3d0d8680; // bytes4(keccak256("deploy(address,uint256,bytes)"))
        
        address registry = addressRegistry; // Must be local for assembly access

        assembly {
            let ptr := mload(0x40)
            mstore(ptr, selector)
            mstore(add(ptr, 0x04), registry)
            mstore(add(ptr, 0x24), vaultId)
            
            // Copy dynamic bytes 'params'
            calldatacopy(add(ptr, 0x44), params.offset, params.length)
            
            let success := delegatecall(gas(), libraryAddress, ptr, add(0x44, params.length), 0x00, 0x20)
            
            if iszero(success) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
            
            vaultAddress := mload(0x00)
        }

        IVeloVault vault = IVeloVault(vaultAddress);

        vaults[vaultId] = vaultAddress;
        emit NewVault(
            vault.token0(),
            vault.token1(),
            vault.stable(),
            vaultAddress,
            vaultId
        );
    }
}
