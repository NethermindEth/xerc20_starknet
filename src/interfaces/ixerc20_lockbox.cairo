use starknet::ContractAddress;

#[starknet::interface]
pub trait IXERC20Lockbox<TState> {
    fn deposit(ref self: TState, amount: u256);
    fn deposit_to(ref self: TState, user: ContractAddress, amount: u256);
    // We might not need this
    fn deposit_native_to(ref self: TState, user: ContractAddress);
    fn withdraw(ref self: TState, amount: u256);
    fn withdraw_to(ref self: TState, user: ContractAddress, amount: u256);
}
