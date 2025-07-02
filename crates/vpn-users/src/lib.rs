pub mod user;
pub mod manager;
pub mod config;
pub mod links;
pub mod batch;
pub mod error;

#[cfg(test)]
pub mod proptest;

pub use user::{User, UserStatus, UserConfig};
pub use manager::UserManager;
pub use links::ConnectionLinkGenerator;
pub use batch::BatchOperations;
pub use error::{UserError, Result};

// Re-export VpnProtocol for external use
pub use vpn_types::protocol::VpnProtocol;