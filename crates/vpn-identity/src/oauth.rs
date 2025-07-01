//! OAuth2 and OpenID Connect providers

use crate::{
    config::OAuth2ProviderConfig,
    error::{IdentityError, Result},
};
use oauth2::{
    basic::BasicClient, reqwest::async_http_client, AuthUrl, AuthorizationCode,
    ClientId, ClientSecret, CsrfToken, PkceCodeChallenge, PkceCodeVerifier,
    RedirectUrl, RevocationUrl, Scope, TokenUrl,
};
use openidconnect::{
    core::{CoreClient, CoreProviderMetadata},
    reqwest::async_http_client as oidc_http_client,
    ClientId as OidcClientId, ClientSecret as OidcClientSecret,
    IssuerUrl, RedirectUrl as OidcRedirectUrl,
};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Clone)]
pub struct OAuth2Provider {
    pub name: String,
    pub config: OAuth2ProviderConfig,
    client: BasicClient,
    pkce_verifier: Option<PkceCodeVerifier>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OAuthConfig {
    pub providers: HashMap<String, OAuth2ProviderConfig>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthorizationRequest {
    pub auth_url: String,
    pub state: String,
    pub code_verifier: Option<String>,
}

impl OAuth2Provider {
    pub fn new(name: String, config: OAuth2ProviderConfig) -> Result<Self> {
        let client_id = ClientId::new(config.client_id.clone());
        let client_secret = ClientSecret::new(config.client_secret.clone());
        let auth_url = AuthUrl::new(config.auth_url.clone())
            .map_err(|e| IdentityError::ConfigError(format!("Invalid auth URL: {}", e)))?;
        let token_url = TokenUrl::new(config.token_url.clone())
            .map_err(|e| IdentityError::ConfigError(format!("Invalid token URL: {}", e)))?;
        let redirect_url = RedirectUrl::new(config.redirect_url.clone())
            .map_err(|e| IdentityError::ConfigError(format!("Invalid redirect URL: {}", e)))?;

        let client = BasicClient::new(client_id, Some(client_secret), auth_url, Some(token_url))
            .set_redirect_uri(redirect_url);

        Ok(Self {
            name,
            config,
            client,
            pkce_verifier: None,
        })
    }

    pub fn create_authorization_request(&mut self) -> AuthorizationRequest {
        let (pkce_challenge, pkce_verifier) = PkceCodeChallenge::new_random_sha256();
        self.pkce_verifier = Some(pkce_verifier.clone());

        let mut auth_request = self.client
            .authorize_url(CsrfToken::new_random)
            .set_pkce_challenge(pkce_challenge);

        // Add scopes
        for scope in &self.config.scopes {
            auth_request = auth_request.add_scope(Scope::new(scope.clone()));
        }

        let (auth_url, csrf_token) = auth_request.url();

        AuthorizationRequest {
            auth_url: auth_url.to_string(),
            state: csrf_token.secret().clone(),
            code_verifier: Some(pkce_verifier.secret().clone()),
        }
    }

    pub async fn exchange_code(
        &self,
        code: String,
        code_verifier: Option<String>,
    ) -> Result<serde_json::Value> {
        let code = AuthorizationCode::new(code);
        
        let mut token_request = self.client.exchange_code(code);
        
        if let Some(verifier) = code_verifier {
            let pkce_verifier = PkceCodeVerifier::new(verifier);
            token_request = token_request.set_pkce_verifier(pkce_verifier);
        }
        
        let token_response = token_request
            .request_async(async_http_client)
            .await
            .map_err(|e| IdentityError::OAuth2Error(format!("Token exchange failed: {}", e)))?;

        // Get user info if URL is provided
        if let Some(userinfo_url) = &self.config.userinfo_url {
            let access_token = token_response.access_token().secret();
            let user_info = self.fetch_user_info(userinfo_url, access_token).await?;
            Ok(user_info)
        } else {
            // Return token info if no userinfo endpoint
            Ok(serde_json::json!({
                "access_token": token_response.access_token().secret(),
                "token_type": token_response.token_type().as_ref(),
                "expires_in": token_response.expires_in().map(|d| d.as_secs()),
                "refresh_token": token_response.refresh_token().map(|t| t.secret()),
            }))
        }
    }

    async fn fetch_user_info(&self, url: &str, access_token: &str) -> Result<serde_json::Value> {
        let client = reqwest::Client::new();
        let response = client
            .get(url)
            .bearer_auth(access_token)
            .send()
            .await
            .map_err(|e| IdentityError::OAuth2Error(format!("Failed to fetch user info: {}", e)))?;

        if !response.status().is_success() {
            return Err(IdentityError::OAuth2Error(format!(
                "User info request failed: {}",
                response.status()
            )));
        }

        let user_info = response
            .json()
            .await
            .map_err(|e| IdentityError::OAuth2Error(format!("Failed to parse user info: {}", e)))?;

        Ok(user_info)
    }
}

pub struct OidcProvider {
    pub name: String,
    pub client: CoreClient,
    pub config: OAuth2ProviderConfig,
}

impl OidcProvider {
    pub async fn discover(name: String, config: OAuth2ProviderConfig) -> Result<Self> {
        let issuer_url = IssuerUrl::new(config.auth_url.clone())
            .map_err(|e| IdentityError::ConfigError(format!("Invalid issuer URL: {}", e)))?;

        let provider_metadata = CoreProviderMetadata::discover_async(issuer_url, oidc_http_client)
            .await
            .map_err(|e| IdentityError::OAuth2Error(format!("OIDC discovery failed: {}", e)))?;

        let client_id = OidcClientId::new(config.client_id.clone());
        let client_secret = OidcClientSecret::new(config.client_secret.clone());
        let redirect_url = OidcRedirectUrl::new(config.redirect_url.clone())
            .map_err(|e| IdentityError::ConfigError(format!("Invalid redirect URL: {}", e)))?;

        let client = CoreClient::from_provider_metadata(
            provider_metadata,
            client_id,
            Some(client_secret),
        )
        .set_redirect_uri(redirect_url);

        Ok(Self {
            name,
            client,
            config,
        })
    }
}