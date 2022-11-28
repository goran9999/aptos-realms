module realm::Proposal{

    use std::string::{String,utf8};
    use std::vector;
    use std::simple_map::{SimpleMap,Self};
    use realm::Governance;
    use realm::Members;
    use std::option::{Self,Option};
    use std::signer;
    use std::timestamp;
    use realm::Fundraise;
    use std::account::create_account_for_test;
    #[test_only]
    use realm::Treasury;
    use std::aptos_coin::AptosCoin;
    use realm::Realm;
    struct Proposal has store,copy,drop{
        name:String,
        description:String,
        approve_vote_weight:u64,
        deny_vote_weight:u64,
        state:u8,
        veto_vote_weight:u64,
        voting_at:u64,
        index:u64
        //TODO:implement script execution hash
    }

    struct GovernanceProposals has key{
        proposals:vector<Proposal>
    }

    struct VoterWeights has key,copy{
        weights:SimpleMap<address,VoterWeihtRecord>
    }

    struct VoterWeihtRecord has store,copy,drop{
        realm:address,
        weight:u64,
        //TODO:check how to store updated_at slot
        //voter_weigt_expiry:u64
        user:address,
    }

    struct MaxVoterWeightRecord has store,copy,drop{
        realm:address,
        max_voter_weight:u64,
        coin_address:address,
        max_voter_weight_expiry:Option<u64>,
    }

    struct MaxVoterWeights has key{
        max_voter_weights:SimpleMap<u64,MaxVoterWeightRecord>
    }

    const VOTING:u8=0;
    const SUCCEDED:u8=1;
    const DEFEATED:u8=2;
    const EXECUTED:u8=3;
    const SIGNING_OFF:u64=4;
    const CANCELED:u64=5;
    const VETOED:u64=6;

    const MAX_VOTING_PROPOSALS_PER_GOVERNANCE:u64=20;

    const ETOO_MANY_VOTING_PROPOSALS:u64=12;
    const EINVALID_VOTER_WEIGHT_RECORD:u64=13;
    const ENOT_ENOUGH_WEIGHT_TO_CREATE_PROPOSAL:u64=14;
    const ENOT_A_MEMBER:u64=15;
    const EINVALID_PROPOSAL_STATE:u64=16;

    const YES_VOTE:u64=0;
    const NO_VOTE:u64=1;

    public entry fun create_proposal(creator:&signer,realm:address,governance:address,name:String,description:String,treasury:address)acquires VoterWeights,GovernanceProposals,MaxVoterWeights{
        Governance::assert_is_valid_realm_for_governance(realm,governance);
        let governance_signer=Governance::get_governance_as_signer(governance);
        if(!exists<GovernanceProposals>(governance)){
            move_to(&governance_signer,GovernanceProposals{
                proposals:vector::empty()
            })
        };
        let creator_address=signer::address_of(creator);
        assert!(Members::is_member(realm,creator_address),ENOT_A_MEMBER);
        let (voting_proposal_count,min_weight_to_create_proposal)=Governance::get_governance(governance);
        assert!(voting_proposal_count < MAX_VOTING_PROPOSALS_PER_GOVERNANCE,ETOO_MANY_VOTING_PROPOSALS);
        let voter_weights=borrow_global<VoterWeights>(creator_address);
        let voter_weight_record=simple_map::borrow(&voter_weights.weights,&governance);
        if(min_weight_to_create_proposal!=option::none()){
            assert!(option::extract(&mut min_weight_to_create_proposal)<voter_weight_record.weight,ENOT_ENOUGH_WEIGHT_TO_CREATE_PROPOSAL);
        };
        let governance_proposals=borrow_global_mut<GovernanceProposals>(governance);
        let proposal_index=vector::length(&governance_proposals.proposals);
        vector::push_back(&mut governance_proposals.proposals,Proposal{
            name,
            description,
            state:0,
            deny_vote_weight:0,
            approve_vote_weight:0,
            veto_vote_weight:0,
            voting_at:timestamp::now_seconds(),
            index:proposal_index
        });
        if(!exists<MaxVoterWeights>(governance)){
            move_to(&governance_signer,MaxVoterWeights{
                max_voter_weights:simple_map::create()
            })
        };
        let max_voter_weights=borrow_global_mut<MaxVoterWeights>(governance).max_voter_weights;
        let (deposited_amount,coin_address)=Treasury::get_deposit_and_address(treasury,realm);
        simple_map::add(&mut max_voter_weights,proposal_index,MaxVoterWeightRecord{
            realm:realm,
            max_voter_weight_expiry:option::none(),
            max_voter_weight:deposited_amount,
            coin_address:coin_address
        });

    }

    public entry fun set_voter_weight(voter:&signer,governance:address,treasury_address:address,realm_address:address)acquires VoterWeights{
        let voter_address=signer::address_of(voter);
        if(!exists<VoterWeights>(voter_address)){
            move_to(voter,VoterWeights{
                weights:simple_map::create()
            })
        };
        let voter_weights=borrow_global_mut<VoterWeights>(voter_address);
        Governance::assert_is_valid_realm_for_governance(realm_address,governance);
        
         let updated_weight=Fundraise::get_member_deposit_amount(treasury_address,voter_address);
         if(!simple_map::contains_key(&voter_weights.weights,&governance)){
            simple_map::add(&mut voter_weights.weights,governance,VoterWeihtRecord{
                weight:updated_weight,
                realm:realm_address,
                user:voter_address
            });
         }else{
         let voter_weight_record=simple_map::borrow_mut(&mut voter_weights.weights,&governance);
             voter_weight_record.weight=updated_weight;
         };
    }

    public entry fun cast_vote(voter:&signer,realm_address:address,governance:address,proposal_id:u64,vote_type:u64) acquires VoterWeights,GovernanceProposals,MaxVoterWeights{
        let voter_address=signer::address_of(voter);
        let voter_weights=borrow_global<VoterWeights>(voter_address).weights;
        let voter_weight_record=simple_map::borrow(&voter_weights,&governance);
        let governance_proposals=borrow_global_mut<GovernanceProposals>(copy governance);
        let proposal=vector::borrow_mut(&mut governance_proposals.proposals,proposal_id);
        Governance::assert_is_valid_realm_for_governance(realm_address,governance);
        assert_is_valid_proposal_for_vote(*proposal);
        if(vote_type==YES_VOTE){
            proposal.approve_vote_weight=proposal.approve_vote_weight+voter_weight_record.weight;
        }else{
            proposal.deny_vote_weight=proposal.deny_vote_weight+voter_weight_record.weight;
        };
        let (approval_quorum,_max_voting_time)=Governance::get_governance_config(realm_address,governance);
        let max_voter_weights=borrow_global<MaxVoterWeights>(governance).max_voter_weights;
        let max_voter_weight_record=simple_map::borrow(&max_voter_weights,&proposal_id);
        if(proposal.approve_vote_weight/max_voter_weight_record.max_voter_weight > (approval_quorum as u64)){
            proposal.state=SUCCEDED;
        }else if(proposal.approve_vote_weight/max_voter_weight_record.max_voter_weight > (approval_quorum as u64)){
            proposal.state=DEFEATED;
        };
        

    }

    fun assert_is_valid_voter_weight(governance:address,member:address)acquires VoterWeights{
        let voter_weights=borrow_global<VoterWeights>(member);
        let voter_weight_record=simple_map::borrow(&voter_weights.weights,&governance);
        assert!(voter_weight_record.user==member,EINVALID_VOTER_WEIGHT_RECORD);
        //TODO:add voter_weight_expiry assertion
    }

    fun assert_is_valid_proposal_for_vote(proposal:Proposal){
        //TODO:add check for max_voting_time
        assert!(proposal.state==0,EINVALID_PROPOSAL_STATE);
    }


    #[test(creator=@0xcaffe,account_creator=@0x99,resource_account=@0x14,realm_account=@0x15,aptos_framework=@0x1)]
    public(friend) fun test_create_proposal(creator:&signer,account_creator:&signer,resource_account:&signer,realm_account:&signer,aptos_framework:&signer)acquires VoterWeights,GovernanceProposals,MaxVoterWeights{
        Realm::test_create_realm(creator,account_creator,resource_account,realm_account);
        let realm_address=Realm::get_realm_address_by_name(utf8(b"Genesis Realm"));
        timestamp::set_time_has_started_for_testing(aptos_framework);
        Members::add_founder_role(account_creator,realm_address);
        create_account_for_test(signer::address_of(account_creator));
        let treasury_address= Treasury::create_treasury<AptosCoin>(account_creator,realm_address,b"First treasury");
        let governance_address=Governance::create_governance_for_test(account_creator,realm_address);
        Fundraise::create_fundraise(account_creator,realm_address,treasury_address,2);
        Fundraise::airdrop_aptos_coin(account_creator,aptos_framework);
        Fundraise::deposit_to_treasury<AptosCoin>(account_creator,treasury_address,realm_address,2);
        set_voter_weight(account_creator,governance_address,treasury_address,realm_address);
        create_proposal(account_creator,realm_address,governance_address,utf8(b"Genesis proposal"),utf8(b"Genesis proposal desc"),treasury_address);
        let governance_proposals=borrow_global<GovernanceProposals>(governance_address);
        let proposal=vector::borrow(&governance_proposals.proposals,0);
        assert!(proposal.name==utf8(b"Genesis proposal"),0);
        assert!(proposal.approve_vote_weight==0,1);
        assert!(proposal.deny_vote_weight==0,1);
        assert!(proposal.state==0,3);
        let member_address=signer::address_of(account_creator);
        let voter_weights=borrow_global<VoterWeights>(member_address);
        let voter_weight=simple_map::borrow(&voter_weights.weights,&governance_address);
        assert!(voter_weight.weight==2,4);

    }

}