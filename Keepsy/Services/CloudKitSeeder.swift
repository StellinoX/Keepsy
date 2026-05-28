import Foundation
import CloudKit

class CloudKitSeeder {
    /// Seeds the CloudKit public database with the Capodimonte artworks and high-res images directly from the local files.
    /// Runs seamlessly in the Simulator since it can read from the host filesystem.
    static func seedDatabase() async {
        print("🚀 Starting CloudKit Seeding...")
        
        let csvPath = "/Users/alfi/Desktop/capodimonte_db/DB opere.csv"
        let imagesDirectory = "/Users/alfi/Desktop/capodimonte_db/extracted_images/Immagini quadri capodimonte/"
        
        guard let csvContent = try? String(contentsOfFile: csvPath, encoding: .utf8) else {
            print("❌ Error: Could not read CSV file at \(csvPath)")
            return
        }
        
        let publicDB = CKContainer.default().publicCloudDatabase
        let rows = csvContent.components(separatedBy: "\n")
        
        print("Reading \(rows.count - 1) records from CSV...")
        
        // Skip header row
        for i in 1..<rows.count {
            let row = rows[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if row.isEmpty { continue }
            
            // Parse columns split by semicolon
            let columns = row.components(separatedBy: ";")
            guard columns.count >= 8 else {
                print("⚠️ Skipping malformed row: \(row)")
                continue
            }
            
            let artist = columns[1].trimmingCharacters(in: .whitespaces)
            let title = columns[2].trimmingCharacters(in: .whitespaces)
            let description = columns[6].trimmingCharacters(in: .whitespaces)
            let internalName = columns[7].trimmingCharacters(in: .whitespaces)
            
            // Use internalName as the unique CloudKit record ID
            let recordID = CKRecord.ID(recordName: internalName)
            let record = CKRecord(recordType: "Artwork", recordID: recordID)
            
            record["title"] = title as CKRecordValue
            record["artist"] = artist as CKRecordValue
            record["description"] = description as CKRecordValue
            record["internalName"] = internalName as CKRecordValue
            record["museumId"] = "capodimonte" as CKRecordValue
            record["imageUrl"] = "" as CKRecordValue
            
            // Load and attach image asset
            let imagePath = "\(imagesDirectory)\(internalName).jpg"
            if FileManager.default.fileExists(atPath: imagePath) {
                let fileURL = URL(fileURLWithPath: imagePath)
                let asset = CKAsset(fileURL: fileURL)
                record["imageFile"] = asset
                print("📸 Attached image asset for: \(internalName)")
            } else {
                print("⚠️ Warning: Image not found at \(imagePath)")
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
