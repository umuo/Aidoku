#!/usr/bin/env python3
"""在 macOS 上独立测试验证模块，不解析整个 App 的第三方依赖。"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="aidoku-verification-") as directory:
        package = Path(directory)
        source = package / "Sources" / "Aidoku"
        tests = package / "Tests" / "AidokuTests"
        source.mkdir(parents=True)
        tests.mkdir(parents=True)
        for name in ["WebsiteVerificationPolicy", "VerificationCookieHeader", "VerificationCookieBridge",
                     "WebsiteVerificationError", "VerificationEligibility", "VerificationSessionQueue", "VerificationRequestRecovery"]:
            shutil.copy2(root / "Aidoku/Core/Sources/Verification" / f"{name}.swift", source)
        for name in ["WebsiteVerificationTests", "VerificationCookieBridgeTests", "VerificationSessionQueueTests", "VerificationRequestRecoveryTests"]:
            shutil.copy2(root / "AidokuTests" / f"{name}.swift", tests)
        (package / "Package.swift").write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "VerificationTests", platforms: [.macOS(.v13)], targets: [
    .target(name: "Aidoku"),
    .testTarget(name: "AidokuTests", dependencies: ["Aidoku"])
])
''')
        environment = dict(os.environ)
        environment["CLANG_MODULE_CACHE_PATH"] = str(package / "clang-cache")
        environment["SWIFTPM_MODULECACHE_OVERRIDE"] = str(package / "swift-cache")
        subprocess.run(["swift", "test", "--package-path", str(package)], env=environment, check=True)


if __name__ == "__main__":
    main()
