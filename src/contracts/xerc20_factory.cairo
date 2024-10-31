//! Solidity version uses CREATE3
//! Need EnumerableSet impl
#[starknet::contract]
mod XERC20Factory {
    #[allow(unused_imports)]
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, Map, StoragePathEntry
    };
    #[allow(unused_imports)]
    use xerc20_starknet::interfaces::ixerc20_factory::IXERC20Factory;
    use core::num::traits::Zero;
    use starknet::ContractAddress;

    #[storage]
    struct Storage {
        lockbox_registry: Map<ContractAddress, ContractAddress>,
        lockbox_registry_array: Map<ContractAddress, bool>, /// TODO: Need EnumerableSet.AddressSet
        xerc20_registry_array: Map<ContractAddress, bool> /// TODO: Need EnumerableSet.AddressSet
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        XERC20Deployed: XERC20Deployed,
        LockboxDeployed: LockboxDeployed
    }

    #[derive(Drop, starknet::Event)]
    struct XERC20Deployed {
        xerc20: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct LockboxDeployed {
        lockbox: ContractAddress,
    }

    pub mod Errors {
        pub const CALLER_NOT_OWNER: felt252 = 'Caller is not the owner';
        pub const BAD_TOKEN_ADDRESS: felt252 = 'Bad token address';
        pub const LOCKBOX_ALREADY_DEPLOYED: felt252 = 'Lockbox alread deployed';
        pub const INVALID_LENGTH: felt252 = 'Invalid length';
    }

    #[abi(embed_v0)]
    impl XERC20FactoryImpl of IXERC20Factory<ContractState> {
        fn deploy_xerc20(
            ref self: ContractState,
            name: ByteArray,
            symbol: ByteArray,
            minter_limits: Span<u256>,
            burner_limits: Span<u256>,
            bridges: Span<ContractAddress>
        ) -> ContractAddress {
            let deployed_address = self
                ._deploy_xerc20(name, symbol, minter_limits, burner_limits, bridges);
            self.emit(XERC20Deployed { xerc20: deployed_address });
            deployed_address
        }

        // NOTE: We might not need `is_native`
        fn deploy_lockbox(
            ref self: ContractState,
            xerc20: ContractAddress,
            base_token: ContractAddress,
            is_native: bool
        ) -> ContractAddress {
            let deployed_address = self._deploy_lockbox(xerc20, base_token, is_native);
            self.emit(LockboxDeployed { lockbox: deployed_address });
            deployed_address
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _deploy_xerc20(
            ref self: ContractState,
            name: ByteArray,
            symbol: ByteArray,
            minter_limits: Span<u256>,
            burner_limits: Span<u256>,
            bridges: Span<ContractAddress>
        ) -> ContractAddress {
            Zero::zero()
        }

        fn _deploy_lockbox(
            ref self: ContractState,
            xerc20: ContractAddress,
            base_token: ContractAddress,
            is_native: bool
        ) -> ContractAddress {
            Zero::zero()
        }
    }
}
