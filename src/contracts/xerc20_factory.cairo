#[starknet::contract]
mod XERC20Factory {
    use core::num::traits::Zero;
    use starknet::ClassHash;
    use starknet::ContractAddress;
    use starknet::SyscallResultTrait;
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, Map, StoragePathEntry
    };
    use xerc20_starknet::interfaces::ixerc20_factory::IXERC20Factory;
    use xerc20_starknet::utils::create3_proxy::{
        ICreate3ProxyDispatcher, ICreate3ProxyDispatcherTrait
    };

    #[storage]
    struct Storage {
        xerc20_class_hash: starknet::ClassHash,
        lockbox_class_hash: starknet::ClassHash,
        create3_proxy_class_hash: starknet::ClassHash,
        lockbox_registry: Map<ContractAddress, ContractAddress>,
        /// NOTE: solidity version only uses add method of enumerable set and they are 'internal'
        /// so if this supposed be top-level contract no need to implement enumerable set.
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

    #[constructor]
    fn constructor(
        ref self: ContractState, xerc20_class_hash: ClassHash, lockbox_class_hash: ClassHash
    ) {
        self.xerc20_class_hash.write(xerc20_class_hash);
        self.lockbox_class_hash.write(lockbox_class_hash);
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
            assert(
                minter_limits.len() == bridges.len() && bridges.len() == burner_limits.len(),
                Errors::INVALID_LENGTH
            );
            let mut serialized_data: Array<felt252> = array![];
            name.serialize(ref serialized_data);
            symbol.serialize(ref serialized_data);

            /// deploy with create 3 here but we only benefit from future cairo vms to be able to
            /// deploy to same address.
            /// There is no address compoatibility between Cairo Vm and EVM.
            starknet::get_caller_address().serialize(ref serialized_data);
            let salt = core::poseidon::poseidon_hash_span(serialized_data.span());
            let serialized_ctor_data: Array<felt252> = array![];
            let deployed_address = self
                .create_without_init_code_factor(
                    self.xerc20_class_hash.read(),
                    salt,
                    Option::Some(selector!("initialize")),
                    Option::Some(serialized_ctor_data.span())
                );
            let registry_storage_path = self.xerc20_registry_array.entry(deployed_address);
            registry_storage_path.write(true);
            deployed_address
        }

        fn _deploy_lockbox(
            ref self: ContractState,
            xerc20: ContractAddress,
            base_token: ContractAddress,
            is_native: bool
        ) -> ContractAddress {
            Zero::zero()
        }

        fn create_without_init_code_factor(
            ref self: ContractState,
            class_hash: ClassHash,
            salt: felt252,
            selector: Option<felt252>,
            calldata: Option<Span<felt252>>
        ) -> ContractAddress {
            let (deployed_address, _) = starknet::syscalls::deploy_syscall(
                self.create3_proxy_class_hash.read(), salt, [].span(), false
            )
                .unwrap_syscall();
            // call contract to upgrade itself to desired implementation and initialize the code.
            ICreate3ProxyDispatcher { contract_address: deployed_address }
                .initialize(class_hash, selector, calldata);
            deployed_address
        }
    }
}
