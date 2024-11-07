#[starknet::interface]
pub trait ICreate3Proxy<TContractState> {
    fn initialize(
        ref self: TContractState,
        new_class_hash: starknet::ClassHash,
        selector: Option<felt252>,
        calldata: Option<Span<felt252>>
    );
}

//! This contract can be utilized for deterministic deployments without `class_hash` and
//! 'ctor_calldata_hash'.
//! Deploy this contract from factory and upgrade it to 'class_hash' you desire then call the
//! initializer of the other contract if is there any.
#[starknet::contract]
mod Create3Proxy {
    use openzeppelin_upgrades::upgradeable::UpgradeableComponent;

    component!(path: UpgradeableComponent, storage: upgrades, event: UpgradeableEvent);

    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        upgrades: UpgradeableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
    }

    #[abi(embed_v0)]
    impl Create3ProxyImpl of super::ICreate3Proxy<ContractState> {
        fn initialize(
            ref self: ContractState,
            new_class_hash: starknet::ClassHash,
            selector: Option<felt252>,
            calldata: Option<Span<felt252>>
        ) {
            match selector {
                Option::Some(selector) => {
                    let calldata = calldata.unwrap();
                    self.upgrades.upgrade_and_call(new_class_hash, selector, calldata);
                },
                Option::None => { self.upgrades.upgrade(new_class_hash); },
            }
        }
    }
}
