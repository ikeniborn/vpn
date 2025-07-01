//! LDAP authentication provider

use crate::{
    auth::AuthProvider,
    config::LdapConfig,
    error::{IdentityError, Result},
    models::{AuthProvider as AuthProviderType, User},
};
use async_trait::async_trait;
use chrono::Utc;
use ldap3::{Ldap, LdapConnAsync, LdapConnSettings, Scope, SearchEntry};
use std::collections::HashMap;
use uuid::Uuid;

#[derive(Clone)]
pub struct LdapProvider {
    config: LdapConfig,
}

impl LdapProvider {
    pub fn new(config: LdapConfig) -> Self {
        Self { config }
    }

    async fn connect(&self) -> Result<Ldap> {
        let settings = LdapConnSettings::new();
        let (conn, mut ldap) = LdapConnAsync::with_settings(
            settings,
            &self.config.url,
        ).await?;
        
        ldap3::drive!(conn);
        
        // Bind if credentials are provided
        if let (Some(bind_dn), Some(bind_password)) = 
            (&self.config.bind_dn, &self.config.bind_password) {
            ldap.simple_bind(bind_dn, bind_password).await?;
        }
        
        Ok(ldap)
    }

    async fn search_user(&self, username: &str) -> Result<Option<SearchEntry>> {
        let mut ldap = self.connect().await?;
        
        let filter = self.config.user_filter.replace("{username}", username);
        let (entries, _) = ldap.search(
            &self.config.base_dn,
            Scope::Subtree,
            &filter,
            &self.config.user_attributes,
        ).await?.success()?;
        
        let entry = entries.into_iter()
            .next()
            .and_then(|e| SearchEntry::construct(e));
        
        ldap.unbind().await?;
        
        Ok(entry)
    }

    fn extract_user_info(&self, entry: SearchEntry) -> Result<(String, String, HashMap<String, Vec<String>>)> {
        let attrs = entry.attrs;
        
        // Try common email attributes
        let email = attrs.get("mail")
            .or(attrs.get("email"))
            .or(attrs.get("userPrincipalName"))
            .and_then(|v| v.first())
            .ok_or_else(|| IdentityError::LdapError(
                ldap3::LdapError::LdapResult {
                    result: ldap3::LdapResult {
                        rc: 1,
                        matched: "".to_string(),
                        text: "Email attribute not found".to_string(),
                        refs: vec![],
                        ctrls: vec![],
                    }
                }
            ))?
            .clone();
        
        // Try common username attributes
        let username = attrs.get("uid")
            .or(attrs.get("sAMAccountName"))
            .or(attrs.get("cn"))
            .and_then(|v| v.first())
            .unwrap_or(&email)
            .clone();
        
        Ok((email, username, attrs))
    }

    async fn get_user_groups(&self, user_dn: &str) -> Result<Vec<String>> {
        if self.config.group_filter.is_none() {
            return Ok(Vec::new());
        }
        
        let mut ldap = self.connect().await?;
        
        let filter = self.config.group_filter.as_ref().unwrap()
            .replace("{dn}", user_dn)
            .replace("{username}", "");
        
        let (entries, _) = ldap.search(
            &self.config.base_dn,
            Scope::Subtree,
            &filter,
            vec!["cn"],
        ).await?.success()?;
        
        let groups = entries.into_iter()
            .filter_map(|e| SearchEntry::construct(e))
            .filter_map(|entry| entry.attrs.get("cn").and_then(|v| v.first()).cloned())
            .collect();
        
        ldap.unbind().await?;
        
        Ok(groups)
    }
}

#[async_trait]
impl AuthProvider for LdapProvider {
    async fn authenticate(&self, username: &str, password: &str) -> Result<User> {
        // Search for user
        let entry = self.search_user(username).await?
            .ok_or(IdentityError::InvalidCredentials)?;
        
        let user_dn = entry.dn.clone();
        let (email, ldap_username, attrs) = self.extract_user_info(entry)?;
        
        // Try to bind as the user to verify password
        let mut ldap = self.connect().await?;
        ldap.simple_bind(&user_dn, password).await
            .map_err(|_| IdentityError::InvalidCredentials)?;
        ldap.unbind().await?;
        
        // Get user groups
        let groups = self.get_user_groups(&user_dn).await?;
        
        // Map LDAP groups to roles (default to "user" if no groups)
        let roles = if groups.is_empty() {
            vec!["user".to_string()]
        } else {
            groups
        };
        
        // Extract display name
        let display_name = attrs.get("displayName")
            .or(attrs.get("cn"))
            .and_then(|v| v.first())
            .cloned();
        
        // Create user object
        let user = User {
            id: Uuid::new_v4(),
            email,
            username: ldap_username,
            display_name,
            provider: AuthProviderType::Ldap,
            provider_id: Some(user_dn),
            password_hash: None,
            roles,
            attributes: serde_json::to_value(&attrs)?,
            is_active: true,
            email_verified: true, // Assume LDAP users are verified
            created_at: Utc::now(),
            updated_at: Utc::now(),
            last_login: Some(Utc::now()),
        };
        
        Ok(user)
    }

    fn provider_type(&self) -> AuthProviderType {
        AuthProviderType::Ldap
    }

    async fn verify_configuration(&self) -> Result<()> {
        let ldap = self.connect().await?;
        ldap.unbind().await?;
        Ok(())
    }
}