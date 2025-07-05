use crate::error::{MonitorError, Result};
use crate::health::HealthStatus;
use crate::metrics::PerformanceMetrics;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::time::Duration;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Alert {
    pub id: String,
    pub rule_id: String,
    pub severity: AlertSeverity,
    pub title: String,
    pub description: String,
    pub timestamp: DateTime<Utc>,
    pub status: AlertStatus,
    pub metadata: HashMap<String, String>,
    pub resolved_at: Option<DateTime<Utc>>,
    pub resolved_by: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AlertRule {
    pub id: String,
    pub name: String,
    pub description: String,
    pub condition: AlertCondition,
    pub severity: AlertSeverity,
    pub enabled: bool,
    pub cooldown_duration: Duration,
    pub notification_channels: Vec<NotificationChannel>,
    pub auto_resolve: bool,
    pub resolve_condition: Option<AlertCondition>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum AlertCondition {
    CpuUsage {
        threshold: f64,
        operator: ComparisonOperator,
    },
    MemoryUsage {
        threshold: f64,
        operator: ComparisonOperator,
    },
    DiskUsage {
        threshold: f64,
        operator: ComparisonOperator,
    },
    ResponseTime {
        threshold_ms: u64,
        operator: ComparisonOperator,
    },
    ErrorRate {
        threshold: f64,
        operator: ComparisonOperator,
    },
    ActiveConnections {
        threshold: u64,
        operator: ComparisonOperator,
    },
    PacketLoss {
        threshold: f64,
        operator: ComparisonOperator,
    },
    ContainerDown {
        container_name: String,
    },
    ServiceUnavailable,
    CustomMetric {
        metric_name: String,
        threshold: f64,
        operator: ComparisonOperator,
    },
    Composite {
        conditions: Vec<AlertCondition>,
        logic: LogicOperator,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum AlertSeverity {
    Low,
    Medium,
    High,
    Critical,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum AlertStatus {
    Active,
    Acknowledged,
    Resolved,
    Suppressed,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum ComparisonOperator {
    GreaterThan,
    LessThan,
    Equals,
    GreaterThanOrEqual,
    LessThanOrEqual,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum LogicOperator {
    And,
    Or,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum NotificationChannel {
    Email {
        address: String,
    },
    Webhook {
        url: String,
        secret: Option<String>,
    },
    Slack {
        webhook_url: String,
        channel: String,
    },
    Discord {
        webhook_url: String,
    },
    SMS {
        phone_number: String,
    },
    PagerDuty {
        integration_key: String,
    },
}

pub struct AlertManager {
    rules: HashMap<String, AlertRule>,
    active_alerts: HashMap<String, Alert>,
    alert_history: Vec<Alert>,
    last_rule_evaluation: HashMap<String, DateTime<Utc>>,
}

impl AlertManager {
    pub fn new() -> Self {
        Self {
            rules: HashMap::new(),
            active_alerts: HashMap::new(),
            alert_history: Vec::new(),
            last_rule_evaluation: HashMap::new(),
        }
    }

    pub fn add_rule(&mut self, rule: AlertRule) {
        self.rules.insert(rule.id.clone(), rule);
    }

    pub fn remove_rule(&mut self, rule_id: &str) -> Option<AlertRule> {
        self.rules.remove(rule_id)
    }

    pub fn update_rule(&mut self, rule: AlertRule) -> Result<()> {
        if !self.rules.contains_key(&rule.id) {
            return Err(MonitorError::AlertError(format!(
                "Rule {} not found",
                rule.id
            )));
        }

        self.rules.insert(rule.id.clone(), rule);
        Ok(())
    }

    pub async fn evaluate_rules(
        &mut self,
        metrics: &PerformanceMetrics,
        health_status: &HealthStatus,
    ) -> Result<Vec<Alert>> {
        let mut new_alerts = Vec::new();
        let current_time = Utc::now();

        let rules: Vec<_> = self.rules.values().cloned().collect();
        for rule in rules {
            if !rule.enabled {
                continue;
            }

            // Check cooldown
            if let Some(last_eval) = self.last_rule_evaluation.get(&rule.id) {
                if current_time
                    .signed_duration_since(*last_eval)
                    .to_std()
                    .unwrap()
                    < rule.cooldown_duration
                {
                    continue;
                }
            }

            // Evaluate condition
            let condition_met = self.evaluate_condition(&rule.condition, metrics, health_status)?;

            if condition_met {
                // Check if alert already exists
                let existing_alert = self
                    .active_alerts
                    .values()
                    .find(|alert| alert.rule_id == rule.id && alert.status == AlertStatus::Active);

                if existing_alert.is_none() {
                    let alert = self.create_alert(&rule, metrics, health_status).await?;
                    new_alerts.push(alert.clone());
                    self.active_alerts.insert(alert.id.clone(), alert);
                }
            } else if rule.auto_resolve {
                // Check for auto-resolution
                let resolve_condition_met = match &rule.resolve_condition {
                    Some(resolve_condition) => {
                        !self.evaluate_condition(resolve_condition, metrics, health_status)?
                    }
                    None => !condition_met,
                };

                if resolve_condition_met {
                    self.auto_resolve_alerts(&rule.id).await?;
                }
            }

            self.last_rule_evaluation
                .insert(rule.id.clone(), current_time);
        }

        Ok(new_alerts)
    }

    fn evaluate_condition(
        &self,
        condition: &AlertCondition,
        metrics: &PerformanceMetrics,
        health_status: &HealthStatus,
    ) -> Result<bool> {
        match condition {
            AlertCondition::CpuUsage {
                threshold,
                operator,
            } => Ok(self.compare_values(metrics.system_metrics.cpu_usage, *threshold, *operator)),
            AlertCondition::MemoryUsage {
                threshold,
                operator,
            } => {
                Ok(self.compare_values(metrics.system_metrics.memory_usage, *threshold, *operator))
            }
            AlertCondition::DiskUsage {
                threshold,
                operator,
            } => Ok(self.compare_values(metrics.system_metrics.disk_usage, *threshold, *operator)),
            AlertCondition::ResponseTime {
                threshold_ms,
                operator,
            } => {
                let response_time_ms = metrics.application_metrics.response_time.as_millis() as f64;
                Ok(self.compare_values(response_time_ms, *threshold_ms as f64, *operator))
            }
            AlertCondition::ErrorRate {
                threshold,
                operator,
            } => Ok(self.compare_values(
                metrics.application_metrics.error_rate,
                *threshold,
                *operator,
            )),
            AlertCondition::ActiveConnections {
                threshold,
                operator,
            } => {
                let connections = metrics.application_metrics.active_connections as f64;
                Ok(self.compare_values(connections, *threshold as f64, *operator))
            }
            AlertCondition::PacketLoss {
                threshold,
                operator,
            } => {
                Ok(self.compare_values(metrics.network_metrics.packet_loss, *threshold, *operator))
            }
            AlertCondition::ContainerDown { container_name } => {
                let container_running = health_status
                    .containers
                    .iter()
                    .find(|c| c.name == *container_name)
                    .map(|c| c.status == crate::health::ServiceStatus::Healthy)
                    .unwrap_or(false);
                Ok(!container_running)
            }
            AlertCondition::ServiceUnavailable => Ok(!health_status.is_healthy()),
            AlertCondition::CustomMetric {
                metric_name,
                threshold,
                operator,
            } => {
                let metric_value = metrics
                    .custom_metrics
                    .get(metric_name)
                    .copied()
                    .unwrap_or(0.0);
                Ok(self.compare_values(metric_value, *threshold, *operator))
            }
            AlertCondition::Composite { conditions, logic } => {
                let results: Result<Vec<bool>> = conditions
                    .iter()
                    .map(|cond| self.evaluate_condition(cond, metrics, health_status))
                    .collect();

                let results = results?;

                match logic {
                    LogicOperator::And => Ok(results.iter().all(|&r| r)),
                    LogicOperator::Or => Ok(results.iter().any(|&r| r)),
                }
            }
        }
    }

    fn compare_values(&self, value: f64, threshold: f64, operator: ComparisonOperator) -> bool {
        match operator {
            ComparisonOperator::GreaterThan => value > threshold,
            ComparisonOperator::LessThan => value < threshold,
            ComparisonOperator::Equals => (value - threshold).abs() < f64::EPSILON,
            ComparisonOperator::GreaterThanOrEqual => value >= threshold,
            ComparisonOperator::LessThanOrEqual => value <= threshold,
        }
    }

    async fn create_alert(
        &self,
        rule: &AlertRule,
        metrics: &PerformanceMetrics,
        health_status: &HealthStatus,
    ) -> Result<Alert> {
        let alert_id = format!("alert_{}", uuid::Uuid::new_v4());

        let (title, description) = self.generate_alert_content(rule, metrics, health_status)?;

        let mut metadata = HashMap::new();
        metadata.insert(
            "cpu_usage".to_string(),
            metrics.system_metrics.cpu_usage.to_string(),
        );
        metadata.insert(
            "memory_usage".to_string(),
            metrics.system_metrics.memory_usage.to_string(),
        );
        metadata.insert(
            "disk_usage".to_string(),
            metrics.system_metrics.disk_usage.to_string(),
        );
        metadata.insert(
            "error_rate".to_string(),
            metrics.application_metrics.error_rate.to_string(),
        );

        let alert = Alert {
            id: alert_id,
            rule_id: rule.id.clone(),
            severity: rule.severity,
            title,
            description,
            timestamp: Utc::now(),
            status: AlertStatus::Active,
            metadata,
            resolved_at: None,
            resolved_by: None,
        };

        // Send notifications
        self.send_notifications(&alert, rule).await?;

        Ok(alert)
    }

    fn generate_alert_content(
        &self,
        rule: &AlertRule,
        metrics: &PerformanceMetrics,
        _health_status: &HealthStatus,
    ) -> Result<(String, String)> {
        let title = match &rule.condition {
            AlertCondition::CpuUsage { threshold, .. } => {
                format!(
                    "High CPU Usage: {:.1}% (threshold: {:.1}%)",
                    metrics.system_metrics.cpu_usage, threshold
                )
            }
            AlertCondition::MemoryUsage { threshold, .. } => {
                format!(
                    "High Memory Usage: {:.1}% (threshold: {:.1}%)",
                    metrics.system_metrics.memory_usage, threshold
                )
            }
            AlertCondition::DiskUsage { threshold, .. } => {
                format!(
                    "High Disk Usage: {:.1}% (threshold: {:.1}%)",
                    metrics.system_metrics.disk_usage, threshold
                )
            }
            AlertCondition::ResponseTime { threshold_ms, .. } => {
                format!(
                    "High Response Time: {}ms (threshold: {}ms)",
                    metrics.application_metrics.response_time.as_millis(),
                    threshold_ms
                )
            }
            AlertCondition::ErrorRate { threshold, .. } => {
                format!(
                    "High Error Rate: {:.2}% (threshold: {:.2}%)",
                    metrics.application_metrics.error_rate, threshold
                )
            }
            AlertCondition::ContainerDown { container_name } => {
                format!("Container Down: {}", container_name)
            }
            AlertCondition::ServiceUnavailable => "Service Unavailable".to_string(),
            _ => rule.name.clone(),
        };

        let description = format!(
            "{}\n\nTriggered at: {}\nRule: {}",
            rule.description,
            Utc::now().format("%Y-%m-%d %H:%M:%S UTC"),
            rule.name
        );

        Ok((title, description))
    }

    async fn send_notifications(&self, alert: &Alert, rule: &AlertRule) -> Result<()> {
        for channel in &rule.notification_channels {
            match channel {
                NotificationChannel::Email { address } => {
                    self.send_email_notification(alert, address).await?;
                }
                NotificationChannel::Webhook { url, secret } => {
                    self.send_webhook_notification(alert, url, secret.as_deref())
                        .await?;
                }
                NotificationChannel::Slack {
                    webhook_url,
                    channel,
                } => {
                    self.send_slack_notification(alert, webhook_url, channel)
                        .await?;
                }
                NotificationChannel::Discord { webhook_url } => {
                    self.send_discord_notification(alert, webhook_url).await?;
                }
                NotificationChannel::SMS { phone_number } => {
                    self.send_sms_notification(alert, phone_number).await?;
                }
                NotificationChannel::PagerDuty { integration_key } => {
                    self.send_pagerduty_notification(alert, integration_key)
                        .await?;
                }
            }
        }

        Ok(())
    }

    async fn send_email_notification(&self, alert: &Alert, _address: &str) -> Result<()> {
        // Email notification implementation would go here
        println!(
            "Email notification: {} - {}",
            alert.title, alert.description
        );
        Ok(())
    }

    async fn send_webhook_notification(
        &self,
        alert: &Alert,
        url: &str,
        _secret: Option<&str>,
    ) -> Result<()> {
        let client = reqwest::Client::new();
        let payload = serde_json::json!({
            "alert_id": alert.id,
            "title": alert.title,
            "description": alert.description,
            "severity": alert.severity.as_str(),
            "timestamp": alert.timestamp,
            "metadata": alert.metadata
        });

        let response = client.post(url).json(&payload).send().await?;

        if !response.status().is_success() {
            return Err(MonitorError::AlertError(format!(
                "Webhook notification failed: {}",
                response.status()
            )));
        }

        Ok(())
    }

    async fn send_slack_notification(
        &self,
        alert: &Alert,
        webhook_url: &str,
        channel: &str,
    ) -> Result<()> {
        let client = reqwest::Client::new();
        let color = match alert.severity {
            AlertSeverity::Low => "#36a64f",
            AlertSeverity::Medium => "#ff9900",
            AlertSeverity::High => "#ff4500",
            AlertSeverity::Critical => "#ff0000",
        };

        let payload = serde_json::json!({
            "channel": channel,
            "attachments": [{
                "color": color,
                "title": alert.title,
                "text": alert.description,
                "fields": [
                    {
                        "title": "Severity",
                        "value": alert.severity.as_str(),
                        "short": true
                    },
                    {
                        "title": "Time",
                        "value": alert.timestamp.format("%Y-%m-%d %H:%M:%S UTC").to_string(),
                        "short": true
                    }
                ]
            }]
        });

        let response = client.post(webhook_url).json(&payload).send().await?;

        if !response.status().is_success() {
            return Err(MonitorError::AlertError(format!(
                "Slack notification failed: {}",
                response.status()
            )));
        }

        Ok(())
    }

    async fn send_discord_notification(&self, alert: &Alert, webhook_url: &str) -> Result<()> {
        let client = reqwest::Client::new();
        let color = match alert.severity {
            AlertSeverity::Low => 0x36a64f,
            AlertSeverity::Medium => 0xff9900,
            AlertSeverity::High => 0xff4500,
            AlertSeverity::Critical => 0xff0000,
        };

        let payload = serde_json::json!({
            "embeds": [{
                "title": alert.title,
                "description": alert.description,
                "color": color,
                "timestamp": alert.timestamp,
                "fields": [
                    {
                        "name": "Severity",
                        "value": alert.severity.as_str(),
                        "inline": true
                    },
                    {
                        "name": "Alert ID",
                        "value": alert.id,
                        "inline": true
                    }
                ]
            }]
        });

        let response = client.post(webhook_url).json(&payload).send().await?;

        if !response.status().is_success() {
            return Err(MonitorError::AlertError(format!(
                "Discord notification failed: {}",
                response.status()
            )));
        }

        Ok(())
    }

    async fn send_sms_notification(&self, alert: &Alert, _phone_number: &str) -> Result<()> {
        // SMS notification implementation would go here
        println!("SMS notification: {} - {}", alert.title, alert.description);
        Ok(())
    }

    async fn send_pagerduty_notification(
        &self,
        alert: &Alert,
        _integration_key: &str,
    ) -> Result<()> {
        // PagerDuty notification implementation would go here
        println!(
            "PagerDuty notification: {} - {}",
            alert.title, alert.description
        );
        Ok(())
    }

    pub async fn acknowledge_alert(&mut self, alert_id: &str, acknowledged_by: &str) -> Result<()> {
        if let Some(alert) = self.active_alerts.get_mut(alert_id) {
            alert.status = AlertStatus::Acknowledged;
            alert
                .metadata
                .insert("acknowledged_by".to_string(), acknowledged_by.to_string());
            alert
                .metadata
                .insert("acknowledged_at".to_string(), Utc::now().to_rfc3339());
        } else {
            return Err(MonitorError::AlertError(format!(
                "Alert {} not found",
                alert_id
            )));
        }

        Ok(())
    }

    pub async fn resolve_alert(&mut self, alert_id: &str, resolved_by: &str) -> Result<()> {
        if let Some(mut alert) = self.active_alerts.remove(alert_id) {
            alert.status = AlertStatus::Resolved;
            alert.resolved_at = Some(Utc::now());
            alert.resolved_by = Some(resolved_by.to_string());

            self.alert_history.push(alert);
        } else {
            return Err(MonitorError::AlertError(format!(
                "Alert {} not found",
                alert_id
            )));
        }

        Ok(())
    }

    async fn auto_resolve_alerts(&mut self, rule_id: &str) -> Result<()> {
        let alerts_to_resolve: Vec<String> = self
            .active_alerts
            .iter()
            .filter(|(_, alert)| alert.rule_id == rule_id && alert.status == AlertStatus::Active)
            .map(|(id, _)| id.clone())
            .collect();

        for alert_id in alerts_to_resolve {
            self.resolve_alert(&alert_id, "system").await?;
        }

        Ok(())
    }

    pub fn get_active_alerts(&self) -> Vec<&Alert> {
        self.active_alerts.values().collect()
    }

    pub fn get_alert_history(&self, limit: Option<usize>) -> Vec<&Alert> {
        let mut history: Vec<&Alert> = self.alert_history.iter().collect();
        history.sort_by(|a, b| b.timestamp.cmp(&a.timestamp));

        if let Some(limit) = limit {
            history.truncate(limit);
        }

        history
    }

    pub fn create_default_rules() -> Vec<AlertRule> {
        vec![
            AlertRule {
                id: "high_cpu".to_string(),
                name: "High CPU Usage".to_string(),
                description: "CPU usage is above 90%".to_string(),
                condition: AlertCondition::CpuUsage {
                    threshold: 90.0,
                    operator: ComparisonOperator::GreaterThan,
                },
                severity: AlertSeverity::High,
                enabled: true,
                cooldown_duration: Duration::from_secs(300),
                notification_channels: vec![],
                auto_resolve: true,
                resolve_condition: Some(AlertCondition::CpuUsage {
                    threshold: 80.0,
                    operator: ComparisonOperator::LessThan,
                }),
            },
            AlertRule {
                id: "high_memory".to_string(),
                name: "High Memory Usage".to_string(),
                description: "Memory usage is above 90%".to_string(),
                condition: AlertCondition::MemoryUsage {
                    threshold: 90.0,
                    operator: ComparisonOperator::GreaterThan,
                },
                severity: AlertSeverity::High,
                enabled: true,
                cooldown_duration: Duration::from_secs(300),
                notification_channels: vec![],
                auto_resolve: true,
                resolve_condition: Some(AlertCondition::MemoryUsage {
                    threshold: 80.0,
                    operator: ComparisonOperator::LessThan,
                }),
            },
            AlertRule {
                id: "container_down".to_string(),
                name: "Container Down".to_string(),
                description: "A critical container is not running".to_string(),
                condition: AlertCondition::ContainerDown {
                    container_name: "xray".to_string(),
                },
                severity: AlertSeverity::Critical,
                enabled: true,
                cooldown_duration: Duration::from_secs(60),
                notification_channels: vec![],
                auto_resolve: true,
                resolve_condition: None,
            },
        ]
    }
}

impl AlertSeverity {
    pub fn as_str(&self) -> &'static str {
        match self {
            AlertSeverity::Low => "low",
            AlertSeverity::Medium => "medium",
            AlertSeverity::High => "high",
            AlertSeverity::Critical => "critical",
        }
    }

    pub fn priority(&self) -> u8 {
        match self {
            AlertSeverity::Low => 1,
            AlertSeverity::Medium => 2,
            AlertSeverity::High => 3,
            AlertSeverity::Critical => 4,
        }
    }
}

impl Default for AlertManager {
    fn default() -> Self {
        Self::new()
    }
}
