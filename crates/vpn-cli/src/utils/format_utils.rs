use chrono::{DateTime, Local, Utc};
use std::collections::HashMap;

pub fn format_timestamp(timestamp: DateTime<Utc>) -> String {
    timestamp
        .with_timezone(&Local)
        .format("%Y-%m-%d %H:%M:%S")
        .to_string()
}

pub fn format_timestamp_relative(timestamp: DateTime<Utc>) -> String {
    let now = Utc::now();
    let duration = now.signed_duration_since(timestamp);

    if duration.num_seconds() < 60 {
        "just now".to_string()
    } else if duration.num_minutes() < 60 {
        format!("{} minutes ago", duration.num_minutes())
    } else if duration.num_hours() < 24 {
        format!("{} hours ago", duration.num_hours())
    } else if duration.num_days() < 7 {
        format!("{} days ago", duration.num_days())
    } else if duration.num_weeks() < 4 {
        format!("{} weeks ago", duration.num_weeks())
    } else {
        format!("{} months ago", duration.num_days() / 30)
    }
}

pub fn format_uptime(seconds: u64) -> String {
    let days = seconds / 86400;
    let hours = (seconds % 86400) / 3600;
    let minutes = (seconds % 3600) / 60;
    let secs = seconds % 60;

    if days > 0 {
        format!("{}d {}h {}m", days, hours, minutes)
    } else if hours > 0 {
        format!("{}h {}m", hours, minutes)
    } else if minutes > 0 {
        format!("{}m {}s", minutes, secs)
    } else {
        format!("{}s", secs)
    }
}

pub fn format_speed(bytes_per_second: f64) -> String {
    const UNITS: &[&str] = &["B/s", "KB/s", "MB/s", "GB/s"];
    const THRESHOLD: f64 = 1024.0;

    let mut speed = bytes_per_second;
    let mut unit_index = 0;

    while speed >= THRESHOLD && unit_index < UNITS.len() - 1 {
        speed /= THRESHOLD;
        unit_index += 1;
    }

    format!("{:.1} {}", speed, UNITS[unit_index])
}

pub fn format_protocol_info(protocol: &str, version: Option<&str>) -> String {
    match version {
        Some(v) => format!("{} v{}", protocol.to_uppercase(), v),
        None => protocol.to_uppercase(),
    }
}

pub fn format_connection_string(host: &str, port: u16, protocol: &str) -> String {
    match protocol.to_lowercase().as_str() {
        "vless" | "vmess" | "trojan" => {
            format!("{}://{}", protocol.to_lowercase(), format_addr(host, port))
        }
        "shadowsocks" => format!("ss://{}", format_addr(host, port)),
        _ => format!("{}:{}", host, port),
    }
}

pub fn format_addr(host: &str, port: u16) -> String {
    if host.contains(':') {
        // IPv6 address
        format!("[{}]:{}", host, port)
    } else {
        format!("{}:{}", host, port)
    }
}

pub fn format_traffic_summary(sent: u64, received: u64) -> String {
    format!(
        "↑ {} ↓ {}",
        crate::utils::display::format_bytes(sent),
        crate::utils::display::format_bytes(received)
    )
}

pub fn format_user_activity_status(last_seen: Option<DateTime<Utc>>) -> String {
    match last_seen {
        Some(timestamp) => {
            let now = Utc::now();
            let duration = now.signed_duration_since(timestamp);

            if duration.num_minutes() < 5 {
                "🟢 Online".to_string()
            } else if duration.num_hours() < 1 {
                "🟡 Recently active".to_string()
            } else if duration.num_days() < 1 {
                "🟠 Active today".to_string()
            } else if duration.num_days() < 7 {
                "🔵 Active this week".to_string()
            } else {
                "⚪ Inactive".to_string()
            }
        }
        None => "❓ Never seen".to_string(),
    }
}

pub fn format_health_score(score: f64) -> String {
    let percentage = score * 100.0;
    let emoji = if percentage >= 90.0 {
        "🟢"
    } else if percentage >= 70.0 {
        "🟡"
    } else if percentage >= 50.0 {
        "🟠"
    } else {
        "🔴"
    };

    format!("{} {:.1}%", emoji, percentage)
}

pub fn format_server_status(is_running: bool, health_score: f64) -> String {
    if is_running {
        format!("🟢 Running ({})", format_health_score(health_score))
    } else {
        "🔴 Stopped".to_string()
    }
}

pub fn format_key_value_table(data: &HashMap<String, String>, max_key_width: usize) -> String {
    let mut output = String::new();

    for (key, value) in data {
        let key_padded = format!("{:<width$}", key, width = max_key_width);
        output.push_str(&format!("{}: {}\n", key_padded, value));
    }

    output
}

pub fn format_list_with_bullets(items: &[String], bullet: &str) -> String {
    items
        .iter()
        .map(|item| format!("{} {}", bullet, item))
        .collect::<Vec<_>>()
        .join("\n")
}

pub fn format_multiline_with_prefix(text: &str, prefix: &str) -> String {
    text.lines()
        .map(|line| format!("{}{}", prefix, line))
        .collect::<Vec<_>>()
        .join("\n")
}

pub fn truncate_string(s: &str, max_length: usize) -> String {
    if s.len() <= max_length {
        s.to_string()
    } else {
        format!("{}...", &s[..max_length.saturating_sub(3)])
    }
}

pub fn format_config_value(value: &serde_json::Value) -> String {
    match value {
        serde_json::Value::String(s) => s.clone(),
        serde_json::Value::Number(n) => n.to_string(),
        serde_json::Value::Bool(b) => b.to_string(),
        serde_json::Value::Array(arr) => {
            format!(
                "[{}]",
                arr.iter()
                    .map(|v| format_config_value(v))
                    .collect::<Vec<_>>()
                    .join(", ")
            )
        }
        serde_json::Value::Object(_) => "[Object]".to_string(),
        serde_json::Value::Null => "null".to_string(),
    }
}

pub fn format_file_size_human(size: u64) -> String {
    crate::utils::display::format_bytes(size)
}

pub fn format_error_context(
    error: &str,
    context: Option<&str>,
    suggestion: Option<&str>,
) -> String {
    let mut output = format!("Error: {}", error);

    if let Some(ctx) = context {
        output.push_str(&format!("\nContext: {}", ctx));
    }

    if let Some(sugg) = suggestion {
        output.push_str(&format!("\nSuggestion: {}", sugg));
    }

    output
}

pub fn format_success_with_next_steps(message: &str, next_steps: &[String]) -> String {
    let mut output = format!("✓ {}", message);

    if !next_steps.is_empty() {
        output.push_str("\n\nNext steps:");
        for (i, step) in next_steps.iter().enumerate() {
            output.push_str(&format!("\n  {}. {}", i + 1, step));
        }
    }

    output
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    #[test]
    fn test_format_uptime() {
        assert_eq!(format_uptime(30), "30s");
        assert_eq!(format_uptime(90), "1m 30s");
        assert_eq!(format_uptime(3665), "1h 1m");
        assert_eq!(format_uptime(90065), "1d 1h 1m");
    }

    #[test]
    fn test_format_speed() {
        assert_eq!(format_speed(512.0), "512.0 B/s");
        assert_eq!(format_speed(1024.0), "1.0 KB/s");
        assert_eq!(format_speed(1048576.0), "1.0 MB/s");
    }

    #[test]
    fn test_format_addr() {
        assert_eq!(format_addr("192.168.1.1", 80), "192.168.1.1:80");
        assert_eq!(format_addr("::1", 80), "[::1]:80");
        assert_eq!(format_addr("2001:db8::1", 443), "[2001:db8::1]:443");
    }

    #[test]
    fn test_format_protocol_info() {
        assert_eq!(format_protocol_info("vless", Some("1.8.0")), "VLESS v1.8.0");
        assert_eq!(format_protocol_info("shadowsocks", None), "SHADOWSOCKS");
    }

    #[test]
    fn test_format_health_score() {
        assert!(format_health_score(0.95).contains("🟢"));
        assert!(format_health_score(0.75).contains("🟡"));
        assert!(format_health_score(0.55).contains("🟠"));
        assert!(format_health_score(0.25).contains("🔴"));
    }

    #[test]
    fn test_truncate_string() {
        assert_eq!(truncate_string("short", 10), "short");
        assert_eq!(
            truncate_string("this is a very long string", 10),
            "this is..."
        );
        assert_eq!(truncate_string("exactly10c", 10), "exactly10c");
    }

    #[test]
    fn test_format_timestamp_relative() {
        let now = Utc::now();
        let five_minutes_ago = now - chrono::Duration::minutes(5);
        let one_hour_ago = now - chrono::Duration::hours(1);
        let one_day_ago = now - chrono::Duration::days(1);

        assert!(format_timestamp_relative(five_minutes_ago).contains("minutes ago"));
        assert!(format_timestamp_relative(one_hour_ago).contains("hour"));
        assert!(format_timestamp_relative(one_day_ago).contains("day"));
    }
}
