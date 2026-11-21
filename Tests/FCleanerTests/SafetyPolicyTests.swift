import Testing
import Foundation
@testable import FCleaner

@Suite struct SafetyPolicyTests {
    @Test(arguments: [
        "/", "/System", "/System/Library/CoreServices", "/usr/bin", "/Applications", "/Library",
        "/Library/Application Support", "/private/var/db/receipts", "/var/db/receipts", "/etc/hosts",
    ])
    func forbiddenSystemPaths(_ path: String) {
        #expect(SafetyPolicy.isForbidden(URL(fileURLWithPath: path)))
    }

    @Test func forbiddenHomeRoots() {
        for path in ["", "Library", "Library/Caches", "Documents", "Desktop", "Downloads", ".Trash"] {
            #expect(SafetyPolicy.isForbidden(Paths.home(path)), "\(path)")
        }
    }

    @Test func volumeRootsAndOtherUsersAreForbidden() {
        #expect(SafetyPolicy.isForbidden(URL(fileURLWithPath: "/Volumes/External")))
        #expect(SafetyPolicy.isForbidden(URL(fileURLWithPath: "/Volumes/Mac/System/Library")))
        #expect(SafetyPolicy.isForbidden(URL(fileURLWithPath: "/Volumes/Mac/Users")))
        #expect(SafetyPolicy.isForbidden(URL(fileURLWithPath: "/Users/Shared")))
        #expect(SafetyPolicy.isForbidden(URL(fileURLWithPath: "/Users/__someone_else__/Documents/a.txt")))
        // Harici diskteki sıradan klasörler ve /Users/Shared içi serbest.
        #expect(!SafetyPolicy.isForbidden(URL(fileURLWithPath: "/Volumes/External/OldBackup")))
        #expect(!SafetyPolicy.isForbidden(URL(fileURLWithPath: "/Users/Shared/installer.dmg")))
    }

    @Test func cachesAreSafe() {
        let url = Paths.library("Caches/com.example.app")
        #expect(!SafetyPolicy.isForbidden(url))
        #expect(SafetyPolicy.level(for: url, base: .safe) == .safe)
    }

    @Test func criticalUserData() {
        let critical = [
            Paths.library("Keychains/login.keychain-db"),
            Paths.library("Mobile Documents/com~apple~CloudDocs"),
            Paths.library("Application Support/MobileSync/Backup/0000-ABC"),
            Paths.library("Containers/com.apple.Notes"),
            Paths.library("Group Containers/group.com.apple.notes"),
            Paths.library("Application Support/1Password"),
            Paths.library("Application Support/Google/Chrome/Default"),
            Paths.home(".ssh/id_ed25519"),
            Paths.home("Pictures/Photos Library.photoslibrary"),
            Paths.home("Documents/passwords.kdbx"),
        ]
        for url in critical {
            #expect(SafetyPolicy.level(for: url, base: .safe) == .critical, "\(url.path)")
        }
    }

    @Test func ancestorsOfCriticalDataAreCritical() {
        for path in ["Application Support/MobileSync", "Developer/Xcode", "Application Support/Google"] {
            #expect(SafetyPolicy.level(for: Paths.library(path), base: .safe) == .critical, "\(path)")
        }
        // Kardeş klasörler etkilenmez.
        #expect(SafetyPolicy.level(for: Paths.library("Developer/Xcode/DerivedData/App-abc"), base: .safe) == .safe)
    }

    @Test func notOverlyCritical() {
        // Uygulama paketi, önbellekler ve Mail ekleri kilitlenmemeli.
        #expect(SafetyPolicy.level(for: URL(fileURLWithPath: "/Applications/1Password.app"), base: .review) == .review)
        #expect(SafetyPolicy.level(for: Paths.library("Caches/com.1password.1password"), base: .safe) == .safe)
        #expect(SafetyPolicy.level(for: Paths.library("Containers/com.apple.mail/Data/Library/Mail Downloads/X"), base: .review) == .review)
        #expect(SafetyPolicy.level(for: Paths.library("Containers/com.example.app"), base: .safe) == .safe)
    }
}
