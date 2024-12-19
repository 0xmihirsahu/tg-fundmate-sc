#[starknet::interface]
pub trait IGroupPayments<TContractState> {
    fn create_group(ref self: TContractState, group_name: felt252) -> u32;
    fn add_member_to_group(ref self: TContractState, group_id: u32, member: ContractAddress);
    fn add_payment(
        ref self: TContractState,
        group_id: u32,
        payer: ContractAddress,
        amount: u256,
        description: felt252
    );
    fn get_member_balance(self: @TContractState, group_id: u32, member: ContractAddress) -> i256;
    fn get_group_members(self: @TContractState, group_id: u32) -> Array<ContractAddress>;
    fn settle_payment(
        ref self: TContractState,
        group_id: u32,
        from: ContractAddress,
        to: ContractAddress,
        amount: u256
    );
    fn get_all_settlements(
        self: @TContractState, group_id: u32
    ) -> Array<(ContractAddress, ContractAddress, u256)>;
}

#[starknet::contract]
mod GroupPayments {
    use core::starknet::ContractAddress;
    use starknet::get_caller_address;
    use array::ArrayTrait;
    use option::OptionTrait;
    use traits::Into;

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        GroupCreated: GroupCreated,
        MemberAdded: MemberAdded,
        PaymentAdded: PaymentAdded,
        PaymentSettled: PaymentSettled,
    }

    #[derive(Drop, starknet::Event)]
    struct GroupCreated {
        group_id: u32,
        name: felt252
    }

    #[derive(Drop, starknet::Event)]
    struct MemberAdded {
        group_id: u32,
        member: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct PaymentAdded {
        group_id: u32,
        payer: ContractAddress,
        amount: u256,
        description: felt252
    }

    #[derive(Drop, starknet::Event)]
    struct PaymentSettled {
        group_id: u32,
        from: ContractAddress,
        to: ContractAddress,
        amount: u256
    }

    #[storage]
    struct Storage {
        group_counter: u32,
        group_name: LegacyMap::<u32, felt252>,
        group_members: LegacyMap::<(u32, ContractAddress), bool>,
        member_balances: LegacyMap::<(u32, ContractAddress), i256>,
        members_array: LegacyMap::<u32, Array<ContractAddress>>,
        settlements: LegacyMap::<u32, Array<(ContractAddress, ContractAddress, u256)>>
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.group_counter.write(0);
    }

    #[external(v0)]
    impl GroupPaymentsImpl of super::IGroupPayments<ContractState> {
        fn create_group(ref self: ContractState, group_name: felt252) -> u32 {
            let group_id = self.group_counter.read() + 1;
            self.group_counter.write(group_id);
            self.group_name.write(group_id, group_name);
            
            // Initialize empty arrays for the new group
            let empty_members: Array<ContractAddress> = ArrayTrait::new();
            self.members_array.write(group_id, empty_members);
            
            let empty_settlements: Array<(ContractAddress, ContractAddress, u256)> = ArrayTrait::new();
            self.settlements.write(group_id, empty_settlements);

            self.emit(GroupCreated { group_id, name: group_name });
            group_id
        }

        fn add_member_to_group(ref self: ContractState, group_id: u32, member: ContractAddress) {
            assert(group_id <= self.group_counter.read(), 'Invalid group ID');
            assert(!self.group_members.read((group_id, member)), 'Member already exists');

            self.group_members.write((group_id, member), true);
            self.member_balances.write((group_id, member), 0);
            
            let mut members = self.members_array.read(group_id);
            members.append(member);
            self.members_array.write(group_id, members);

            self.emit(MemberAdded { group_id, member });
        }

        fn add_payment(
            ref self: ContractState,
            group_id: u32,
            payer: ContractAddress,
            amount: u256,
            description: felt252
        ) {
            assert(group_id <= self.group_counter.read(), 'Invalid group ID');
            assert(self.group_members.read((group_id, payer)), 'Payer not in group');
            assert(amount > 0, 'Amount must be positive');

            let members = self.members_array.read(group_id);
            let member_count = members.len();
            assert(member_count > 0, 'No members in group');

            let share_per_member: u256 = amount / member_count.into();

            // Update balances
            let mut i = 0;
            loop {
                if i >= member_count {
                    break;
                }
                let member = *members.at(i);
                if member != payer {
                    let current_balance = self.member_balances.read((group_id, member));
                    self.member_balances.write(
                        (group_id, member), current_balance - share_per_member.into()
                    );
                }
                i += 1;
            }

            // Update payer's balance
            let payer_balance = self.member_balances.read((group_id, payer));
            self.member_balances.write(
                (group_id, payer),
                payer_balance + (amount - share_per_member).into()
            );

            self.emit(PaymentAdded { group_id, payer, amount, description });
        }

        fn get_member_balance(
            self: @ContractState, group_id: u32, member: ContractAddress
        ) -> i256 {
            self.member_balances.read((group_id, member))
        }

        fn get_group_members(self: @ContractState, group_id: u32) -> Array<ContractAddress> {
            self.members_array.read(group_id)
        }

        fn settle_payment(
            ref self: ContractState,
            group_id: u32,
            from: ContractAddress,
            to: ContractAddress,
            amount: u256
        ) {
            assert(group_id <= self.group_counter.read(), 'Invalid group ID');
            assert(self.group_members.read((group_id, from)), 'From member not in group');
            assert(self.group_members.read((group_id, to)), 'To member not in group');
            assert(amount > 0, 'Amount must be positive');

            let from_balance = self.member_balances.read((group_id, from));
            let to_balance = self.member_balances.read((group_id, to));

            // Update balances
            self.member_balances.write((group_id, from), from_balance + amount.into());
            self.member_balances.write((group_id, to), to_balance - amount.into());

            // Record settlement
            let mut settlements = self.settlements.read(group_id);
            settlements.append((from, to, amount));
            self.settlements.write(group_id, settlements);

            self.emit(PaymentSettled { group_id, from, to, amount });
        }

        fn get_all_settlements(
            self: @ContractState,
            group_id: u32
        ) -> Array<(ContractAddress, ContractAddress, u256)> {
            self.settlements.read(group_id)
        }
    }
}