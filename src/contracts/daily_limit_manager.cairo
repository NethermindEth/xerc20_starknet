#[starknet::component]
pub mod DailyLimitManagerComponent {
    use crate::contracts::xerc20_component::{
        XERC20Component, XERC20Component::LimitManagerTrait, XERC20Component::XERC20Impl
    };
    use crate::interfaces::ixerc20::IXERC20;
    use openzeppelin_access::ownable::ownable::OwnableComponent;
    use openzeppelin_token::erc20::erc20::ERC20Component;
    use starknet::ContractAddress;
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, Map, StoragePathEntry
    };

    // 1 Day
    pub const DURATION: u64 = 60 * 60 * 24;

    #[storage]
    pub struct Storage {
        pub time_limit_params: Map<ContractAddress, Params>
    }

    #[starknet::storage_node]
    pub struct Params {
        burner_time_limits: TimelyLimiterParams,
        minter_time_limits: TimelyLimiterParams
    }

    #[starknet::storage_node]
    pub struct TimelyLimiterParams {
        pub timestamp: u64,
        pub rate_per_second: u256,
    }

    pub impl DailyLimitManager<
        TContractState,
        +HasComponent<TContractState>,
        +XERC20Component::HasComponent<TContractState>,
        +ERC20Component::HasComponent<TContractState>,
        +ERC20Component::ERC20HooksTrait<TContractState>,
        +OwnableComponent::HasComponent<TContractState>,
        +Drop<TContractState>
    > of LimitManagerTrait<TContractState> {
        fn calculate_new_current_limit(
            self: @XERC20Component::ComponentState<TContractState>,
            bridge: ContractAddress,
            limit: u256,
            old_limit: u256,
            current_limit: u256
        ) -> u256 {
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
            self: @XERC20Component::ComponentState<TContractState>,
            bridge: ContractAddress,
            current_limit: u256,
            max_limit: u256,
            is_minter: bool
        ) -> u256 {
            if current_limit == max_limit {
                return current_limit;
            }

            let contract_state = XERC20Component::HasComponent::get_contract(self);
            let component_state = HasComponent::get_component(contract_state);

            let time_limit_params_storage_path = if is_minter {
                component_state.time_limit_params.entry(bridge).minter_time_limits.deref()
            } else {
                component_state.time_limit_params.entry(bridge).burner_time_limits.deref()
            };

            let timestamp = time_limit_params_storage_path.timestamp.read();
            let current_timestamp = starknet::get_block_timestamp();
            if timestamp + DURATION <= current_timestamp {
                return max_limit;
            }
            let rate_per_second = time_limit_params_storage_path.rate_per_second.read();
            let time_delta = current_timestamp - timestamp;
            let calculated_limit = current_limit + (time_delta.into() * rate_per_second);
            if calculated_limit > max_limit {
                max_limit
            } else {
                calculated_limit
            }
        }

        fn use_minter_limits(
            ref self: XERC20Component::ComponentState<TContractState>,
            bridge: ContractAddress,
            change: u256
        ) {
            let current_limit = self.minting_current_limit_of(bridge);
            let mut contract_state_mut = XERC20Component::HasComponent::get_contract_mut(ref self);
            let mut component_state_mut = HasComponent::get_component_mut(ref contract_state_mut);

            component_state_mut
                .time_limit_params
                .entry(bridge)
                .minter_time_limits
                .deref()
                .timestamp
                .write(starknet::get_block_timestamp());
            self
                .bridges
                .entry(bridge)
                .minter_params
                .deref()
                .current_limit
                .write(current_limit - change);
        }

        fn use_burner_limits(
            ref self: XERC20Component::ComponentState<TContractState>,
            bridge: ContractAddress,
            change: u256
        ) {
            let current_limit = self.burning_current_limit_of(bridge);
            let burner_params_storage_path = self.bridges.entry(bridge).burner_params.deref();
            burner_params_storage_path.current_limit.write(current_limit - change);
            let mut contract_state_mut = XERC20Component::HasComponent::get_contract_mut(ref self);
            let mut component_state = HasComponent::get_component_mut(ref contract_state_mut);
            component_state
                .time_limit_params
                .entry(bridge)
                .burner_time_limits
                .deref()
                .timestamp
                .write(starknet::get_block_timestamp());
        }

        fn change_minter_limit(
            ref self: XERC20Component::ComponentState<TContractState>,
            bridge: ContractAddress,
            limit: u256
        ) {
            let minter_params_storage_path = self.bridges.entry(bridge).minter_params.deref();
            let old_limit = minter_params_storage_path.max_limit.read();
            let current_limit = self.minting_current_limit_of(bridge);

            minter_params_storage_path.max_limit.write(limit);
            let new_current_limit = self
                .calculate_new_current_limit(bridge, limit, old_limit, current_limit);
            minter_params_storage_path.current_limit.write(new_current_limit);
            let mut contract_state_mut = XERC20Component::HasComponent::get_contract_mut(ref self);
            let mut component_state_mut = HasComponent::get_component_mut(ref contract_state_mut);
            let time_limits_storage_path = component_state_mut
                .time_limit_params
                .entry(bridge)
                .minter_time_limits
                .deref();
            time_limits_storage_path.rate_per_second.write(limit / DURATION.into());
            time_limits_storage_path.timestamp.write(starknet::get_block_timestamp());
        }

        fn change_burner_limit(
            ref self: XERC20Component::ComponentState<TContractState>,
            bridge: ContractAddress,
            limit: u256
        ) {
            let burner_params_storage_path = self.bridges.entry(bridge).burner_params.deref();
            let old_limit = burner_params_storage_path.max_limit.read();
            let current_limit = self.burning_current_limit_of(bridge);

            burner_params_storage_path.max_limit.write(limit);
            let new_current_limit = self
                .calculate_new_current_limit(bridge, limit, old_limit, current_limit);
            burner_params_storage_path.current_limit.write(new_current_limit);
            let mut contract_state_mut = XERC20Component::HasComponent::get_contract_mut(ref self);
            let mut component_state_mut = HasComponent::get_component_mut(ref contract_state_mut);
            let time_limits_storage_path = component_state_mut
                .time_limit_params
                .entry(bridge)
                .burner_time_limits
                .deref();
            time_limits_storage_path.rate_per_second.write(limit / DURATION.into());
            time_limits_storage_path.timestamp.write(starknet::get_block_timestamp());
        }
    }
}
