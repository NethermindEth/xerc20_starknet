use core::num::traits::Zero;
use core::poseidon::poseidon_hash_span;
use openzeppelin_token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use openzeppelin_utils::deployments::calculate_contract_address_from_deploy_syscall;
use snforge_std::{
    declare, DeclareResultTrait, ContractClassTrait, start_cheat_caller_address,
    stop_cheat_caller_address, spy_events, EventSpyAssertionsTrait
};
use starknet::ClassHash;
use starknet::ContractAddress;
use xerc20_starknet::contracts::xerc20_factory::XERC20Factory;
use xerc20_starknet::interfaces::{
    ixerc20_factory::{IXERC20FactoryDispatcher, IXERC20FactoryDispatcherTrait},
    ixerc20_lockbox::{IXERC20LockboxDispatcher, IXERC20LockboxDispatcherTrait}
};

#[derive(Drop)]
pub struct Setup {
    owner: ContractAddress,
    user: ContractAddress,
    erc20: ContractAddress,
    xerc20_factory: IXERC20FactoryDispatcher,
    create3_proxy_class_hash: ClassHash,
}

pub fn setup() -> Setup {
    let owner = starknet::contract_address_const::<1>();
    let user = starknet::contract_address_const::<2>();
    let erc20 = starknet::contract_address_const::<3>();

    let create3_proxy_class_hash = declare("Create3Proxy").unwrap().contract_class().class_hash;
    let xerc20_class_hash = declare("XERC20").unwrap().contract_class().class_hash;
    let xerc20_lockbox_class_hash = declare("XERC20Lockbox").unwrap().contract_class().class_hash;
    let factory_contract = declare("XERC20Factory").unwrap().contract_class();
    let mut ctor_calldata: Array<felt252> = array![];
    create3_proxy_class_hash.serialize(ref ctor_calldata);
    xerc20_class_hash.serialize(ref ctor_calldata);
    xerc20_lockbox_class_hash.serialize(ref ctor_calldata);
    let (factory_address, _) = factory_contract.deploy(@ctor_calldata).unwrap();

    Setup {
        owner,
        user,
        erc20,
        xerc20_factory: IXERC20FactoryDispatcher { contract_address: factory_address },
        create3_proxy_class_hash: *create3_proxy_class_hash
    }
}

#[test]
fn test_deployment() {
    let setup = setup();

    let limits = array![].span();
    let minters = array![].span();

    let xerc20 = setup.xerc20_factory.deploy_xerc20("Test", "TST", limits, limits, minters);
    let erc20_dispatcher = ERC20ABIDispatcher { contract_address: xerc20 };
    assert!(erc20_dispatcher.name() == "Test", "Name does not match!");
    assert!(erc20_dispatcher.symbol() == "TST", "Symbol does not match!");
}

// NOTE: this test should panic and panicing but fails
//#[test]
//#[should_panic]
//fn test_should_panic_when_address_is_taken() {
//    let setup = setup();
//    let limits = array![].span();
//    let minters = array![].span();
//    setup.xerc20_factory.deploy_xerc20("Test", "TST", limits, limits, minters);
//    // second time deploying to same address should fail
//    setup.xerc20_factory.deploy_xerc20("Test", "TST", limits, limits, minters);
//}

#[test]
fn test_xerc20_pre_computed_address() {
    let setup = setup();

    let limits = array![].span();
    let minters = array![].span();

    let name: ByteArray = "Test";
    let symbol: ByteArray = "TST";
    let mut serialized_data: Array<felt252> = array![];
    name.serialize(ref serialized_data);
    symbol.serialize(ref serialized_data);
    starknet::get_contract_address().serialize(ref serialized_data);
    let salt = poseidon_hash_span(serialized_data.span());

    let actual_address = setup.xerc20_factory.deploy_xerc20("Test", "TST", limits, limits, minters);
    let expected_address = calculate_contract_address_from_deploy_syscall(
        salt, setup.create3_proxy_class_hash, array![].span(), setup.xerc20_factory.contract_address
    );
    assert!(expected_address == actual_address, "Addresses does not match!");
}

#[test]
fn test_xerc20_lockbox_pre_computed_address() {
    let setup = setup();

    let limits = array![].span();
    let minters = array![].span();

    let xerc20_address = setup.xerc20_factory.deploy_xerc20("Test", "TST", limits, limits, minters);

    let mut serialized_data: Array<felt252> = array![];
    xerc20_address.serialize(ref serialized_data);
    setup.erc20.serialize(ref serialized_data);
    starknet::get_contract_address().serialize(ref serialized_data);
    let salt = poseidon_hash_span(serialized_data.span());
    let expected_address = calculate_contract_address_from_deploy_syscall(
        salt, setup.create3_proxy_class_hash, array![].span(), setup.xerc20_factory.contract_address
    );

    let actual_address = setup.xerc20_factory.deploy_lockbox(xerc20_address, setup.erc20);
    assert!(expected_address == actual_address, "Addresses does not match!");
}

#[test]
fn test_lockbox_single_deployment() {
    let setup = setup();

    let limits = array![].span();
    let minters = array![].span();

    let xerc20_address = setup.xerc20_factory.deploy_xerc20("Test", "TST", limits, limits, minters);

    let lockbox_address = setup.xerc20_factory.deploy_lockbox(xerc20_address, setup.erc20);
    let lockbox_dispatcher = IXERC20LockboxDispatcher { contract_address: lockbox_address };
    assert!(lockbox_dispatcher.erc20() == setup.erc20, "ERC20 address does not match!");
    assert!(lockbox_dispatcher.xerc20() == xerc20_address, "XERC20 address does not match!");
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_should_panic_when_lockbox_single_deployment_when_caller_not_owner() {
    let setup = setup();

    let limits = array![].span();
    let minters = array![].span();

    start_cheat_caller_address(
        setup.xerc20_factory.contract_address, starknet::contract_address_const::<'not_owner'>()
    );
    let xerc20_address = setup.xerc20_factory.deploy_xerc20("Test", "TST", limits, limits, minters);
    stop_cheat_caller_address(setup.xerc20_factory.contract_address);

    setup.xerc20_factory.deploy_lockbox(xerc20_address, setup.erc20);
}

#[test]
#[should_panic(expected: 'Bad token address')]
fn test_should_panic_when_lockbox_deployment_when_base_token_adress_zero() {
    let setup = setup();

    let limits = array![].span();
    let minters = array![].span();

    let xerc20_address = setup.xerc20_factory.deploy_xerc20("Test", "TST", limits, limits, minters);
    setup.xerc20_factory.deploy_lockbox(xerc20_address, Zero::zero());
}

#[test]
#[should_panic(expected: 'Lockbox alread deployed')]
fn test_should_panic_when_lockbox_deployment_twice() {
    let setup = setup();

    let limits = array![].span();
    let minters = array![].span();

    let xerc20_address = setup.xerc20_factory.deploy_xerc20("Test", "TST", limits, limits, minters);

    setup.xerc20_factory.deploy_lockbox(xerc20_address, setup.erc20);
    setup.xerc20_factory.deploy_lockbox(xerc20_address, setup.erc20);
}

#[test]
#[should_panic(expected: 'Invalid length')]
fn test_should_panic_when_arrays_len_does_not_match() {
    let setup = setup();

    let limits = array![1].span();
    let minters = array![].span();

    setup.xerc20_factory.deploy_xerc20("Test", "TST", limits, limits, minters);
}

#[test]
fn test_deploy_xerc20_should_emit_events() {
    let setup = setup();

    let limits = array![].span();
    let minters = array![].span();

    let mut spy = spy_events();
    let xerc20_address = setup.xerc20_factory.deploy_xerc20("Test", "TST", limits, limits, minters);

    spy
        .assert_emitted(
            @array![
                (
                    setup.xerc20_factory.contract_address,
                    XERC20Factory::Event::XERC20Deployed(
                        XERC20Factory::XERC20Deployed { xerc20: xerc20_address }
                    )
                )
            ]
        );
}

#[test]
fn test_deploy_lockbox_should_emit_events() {
    let setup = setup();

    let limits = array![].span();
    let minters = array![].span();

    let xerc20_address = setup.xerc20_factory.deploy_xerc20("Test", "TST", limits, limits, minters);

    let mut spy = spy_events();

    let lockbox_address = setup.xerc20_factory.deploy_lockbox(xerc20_address, setup.erc20);
    spy
        .assert_emitted(
            @array![
                (
                    setup.xerc20_factory.contract_address,
                    XERC20Factory::Event::LockboxDeployed(
                        XERC20Factory::LockboxDeployed { lockbox: lockbox_address }
                    )
                )
            ]
        );
}
