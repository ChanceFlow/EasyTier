const COMMANDS: &[&str] = &[
    "ping",
    "prepare_vpn",
    "start_vpn",
    "stop_vpn",
    "get_vpn_status",
    "update_notification",
    "set_ui_chrome",
    "notification_status",
    "open_notification_settings",
    "consume_vpn_tile_action",
    "registerListener",
];

fn main() {
    tauri_plugin::Builder::new(COMMANDS)
        .android_path("android")
        .ios_path("ios")
        .build();
}
