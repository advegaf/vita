import XCTest
import UIKit
@testable import Vita

/// Pure checks on the vision request body + the reused tool-input parse.
final class LabVisionRequestTests: XCTestCase {

    func testLabErrorMessagesAreSpecific() {
        XCTAssertTrue(LabScanFlow.labErrorMessage(AnthropicClient.AnthropicError.transport).lowercased().contains("offline"))
        XCTAssertTrue(LabScanFlow.labErrorMessage(AnthropicClient.AnthropicError.noKey).contains("API key"))
        XCTAssertTrue(LabScanFlow.labErrorMessage(AnthropicClient.AnthropicError.http(413, "x")).contains("413"))
        XCTAssertTrue(LabScanFlow.labErrorMessage(AnthropicClient.AnthropicError.overloaded(529)).lowercased().contains("busy"))
    }

    func testPdfTextLayerDetection() {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let textPDF = UIGraphicsPDFRenderer(bounds: bounds).pdfData { ctx in
            ctx.beginPage()
            ("Glucose 104 mg/dL   HDL 41 mg/dL   TSH 2.1 mIU/L" as NSString).draw(
                at: CGPoint(x: 40, y: 40), withAttributes: [.font: UIFont.systemFont(ofSize: 16)])
        }
        XCTAssertTrue(LabImageEncoder.pdfHasTextLayer(textPDF))            // text PDF → read natively
        let blankPDF = UIGraphicsPDFRenderer(bounds: bounds).pdfData { ctx in ctx.beginPage() }
        XCTAssertFalse(LabImageEncoder.pdfHasTextLayer(blankPDF))         // scan/blank → rasterize
        XCTAssertFalse(LabImageEncoder.pdfHasTextLayer(Data([0x00, 0x01])))
    }

    func testLabsTokenCeilingRaised() {
        // A multi-page panel needs ~6k output tokens; 4096 truncated to 0 values.
        XCTAssertGreaterThanOrEqual(ClaudeService().labsMaxTokens, 8192)
    }

    func testLabsRunOnSonnet() {
        // Cost control: lab vision is the app's most expensive call and Sonnet
        // transcribes printed values as accurately as Opus at ~40% of the price.
        XCTAssertEqual(ClaudeService().labsModel, "claude-sonnet-4-6")
    }

    func testRasterizePDFProducesImages() {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let pdf = UIGraphicsPDFRenderer(bounds: bounds).pdfData { ctx in
            ctx.beginPage()
            ("Glucose 104 mg/dL" as NSString).draw(at: CGPoint(x: 40, y: 40),
                withAttributes: [.font: UIFont.systemFont(ofSize: 18)])
        }
        XCTAssertEqual(LabImageEncoder.pdfPageCount(pdf), 1)
        let imgs = LabImageEncoder.imagesFromPDF(pdf)
        XCTAssertEqual(imgs.count, 1)
        XCTAssertGreaterThan(imgs.first?.count ?? 0, 0)
        XCTAssertNil(LabImageEncoder.imagesFromPDF(Data([0x00, 0x01])).first)   // not a PDF → empty
    }

    /// Parse the OrderedJSON wire bytes back for content asserts.
    private func parsed(_ j: OrderedJSON) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: j.data()) as? [String: Any]) ?? [:]
    }

    func testMakeVisionBodyHasImageBlockAndForcedTool() {
        let img = AnthropicClient.imageBlock(base64: "QUJD", mediaType: "image/jpeg")
        let body = AnthropicClient.makeVisionBody(
            maxTokens: 2048,
            system: [.init(text: "sys", cache: false)],
            userBlocks: [.object([("type", .string("text")), ("text", .string("read"))]), img],
            tool: ClaudeSchemas.interpretLabsTool,
            toolName: ClaudeSchemas.labsToolName)
        let b = parsed(body)

        let messages = b["messages"] as! [[String: Any]]
        let content = messages[0]["content"] as! [[String: Any]]
        let imageBlock = content.first { ($0["type"] as? String) == "image" }
        XCTAssertNotNil(imageBlock)
        let source = imageBlock?["source"] as? [String: Any]
        XCTAssertEqual(source?["type"] as? String, "base64")
        XCTAssertEqual(source?["media_type"] as? String, "image/jpeg")
        XCTAssertEqual(source?["data"] as? String, "QUJD")

        let toolChoice = b["tool_choice"] as? [String: Any]
        XCTAssertEqual(toolChoice?["type"] as? String, "tool")
        XCTAssertEqual(toolChoice?["name"] as? String, "interpret_labs")
    }

    func testDocumentBlockForPDF() {
        let doc = parsed(AnthropicClient.documentBlock(base64: "JVBERg=="))
        XCTAssertEqual(doc["type"] as? String, "document")
        let source = doc["source"] as? [String: Any]
        XCTAssertEqual(source?["media_type"] as? String, "application/pdf")
    }

    func testVisionBodyOmitsSamplingAndThinking() {
        let body = parsed(AnthropicClient.makeVisionBody(
            maxTokens: 2048, system: [], userBlocks: [.object([("type", .string("text")), ("text", .string("x"))])],
            tool: ClaudeSchemas.interpretLabsTool, toolName: ClaudeSchemas.labsToolName))
        XCTAssertNil(body["temperature"])
        XCTAssertNil(body["top_p"])
        XCTAssertNil(body["top_k"])
        XCTAssertNil(body["thinking"])
        XCTAssertNil(body["stream"])
    }

    /// THE regression test for the degenerate-extraction bug: the tool schema's
    /// field order must reach the wire exactly as authored, every time. (Swift
    /// dictionaries serialize in per-launch hash order; a scrambled schema was
    /// observed live to collapse 69-marker extractions into 0-1 values with
    /// tool-markup leaking into string fields.)
    func testLabsToolWireBytesAreDeterministicAndOrdered() {
        let s1 = ClaudeSchemas.interpretLabsTool.serialized
        let s2 = ClaudeSchemas.interpretLabsTool.serialized
        XCTAssertEqual(s1, s2)                              // deterministic across builds

        func pos(_ needle: String) -> Int {
            XCTAssertNotNil(s1.range(of: needle), "missing \(needle)")
            return s1.range(of: needle).map { s1.distance(from: s1.startIndex, to: $0.lowerBound) } ?? -1
        }
        // Property-DEFINITION positions (`"key":{`) — plain `"name"` would match the
        // tool's own top-level name key first.
        // Top-level schema property order as authored.
        XCTAssertLessThan(pos("\"panel_date\":{"), pos("\"source_lab_name\":{"))
        XCTAssertLessThan(pos("\"source_lab_name\":{"), pos("\"values\":{"))
        XCTAssertLessThan(pos("\"values\":{"), pos("\"summary\":{"))
        // Value-item property order as authored.
        XCTAssertLessThan(pos("\"marker_key\":{"), pos("\"name\":{\"type\":\"string\",\"description\":\"Marker name"))
        XCTAssertLessThan(pos("\"name\":{\"type\":\"string\",\"description\":\"Marker name"), pos("\"value\":{"))
        XCTAssertLessThan(pos("\"value\":{"), pos("\"unit\":{"))
        XCTAssertLessThan(pos("\"unit\":{"), pos("\"ref_low\":{"))
        XCTAssertLessThan(pos("\"ref_low\":{"), pos("\"ref_high\":{"))
        XCTAssertLessThan(pos("\"ref_high\":{"), pos("\"ref_text\":{"))
        XCTAssertLessThan(pos("\"ref_text\":{"), pos("\"flag_raw\":{"))
    }

    func testOrderedJSONSerialization() {
        let j = OrderedJSON.object([
            ("b", .string("x\"y\n")),
            ("a", .int(2)),
            ("c", .array([.bool(true), .null, .double(0.5), .double(3)])),
        ])
        XCTAssertEqual(j.serialized, #"{"b":"x\"y\n","a":2,"c":[true,null,0.5,3]}"#)
        // Round-trips through a standard parser.
        let parsed = try? JSONSerialization.jsonObject(with: j.data()) as? [String: Any]
        XCTAssertEqual(parsed?["a"] as? Int, 2)
        XCTAssertEqual(parsed?["b"] as? String, "x\"y\n")
    }

    func testStripMarkupRemovesTagsKeepsComparisons() {
        XCTAssertEqual(LabPanelDTO.stripMarkup("ok <parameter name=\"x\">junk</parameter> done"),
                       "ok junk done")
        XCTAssertEqual(LabPanelDTO.stripMarkup("<150"), "<150")          // numeric comparison survives
        XCTAssertEqual(LabPanelDTO.stripMarkup("Low <2.28, High >7.13"), "Low <2.28, High >7.13")
        XCTAssertEqual(LabPanelDTO.stripMarkup("plain"), "plain")
    }

    func testParseExtractsInterpretLabsInput() throws {
        let response = """
        {"usage":{"cache_read_input_tokens":0},
         "content":[
           {"type":"tool_use","name":"interpret_labs","input":{"panel_date":"2026-05-20","source_lab_name":"Quest","summary":"s","disclaimer":"Educational, not medical advice.","values":[{"marker_key":"tsh","name":"TSH","value":2.1,"unit":"mIU/L","ref_low":0.4,"ref_high":4.0,"ref_text":null,"flag_raw":null}]}}
         ]}
        """.data(using: .utf8)!
        let result = try AnthropicClient.parse(data: response, toolName: "interpret_labs")
        let dto = try JSONDecoder().decode(LabPanelDTO.self, from: result.toolInput!)
        XCTAssertEqual(dto.sourceLabName, "Quest")
        XCTAssertEqual(dto.values.first?.markerKey, "tsh")
    }
}
