module realm::Governance{

    use std::simple_map::{SimpleMap,Self};
    use std::signer;
    use std::aptos_coin::AptosCoin;
    use std::string::utf8;
    use std::option::{Option,Self};
    use realm::Members;
    use realm::Realm;
    use realm::Treasury;
    struct Governance has store,copy,drop{
        realm:address,
        voting_proposal_count:u64,
        governance_config:GovernanceConfig,
        min_weight_to_create_proposal:Option<u64>,
    }

    struct RealmGovernances has key{
        governances:SimpleMap<address,Governance>
    }

    struct GovernanceConfig has store,drop,copy{
        max_voting_time:u64,
        approval_quorum:u8
    }

    const MIN_VOTING_TIME:u64=7*86400+1;
    const MIN_APPROVAL_QUORUM:u8=51;

    const EINVALID_VOTING_TIME:u64=8;
    const EINVALID_VOTING_QUORUM:u64=9;

    public entry fun create_governance(creator:&signer,realm_address:address,min_weight_to_create_proposal:Option<u64>,governed_account:address,governance_config:GovernanceConfig)acquires RealmGovernances{
        let signer_address=signer::address_of(creator);
        let _role=Members::get_member_data_role(signer_address,realm_address);
        //TODO:check role permission for action
        let realm_signer=Realm::get_realm_by_address(realm_address);

       assert_is_valid_governance_config(&governance_config);

        if(!exists<RealmGovernances>(realm_address)){
            move_to(&realm_signer,RealmGovernances{
                governances:simple_map::create()
            })
        };
        let governances=borrow_global_mut<RealmGovernances>(realm_address);
        simple_map::add(&mut governances.governances,governed_account,Governance{
            governance_config,
            voting_proposal_count:0,
            realm:realm_address,
            min_weight_to_create_proposal
        });
    }

    public entry fun set_governance_config(governed_account:&signer,realm_address:address,governance_config:GovernanceConfig)acquires RealmGovernances{
        let governances=borrow_global_mut<RealmGovernances>(realm_address);
        let governed_account_address=signer::address_of(governed_account);
        let governance=simple_map::borrow_mut(&mut governances.governances,&governed_account_address);

        assert_is_valid_governance_config(&governance_config);

        governance.governance_config=governance_config;
    }

    public (friend) fun get_governance_config(realm_address:address,governaned_account:address):GovernanceConfig acquires RealmGovernances{
        let governances=borrow_global<RealmGovernances>(realm_address);
        let governance=simple_map::borrow(&governances.governances,&governaned_account);
        governance.governance_config
    }

    public (friend) fun change_proposal_count(realm_address:address,governaned_account:address,is_increase:bool)acquires RealmGovernances{
        let governances=borrow_global_mut<RealmGovernances>(realm_address);
        let governance=simple_map::borrow_mut(&mut governances.governances,&governaned_account);
        if(is_increase){
            governance.voting_proposal_count=governance.voting_proposal_count+1;
        }else{
            governance.voting_proposal_count=governance.voting_proposal_count-1;
        }
    }

    fun assert_is_valid_governance_config(config:&GovernanceConfig){
        assert!(config.max_voting_time>=MIN_VOTING_TIME,EINVALID_VOTING_TIME);

        assert!(config.approval_quorum>=MIN_APPROVAL_QUORUM,EINVALID_VOTING_QUORUM);
    }
     
     #[test(creator=@0xcaffe,account_creator=@0x99,resource_account=@0x14,realm_account=@0x15)]
     public fun test_create_governance(creator:signer,account_creator:&signer,resource_account:signer,realm_account:&signer) acquires RealmGovernances{
        Realm::test_create_realm(creator,account_creator,resource_account,realm_account);
        let realm_address=Realm::get_realm_address_by_name(utf8(b"Genesis Realm"));
        Members::add_founder_role(account_creator,realm_address);
        let realm=Realm::get_realm_by_address(realm_address);
        Treasury::init_treasury_resource(&realm);
        let treasury_address=Treasury::create_treasury<AptosCoin>(account_creator,realm_address,b"First treasury");
        create_governance(account_creator,realm_address,option::none(),treasury_address,GovernanceConfig{max_voting_time:40*86400+1,approval_quorum:55});
        let realm_governances=borrow_global<RealmGovernances>(realm_address).governances;
        assert!(simple_map::borrow(&realm_governances,&treasury_address).governance_config.approval_quorum==55,0);
     }
}