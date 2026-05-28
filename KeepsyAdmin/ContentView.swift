//
//  ContentView.swift
//  KeepsyAdmin
//
//  Created by Alfonso Giuseppe Auriemma on 28/05/2026.
//

import SwiftUI
import CloudKit

struct LogLine: Identifiable {
    let id = UUID()
    let text: String
}

struct ContentView: View {
    @State private var isSeeding = false
    @State private var statusText = "Pronto per il caricamento."
    @State private var progressText = ""
    @State private var logLines: [LogLine] = []
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "icloud.and.arrow.up.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
                    .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                
                Text("Keepsy CloudKit Seeder")
                    .font(.title2)
                    .bold()
                
                Text("Pannello di amministrazione per il caricamento dinamico dei musei")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 10)
            
            Divider()
            
            // Console log view
            VStack(alignment: .leading, spacing: 5) {
                Text("LOG DI SISTEMA:")
                    .font(.caption2)
                    .bold()
                    .foregroundColor(.secondary)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if logLines.isEmpty {
                            Text("In attesa dell'avvio...")
                                .foregroundColor(.secondary)
                                .font(.system(.footnote, design: .monospaced))
                        } else {
                            ForEach(logLines) { line in
                                Text(line.text)
                                    .font(.system(.footnote, design: .monospaced))
                                    .foregroundColor(line.text.contains("❌") ? .red : (line.text.contains("✅") ? .green : .primary))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .frame(height: 180)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            }
            
            // Controls
            HStack {
                if isSeeding {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Caricamento in corso...")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    Text(statusText)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    Task {
                        await runSeeder()
                    }
                }) {
                    Text(isSeeding ? "Attendere..." : "Avvia Caricamento Capodimonte")
                        .bold()
                }
                .disabled(isSeeding)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.bottom, 10)
        }
        .padding(24)
        .frame(width: 480, height: 400)
    }
    
    private func addLog(_ message: String) {
        DispatchQueue.main.async {
            logLines.append(LogLine(text: message))
        }
    }
    
    private func runSeeder() async {
        isSeeding = true
        statusText = "Preparazione in corso..."
        logLines = []
        
        let csvPath = "/Users/alfi/Desktop/capodimonte_db/DB opere.csv"
        let imagesDirectory = "/Users/alfi/Desktop/capodimonte_db/extracted_images/Immagini quadri capodimonte/"
        
        addLog("🚀 Inizio lettura file da desktop...")
        
        guard let csvContent = try? String(contentsOfFile: csvPath, encoding: .utf8) else {
            addLog("❌ Errore: Impossibile leggere il file CSV al percorso: \(csvPath)")
            statusText = "Errore di caricamento."
            isSeeding = false
            return
        }
        
        let publicDB = CKContainer(identifier: "iCloud.group.keepsy.app").publicCloudDatabase
        let rows = csvContent.components(separatedBy: "\n")
        addLog("📊 CSV letto correttamente. Trovate \(rows.count - 1) righe.")
        
        // Skip header row
        for i in 1..<rows.count {
            let row = rows[i].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if row.isEmpty { continue }
            
            // Parse columns split by semicolon, respecting double-quotes
            let columns = parseCSVRow(row)
            guard columns.count >= 8 else {
                addLog("⚠️ Riga saltata (malformata): \(row.prefix(30))...")
                continue
            }
            
            let inventoryNumber = columns[0].trimmingCharacters(in: CharacterSet.whitespaces)
            let artist = columns[1].trimmingCharacters(in: CharacterSet.whitespaces)
            let title = columns[2].trimmingCharacters(in: CharacterSet.whitespaces)
            let date = columns[3].trimmingCharacters(in: CharacterSet.whitespaces)
            let technique = columns[4].trimmingCharacters(in: CharacterSet.whitespaces)
            let dimensions = columns[5].trimmingCharacters(in: CharacterSet.whitespaces)
            let description = columns[6].trimmingCharacters(in: CharacterSet.whitespaces)
            let internalName = columns[7].trimmingCharacters(in: CharacterSet.whitespaces)
            
            let recordID = CKRecord.ID(recordName: internalName)
            var record: CKRecord
            
            // Fetch first to get existing record with valid recordChangeTag for seamless update
            do {
                record = try await publicDB.record(for: recordID)
                addLog("ℹ️ Opera esistente trovata: \(title). Aggiornamento in corso...")
            } catch {
                let nsError = error as NSError
                if (error as? CKError)?.code == .unknownItem || nsError.code == 11 {
                    record = CKRecord(recordType: "Artwork", recordID: recordID)
                    addLog("🆕 Creazione nuova opera per: \(title)")
                } else {
                    addLog("❌ Errore nel recupero di \(title): \(error.localizedDescription) (Codice: \(nsError.code))")
                    continue
                }
            }
            
            record["inventoryNumber"] = inventoryNumber as CKRecordValue
            record["title"] = title as CKRecordValue
            record["artist"] = artist as CKRecordValue
            record["date"] = date as CKRecordValue
            record["technique"] = technique as CKRecordValue
            record["dimensions"] = dimensions as CKRecordValue
            record["description"] = description as CKRecordValue
            record["internalName"] = internalName as CKRecordValue
            record["museumId"] = "capodimonte" as CKRecordValue
            record["imageUrl"] = "" as CKRecordValue
            
            // Load and attach image asset from direct host filesystem
            let imagePath = "\(imagesDirectory)\(internalName).jpg"
            if FileManager.default.fileExists(atPath: imagePath) {
                let fileURL = URL(fileURLWithPath: imagePath)
                let asset = CKAsset(fileURL: fileURL)
                record["imageFile"] = asset
                addLog("📸 Allegata immagine per: \(title)")
            } else {
                addLog("⚠️ Immagine non trovata per: \(title)")
            }
            
            // Save/Upsert to CloudKit using the modern async save method
            do {
                try await publicDB.save(record)
                addLog("✅ Salvata opera: \(title)")
            } catch {
                let nsError = error as NSError
                addLog("❌ Errore \(title): \(nsError.localizedDescription) (Codice: \(nsError.code), Dominio: \(nsError.domain))")
                if let partialErrors = nsError.userInfo[CKPartialErrorsByItemIDKey] as? [CKRecord.ID: Error] {
                    for (failID, partialError) in partialErrors {
                        addLog("   - Dettaglio per \(failID.recordName): \(partialError.localizedDescription)")
                    }
                }
            }
        }
        
        addLog("🎉 Seeding completato con successo!")
        statusText = "Caricamento completato!"
        isSeeding = false
    }
    
    private func parseCSVRow(_ row: String) -> [String] {
        var columns: [String] = []
        var currentColumn = ""
        var insideQuotes = false
        
        let characters = Array(row)
        var i = 0
        while i < characters.count {
            let char = characters[i]
            if char == "\"" {
                insideQuotes.toggle()
            } else if char == ";" && !insideQuotes {
                columns.append(currentColumn.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
                currentColumn = ""
            } else {
                currentColumn.append(char)
            }
            i += 1
        }
        columns.append(currentColumn.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
        return columns
    }
}

#Preview {
    ContentView()
}
