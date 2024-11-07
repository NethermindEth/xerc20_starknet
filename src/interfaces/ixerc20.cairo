use starknet::ContractAddress;

// TODO: Ensure interface matches with whats in the hyperlane repo.
#[starknet::interface]
pub trait IXERC20<TState> {
    fn set_lockbox(ref self: TState, lockbox: ContractAddress);
    fn set_limits(
        ref self: TState, bridge: ContractAddress, minting_limit: u256, burning_limit: u256
    );
    fn mint(ref self: TState, user: ContractAddress, amount: u256);
    fn burn(ref self: TState, user: ContractAddress, amount: u256);
    fn minting_max_limit_of(self: @TState, minter: ContractAddress) -> u256;
    fn burning_max_limit_of(self: @TState, bridge: ContractAddress) -> u256;
    fn minting_current_limit_of(self: @TState, minter: ContractAddress) -> u256;
    fn burning_current_limit_of(self: @TState, bridge: ContractAddress) -> u256;
}
