module realm::Fundraise{

    use realm::Treasury;
    use realm::Members;
    use realm::Realm;
    use std::signer;
    use std::type_info;
    use std::simple_map::{SimpleMap,Self};
    use std::coin::{transfer,register,Self,MintCapability,BurnCapability,balance};
    use std::string::utf8;
    use std::debug;
    use std::vector;
    #[test_only]
    use std::aptos_coin::{AptosCoin,initialize_for_test};
    use aptos_framework::account::create_account_for_test;


    struct Fundraises has key{
        fundraises:vector<FundraiseData>
    }

    struct FundraiseData has store,drop,copy{
        fundraise_index:u64,
        fundraise_cap:u64,
        raised_amount:u64,
        is_active:bool,
        treasury:address,
    }

    struct DepositRecord has store,copy,drop{
        treasury:address,
        fundraise_index:u64,
        amount:u64,
        coin_address:address
    }

    struct RealmDeposits has key,drop{
        deposits:SimpleMap<address,SimpleMap<u64,DepositRecord>>
    }
  


    const CREATE_FUNDRAISE_ACTION:u8=4;

    const EFUNDRAISE_ALREDY_ACTIVE:u64=4;
    const EFUNDRAISE_CLOSED:u64=5;
    const EINVALID_SUPPORT_COIN:u64=6;
    const ENOT_A_MEMBER:u64=7;

    public entry fun create_fundraise(realm_auth:&signer,realm_address:address,treasury_address:address,fundraise_cap:u64)acquires Fundraises{
     let treasury=Treasury::get_treasury_as_signer(treasury_address,realm_address);
     let _member_address=signer::address_of(realm_auth);
    // assert!(Realm::is_valid_role_for_action(Members::get_member_data_role(member_address,realm_address),CREATE_FUNDRAISE_ACTION,&realm_address),1);
     let treasury_address=signer::address_of(&treasury);
     Treasury::change_fundraise_status(treasury_address,true,realm_address);
     if(!exists<Fundraises>(treasury_address)){
        let fundraise_vector=vector::empty<FundraiseData>();
        vector::push_back(&mut fundraise_vector,FundraiseData{
            fundraise_cap,
            is_active:true,
            treasury:treasury_address,
            raised_amount:0,
            fundraise_index:1,
        });
        move_to(&treasury,Fundraises{
            fundraises:fundraise_vector
        })
     }else{
        let fundraises=borrow_global_mut<Fundraises>(treasury_address);
        let fundraise_index=vector::length(&fundraises.fundraises);
        assert!(!vector::borrow(&fundraises.fundraises,fundraise_index-1).is_active,EFUNDRAISE_ALREDY_ACTIVE);
        vector::push_back(&mut fundraises.fundraises,FundraiseData{
            fundraise_cap,
            is_active:true,
            treasury:treasury_address,
            raised_amount:0,
            fundraise_index:fundraise_index
            })
        };
        Treasury::update_fundraise_count(realm_address,treasury_address);
    }

    public entry fun deposit_to_treasury<CoinType>(supporter:&signer,treasury_address:address,realm_address:address,amount:u64) acquires Fundraises,RealmDeposits{
        let (coin_address,_is_fundraise_active,fundraise_count)=Treasury::get_treasury_state(treasury_address,realm_address);
        let signer_address=signer::address_of(supporter);
        assert!(Members::is_member(copy signer_address),ENOT_A_MEMBER);
        let coin_type=type_info::type_of<CoinType>();
        assert!(type_info::account_address(&coin_type)==coin_address,EINVALID_SUPPORT_COIN);
        let fundraise_data_vec=borrow_global_mut<Fundraises>(treasury_address).fundraises;
        let fundraise_data=vector::borrow_mut(&mut fundraise_data_vec,fundraise_count-1);
        assert!(fundraise_data.is_active,EFUNDRAISE_CLOSED);
        let support_amount=if(amount>(fundraise_data.fundraise_cap-fundraise_data.raised_amount)){
          Treasury::change_fundraise_status(treasury_address,false,realm_address);
          fundraise_data.is_active=false;
          debug::print(&fundraise_data.is_active);
          fundraise_data.fundraise_cap-fundraise_data.raised_amount
        }else{
            amount
        };
        if(!exists<RealmDeposits>(signer_address)){
            move_to(supporter,RealmDeposits{
                deposits:simple_map::create()
            })
        };
        let realm_deposits=borrow_global_mut<RealmDeposits>(signer_address);
        if(simple_map::contains_key(&realm_deposits.deposits,&treasury_address)){
            let deposits_map=simple_map::borrow_mut(&mut realm_deposits.deposits,&treasury_address);
             if(simple_map::contains_key(deposits_map,&fundraise_count)){
             let deposit_record=simple_map::borrow_mut(deposits_map,&fundraise_count);
             deposit_record.amount=deposit_record.amount+support_amount;
            }else{
                simple_map::add(deposits_map,fundraise_count,DepositRecord{
                treasury:treasury_address,
                coin_address,
                amount:support_amount,
                fundraise_index:fundraise_count
                })
            }
        }else{
             let fundraise_deposit_map=simple_map::create<u64,DepositRecord>();
             simple_map::add(&mut fundraise_deposit_map,fundraise_count,DepositRecord{
                treasury:treasury_address,
                coin_address,
                amount:support_amount,
                fundraise_index:fundraise_count
            });
            simple_map::add(&mut realm_deposits.deposits,treasury_address,fundraise_deposit_map);
        };
         
         transfer<CoinType>(supporter,treasury_address,support_amount);
         fundraise_data.raised_amount=fundraise_data.raised_amount+support_amount;
         debug::print(&fundraise_data.raised_amount);
    
    }

    #[test(creator=@0xcaffe,account_creator=@0x99,resource_account=@0x14,realm_account=@0x15)]
    public fun test_create_fundraise(creator:signer,account_creator:&signer,resource_account:signer,realm_account:&signer):address acquires Fundraises{
        let treasury_address=Treasury::test_create_treasury(creator,account_creator,resource_account,realm_account);
        let realm_address=Realm::get_realm_address_by_name(utf8(b"Genesis Realm"));
        create_fundraise(account_creator,realm_address,treasury_address,2);
        let fundraises=borrow_global<Fundraises>(treasury_address);
        let fundraise_data=vector::borrow(&fundraises.fundraises,vector::length(&fundraises.fundraises)-1);
        assert!(fundraise_data.fundraise_cap==2,1);
        assert!(fundraise_data.is_active,2);
        assert!(fundraise_data.treasury==treasury_address,3);
        assert!(fundraise_data.fundraise_index==1,4);
        let (_coin_address,is_active,fundraise_count)=Treasury::get_treasury_state(treasury_address,realm_address);
        assert!(fundraise_count==1,5);
        assert!(is_active,6);
        treasury_address
    }
    #[test_only]
    struct MintAndBurnCap has key{
        mint_cap:MintCapability<AptosCoin>,
        burn_cap:BurnCapability<AptosCoin>
    }
  
    #[test(creator=@0xcaffe,account_creator=@0x99,resource_account=@0x14,realm_account=@0x15,aptos_framework=@0x1)]
    public fun test_deposit_to_fundraise(creator:signer,account_creator:&signer,resource_account:signer,realm_account:&signer,aptos_framework:signer)acquires Fundraises,RealmDeposits{
        let treasury_address=test_create_fundraise(creator,account_creator,resource_account,realm_account);
        create_account_for_test(signer::address_of(account_creator));
        let realm_address=Realm::get_realm_address_by_name(utf8(b"Genesis Realm"));
        register<AptosCoin>(account_creator);
        let(burn,mint)=initialize_for_test(&aptos_framework);
        let coin = coin::mint<AptosCoin>(100, &mint);
        coin::deposit(signer::address_of(account_creator), coin);
        move_to(account_creator,MintAndBurnCap{
            mint_cap:mint,
            burn_cap:burn
        });
       deposit_to_treasury<AptosCoin>(account_creator,treasury_address,realm_address,5);
       let treasury_balance=balance<AptosCoin>(treasury_address);
       assert!(treasury_balance==2,6);
       let deposit_records=borrow_global<RealmDeposits>(signer::address_of(account_creator));
       let deposits_map=simple_map::borrow(&deposit_records.deposits,&treasury_address);
       let deposit_data=simple_map::borrow(deposits_map,&1);
       assert!(deposit_data.amount==2,7);
       assert!(deposit_data.fundraise_index==1,7);
       let fundraises=borrow_global<Fundraises>(treasury_address);
       assert!(vector::length(&fundraises.fundraises)==1,8);
       let fundraise_data=vector::borrow(&fundraises.fundraises,0);
       debug::print(&fundraise_data.raised_amount);
       //TODO:check why fundraise_record 
    }
}