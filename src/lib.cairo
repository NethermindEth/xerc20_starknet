pub mod interfaces {
    pub mod ixerc20;
    pub mod ixerc20_factory;
    pub mod ixerc20_lockbox;
}

pub mod contracts {
    pub mod xerc20;
    pub mod xerc20_factory;
    pub mod xerc20_lockbox;
}

pub mod utils {
    // this might be unnecessary since we cannot have same addresses with EVM chains
    pub mod create3_proxy;
}
