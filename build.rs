fn main() {
    let output = std::process::Command::new("git")
        .args(["describe", "--tags", "--always", "--dirty"])
        .output();

    let pkg_ver = format!("v{}", env!("CARGO_PKG_VERSION"));

    let version = match output {
        Ok(out) if out.status.success() => {
            let desc = String::from_utf8_lossy(&out.stdout).trim().to_string();
            // bare hash (shallow clone, no tags) → use package version
            if desc.starts_with(|c: char| c.is_ascii_hexdigit()) && desc.len() < 12 {
                pkg_ver
            } else {
                desc
            }
        }
        _ => pkg_ver,
    };

    println!("cargo:rustc-env=BUILD_GIT_VERSION={}", version);
    println!("cargo:rerun-if-changed=.git/HEAD");
    println!("cargo:rerun-if-changed=.git/refs/tags");
    println!("cargo:rerun-if-changed=.git/index");
}
