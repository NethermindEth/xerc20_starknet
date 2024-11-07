use starknet::ContractAddress;

#[starknet::interface]
trait XERC20LockboxInitializer<TContractState> {
    fn initialize(ref self: TContractState, xerc20: ContractAddress, erc20: ContractAddress);
}

//! Logics re-Native might be removed
#[starknet::contract]
mod XERC20Lockbox {
    use openzeppelin_security::initializable::InitializableComponent;
    use openzeppelin_token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use xerc20_starknet::interfaces::{
        ixerc20_lockbox::IXERC20Lockbox, ixerc20::{IXERC20Dispatcher, IXERC20DispatcherTrait}
    };

    component!(path: InitializableComponent, storage: initializable, event: InitializableEvent);

    #[abi(embed_v0)]
    impl InitializableImpl =
        InitializableComponent::InitializableImpl<ContractState>;
    impl InitializableOInternalImpl = InitializableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        xerc20: IXERC20Dispatcher,
        erc20: ERC20ABIDispatcher,
        #[substorage(v0)]
        initializable: InitializableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Deposit: Deposit,
        Withdraw: Withdraw,
        #[flat]
        InitializableEvent: InitializableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct Deposit {
        sender: ContractAddress,
        amount: u256
    }

    #[derive(Drop, starknet::Event)]
    struct Withdraw {
        sender: ContractAddress,
        amount: u256
    }

    pub mod Errors {
        // Reverts when a user tries to deposit native tokens on a non-native lockbox
        pub const NOT_NATIVE: felt252 = 'Not native token';
        // Reverts when a user tries to deposit non-native tokens on a native lockbox
        pub const NATIVE: felt252 = 'Native token';
        // Reverts when a user tries to withdraw and the call fails
        pub const WITHDRAW_FAILED: felt252 = 'Withdraw failed';
        pub const ERC20_TRANSFER_FAILED: felt252 = 'ERC20 transfer failed';
        pub const ERC20_TRANSFER_FROM_FAILED: felt252 = 'ERC20 transfer_from failed';
    }

    #[constructor]
    fn constructor(ref self: ContractState, xerc20: ContractAddress, erc20: ContractAddress) {
        self.xerc20.write(IXERC20Dispatcher { contract_address: xerc20 });
        self.erc20.write(ERC20ABIDispatcher { contract_address: erc20 });
        self.initializable.initialize();
    }

    #[abi(embed_v0)]
    impl InitializerImpl of super::XERC20LockboxInitializer<ContractState> {
        fn initialize(ref self: ContractState, xerc20: ContractAddress, erc20: ContractAddress) {
            self.xerc20.write(IXERC20Dispatcher { contract_address: xerc20 });
            self.erc20.write(ERC20ABIDispatcher { contract_address: erc20 });
            self.initializable.initialize();
        }
    }

    #[abi(embed_v0)]
    impl XERC20LockboxImpl of IXERC20Lockbox<ContractState> {
        fn deposit(ref self: ContractState, amount: u256) {
            self._deposit(starknet::get_caller_address(), amount);
        }

        fn deposit_to(ref self: ContractState, user: ContractAddress, amount: u256) {
            self._deposit(user, amount);
        }

        fn withdraw(ref self: ContractState, amount: u256) {
            self._withdraw(starknet::get_caller_address(), amount);
        }

        fn withdraw_to(ref self: ContractState, user: ContractAddress, amount: u256) {
            self._withdraw(user, amount);
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _withdraw(ref self: ContractState, to: ContractAddress, amount: u256) {
            // NOTE: event field sender seems to not correctly utilized, sender is caller address,
            // to is receiver.
            self.emit(Withdraw { sender: to, amount });
            self.xerc20.read().burn(starknet::get_caller_address(), amount);
            assert(self.erc20.read().transfer(to, amount), Errors::ERC20_TRANSFER_FAILED);
        }

        fn _deposit(ref self: ContractState, to: ContractAddress, amount: u256) {
            assert(
                self
                    .erc20
                    .read()
                    .transfer_from(
                        starknet::get_caller_address(), starknet::get_contract_address(), amount
                    ),
                Errors::ERC20_TRANSFER_FROM_FAILED
            );
            self.xerc20.read().mint(to, amount);
            // NOTE: event field sender seems to not correctly utilized, sender is caller address,
            // to is receiver.
            self.emit(Deposit { sender: to, amount: amount });
        }
    }
}

