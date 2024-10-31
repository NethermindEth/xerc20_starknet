#[starknet::contract]
mod XERC20 {
    #[allow(unused_imports)]
    use openzeppelin_token::erc20::{
        erc20::{ERC20Component, ERC20HooksEmptyImpl}, snip12_utils::permit::Permit
    };
    #[allow(unused_imports)]
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, Map, StoragePathEntry
    };
    use openzeppelin_access::ownable::ownable::OwnableComponent;
    use starknet::ContractAddress;
    use xerc20_starknet::interfaces::ixerc20::IXERC20;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);

    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    // 1 Day
    pub const DURATION: u256 = 60 * 60 * 24;

    #[storage]
    struct Storage {
        factory: ContractAddress,
        lockbox: ContractAddress,
        bridges: Map<ContractAddress, Bridge>,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        erc20: ERC20Component::Storage
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        LockboxSet: LockboxSet,
        BridgeLimitsSet: BridgeLimitsSet,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        ERC20Event: ERC20Component::Event
    }

    #[derive(Drop, starknet::Event)]
    struct LockboxSet {
        pub lockbox: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct BridgeLimitsSet {
        pub minting_limit: u256,
        pub burning_limit: u256,
        #[key]
        pub bride: ContractAddress
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
        pub timestamp: u256,
        pub rate_per_second: u256,
        pub max_limits: u256,
        pub current_limit: u256
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, name: ByteArray, symbol: ByteArray, factory: ContractAddress
    ) {
        self.ownable.initializer(factory);
        self.erc20.initializer(name, symbol);
    }

    #[abi(embed_v0)]
    impl XERC20Impl of IXERC20<ContractState> {
        fn set_lockbox(ref self: ContractState, lockbox: ContractAddress) {}

        fn set_limits(
            ref self: ContractState,
            bridge: ContractAddress,
            minting_limit: u256,
            burning_limit: u256
        ) {}

        fn mint(ref self: ContractState, user: ContractAddress, amount: u256) {}

        fn burn(ref self: ContractState, user: ContractAddress, amount: u256) {}

        fn minting_max_limit_of(self: @ContractState, minter: ContractAddress) -> u256 {
            0
        }

        fn burning_max_limit_of(self: @ContractState, bridge: ContractAddress) -> u256 {
            0
        }

        fn minting_current_limit_of(self: @ContractState, minter: ContractAddress) -> u256 {
            0
        }

        fn burning_current_limit_of(self: @ContractState, bridge: ContractAddress) -> u256 {
            0
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        // NOTE: rather than change 'delta' might be better naming
        fn use_minter_limits(ref self: ContractState, bridge: ContractAddress, change: u256) {}

        // NOTE: rather than change 'delta' might be better naming
        fn use_burner_limits(ref self: ContractState, bridge: ContractAddress, change: u256) {}

        fn change_minter_limit(ref self: ContractState, bride: ContractAddress, limit: u256) {}

        fn change_burner_limit(ref self: ContractState, bridge: ContractAddress, limit: u256) {}
        // NOTE: Pure function in solidity might implement in seperate block since no state access
        // needed.
        fn calculate_new_current_limit(
            self: ContractState, limit: u256, old_limit: u256, current_limit: u256
        ) -> u256 {
            0
        }

        fn get_current_limit(
            ref self: ContractState,
            current_limit: u256,
            max_limit: u256,
            timestamp: u256,
            rate_per_second: u256
        ) -> u256 {
            0
        }

        fn burn_with_caller(
            ref self: ContractState, caller: ContractAddress, user: ContractAddress, amount: u256
        ) {}

        fn mint_with_caller(
            ref self: ContractState, caller: ContractAddress, user: ContractAddress, amount: u256
        ) {}
    }
}
