use starknet::ContractAddress;

#[starknet::interface]
pub trait IXERC20Lockbox<TState> {
    fn deposit(ref self: TState, amount: u256);
    fn deposit_to(ref self: TState, user: ContractAddress, amount: u256);
    fn withdraw(ref self: TState, amount: u256);
    fn withdraw_to(ref self: TState, user: ContractAddress, amount: u256);
    // getters
    fn xerc20(self: @TState) -> ContractAddress;
    fn erc20(self: @TState) -> ContractAddress;
}
