//! Small repository check entrypoint; never launches the application.
use std::{
    env,
    process::{Command, ExitCode},
};

fn main() -> ExitCode {
    if env::args().nth(1).as_deref() != Some("check") {
        eprintln!("Usage: cargo xtask check");
        return ExitCode::FAILURE;
    }
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).parent();
    let Some(root) = root else {
        return ExitCode::FAILURE;
    };
    for args in [
        vec!["fmt", "--all", "--", "--check"],
        vec![
            "test",
            "--locked",
            "-p",
            "typad-core",
            "-p",
            "typad-service",
        ],
        vec!["check", "--locked", "-p", "typad-ffi"],
    ] {
        match Command::new(env::var_os("CARGO").unwrap_or_else(|| "cargo".into()))
            .args(args)
            .current_dir(root)
            .status()
        {
            Ok(status) if status.success() => {}
            result => {
                eprintln!("Check failed: {result:?}");
                return ExitCode::FAILURE;
            }
        }
    }
    ExitCode::SUCCESS
}
