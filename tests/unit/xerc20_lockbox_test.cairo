use snforge_std::{declare, DeclareResultTrait, ContractClassTrait};
use starknet::ContractAddress;
use xerc20_starknet::interfaces::ixerc20_lockbox::IXERC20LockboxDispatcher;

#[derive(Drop)]
pub struct Setup {
    owner: ContractAddress,
    user: ContractAddress,
    minter: ContractAddress,
    xerc20: ContractAddress,
    erc20: ContractAddress,
    lockbox: IXERC20LockboxDispatcher,
}

pub fn setup() -> Setup {
    let owner = starknet::contract_address_const::<1>();
    let user = starknet::contract_address_const::<2>();
    let minter = starknet::contract_address_const::<3>();
    let xerc20 = starknet::contract_address_const::<'xerc20'>();
    let erc20 = starknet::contract_address_const::<'erc20'>();

    let xerc20_lockbox_contract = declare("XERC20Lockbox").unwrap().contract_class();
    let (xerc20_lockbox_address, _) = xerc20_lockbox_contract
        .deploy(@array![xerc20.into(), erc20.into()])
        .unwrap();

    Setup {
        owner,
        user,
        minter,
        xerc20,
        erc20,
        lockbox: IXERC20LockboxDispatcher { contract_address: xerc20_lockbox_address },
    }
}

mod unit_deposit {
    use core::num::traits::Bounded;
    use crate::unit::common::{bound};
    use snforge_std::{
        start_cheat_caller_address, stop_cheat_caller_address, mock_call, spy_events,
        EventSpyAssertionsTrait
    };
    use super::setup;
    use xerc20_starknet::contracts::xerc20_lockbox::XERC20Lockbox;
    use xerc20_starknet::interfaces::ixerc20_lockbox::IXERC20LockboxDispatcherTrait;

    // TODO: uses expect_call. find a way to test this
    #[test]
    fn test_deposit(mut amount: u256) {
        let setup = setup();

        amount = bound(amount, 1, Bounded::MAX);
        mock_call(setup.erc20, selector!("transfer_from"), true, 1);
        mock_call(setup.xerc20, selector!("mint"), (), 1);

        start_cheat_caller_address(setup.lockbox.contract_address, setup.owner);
        setup.lockbox.deposit(amount);
        stop_cheat_caller_address(setup.lockbox.contract_address);
    }

    #[test]
    #[should_panic(expected: 'ERC20 transfer_from failed')]
    fn test_deposit_should_panic_when_transfer_from_returns_false(mut amount: u256) {
        let setup = setup();

        amount = bound(amount, 1, Bounded::MAX);
        mock_call(setup.erc20, selector!("transfer_from"), false, 1);
        mock_call(setup.xerc20, selector!("mint"), (), 1);

        start_cheat_caller_address(setup.lockbox.contract_address, setup.owner);
        setup.lockbox.deposit(amount);
        stop_cheat_caller_address(setup.lockbox.contract_address);
    }

    // TODO: uses expect_call. find a way to test this
    #[test]
    fn test_deposit_to(mut amount: u256) {
        let setup = setup();

        amount = bound(amount, 1, Bounded::MAX);
        mock_call(setup.erc20, selector!("transfer_from"), true, 1);
        mock_call(setup.xerc20, selector!("mint"), (), 1);

        start_cheat_caller_address(setup.lockbox.contract_address, setup.owner);
        setup.lockbox.deposit_to(setup.user, amount);
        stop_cheat_caller_address(setup.lockbox.contract_address);
    }

    #[test]
    #[should_panic(expected: 'ERC20 transfer_from failed')]
    fn test_deposit_to_should_panic_when_transfer_from_returns_false(mut amount: u256) {
        let setup = setup();

        amount = bound(amount, 1, Bounded::MAX);
        mock_call(setup.erc20, selector!("transfer_from"), false, 1);
        mock_call(setup.xerc20, selector!("mint"), (), 1);

        start_cheat_caller_address(setup.lockbox.contract_address, setup.owner);
        setup.lockbox.deposit_to(setup.user, amount);
        stop_cheat_caller_address(setup.lockbox.contract_address);
    }

    #[test]
    fn test_deposit_emits_event(mut amount: u256) {
        let setup = setup();

        amount = bound(amount, 1, Bounded::MAX);
        mock_call(setup.erc20, selector!("transfer_from"), true, 1);
        mock_call(setup.xerc20, selector!("mint"), (), 1);

        let mut spy = spy_events();
        start_cheat_caller_address(setup.lockbox.contract_address, setup.owner);
        setup.lockbox.deposit(amount);
        stop_cheat_caller_address(setup.lockbox.contract_address);
        spy
            .assert_emitted(
                @array![
                    (
                        setup.lockbox.contract_address,
                        XERC20Lockbox::Event::Deposit(
                            XERC20Lockbox::Deposit { sender: setup.owner, amount }
                        )
                    )
                ]
            );
    }
}


pub mod unit_withdraw {
    use core::num::traits::Bounded;
    use crate::unit::common::{bound};
    use snforge_std::{
        start_cheat_caller_address, stop_cheat_caller_address, mock_call, spy_events,
        EventSpyAssertionsTrait
    };
    use super::setup;
    use xerc20_starknet::contracts::xerc20_lockbox::XERC20Lockbox;
    use xerc20_starknet::interfaces::ixerc20_lockbox::IXERC20LockboxDispatcherTrait;

    // TODO: uses expect_call. find a way to test this
    #[test]
    fn test_withdraw(mut amount: u256) {
        let setup = setup();

        amount = bound(amount, 1, Bounded::MAX);
        mock_call(setup.erc20, selector!("transfer"), true, 1);
        mock_call(setup.xerc20, selector!("burn"), (), 1);

        start_cheat_caller_address(setup.lockbox.contract_address, setup.owner);
        setup.lockbox.withdraw(amount);
        stop_cheat_caller_address(setup.lockbox.contract_address);
    }

    #[test]
    #[should_panic(expected: 'ERC20 transfer failed')]
    fn test_withdraw_should_panic_when_transfer_returns_false(mut amount: u256) {
        let setup = setup();

        amount = bound(amount, 1, Bounded::MAX);
        mock_call(setup.erc20, selector!("transfer"), false, 1);
        mock_call(setup.xerc20, selector!("burn"), (), 1);

        start_cheat_caller_address(setup.lockbox.contract_address, setup.owner);
        setup.lockbox.withdraw(amount);
        stop_cheat_caller_address(setup.lockbox.contract_address);
    }

    // TODO: uses expect_call. find a way to test this
    #[test]
    fn test_withdraw_to(mut amount: u256) {
        let setup = setup();

        amount = bound(amount, 1, Bounded::MAX);
        mock_call(setup.erc20, selector!("transfer"), true, 1);
        mock_call(setup.xerc20, selector!("burn"), (), 1);

        start_cheat_caller_address(setup.lockbox.contract_address, setup.owner);
        setup.lockbox.withdraw_to(setup.user, amount);
        stop_cheat_caller_address(setup.lockbox.contract_address);
    }

    #[test]
    #[should_panic(expected: 'ERC20 transfer failed')]
    fn test_withdraw_to_should_panic_when_transfer_returns_false(mut amount: u256) {
        let setup = setup();

        amount = bound(amount, 1, Bounded::MAX);
        mock_call(setup.erc20, selector!("transfer"), false, 1);
        mock_call(setup.xerc20, selector!("burn"), (), 1);

        start_cheat_caller_address(setup.lockbox.contract_address, setup.owner);
        setup.lockbox.withdraw_to(setup.user, amount);
        stop_cheat_caller_address(setup.lockbox.contract_address);
    }

    #[test]
    fn test_withdraw_emit_events(mut amount: u256) {
        let setup = setup();

        amount = bound(amount, 1, Bounded::MAX);
        mock_call(setup.erc20, selector!("transfer"), true, 1);
        mock_call(setup.xerc20, selector!("burn"), (), 1);

        let mut spy = spy_events();
        start_cheat_caller_address(setup.lockbox.contract_address, setup.owner);
        setup.lockbox.withdraw(amount);
        stop_cheat_caller_address(setup.lockbox.contract_address);
        spy
            .assert_emitted(
                @array![
                    (
                        setup.lockbox.contract_address,
                        XERC20Lockbox::Event::Withdraw(
                            XERC20Lockbox::Withdraw { sender: setup.owner, amount }
                        )
                    )
                ]
            );
    }
}
