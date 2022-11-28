module realm::Treasury{

    use std::string::{String,utf8};
     use std::account::{SignerCapability,create_resource_account,create_signer_with_capability};
     use std::simple_map::{Self,SimpleMap};
     use std::signer;
     use std::coin::{register,balance};
     use std::aptos_coin::{AptosCoin};
     use realm::Realm;
     use realm::Members;
     use std::type_info;

     friend realm::Fundraise;
     friend realm::Governance;
     #[test_only]
     friend realm::Proposal;

    struct Treasury has store{
        realm:address,
        fundraise_count:u64,
        name:String,
        has_active_fundraise:bool,
        signer_cap:SignerCapability,
        coin_address:address
    }

    struct RealmTreasuries has key{
        treasuries:SimpleMap<address,Treasury>
    }

    const CREATE_TREASURY_ACTION:u8=3;

    const ENOT_VALID_ACTION_FOR_ROLE:u64=1;

  

    public entry fun create_treasury<CoinType>(realm_authority:&signer,realm_address:address,name:vector<u8>):address acquires RealmTreasuries{
        let realm_auth_address=signer::address_of(realm_authority);
        let _role=Members::get_member_data_role(realm_auth_address,realm_address);
       // assert!(Realm::is_valid_role_for_action(role,CREATE_TREASURY_ACTION,&realm_address),ENOT_VALID_ACTION_FOR_ROLE);

         if(!exists<RealmTreasuries>(realm_address)){
            let realm=Realm::get_realm_by_address(realm_address);
            move_to(&realm,RealmTreasuries{
                treasuries:simple_map::create()
            })
        };

        let realm_signer=Realm::get_realm_by_address(realm_address);

        let (treasury_account,treasury_signer_cap)=create_resource_account(&realm_signer,b"treasury");

        register<CoinType>(&treasury_account);

        let treasury_address=signer::address_of(&treasury_account);

        let coin_address=type_info::type_of<CoinType>();
        
        let realm_treasuries=borrow_global_mut<RealmTreasuries>(realm_address);
        simple_map::add(&mut realm_treasuries.treasuries,treasury_address,Treasury{
            realm:realm_address,
            coin_address:type_info::account_address(&coin_address),
            name:utf8(name),
            has_active_fundraise:false,
            fundraise_count:0,
            signer_cap:treasury_signer_cap
        });

        treasury_address
    }

    public(friend) fun get_treasury_as_signer(treasury_address:address,realm_address:address):signer acquires RealmTreasuries{
        let treasury=borrow_global<RealmTreasuries>(realm_address);
        let treasury_data=simple_map::borrow(&treasury.treasuries,&treasury_address);
        create_signer_with_capability(&treasury_data.signer_cap)
    }

    public(friend) fun change_fundraise_status(treasury_address:address,new_status:bool,realm_address:address)acquires RealmTreasuries{
        let realm_treasuries=borrow_global_mut<RealmTreasuries>(realm_address);
        let treasury_data=simple_map::borrow_mut(&mut realm_treasuries.treasuries,&treasury_address);
        treasury_data.has_active_fundraise=new_status;
    }

    public(friend) fun get_treasury_state(treasury_address:address,realm_address:address):(address,bool,u64)acquires RealmTreasuries{
        let treasuries=borrow_global<RealmTreasuries>(realm_address);
        let treasury_data=simple_map::borrow(&treasuries.treasuries,&treasury_address);
        (treasury_data.coin_address,treasury_data.has_active_fundraise,treasury_data.fundraise_count)
    }

    public (friend) fun update_fundraise_count(realm_address:address,treasury_address:address) acquires RealmTreasuries{
        let realm_treasuries=borrow_global_mut<RealmTreasuries>(realm_address);
        let treasury_data=simple_map::borrow_mut(&mut realm_treasuries.treasuries,&treasury_address);
        treasury_data.fundraise_count=treasury_data.fundraise_count+1;

    }

    public(friend) fun get_deposit_and_address(treasury_address:address,realm:address):(u64,address) acquires RealmTreasuries{
        let treasuries=borrow_global<RealmTreasuries>(realm);
        let treasury=simple_map::borrow(&treasuries.treasuries,&treasury_address);
        //TODO:figure out how to make this flexible(to make it work with any coin,not only AptosCoin)
        (balance<AptosCoin>(copy treasury_address),treasury.coin_address)

    }

    #[test(creator=@0xcaffe,account_creator=@0x99,resource_account=@0x14,realm_account=@0x15)]
    public entry fun test_create_treasury(creator:signer,account_creator:&signer,resource_account:signer,realm_account:&signer):address acquires RealmTreasuries{
        Members::test_add_founder(creator,account_creator,resource_account,realm_account);
        let realm_address=Realm::get_realm_address_by_name(utf8(b"Genesis Realm"));
        let treasury_address=create_treasury<AptosCoin>(account_creator,realm_address,b"First treasury");
        let treasuries=borrow_global<RealmTreasuries>(realm_address);
        let treasury_resource=simple_map::borrow(&treasuries.treasuries,&treasury_address);
        assert!(treasury_resource.name==utf8(b"First treasury"),1);
        let _treasury_signer=get_treasury_as_signer(treasury_address,realm_address);
        assert!(balance<AptosCoin>(treasury_address)==0,1);
        treasury_address
        
    }
  

}