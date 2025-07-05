pub mod batch;
pub mod config;
pub mod error;
pub mod links;
pub mod manager;
pub mod user;

#[cfg(test)]
pub mod proptest;

pub use batch::BatchOperations;
pub use error::{Result, UserError};
pub use links::ConnectionLinkGenerator;
pub use manager::UserManager;
pub use user::{User, UserConfig, UserStats, UserStatus};

// Re-export VpnProtocol for external use
pub use vpn_types::protocol::VpnProtocol;
