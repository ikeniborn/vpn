//! Common types and traits shared across VPN crates
//! 
//! This crate provides shared types, traits, and utilities to reduce
//! direct dependencies between service crates.

pub mod protocol;
pub mod user;
pub mod network;
pub mod container;
pub mod error;
pub mod validation;

pub use protocol::*;
pub use user::*;
pub use network::*;
pub use container::*;
pub use error::*;
pub use validation::*;