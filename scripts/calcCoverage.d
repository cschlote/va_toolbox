#!/usr/bin/ldc2 --run
import std.algorithm;
import std.array;
import std.conv;
import std.file;
import std.format;
import std.getopt;
import std.range;
import std.json;
import std.path;
import std.stdio; // Für JSON-Ausgabe

struct CoverageResult {
    string fileName;
    size_t totalLines;
    size_t coveredLines;

    double coverage() const {
        if (totalLines == 0)
            return 0.0;
        return cast(double)(coveredLines) / totalLines * 100.0;
    }
}

import std.string; // Für die Verwendung von strip

CoverageResult analyzeCoverageFile(string fileName) {
    auto lines = readText(fileName).splitter("\n");
    size_t totalLines = 0;
    size_t coveredLines = 0;
    size_t percentage = 0;

    foreach (line; lines) {
        //writeln("Analysiere Zeile: ", line);

        // Suche nach der Coverage-Zeile
        if (line.startsWith("source") && line.canFind("is") && line.canFind("% covered")) {
            // Beispiel: source/va_toolbox/hashed_enum.d is 100% covered
            auto parts = line.split(" ");
            // writeln(parts);
            if (parts.length >= 4) {
                auto percentageStr = parts[2].stripRight("%"); // Entferne das "%" Zeichen
                percentage = (percentageStr).to!size_t; // Umwandlung in size_t

                // writeln("Coverage für Datei ", fileName, ": ", percentage, "% : ", totalLines); // Debugging
            }
        } else {
            // Zähle totalLines für alle anderen Zeilen
            auto parts = line.split("|");
            // writeln(parts);
            if (parts.length >=2) {
                if (parts[0].strip != "") {
                    // writeln("'",parts[0].strip, "'");
                    totalLines++;
                    if (parts[0].strip.to!size_t)
                        coveredLines++;
                }
            }
        }
    }

    return CoverageResult(fileName, totalLines, coveredLines);
}


void printCoverageResults(CoverageResult[] results, size_t totalLines, size_t totalCoveredLines) {
    writeln("\nCoverage pro Datei:");
    auto headline = format("%-40s %10s%% %13s","File","Coverage", "Covered/Total");
    auto separator = "-".repeat.take(headline.length).joiner.array;
    writeln(headline);
    writeln(separator);

    foreach (result; results) {
        writeln(format("%-40s %10.2f%% (%05d/%05d)",
                result.fileName.baseName, result.coverage(), result.coveredLines, result.totalLines));
    }

    writeln("\nGesamt-Coverage:\n", separator);
    if (totalLines == 0) {
        writeln("Keine zu analysierenden Zeilen gefunden.");
    } else {
        double overallCoverage = cast(double)(totalCoveredLines) / totalLines * 100.0;
        writeln(format("%-40s %10.1f%% covered", "Lines:", overallCoverage));
        writeln(format("%-40s %10s  (%05d/%05d)", "Lines (total):", "", totalCoveredLines, totalLines));
    }

    // writeln("Lines: %d%% covered", overa);
}

void writeCoverageToJson(string jsonFileName, CoverageResult[] results, size_t totalLines, size_t totalCoveredLines) {
    // Konvertiere die Coverage-Ergebnisse in ein JSON-kompatibles Format
    JSONValue[] fileCoverages = results.map!(r => JSONValue([
        "fileName": JSONValue(r.fileName), // fileName als JSONValue
        "totalLines": JSONValue(r.totalLines), // totalLines als JSONValue
        "coveredLines": JSONValue(r.coveredLines), // coveredLines als JSONValue
        "coverage": JSONValue(r.coverage()) // coverage als JSONValue
    ])).array;

    JSONValue json = JSONValue([
        "files": JSONValue(fileCoverages), // Array von JSON-Werten
        "totalCoverage": JSONValue(cast(double)(totalCoveredLines) / totalLines * 100.0), // Gesamt-Coverage als JSON-Wert
        "totalLines": JSONValue(totalLines), // Gesamtzeilen als JSON-Wert
        "totalCoveredLines": JSONValue(totalCoveredLines) // Abgedeckte Zeilen als JSON-Wert
    ]);

    // JSON in die Datei schreiben
    std.file.write(jsonFileName, json.toPrettyString);
    writeln("Daten erfolgreich als JSON in ", jsonFileName, " gespeichert.");
}

void main(string[] args) {
    string jsonFileName;

    // CLI-Optionen mit getopt
    getopt(args,
        "j|json", "Speichert die Coverage-Daten in eine JSON-Datei", &jsonFileName
    );

    // Finde alle *.lst Dateien im aktuellen Verzeichnis
    string[] lstFiles = dirEntries(".", "source*.lst", SpanMode.shallow)
        .map!(f => f.name)
        .array;

    size_t totalLines;
    size_t totalCoveredLines;
    CoverageResult[] results;

    foreach (fileName; lstFiles) {
        auto result = analyzeCoverageFile(fileName);
        results ~= result;

        totalLines += result.totalLines;
        totalCoveredLines += result.coveredLines;
    }

    // Ergebnisse in der Shell anzeigen
    printCoverageResults(results, totalLines, totalCoveredLines);

    // Optional: JSON-Datei schreiben
    if (jsonFileName.length > 0) {
        writeCoverageToJson(jsonFileName, results, totalLines, totalCoveredLines);
    }


}
