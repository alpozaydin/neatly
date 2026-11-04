nonisolated(unsafe) var failures = 0
func expect(_ ok: Bool, _ line: Int = #line) {
    if !ok { failures += 1; print("FAIL main.swift:\(line)") }
}
import Foundation
@testable import NamerCore

private func date(_ y: Int, _ m: Int, _ d: Int = 1) -> Date {
    Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
}

func terms() {
    expect(Style.term(date(2026, 11, 4)) == "fall26")
    expect(Style.term(date(2027, 1, 10)) == "fall26")
    expect(Style.term(date(2026, 3)) == "spring26")
    expect(Style.term(date(2026, 7)) == "summer26")
}

func slugWords() {
    expect(Style.words("Student Transcript") == ["transcript"])
    expect(Style.words("Öğrenci Belgesi — İstanbul") == ["ogrenci", "istanbul"])
}

func kinds() {
    expect(Style.kind(in: "Student Transcript")?.word == "transcript")
    expect(Style.kind(in: "e-Arşiv Fatura")?.word == "invoice")
    expect(Style.kind(in: "Monocular depth estimation") == nil)
}

func issuer() {
    expect(Style.issuer(host: "student.metu.edu.tr") == "metu")
    expect(Style.issuer(host: "www.turkiye.gov.tr") == "edevlet")
    expect(Style.issuer(host: "secure.turkcell.com.tr") == "turkcell")
}

func papers() {
    expect(Style.paperName(title: "UniDepth: Universal Monocular Metric Depth Estimation", year: 2024) == "unidepth-2024")
    expect(Style.paperName(title: "Attention Is All You Need", year: 2017) == "attention-is-all-2017")
}

func isJunk(_ s: String) -> Bool { Decision.junkReason(s) != nil }

func junkNames() {
    expect(isJunk("WhatsApp Image 2026-10-30 at 13.45.29"))
    expect(isJunk("IMG_4009"))
    expect(isJunk("Anfrage-26F04668426"))
    expect(isJunk("7f3a9c2be81d4f0a9b6c"))
    expect(!isJunk("CivCore deck - Oct 2026"))
    expect(!isJunk("imagenet-results"))
    expect(!isJunk("invoice-turkcell-nov26"))
    expect(isJunk("1234567_2026-11-04_124701"))
    expect(isJunk("1909.00871v3"))
    expect(isJunk("download (3)"))
    expect(!isJunk("transcript-fall26"))
    expect(!isJunk("27oct2026sila_hoca_meet"))
}

func transcriptRule() {
    var e = Evidence(url: URL(fileURLWithPath: "/tmp/1234567_2026-11-04_124701.pdf"))
    e.metadataTitle = "Student Transcript"
    e.sourceURLs = ["https://student.metu.edu.tr/proxy/Student_Information/main.php"]
    e.date = date(2026, 11, 4)
    expect(Namer().ruleName(e) == "transcript-fall26")
}

func styleLearning() {
    let work = StyleProfile.learn(names: ["CivCore AI Model - MAO", "Slush 2026 Side Events - MAO", "Market Map - MAO"])
    expect(work.separator == " " && !work.lowercase && work.suffix == "MAO")
    expect(work.render("invoice-turkcell-nov26") == "Invoice Turkcell Nov26 - MAO")
    let school = StyleProfile.learn(names: ["hw1-bomblab", "courses-fall26", "CENG315-W123", "lec1"])
    expect(school.separator == "-" && school.lowercase && school.suffix == nil)
    expect(StyleProfile.standard.render("ceng213-hw2") == "ceng213-hw2")
}

func period() {
    let c = Calendar.current
    expect(Style.period(in: "Fatura Dönemi: Ekim 2026").map { c.component(.month, from: $0) } == 10)
    expect(Style.period(in: "Tarih: 03.11.2026").map { c.component(.month, from: $0) } == 11)
    expect(Style.courseCode(in: "CENG 334 Operating Systems", academicSource: false) == "ceng334")
    expect(Style.courseCode(in: "Lufthansa LH1357", academicSource: false) == nil)
    expect(Style.academicItem(in: "Homework 2: Hash Tables") == "hw2")
}

for t in [styleLearning, period, terms, slugWords, kinds, issuer, papers, junkNames, transcriptRule] { t() }
print(failures == 0 ? "all checks passed" : "\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
