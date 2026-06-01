fn main() {
    let output = std::process::Command::new("git")
        .args(["describe", "--tags", "--always", "--dirty"])
        .output();

    let version = match output {
        Ok(out) if out.status.success() => {
            String::from_utf8_lossy(&out.stdout).trim().to_string()
        }
        _ => env!("CARGO_PKG_VERSION").to_string(),
    };

    println!("cargo:rustc-env=BUILD_GIT_VERSION={}", version);
    println!("cargo:rerun-if-changed=.git/HEAD");
    println!("cargo:rerun-if-changed=.git/refs/tags");
    println!("cargo:rerun-if-changed=.git/index");
}
