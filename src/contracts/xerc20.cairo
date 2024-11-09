use starknet::ContractAddress;

#[starknet::interface]
pub trait XERC20Initializer<TContractState> {
    fn initialize(
        ref self: TContractState, name: ByteArray, symbol: ByteArray, factory: ContractAddress
    );
}

#[starknet::contract]
pub mod XERC20 {
    use crate::interfaces::ixerc20::{IXERC20, BridgeSerde, BridgeParametersSerde};
    use openzeppelin_access::ownable::ownable::OwnableComponent;
    use openzeppelin_security::initializable::InitializableComponent;
    use openzeppelin_token::erc20::{erc20::{ERC20Component, ERC20HooksEmptyImpl}};
    use openzeppelin_utils::cryptography::{nonces::NoncesComponent, snip12::SNIP12Metadata};
    use starknet::ContractAddress;
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, Map, StoragePathEntry
    };

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    component!(path: NoncesComponent, storage: nonces, event: NoncesEvent);

    impl NoncesImpl = NoncesComponent::NoncesImpl<ContractState>;
    impl NoncesInternalImpl = NoncesComponent::InternalImpl<ContractState>;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);

    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    #[abi(embed_v0)]
    impl SNIP12MetadataExternalImpl =
        ERC20Component::SNIP12MetadataExternalImpl<ContractState>;
    #[abi(embed_v0)]
    impl ERC20PermitImpl = ERC20Component::ERC20PermitImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    component!(path: InitializableComponent, storage: initializable, event: InitializableEvent);

    #[abi(embed_v0)]
    impl InitializableImpl =
        InitializableComponent::InitializableImpl<ContractState>;
    impl InitializableOInternalImpl = InitializableComponent::InternalImpl<ContractState>;

    // 1 Day
    pub const DURATION: u64 = 60 * 60 * 24;
    pub const U256MAX_DIV_2: u256 = core::num::traits::Bounded::MAX / 2;

    #[storage]
    struct Storage {
        factory: ContractAddress,
        lockbox: ContractAddress,
        bridges: Map<ContractAddress, Bridge>,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        initializable: InitializableComponent::Storage,
        #[substorage(v0)]
        nonces: NoncesComponent::Storage
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        LockboxSet: LockboxSet,
        BridgeLimitsSet: BridgeLimitsSet,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        InitializableEvent: InitializableComponent::Event,
        #[flat]
        NoncesEvent: NoncesComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    pub struct LockboxSet {
        pub lockbox: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct BridgeLimitsSet {
        pub minting_limit: u256,
        pub burning_limit: u256,
        #[key]
        pub bridge: ContractAddress
    }

    pub mod Errors {
        pub const NOT_HIGH_ENOUGH_LIMITS: felt252 = 'User does not have enough limit';
        pub const CALLER_NOT_FACTORY: felt252 = 'Caller is not the factory';
        pub const LIMITS_TO_HIGH: felt252 = 'Limits too high';
    }

    #[starknet::storage_node]
    pub struct Bridge {
        pub minter_params: BridgeParameters,
        pub burner_params: BridgeParameters
    }

    #[starknet::storage_node]
    pub struct BridgeParameters {
        pub timestamp: u64,
        pub rate_per_second: u256,
        pub max_limit: u256,
        pub current_limit: u256
    }

    pub impl SNIP12MetadataImpl of SNIP12Metadata {
        fn name() -> felt252 {
            'XERC20_Starknet'
        }
        fn version() -> felt252 {
            '0.1.0'
        }
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, name: ByteArray, symbol: ByteArray, factory: ContractAddress
    ) {
        self.ownable.initializer(factory);
        self.erc20.initializer(name, symbol);
        self.initializable.initialize();
    }

    #[abi(embed_v0)]
    impl InitializerImpl of super::XERC20Initializer<ContractState> {
        /// Dev: meanted to called if initialied by the proxy via upgrade, otherwise constructor
        /// will be executed.
        fn initialize(
            ref self: ContractState, name: ByteArray, symbol: ByteArray, factory: ContractAddress
        ) {
            self.ownable.initializer(factory);
            self.erc20.initializer(name, symbol);
            self.initializable.initialize();
        }
    }

    #[abi(embed_v0)]
    impl XERC20Impl of IXERC20<ContractState> {
        fn set_lockbox(ref self: ContractState, lockbox: ContractAddress) {
            self.ownable.assert_only_owner();
            self.lockbox.write(lockbox);
            self.emit(LockboxSet { lockbox });
        }

        fn set_limits(
            ref self: ContractState,
            bridge: ContractAddress,
            minting_limit: u256,
            burning_limit: u256
        ) {
            self.ownable.assert_only_owner();
            assert(
                minting_limit <= U256MAX_DIV_2 && burning_limit <= U256MAX_DIV_2,
                Errors::LIMITS_TO_HIGH
            );

            self.change_minter_limit(bridge, minting_limit);
            self.change_burner_limit(bridge, burning_limit);
            self.emit(BridgeLimitsSet { minting_limit, burning_limit, bridge });
        }

        fn mint(ref self: ContractState, user: ContractAddress, amount: u256) {
            self.mint_with_caller(starknet::get_caller_address(), user, amount);
        }

        fn burn(ref self: ContractState, user: ContractAddress, amount: u256) {
            let caller = starknet::get_caller_address();
            if caller != user {
                self.erc20._spend_allowance(user, caller, amount);
            }
            self.burn_with_caller(caller, user, amount);
        }

        fn minting_max_limit_of(self: @ContractState, minter: ContractAddress) -> u256 {
            self.bridges.entry(minter).minter_params.deref().max_limit.read()
        }

        fn burning_max_limit_of(self: @ContractState, bridge: ContractAddress) -> u256 {
            self.bridges.entry(bridge).burner_params.deref().max_limit.read()
        }

        fn minting_current_limit_of(self: @ContractState, minter: ContractAddress) -> u256 {
            let minter_params_storage_path = self.bridges.entry(minter).minter_params.deref();
            get_current_limit(
                minter_params_storage_path.current_limit.read(),
                minter_params_storage_path.max_limit.read(),
                minter_params_storage_path.timestamp.read(),
                minter_params_storage_path.rate_per_second.read()
            )
        }

        fn burning_current_limit_of(self: @ContractState, bridge: ContractAddress) -> u256 {
            let burner_params_storage_path = self.bridges.entry(bridge).burner_params.deref();
            get_current_limit(
                burner_params_storage_path.current_limit.read(),
                burner_params_storage_path.max_limit.read(),
                burner_params_storage_path.timestamp.read(),
                burner_params_storage_path.rate_per_second.read()
            )
        }

        fn lockbox(self: @ContractState) -> ContractAddress {
            self.lockbox.read()
        }

        fn factory(self: @ContractState) -> ContractAddress {
            self.factory.read()
        }

        fn get_bridge_params(self: @ContractState, bridge: ContractAddress) -> BridgeSerde {
            let bridge_storage_path = self.bridges.entry(bridge).deref();
            let minter_params = bridge_storage_path.minter_params.deref();
            let burner_params = bridge_storage_path.burner_params.deref();
            BridgeSerde {
                minter_params: BridgeParametersSerde {
                    timestamp: minter_params.timestamp.read(),
                    rate_per_second: minter_params.rate_per_second.read(),
                    max_limit: minter_params.max_limit.read(),
                    current_limit: minter_params.current_limit.read()
                },
                burner_params: BridgeParametersSerde {
                    timestamp: burner_params.timestamp.read(),
                    rate_per_second: burner_params.rate_per_second.read(),
                    max_limit: burner_params.max_limit.read(),
                    current_limit: burner_params.current_limit.read()
                }
            }
        }
    }

    fn calculate_new_current_limit(limit: u256, old_limit: u256, current_limit: u256) -> u256 {
        if old_limit <= limit {
            let difference = limit - old_limit;
            return current_limit + difference;
        }

        let difference = old_limit - limit;
        if current_limit > difference {
            current_limit - difference
        } else {
            0
        }
    }

    fn get_current_limit(
        current_limit: u256, max_limit: u256, timestamp: u64, rate_per_second: u256
    ) -> u256 {
        if current_limit == max_limit {
            return current_limit;
        }

        let current_timestamp = starknet::get_block_timestamp();
        if timestamp + DURATION <= current_timestamp {
            return max_limit;
        }

        let time_delta = current_timestamp - timestamp;
        let calculated_limit = current_limit + (time_delta.into() * rate_per_second);
        if calculated_limit > max_limit {
            max_limit
        } else {
            calculated_limit
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn use_minter_limits(ref self: ContractState, bridge: ContractAddress, change: u256) {
            let current_limit = self.minting_current_limit_of(bridge);
            let minter_params_storage_path = self.bridges.entry(bridge).minter_params.deref();
            minter_params_storage_path.timestamp.write(starknet::get_block_timestamp());
            minter_params_storage_path.current_limit.write(current_limit - change);
        }

        fn use_burner_limits(ref self: ContractState, bridge: ContractAddress, change: u256) {
            let current_limit = self.burning_current_limit_of(bridge);
            let burner_params_storage_path = self.bridges.entry(bridge).burner_params.deref();
            burner_params_storage_path.timestamp.write(starknet::get_block_timestamp());
            burner_params_storage_path.current_limit.write(current_limit - change);
        }

        fn change_minter_limit(ref self: ContractState, bridge: ContractAddress, limit: u256) {
            let minter_params_storage_path = self.bridges.entry(bridge).minter_params.deref();
            let old_limit = minter_params_storage_path.max_limit.read();
            let current_limit = self.minting_current_limit_of(bridge);

            minter_params_storage_path.max_limit.write(limit);
            let new_current_limit = calculate_new_current_limit(limit, old_limit, current_limit);
            minter_params_storage_path.current_limit.write(new_current_limit);
            minter_params_storage_path.rate_per_second.write(limit / DURATION.into());
            minter_params_storage_path.timestamp.write(starknet::get_block_timestamp());
        }

        fn change_burner_limit(ref self: ContractState, bridge: ContractAddress, limit: u256) {
            let burner_params_storage_path = self.bridges.entry(bridge).burner_params.deref();
            let old_limit = burner_params_storage_path.max_limit.read();
            let current_limit = self.burning_current_limit_of(bridge);

            burner_params_storage_path.max_limit.write(limit);
            let new_current_limit = calculate_new_current_limit(limit, old_limit, current_limit);
            burner_params_storage_path.current_limit.write(new_current_limit);
            burner_params_storage_path.rate_per_second.write(limit / DURATION.into());
            burner_params_storage_path.timestamp.write(starknet::get_block_timestamp());
        }

        fn burn_with_caller(
            ref self: ContractState, caller: ContractAddress, user: ContractAddress, amount: u256
        ) {
            if caller != self.lockbox.read() {
                let current_limit = self.burning_current_limit_of(caller);
                assert(current_limit >= amount, Errors::NOT_HIGH_ENOUGH_LIMITS);
                self.use_burner_limits(caller, amount);
            }
            self.erc20.burn(user, amount);
        }

        fn mint_with_caller(
            ref self: ContractState, caller: ContractAddress, user: ContractAddress, amount: u256
        ) {
            if caller != self.lockbox.read() {
                let current_limit = self.minting_current_limit_of(caller);
                assert(current_limit >= amount, Errors::NOT_HIGH_ENOUGH_LIMITS);
                self.use_minter_limits(caller, amount);
            }
            self.erc20.mint(user, amount);
        }
    }
}
