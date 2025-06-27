use colored::*;
use std::time::Duration;

pub fn success(message: &str) {
    println!("{} {}", "✓".green().bold(), message);
}

pub fn error(message: &str) {
    eprintln!("{} {}", "✗".red().bold(), message);
}

pub fn warning(message: &str) {
    println!("{} {}", "⚠".yellow().bold(), message);
}

pub fn info(message: &str) {
    println!("{} {}", "ℹ".blue().bold(), message);
}

pub fn debug(message: &str) {
    println!("{} {}", "🐛".purple(), message.dimmed());
}

pub fn header(title: &str) {
    println!();
    println!("{}", title.cyan().bold());
    println!("{}", "=".repeat(title.len()).cyan());
}

pub fn subheader(title: &str) {
    println!();
    println!("{}", title.yellow().bold());
    println!("{}", "-".repeat(title.len()).yellow());
}

pub fn format_bytes(bytes: u64) -> String {
    const UNITS: &[&str] = &["B", "KB", "MB", "GB", "TB"];
    const THRESHOLD: f64 = 1024.0;
    
    if bytes == 0 {
        return "0 B".to_string();
    }
    
    let mut size = bytes as f64;
    let mut unit_index = 0;
    
    while size >= THRESHOLD && unit_index < UNITS.len() - 1 {
        size /= THRESHOLD;
        unit_index += 1;
    }
    
    format!("{:.1} {}", size, UNITS[unit_index])
}

pub fn format_duration(duration: Duration) -> String {
    let total_seconds = duration.as_secs();
    
    if total_seconds < 60 {
        format!("{}s", total_seconds)
    } else if total_seconds < 3600 {
        let minutes = total_seconds / 60;
        let seconds = total_seconds % 60;
        format!("{}m {}s", minutes, seconds)
    } else if total_seconds < 86400 {
        let hours = total_seconds / 3600;
        let minutes = (total_seconds % 3600) / 60;
        format!("{}h {}m", hours, minutes)
    } else {
        let days = total_seconds / 86400;
        let hours = (total_seconds % 86400) / 3600;
        format!("{}d {}h", days, hours)
    }
}

pub fn format_percentage(value: f64, total: f64) -> String {
    if total == 0.0 {
        "0.0%".to_string()
    } else {
        format!("{:.1}%", (value / total) * 100.0)
    }
}

pub fn format_rate(value: f64, unit: &str) -> String {
    format!("{:.2} {}/s", value, unit)
}

pub fn progress_bar(current: u64, total: u64, width: usize) -> String {
    if total == 0 {
        return "█".repeat(width);
    }
    
    let progress = (current as f64 / total as f64).min(1.0);
    let filled = (progress * width as f64) as usize;
    let empty = width - filled;
    
    format!("{}{}",
        "█".repeat(filled).green(),
        "░".repeat(empty).dimmed()
    )
}

pub fn status_indicator(status: &str) -> ColoredString {
    match status.to_lowercase().as_str() {
        "running" | "active" | "healthy" | "online" | "enabled" => {
            "●".green()
        }
        "stopped" | "inactive" | "offline" | "disabled" => {
            "●".red()
        }
        "warning" | "degraded" | "partial" => {
            "●".yellow()
        }
        "unknown" | "pending" => {
            "●".blue()
        }
        _ => "●".white()
    }
}

pub fn table_separator(width: usize) -> String {
    "─".repeat(width).dimmed().to_string()
}

pub fn aligned_text(text: &str, width: usize, align: TextAlign) -> String {
    match align {
        TextAlign::Left => format!("{:<width$}", text, width = width),
        TextAlign::Right => format!("{:>width$}", text, width = width),
        TextAlign::Center => {
            let padding = width.saturating_sub(text.len());
            let left_pad = padding / 2;
            let right_pad = padding - left_pad;
            format!("{}{}{}", 
                " ".repeat(left_pad), 
                text, 
                " ".repeat(right_pad)
            )
        }
    }
}

pub enum TextAlign {
    Left,
    Right,
    Center,
}

pub fn confirm_prompt(message: &str, default: bool) -> String {
    let default_indicator = if default { "[Y/n]" } else { "[y/N]" };
    format!("{} {}: ", message, default_indicator.dimmed())
}

pub fn input_prompt(message: &str, default: Option<&str>) -> String {
    match default {
        Some(default_val) => {
            format!("{} [{}]: ", message, default_val.dimmed())
        }
        None => {
            format!("{}: ", message)
        }
    }
}

pub fn error_details(error_msg: &str, details: Option<&str>) {
    error(error_msg);
    if let Some(details) = details {
        println!("  {}", details.dimmed());
    }
}

pub fn success_with_details(message: &str, details: &[String]) {
    success(message);
    for detail in details {
        println!("  {}", detail.dimmed());
    }
}

pub fn warning_with_suggestion(warning_msg: &str, suggestion: &str) {
    warning(warning_msg);
    println!("  💡 {}: {}", "Suggestion".yellow(), suggestion.dimmed());
}

pub fn loading_spinner() -> &'static str {
    "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
}

pub fn format_json_pretty(value: &serde_json::Value) -> String {
    serde_json::to_string_pretty(value).unwrap_or_else(|_| "Invalid JSON".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_format_bytes() {
        assert_eq!(format_bytes(0), "0 B");
        assert_eq!(format_bytes(512), "512.0 B");
        assert_eq!(format_bytes(1024), "1.0 KB");
        assert_eq!(format_bytes(1536), "1.5 KB");
        assert_eq!(format_bytes(1048576), "1.0 MB");
        assert_eq!(format_bytes(1073741824), "1.0 GB");
    }

    #[test]
    fn test_format_duration() {
        assert_eq!(format_duration(Duration::from_secs(30)), "30s");
        assert_eq!(format_duration(Duration::from_secs(90)), "1m 30s");
        assert_eq!(format_duration(Duration::from_secs(3665)), "1h 1m");
        assert_eq!(format_duration(Duration::from_secs(90065)), "1d 1h");
    }

    #[test]
    fn test_format_percentage() {
        assert_eq!(format_percentage(50.0, 100.0), "50.0%");
        assert_eq!(format_percentage(33.0, 100.0), "33.0%");
        assert_eq!(format_percentage(0.0, 0.0), "0.0%");
    }

    #[test]
    fn test_progress_bar() {
        let bar = progress_bar(50, 100, 10);
        assert_eq!(bar.len(), 10); // Should always be the specified width
        
        let empty_bar = progress_bar(0, 100, 10);
        assert_eq!(empty_bar.len(), 10);
        
        let full_bar = progress_bar(100, 100, 10);
        assert_eq!(full_bar.len(), 10);
    }

    #[test]
    fn test_aligned_text() {
        assert_eq!(aligned_text("test", 10, TextAlign::Left), "test      ");
        assert_eq!(aligned_text("test", 10, TextAlign::Right), "      test");
        assert_eq!(aligned_text("test", 10, TextAlign::Center), "   test   ");
    }
}