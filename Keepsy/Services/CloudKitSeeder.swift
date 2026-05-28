import Foundation
import CloudKit

class CloudKitSeeder {
    /// Seeds the CloudKit public database with the Capodimonte artworks and high-res images directly from the App Bundle.
    /// Works perfectly on physical devices (like iPhone 16) since resources are packaged directly inside the app bundle.
    static func seedDatabase() async {
        print("🚀 Starting CloudKit Seeding from App Bundle...")
        
        guard let csvURL = Bundle.main.url(forResource: "DB opere", withExtension: "csv"),
              let csvContent = try? String(contentsOf: csvURL, encoding: .utf8) else {
            print("❌ Error: Could not find or read 'DB opere.csv' in the App Bundle.")
            print("Please make sure you have dragged 'DB opere.csv' into Xcode and added it to the target.")
            return
        }
        
        // Explicitly target the verified active iCloud container configured in Xcode
        let publicDB = CKContainer(identifier: "iCloud.group.keepsy.app").publicCloudDatabase
        let rows = csvContent.components(separatedBy: "\n")
        
        print("Reading \(rows.count - 1) records from CSV...")
        
        // Skip header row
        for i in 1..<rows.count {
            let row = rows[i].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if row.isEmpty { continue }
            
            // Parse columns split by semicolon
            let columns = row.components(separatedBy: ";")
            guard columns.count >= 8 else {
                print("⚠️ Skipping malformed row: \(row)")
                continue
            }
            
            let artist = columns[1].trimmingCharacters(in: CharacterSet.whitespaces)
            let title = columns[2].trimmingCharacters(in: CharacterSet.whitespaces)
            let description = columns[6].trimmingCharacters(in: CharacterSet.whitespaces)
            let internalName = columns[7].trimmingCharacters(in: CharacterSet.whitespaces)
            
            // Use internalName as the unique CloudKit record ID
            let recordID = CKRecord.ID(recordName: internalName)
            let record = CKRecord(recordType: "Artwork", recordID: recordID)
            
            record["title"] = title as CKRecordValue
            record["artist"] = artist as CKRecordValue
            record["description"] = description as CKRecordValue
            record["internalName"] = internalName as CKRecordValue
            record["museumId"] = "capodimonte" as CKRecordValue
            record["imageUrl"] = "" as CKRecordValue
            
            // Load and attach image asset from Bundle.main
            if let imageURL = Bundle.main.url(forResource: internalName, withExtension: "jpg") {
                let asset = CKAsset(fileURL: imageURL)
                record["imageFile"] = asset
                print("📸 Attached image asset for: \(internalName)")
            } else {
                print("⚠️ Warning: Image '\(internalName).jpg' not found in App Bundle")
            }
            
            // Save to CloudKit
            do {
                try await publicDB.save(record)
                print("✅ Successfully seeded artwork: \(title)")
            } catch {
                // If it already exists, that is fine, print info
                print("ℹ️ Info: Skipping or updating \(title): \(error.localizedDescription)")
            }
        }
        
        print("🎉 CloudKit seeding finished!")
    }
}
