//! Cluster membership management

use crate::error::Result;
use crate::node::{Node, NodeId};
use std::collections::HashMap;

/// Manages cluster membership (placeholder)
pub struct MembershipManager {
    node_id: NodeId,
    members: HashMap<NodeId, Node>,
}

impl MembershipManager {
    pub fn new(node_id: NodeId) -> Self {
        Self {
            node_id,
            members: HashMap::new(),
        }
    }

    pub async fn join(&mut self, node: Node) -> Result<()> {
        tracing::info!("Node {} joining cluster", node.id);
        self.members.insert(node.id.clone(), node);
        Ok(())
    }

    pub async fn leave(&mut self, node_id: &NodeId) -> Result<()> {
        tracing::info!("Node {} leaving cluster", node_id);
        self.members.remove(node_id);
        Ok(())
    }

    pub fn get_members(&self) -> Vec<&Node> {
        self.members.values().collect()
    }
}