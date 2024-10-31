//! Logics re-Native might be removed
#[starknet::contract]
mod XERC20Lockbox {
    #[allow(unused_imports)]
    use openzeppelin_token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
    #[allow(unused_imports)]
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    #[allow(unused_imports)]
    use xerc20_starknet::interfaces::{
        ixerc20_lockbox::IXERC20Lockbox, ixerc20::{IXERC20Dispatcher, IXERC20DispatcherTrait}
    };
    use starknet::ContractAddress;


    #[storage]
    struct Storage {
        xerc20: IXERC20Dispatcher,
        erc20: ERC20ABIDispatcher,
        /// NOTE: native might not needed
        is_native: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Deposit: Deposit,
        Withdraw: Withdraw
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
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, xerc20: ContractAddress, erc20: ContractAddress, is_native: bool
    ) {
        self.xerc20.write(IXERC20Dispatcher { contract_address: xerc20 });
        self.erc20.write(ERC20ABIDispatcher { contract_address: erc20 });
        self.is_native.write(is_native);
    }

    #[abi(embed_v0)]
    impl XERC20LockboxImpl of IXERC20Lockbox<ContractState> {
        fn deposit(ref self: ContractState, amount: u256) {
            /// NOTE: checks if is_native, we dont have native token in starknet
            self._deposit(starknet::get_caller_address(), amount);
        }
        fn deposit_to(ref self: ContractState, user: ContractAddress, amount: u256) {
            /// NOTE: checks if is_native, we dont have native token in starknet
            self._deposit(user, amount);
        }
        // We might not need this
        fn deposit_native_to(ref self: ContractState, user: ContractAddress) {}

        fn withdraw(ref self: ContractState, amount: u256) {
            self._withdraw(starknet::get_caller_address(), amount);
        }

        fn withdraw_to(ref self: ContractState, user: ContractAddress, amount: u256) {
            self._withdraw(user, amount);
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _withdraw(ref self: ContractState, to: ContractAddress, amount: u256) {}
        fn _deposit(ref self: ContractState, to: ContractAddress, amount: u256) {}
    }
}

