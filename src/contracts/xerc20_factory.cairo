#[starknet::contract]
pub mod XERC20Factory {
    use core::num::traits::Zero;
    use openzeppelin_access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
    use starknet::ClassHash;
    use starknet::ContractAddress;
    use starknet::SyscallResultTrait;
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, Map, StoragePathEntry
    };
    use xerc20_starknet::interfaces::{
        ixerc20_factory::IXERC20Factory, ixerc20::{IXERC20Dispatcher, IXERC20DispatcherTrait}
    };
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
    pub enum Event {
        XERC20Deployed: XERC20Deployed,
        LockboxDeployed: LockboxDeployed
    }

    #[derive(Drop, starknet::Event)]
    pub struct XERC20Deployed {
        pub xerc20: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct LockboxDeployed {
        pub lockbox: ContractAddress,
    }

    pub mod Errors {
        pub const CALLER_NOT_OWNER: felt252 = 'Caller is not the owner';
        pub const BAD_TOKEN_ADDRESS: felt252 = 'Bad token address';
        pub const LOCKBOX_ALREADY_DEPLOYED: felt252 = 'Lockbox alread deployed';
        pub const INVALID_LENGTH: felt252 = 'Invalid length';
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        create3_proxy_class_hash: ClassHash,
        xerc20_class_hash: ClassHash,
        lockbox_class_hash: ClassHash
    ) {
        self.create3_proxy_class_hash.write(create3_proxy_class_hash);
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

        fn deploy_lockbox(
            ref self: ContractState, xerc20: ContractAddress, base_token: ContractAddress,
        ) -> ContractAddress {
            assert(base_token.is_non_zero(), Errors::BAD_TOKEN_ADDRESS);
            let base_token_owner = IOwnableDispatcher { contract_address: xerc20 }.owner();

            assert(base_token_owner == starknet::get_caller_address(), Errors::CALLER_NOT_OWNER);
            let lockbock_storage_path = self.lockbox_registry.entry(xerc20);
            assert(lockbock_storage_path.read().is_zero(), Errors::LOCKBOX_ALREADY_DEPLOYED);
            let deployed_address = self._deploy_lockbox(xerc20, base_token);
            lockbock_storage_path.write(deployed_address);
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
            /// There is no address compatibility between Cairo Vm and EVM.
            starknet::get_caller_address().serialize(ref serialized_data);
            let salt = core::poseidon::poseidon_hash_span(serialized_data.span());
            let mut serialized_ctor_data: Array<felt252> = array![];
            name.serialize(ref serialized_ctor_data);
            symbol.serialize(ref serialized_ctor_data);
            starknet::get_contract_address().serialize(ref serialized_ctor_data);

            let deployed_address = self
                .create_without_init_code_factor(
                    self.xerc20_class_hash.read(),
                    salt,
                    Option::Some(selector!("initialize")),
                    Option::Some(serialized_ctor_data.span())
                );

            let xerc20_dispatcher = IXERC20Dispatcher { contract_address: deployed_address };
            for i in 0
                ..minter_limits
                    .len() {
                        xerc20_dispatcher
                            .set_limits(*bridges.at(i), *minter_limits.at(i), *burner_limits.at(i));
                    };
            self.xerc20_registry_array.entry(deployed_address).write(true);
            IOwnableDispatcher { contract_address: deployed_address }
                .transfer_ownership(starknet::get_caller_address());
            deployed_address
        }

        fn _deploy_lockbox(
            ref self: ContractState, xerc20: ContractAddress, base_token: ContractAddress,
        ) -> ContractAddress {
            let mut serialized_data: Array<felt252> = array![];
            xerc20.serialize(ref serialized_data);
            base_token.serialize(ref serialized_data);
            /// deploy with create 3 here but we only benefit from future cairo vms to be able to
            /// deploy to same address.
            /// There is no address compatibility between Cairo Vm and EVM.
            starknet::get_caller_address().serialize(ref serialized_data);
            let salt = core::poseidon::poseidon_hash_span(serialized_data.span());
            let mut serialized_ctor_data: Array<felt252> = array![];
            xerc20.serialize(ref serialized_ctor_data);
            base_token.serialize(ref serialized_ctor_data);

            let deployed_address = self
                .create_without_init_code_factor(
                    self.lockbox_class_hash.read(),
                    salt,
                    Option::Some(selector!("initialize")),
                    Option::Some(serialized_ctor_data.span())
                );
            self.xerc20_registry_array.entry(deployed_address).write(true);
            deployed_address
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
