#[starknet::component]
pub mod XERC20Component {
    use crate::interfaces::ixerc20::IXERC20;
    use openzeppelin_access::ownable::ownable::{
        OwnableComponent, OwnableComponent::InternalTrait as OwnableInternalTrait
    };
    use openzeppelin_token::erc20::{
        erc20::{ERC20Component, ERC20Component::InternalTrait as ERC20InternalTrait}
    };
    use starknet::ContractAddress;
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, Map, StoragePathEntry
    };

    pub const U256MAX_DIV_2: u256 = core::num::traits::Bounded::MAX / 2;

    #[storage]
    pub struct Storage {
        factory: ContractAddress,
        lockbox: ContractAddress,
        pub bridges: Map<ContractAddress, Bridge>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        LockboxSet: LockboxSet,
        BridgeLimitsSet: BridgeLimitsSet,
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
        pub max_limit: u256,
        pub current_limit: u256
    }

    pub trait LimitManagerTrait<TContractState> {
        fn calculate_new_current_limit(
            self: @ComponentState<TContractState>,
            bridge: ContractAddress,
            limit: u256,
            old_limit: u256,
            current_limit: u256
        ) -> u256;

        fn get_current_limit(
            self: @ComponentState<TContractState>,
            bridge: ContractAddress,
            current_limit: u256,
            max_limit: u256,
            is_minter: bool,
        ) -> u256;

        fn use_minter_limits(
            ref self: ComponentState<TContractState>, bridge: ContractAddress, change: u256
        );

        fn use_burner_limits(
            ref self: ComponentState<TContractState>, bridge: ContractAddress, change: u256
        );

        fn change_minter_limit(
            ref self: ComponentState<TContractState>, bridge: ContractAddress, limit: u256
        );

        fn change_burner_limit(
            ref self: ComponentState<TContractState>, bridge: ContractAddress, limit: u256
        );
    }

    #[embeddable_as(XERC20)]
    pub impl XERC20Impl<
        TContractState,
        +HasComponent<TContractState>,
        impl Ownable: OwnableComponent::HasComponent<TContractState>,
        impl ERC20: ERC20Component::HasComponent<TContractState>,
        +ERC20Component::ERC20HooksTrait<TContractState>,
        impl LimitManager: LimitManagerTrait<TContractState>,
        +Drop<TContractState>,
    > of IXERC20<ComponentState<TContractState>> {
        fn set_lockbox(ref self: ComponentState<TContractState>, lockbox: ContractAddress) {
            let ownable_comp = get_dep_component!(@self, Ownable);
            ownable_comp.assert_only_owner();
            self.lockbox.write(lockbox);
            self.emit(LockboxSet { lockbox });
        }

        fn set_limits(
            ref self: ComponentState<TContractState>,
            bridge: ContractAddress,
            minting_limit: u256,
            burning_limit: u256
        ) {
            let ownable_comp = get_dep_component!(@self, Ownable);
            ownable_comp.assert_only_owner();
            assert(
                minting_limit <= U256MAX_DIV_2 && burning_limit <= U256MAX_DIV_2,
                Errors::LIMITS_TO_HIGH
            );

            LimitManager::change_minter_limit(ref self, bridge, minting_limit);
            LimitManager::change_burner_limit(ref self, bridge, burning_limit);
            self.emit(BridgeLimitsSet { minting_limit, burning_limit, bridge });
        }

        fn mint(ref self: ComponentState<TContractState>, user: ContractAddress, amount: u256) {
            self.mint_with_caller(starknet::get_caller_address(), user, amount);
        }

        fn burn(ref self: ComponentState<TContractState>, user: ContractAddress, amount: u256) {
            let caller = starknet::get_caller_address();
            if caller != user {
                let mut erc20_comp = get_dep_component_mut!(ref self, ERC20);
                erc20_comp._spend_allowance(user, caller, amount);
            }
            self.burn_with_caller(caller, user, amount);
        }

        fn minting_max_limit_of(
            self: @ComponentState<TContractState>, minter: ContractAddress
        ) -> u256 {
            self.bridges.entry(minter).minter_params.deref().max_limit.read()
        }

        fn burning_max_limit_of(
            self: @ComponentState<TContractState>, bridge: ContractAddress
        ) -> u256 {
            self.bridges.entry(bridge).burner_params.deref().max_limit.read()
        }

        fn minting_current_limit_of(
            self: @ComponentState<TContractState>, minter: ContractAddress
        ) -> u256 {
            let minter_params_storage_path = self.bridges.entry(minter).minter_params.deref();
            LimitManager::get_current_limit(
                self,
                minter,
                minter_params_storage_path.current_limit.read(),
                minter_params_storage_path.max_limit.read(),
                true
            )
        }

        fn burning_current_limit_of(
            self: @ComponentState<TContractState>, bridge: ContractAddress
        ) -> u256 {
            let burner_params_storage_path = self.bridges.entry(bridge).burner_params.deref();
            LimitManager::get_current_limit(
                self,
                bridge,
                burner_params_storage_path.current_limit.read(),
                burner_params_storage_path.max_limit.read(),
                false
            )
        }

        fn lockbox(self: @ComponentState<TContractState>) -> ContractAddress {
            self.lockbox.read()
        }

        fn factory(self: @ComponentState<TContractState>) -> ContractAddress {
            self.factory.read()
        }
    }

    #[generate_trait]
    impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +OwnableComponent::HasComponent<TContractState>,
        impl ERC20: ERC20Component::HasComponent<TContractState>,
        +ERC20Component::ERC20HooksTrait<TContractState>,
        impl LimitManager: LimitManagerTrait<TContractState>,
        +Drop<TContractState>
    > of InternalTrait<TContractState> {
        fn initialize(
            ref self: ComponentState<TContractState>, name: ByteArray, symbol: ByteArray
        ) {
            let mut erc20_comp = get_dep_component_mut!(ref self, ERC20);
            erc20_comp.initializer(name, symbol);
        }

        fn burn_with_caller(
            ref self: ComponentState<TContractState>,
            caller: ContractAddress,
            user: ContractAddress,
            amount: u256
        ) {
            if caller != self.lockbox.read() {
                let current_limit = self.burning_current_limit_of(caller);
                assert(current_limit >= amount, Errors::NOT_HIGH_ENOUGH_LIMITS);
                LimitManager::use_burner_limits(ref self, caller, amount);
            }
            let mut erc20_comp = get_dep_component_mut!(ref self, ERC20);
            erc20_comp.burn(user, amount);
        }

        fn mint_with_caller(
            ref self: ComponentState<TContractState>,
            caller: ContractAddress,
            user: ContractAddress,
            amount: u256
        ) {
            if caller != self.lockbox.read() {
                let current_limit = self.minting_current_limit_of(caller);
                assert(current_limit >= amount, Errors::NOT_HIGH_ENOUGH_LIMITS);
                LimitManager::use_minter_limits(ref self, caller, amount);
            }
            let mut erc20_comp = get_dep_component_mut!(ref self, ERC20);
            erc20_comp.mint(user, amount);
        }
    }
}

