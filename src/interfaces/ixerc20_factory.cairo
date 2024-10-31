use starknet::ContractAddress;

#[starknet::interface]
pub trait IXERC20Factory<TState> {
    fn deploy_xerc20(
        ref self: TState,
        name: ByteArray,
        symbol: ByteArray,
        minter_limits: Span<u256>,
        burner_limits: Span<u256>,
        bridges: Span<ContractAddress>
    ) -> ContractAddress;
    // NOTE: We might not need `is_native`
    fn deploy_lockbox(
        ref self: TState, xerc20: ContractAddress, base_token: ContractAddress, is_native: bool
    ) -> ContractAddress;
}
