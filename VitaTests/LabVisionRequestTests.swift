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

    func testMakeVisionBodyHasImageBlockAndForcedTool() {
        let img = AnthropicClient.imageBlock(base64: "QUJD", mediaType: "image/jpeg")
        let body = AnthropicClient.makeVisionBody(
            maxTokens: 2048,
            system: [.init(text: "sys", cache: true)],
            userBlocks: [["type": "text", "text": "read"], img],
            tools: [ClaudeSchemas.interpretLabsTool],
            toolName: ClaudeSchemas.labsToolName)

        let messages = body["messages"] as! [[String: Any]]
        let content = messages[0]["content"] as! [[String: Any]]
        let imageBlock = content.first { ($0["type"] as? String) == "image" }
        XCTAssertNotNil(imageBlock)
        let source = imageBlock?["source"] as? [String: Any]
        XCTAssertEqual(source?["type"] as? String, "base64")
        XCTAssertEqual(source?["media_type"] as? String, "image/jpeg")
        XCTAssertEqual(source?["data"] as? String, "QUJD")

        let toolChoice = body["tool_choice"] as? [String: Any]
        XCTAssertEqual(toolChoice?["type"] as? String, "tool")
        XCTAssertEqual(toolChoice?["name"] as? String, "interpret_labs")
    }

    func testDocumentBlockForPDF() {
        let doc = AnthropicClient.documentBlock(base64: "JVBERg==")
        XCTAssertEqual(doc["type"] as? String, "document")
        let source = doc["source"] as? [String: Any]
        XCTAssertEqual(source?["media_type"] as? String, "application/pdf")
    }

    func testVisionBodyOmitsSamplingAndThinking() {
        let body = AnthropicClient.makeVisionBody(
            maxTokens: 2048, system: [], userBlocks: [["type": "text", "text": "x"]],
            tools: [ClaudeSchemas.interpretLabsTool], toolName: ClaudeSchemas.labsToolName)
        XCTAssertNil(body["temperature"])
        XCTAssertNil(body["top_p"])
        XCTAssertNil(body["top_k"])
        XCTAssertNil(body["thinking"])
        XCTAssertNil(body["stream"])
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
