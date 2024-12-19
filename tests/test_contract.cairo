use starknet::ContractAddress;
use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};
use array::ArrayTrait;
use core::traits::Into;
use group_payments::IGroupPaymentsDispatcher;
use group_payments::IGroupPaymentsDispatcherTrait;
use group_payments::IGroupPaymentsSafeDispatcher;
use group_payments::IGroupPaymentsSafeDispatcherTrait;
use starknet::testing::set_contract_address;

fn deploy_contract(name: ByteArray) -> ContractAddress {
    let contract = declare(name).unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@ArrayTrait::new()).unwrap();
    contract_address
}

fn setup_test_addresses() -> (ContractAddress, ContractAddress, ContractAddress) {
    let member1: ContractAddress = 0x123.try_into().unwrap();
    let member2: ContractAddress = 0x456.try_into().unwrap();
    let member3: ContractAddress = 0x789.try_into().unwrap();
    (member1, member2, member3)
}

#[test]
fn test_create_group() {
    let contract_address = deploy_contract("GroupPayments");
    let dispatcher = IGroupPaymentsDispatcher { contract_address };
    
    let group_id = dispatcher.create_group('Test Group');
    assert(group_id == 1, 'Invalid group ID');
    
    let members = dispatcher.get_group_members(group_id);
    assert(members.len() == 0, 'Group should be empty');
}

#[test]
fn test_add_members_and_check_balance() {
    let contract_address = deploy_contract("GroupPayments");
    let dispatcher = IGroupPaymentsDispatcher { contract_address };
    let (member1, member2, _) = setup_test_addresses();
    
    let group_id = dispatcher.create_group('Test Group');
    dispatcher.add_member_to_group(group_id, member1);
    dispatcher.add_member_to_group(group_id, member2);
    
    let members = dispatcher.get_group_members(group_id);
    assert(members.len() == 2, 'Should have 2 members');
    
    let balance1 = dispatcher.get_member_balance(group_id, member1);
    let balance2 = dispatcher.get_member_balance(group_id, member2);
    assert(balance1 == 0, 'Initial balance should be 0');
    assert(balance2 == 0, 'Initial balance should be 0');
}

#[test]
fn test_add_payment() {
    let contract_address = deploy_contract("GroupPayments");
    let dispatcher = IGroupPaymentsDispatcher { contract_address };
    let (member1, member2, _) = setup_test_addresses();
    
    let group_id = dispatcher.create_group('Test Group');
    dispatcher.add_member_to_group(group_id, member1);
    dispatcher.add_member_to_group(group_id, member2);
    
    set_contract_address(member1);
    dispatcher.add_payment(group_id, member1, 100.into(), 'Dinner');
    
    let payer_balance = dispatcher.get_member_balance(group_id, member1);
    let other_balance = dispatcher.get_member_balance(group_id, member2);
    
    assert(payer_balance == 50, 'Incorrect payer balance');
    assert(other_balance == -50, 'Incorrect receiver balance');
}

#[test]
fn test_settlement() {
    let contract_address = deploy_contract("GroupPayments");
    let dispatcher = IGroupPaymentsDispatcher { contract_address };
    let (member1, member2, _) = setup_test_addresses();
    
    let group_id = dispatcher.create_group('Test Group');
    dispatcher.add_member_to_group(group_id, member1);
    dispatcher.add_member_to_group(group_id, member2);
    
    set_contract_address(member1);
    dispatcher.add_payment(group_id, member1, 100.into(), 'Dinner');
    
    dispatcher.settle_payment(group_id, member2, member1, 50.into());
    
    let balance1 = dispatcher.get_member_balance(group_id, member1);
    let balance2 = dispatcher.get_member_balance(group_id, member2);
    assert(balance1 == 0, 'Balance should be settled');
    assert(balance2 == 0, 'Balance should be settled');
}

#[test]
#[feature("safe_dispatcher")]
fn test_invalid_payment_amount() {
    let contract_address = deploy_contract("GroupPayments");
    let safe_dispatcher = IGroupPaymentsSafeDispatcher { contract_address };
    let (member1, _, _) = setup_test_addresses();
    
    let group_id = safe_dispatcher.create_group('Test Group').unwrap();
    safe_dispatcher.add_member_to_group(group_id, member1).unwrap();
    
    set_contract_address(member1);
    match safe_dispatcher.add_payment(group_id, member1, 0.into(), 'Invalid') {
        Result::Ok(_) => panic_with_felt252('Should have panicked'),
        Result::Err(panic_data) => {
            assert(*panic_data.at(0) == 'Amount must be positive', *panic_data.at(0));
        }
    };
}

#[test]
#[feature("safe_dispatcher")]
fn test_invalid_group_id() {
    let contract_address = deploy_contract("GroupPayments");
    let safe_dispatcher = IGroupPaymentsSafeDispatcher { contract_address };
    let (member1, _, _) = setup_test_addresses();
    
    match safe_dispatcher.add_member_to_group(99, member1) {
        Result::Ok(_) => panic_with_felt252('Should have panicked'),
        Result::Err(panic_data) => {
            assert(*panic_data.at(0) == 'Invalid group ID', *panic_data.at(0));
        }
    };
}

#[test]
#[feature("safe_dispatcher")]
fn test_duplicate_member() {
    let contract_address = deploy_contract("GroupPayments");
    let safe_dispatcher = IGroupPaymentsSafeDispatcher { contract_address };
    let (member1, _, _) = setup_test_addresses();
    
    let group_id = safe_dispatcher.create_group('Test Group').unwrap();
    safe_dispatcher.add_member_to_group(group_id, member1).unwrap();
    
    match safe_dispatcher.add_member_to_group(group_id, member1) {
        Result::Ok(_) => panic_with_felt252('Should have panicked'),
        Result::Err(panic_data) => {
            assert(*panic_data.at(0) == 'Member already exists', *panic_data.at(0));
        }
    };
}