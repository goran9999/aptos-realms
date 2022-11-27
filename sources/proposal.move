module realm::Proposal{

    use std::string::{String};
    use std::simple_map::{SimpleMap};

    struct Proposal has store{
        name:String,
        description:String,
        governed_account:address,
        yes_vote_count:u64,
        no_vote_count:u64,
        state:u8,
        index:u64
    }

    struct RealmProposals has key{
        proposals:SimpleMap<address,SimpleMap<u64,Proposal>>
    }


    const VOTING:u8=0;
    const SUCCEDED:u8=1;
    const DEFEATED:u8=2;
    const EXECUTED:u8=3;



}