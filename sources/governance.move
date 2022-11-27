module realm::Governance{

    use std::signer;
    use std::string::{utf8,String};
    use std::vector;
    use std::account::{create_resource_account,SignerCapability,create_signer_with_capability};
    use std::option::{Option,Self};
    use realm::Members;
    use realm::Realm;
    use std::debug;
    use realm::Treasury;
    friend realm::Proposal;
    struct Governance has store,drop,key{
        realm:address,
        voting_proposal_count:u64,
        governance_config:GovernanceConfig,
        min_weight_to_create_proposal:Option<u64>,
        governance_signer_cap:SignerCapability,
        governed_account:String
    }

    struct RealmGovernances has key{
        governances:vector<address>
    }

    struct GovernanceConfig has store,drop,copy{
        max_voting_time:u64,
        approval_quorum:u8
    }

    const MIN_VOTING_TIME:u64=7*86400+1;
    const MIN_APPROVAL_QUORUM:u8=51;

    const EINVALID_VOTING_TIME:u64=8;
    const EINVALID_VOTING_QUORUM:u64=9;
    const EINVALID_REALM_FOR_GOVERNANCE:u64=10;
    const EINVALID_GOVERNED_ACCOUNT:u64=11;

    public entry fun create_governance(creator:&signer,realm_address:address,min_weight_to_create_proposal:Option<u64>,governed_account:vector<u8>,governance_config:GovernanceConfig)acquires RealmGovernances,Governance{
        let signer_address=signer::address_of(creator);
        let _role=Members::get_member_data_role(signer_address,realm_address);
        //TODO:check role permission for action
        let realm_signer=Realm::get_realm_by_address(realm_address);

       assert_is_valid_governance_config(&governance_config);

        if(!exists<RealmGovernances>(realm_address)){
            let (governance,governance_signer_cap)=create_resource_account(&realm_signer,governed_account);
            move_to(&governance,Governance{
            governance_config,
            voting_proposal_count:0,
            realm:realm_address,
            min_weight_to_create_proposal,
            governance_signer_cap,
            governed_account:utf8(governed_account)
         });
            let governances_vector=vector::empty<address>();
            let governance_address=signer::address_of(&governance);
            vector::push_back(&mut governances_vector,governance_address);
            move_to(&realm_signer,RealmGovernances{
                governances:governances_vector
            })
        }else{
            let realm_governances=borrow_global_mut<RealmGovernances>(realm_address);
            let last_governance=vector::borrow(&realm_governances.governances,vector::length(&realm_governances.governances)-1);
            let governance_signer=get_governance_as_signer(*last_governance);
            let (new_governance,new_governance_cap)=create_resource_account(&governance_signer,governed_account);
            move_to(&new_governance,Governance{
                governance_config,
                voting_proposal_count:0,
                realm:realm_address,
                min_weight_to_create_proposal,
                governance_signer_cap:new_governance_cap,
                governed_account:utf8(governed_account)
            });
            vector::push_back(&mut realm_governances.governances,signer::address_of(&new_governance));
        }
        
    }

    public entry fun set_governance_config(governed_account:&signer,realm_address:address,governance_config:GovernanceConfig,governance:address)acquires RealmGovernances,Governance{
        assert_is_valid_realm_for_governance(realm_address,governance);
        let governance=borrow_global_mut<Governance>(governance);
        let _governed_account_address=signer::address_of(governed_account);
        //TODO:check if governed_account signed
       // assert!(governance.governed_account==governed_account_address,EINVALID_GOVERNED_ACCOUNT);
        governance.governance_config==governance_config;

    }

    public (friend) fun get_governance_config(realm_address:address,governance:address):GovernanceConfig acquires RealmGovernances,Governance{
        assert_is_valid_realm_for_governance(realm_address,governance);
        let governance=borrow_global<Governance>(governance);
        governance.governance_config
    }

    public (friend) fun change_proposal_count(realm_address:address,governance:address,is_increase:bool)acquires Governance,RealmGovernances{
        assert_is_valid_realm_for_governance(realm_address,governance);
        let governance=borrow_global_mut<Governance>(governance);
        if(is_increase){
            governance.voting_proposal_count=governance.voting_proposal_count+1;
        }else{
            governance.voting_proposal_count=governance.voting_proposal_count-1;
        }
    }

    // public (friend) fun get_governance(governance_address:address):&Governance acquires Governance{
    //    borrow_global<Governance>(governance_address)
    // }

    public (friend) fun get_governance_as_signer(governance_address:address):signer acquires Governance{
        let governance=borrow_global<Governance>(governance_address);
        create_signer_with_capability(&governance.governance_signer_cap)
        
    }

    fun assert_is_valid_governance_config(config:&GovernanceConfig){
        assert!(config.max_voting_time>=MIN_VOTING_TIME,EINVALID_VOTING_TIME);

        assert!(config.approval_quorum>=MIN_APPROVAL_QUORUM,EINVALID_VOTING_QUORUM);
    }

    fun assert_is_valid_realm_for_governance(realm:address,governance:address) acquires RealmGovernances{
        let realm_governances=borrow_global<RealmGovernances>(realm);
        assert!(vector::contains(&realm_governances.governances,&governance),EINVALID_REALM_FOR_GOVERNANCE);
    }
     
     #[test(creator=@0xcaffe,account_creator=@0x99,resource_account=@0x14,realm_account=@0x15)]
     public fun test_create_governance(creator:signer,account_creator:&signer,resource_account:signer,realm_account:&signer) acquires RealmGovernances,Governance{
        Realm::test_create_realm(creator,account_creator,resource_account,realm_account);
        let realm_address=Realm::get_realm_address_by_name(utf8(b"Genesis Realm"));
        Members::add_founder_role(account_creator,realm_address);
        let realm=Realm::get_realm_by_address(realm_address);
        Treasury::init_treasury_resource(&realm);
        //TODO:check how to turn address to vector<u8>
        create_governance(account_creator,realm_address,option::none(),b"treasury_address",GovernanceConfig{max_voting_time:40*86400+1,approval_quorum:55});
        let realm_governances=borrow_global<RealmGovernances>(realm_address).governances;
        let governance_address=vector::borrow(&realm_governances,vector::length(&realm_governances)-1);
        let governance=borrow_global<Governance>(*governance_address);
        assert!(governance.governance_config.approval_quorum==55,0);
        //CRETING 2nd governance in realm
        create_governance(account_creator,realm_address,option::none(),b"treasury_address2",GovernanceConfig{max_voting_time:40*86400+1,approval_quorum:88});
        let realm_governances_new=borrow_global<RealmGovernances>(realm_address).governances;
        let new_governance_address=vector::borrow(&realm_governances_new,vector::length(&realm_governances_new)-1);
        let new_governance=borrow_global<Governance>(*new_governance_address);
        debug::print(&new_governance.governance_config);
        assert!(new_governance.governance_config.approval_quorum==88,0);
     }
}