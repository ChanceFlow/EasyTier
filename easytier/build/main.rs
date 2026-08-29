use cfg_aliases::cfg_aliases;
use std::env;

struct WindowsBuild {}

impl WindowsBuild {
    // Add the bundled third_party dir (npcap Packet lib, WinDivert driver,
    // wintun) to the link search path. NOTE: must be gated on the TARGET
    // os, not the build-script host os: `#[cfg(target_os = "windows")]`
    // here evaluates against the Linux host when cross-compiling, which
    // silently dropped the link path and broke `-lPacket` resolution.
    // The path is anchored to CARGO_MANIFEST_DIR so it also works when
    // the build is invoked from a different working directory.
    pub fn check_for_win(target: &str) {
        let manifest_dir = env::var("CARGO_MANIFEST_DIR").unwrap_or_default();
        if target.contains("x86_64") {
            println!("cargo:rustc-link-search=native={manifest_dir}/third_party/x86_64/");
        } else if target.contains("i686") {
            println!("cargo:rustc-link-search=native={manifest_dir}/third_party/i686/");
        } else if target.contains("aarch64") {
            println!("cargo:rustc-link-search=native={manifest_dir}/third_party/arm64/");
        }
    }
}

fn workdir() -> Option<String> {
    if let Ok(cargo_manifest_dir) = std::env::var("CARGO_MANIFEST_DIR") {
        return Some(cargo_manifest_dir);
    }

    let dest = std::env::var("OUT_DIR");
    if dest.is_err() {
        return None;
    }
    let dest = dest.unwrap();

    let seperator = regex::Regex::new(r"(/target/(.+?)/build/)|(\\target\\(.+?)\\build\\)")
        .expect("Invalid regex");
    let parts = seperator.split(dest.as_str()).collect::<Vec<_>>();

    if parts.len() >= 2 {
        return Some(parts[0].to_string());
    }

    None
}

fn check_locale() {
    let workdir = workdir().unwrap_or("./".to_string());

    let locale_path = format!("{workdir}/**/locales/**/*");
    if let Ok(globs) = globwalk::glob(locale_path) {
        for entry in globs {
            if let Err(e) = entry {
                println!("cargo:i18n-error={e}");
                continue;
            }

            let entry = entry.unwrap().into_path();
            println!("cargo:rerun-if-changed={}", entry.display());
        }
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    cfg_aliases! {
        mobile: {
            any(
                target_os = "android",
                target_os = "ios",
                all(target_os = "macos", feature = "macos-ne"),
                target_env = "ohos"
            )
        }
    }

    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    let target_arch = env::var("CARGO_CFG_TARGET_ARCH").unwrap_or_default();
    // enable thunk-rs when target os is windows and arch is x86_64 or i686
    if target_os == "windows" && (target_arch == "x86" || target_arch == "x86_64") {
        thunk::thunk();
    }

    let target = env::var("TARGET").unwrap_or_default();
    if target_os == "windows" {
        WindowsBuild::check_for_win(&target);
    }

    check_locale();
    Ok(())
}
