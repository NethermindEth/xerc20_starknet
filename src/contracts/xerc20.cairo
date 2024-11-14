use starknet::ContractAddress;

#[starknet::interface]
pub trait XERC20Initializer<TContractState> {
    fn initialize(
        ref self: TContractState, name: ByteArray, symbol: ByteArray, factory: ContractAddress
    );
}

#[starknet::contract]
pub mod XERC20 {
    use crate::contracts::{
        xerc20_component::XERC20Component, daily_limit_manager::DailyLimitManagerComponent
    };
    use openzeppelin_access::ownable::ownable::OwnableComponent;
    use openzeppelin_security::initializable::InitializableComponent;
    use openzeppelin_token::erc20::{erc20::{ERC20Component, ERC20HooksEmptyImpl}};
    use openzeppelin_utils::cryptography::{nonces::NoncesComponent, snip12::SNIP12Metadata};
    use starknet::ContractAddress;

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

    component!(path: XERC20Component, storage: xerc20, event: XERC20Event);

    #[abi(embed_v0)]
    impl XERC20Impl = XERC20Component::XERC20<ContractState>;

    component!(
        path: DailyLimitManagerComponent, storage: limit_manager, event: DailyLimitManagerEvent
    );

    impl LimitManagerImpl = DailyLimitManagerComponent::DailyLimitManager<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        initializable: InitializableComponent::Storage,
        #[substorage(v0)]
        nonces: NoncesComponent::Storage,
        #[substorage(v0)]
        xerc20: XERC20Component::Storage,
        #[substorage(v0)]
        limit_manager: DailyLimitManagerComponent::Storage
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        InitializableEvent: InitializableComponent::Event,
        #[flat]
        NoncesEvent: NoncesComponent::Event,
        #[flat]
        XERC20Event: XERC20Component::Event,
        #[flat]
        DailyLimitManagerEvent: DailyLimitManagerComponent::Event
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
}
