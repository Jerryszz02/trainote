import Foundation
import XCTest

@testable import Trainote

/// AnalysisFixtures.report is deliberately not a production wire contract.
/// These runtime/generator tests need a current identity and opaque 64-hex fingerprint.
private func validRuntimeReportInput() -> ReportInput {
  .init(reportType: .today, asOf: AnalysisFixtures.asOf,
    inputFingerprint: String(repeating: "a", count: 64), facts: [], candidates: [],
    goalDirection: nil, knowledgeVersion: AIReportPolicy.knowledgeVersion,
    calculationVersions: ["trend-v1"], missingData: [])
}

final class LlamaReportRuntimeTests: XCTestCase {
  func testMissingModelFailsWithoutLoadingAnEngine() async throws {
    let runtime = BundledLlamaRuntime(modelURL: nil)
    do {
      _ = try await runtime.generate(prompt: "test", grammar: "root ::= \"{}\"", maximumTokens: 32)
      XCTFail("Missing model must fall back")
    } catch OnDeviceRuntimeError.modelUnavailable {} catch { XCTFail("Unexpected error: \(error)") }
  }

  func testHardLimitsRejectBeforeTouchingModelBytes() async throws {
    // A zero-byte file proves rejection happens before native model loading.
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data().write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let runtime = BundledLlamaRuntime(modelURL: url)
    for count in [0, -1, 257, Int.max] {
      do {
        _ = try await runtime.generate(prompt: "test", grammar: "root ::= \"{}\"", maximumTokens: count)
        XCTFail("Invalid output cap accepted: \(count)")
      } catch OnDeviceRuntimeError.inputTooLong {} catch { XCTFail("Unexpected error: \(error)") }
    }
    for (prompt, grammar) in [(String(repeating: "x", count: 24_001), "root ::= \"{}\""),
      ("test", String(repeating: "x", count: 24_001))] {
      do {
        _ = try await runtime.generate(prompt: prompt, grammar: grammar, maximumTokens: 32)
        XCTFail("Oversized input must be rejected before native loading")
      } catch OnDeviceRuntimeError.inputTooLong {} catch { XCTFail("Unexpected error: \(error)") }
    }
  }

  func testAlreadyCancelledTaskNeverStartsModelLoading() async throws {
    let runtime = BundledLlamaRuntime(modelURL: nil)
    let result = await Task { () -> Bool in
      withUnsafeCurrentTask { $0?.cancel() }
      do {
        _ = try await runtime.generate(prompt: "test", grammar: "root ::= \"{}\"", maximumTokens: 32)
        return false
      } catch is CancellationError { return true } catch { return false }
    }.value
    XCTAssertTrue(result)
  }
}

extension LlamaReportRuntimeTests {
  func testEvaluationGoldenMatchesProductionRequestProjectionAndGrammar() throws {
    var input = validRuntimeReportInput()
    input.reportType = .recovery
    input.goalDirection = nil
    input.missingData = []
    input.facts = [
      .init(id: "source-f00", metric: "recovery.quads.pain", value: 1, unit: .none, window: AnalysisFixtures.window, sources: [.manual]),
      .init(id: "source-f01", metric: "recovery.readiness", value: 21, unit: .score, window: AnalysisFixtures.window, sources: [.manual]),
      .init(id: "source-f02", metric: "recommendation.recentWorkingSets", value: 19, unit: .count, window: AnalysisFixtures.window, sources: [.manual]),
      .init(id: "source-f03", metric: "recovery.feeling", value: 2, unit: .none, window: AnalysisFixtures.window, sources: [.manual]),
    ]
    input.candidates = [.init(actionID: "source-a00", action: .rest, muscleIDs: [], reasonFactIDs: ["source-f00", "source-f01", "source-f02"])]
    let request = try OnDeviceReportRequest(input)
    // These frozen strings come from evaluate.py's evaluation-conflict-1, not product helpers.
    let expectedPrompt = String(decoding: try XCTUnwrap(Data(base64Encoded: "PHxpbV9zdGFydHw+c3lzdGVtClNlbGVjdCB1c2VmdWwgZmFjdHMgYW5kIGFwcHJvdmVkIGFjdGlvbnMgZm9yIGEgZml0bmVzcyByZXBvcnQuIFJldHVybiBvbmx5IEpTT04gd2l0aCBmYWN0SURzIGFuZCBhY3Rpb25JRHMsIGVhY2ggYXQgbW9zdCAzIHVuaXF1ZSBJRHMuIFByaW9yaXRpemUgcGFpbiwgbGltaXRhdGlvbnMsIHBvb3IgcmVjb3ZlcnkgYW5kIG1pc3NpbmcgZXZpZGVuY2UgYmVmb3JlIHJvdXRpbmUgcG9zaXRpdmUgZmFjdHMuIE1hdGNoIHRoZSByZXBvcnQgc2NvcGUuIFVua25vd24gaXMgbm90IHplcm87IHVuY2VydGFpbiBmYWN0cyByZW1haW4gdW5jZXJ0YWluLiBTZWxlY3Qgb25seSBJRHMgZnJvbSB0aGUgc3VwcGxpZWQgbGlzdHMuIEFjdGlvbnMgYXJlIGFscmVhZHkgYXBwcm92ZWQgYnkgY29kZTsgZG8gbm90IGNyZWF0ZSBhY3Rpb25zLCBudW1iZXJzIG9yIGFkdmljZS4gSWYgbm8gcmVsZXZhbnQgaXRlbSBleGlzdHMsIHJldHVybiBhbiBlbXB0eSBhcnJheS4gL25vX3RoaW5rCjx8aW1fZW5kfD4KPHxpbV9zdGFydHw+dXNlcgp7ImFjdGlvbnMiOlt7ImFjdGlvbiI6InJlc3QiLCJmYWN0cyI6WyJmMCIsImYxIiwiZjIiXSwiaWQiOiJhMCJ9XSwiZmFjdHMiOlt7ImlkIjoiZjAiLCJtZXRyaWMiOiJyZWNvdmVyeS5xdWFkcy5wYWluIiwicXVhbGl0eSI6W10sInVuaXQiOiJub25lIiwidmFsdWUiOjF9LHsiaWQiOiJmMSIsIm1ldHJpYyI6InJlY292ZXJ5LnJlYWRpbmVzcyIsInF1YWxpdHkiOltdLCJ1bml0Ijoic2NvcmUiLCJ2YWx1ZSI6MjF9LHsiaWQiOiJmMiIsIm1ldHJpYyI6InJlY29tbWVuZGF0aW9uLnJlY2VudFdvcmtpbmdTZXRzIiwicXVhbGl0eSI6W10sInVuaXQiOiJjb3VudCIsInZhbHVlIjoxOX0seyJpZCI6ImYzIiwibWV0cmljIjoicmVjb3ZlcnkuZmVlbGluZyIsInF1YWxpdHkiOltdLCJ1bml0Ijoibm9uZSIsInZhbHVlIjoyfV0sIm1pc3NpbmciOltdLCJzY29wZSI6InJlY292ZXJ5In0KPHxpbV9lbmR8Pgo8fGltX3N0YXJ0fD5hc3Npc3RhbnQKPHRoaW5rPgoKPC90aGluaz4=")), as: UTF8.self)
    let expectedGrammar = String(decoding: try XCTUnwrap(Data(base64Encoded: "cm9vdCA6Oj0gInsiIHdzICJcImZhY3RJRHNcIiIgd3MgIjoiIHdzIGZhY3RzIHdzICIsIiB3cyAiXCJhY3Rpb25JRHNcIiIgd3MgIjoiIHdzIGFjdGlvbnMgd3MgIn0iIHdzCndzIDo6PSBbIFx0XG5ccl0qCmZhY3RzLWlkIDo6PSAiXCJmMFwiIiB8ICJcImYxXCIiIHwgIlwiZjJcIiIgfCAiXCJmM1wiIgpmYWN0cyA6Oj0gIlsiIHdzIChmYWN0cy1pZCAod3MgIiwiIHdzIGZhY3RzLWlkICh3cyAiLCIgd3MgZmFjdHMtaWQpPyk/KT8gd3MgIl0iCmFjdGlvbnMtaWQgOjo9ICJcImEwXCIiCmFjdGlvbnMgOjo9ICJbIiB3cyAoYWN0aW9ucy1pZCAod3MgIiwiIHdzIGFjdGlvbnMtaWQgKHdzICIsIiB3cyBhY3Rpb25zLWlkKT8pPyk/IHdzICJdIg==")), as: UTF8.self)
    XCTAssertEqual(request.prompt.trimmingCharacters(in: .whitespacesAndNewlines), expectedPrompt)
    XCTAssertEqual(request.grammar.trimmingCharacters(in: .whitespacesAndNewlines), expectedGrammar)
  }
}

extension LlamaReportRuntimeTests {
  func testEvaluationTrendGoldenMatchesProductionScopeFilter() throws {
    var input = validRuntimeReportInput()
    input.reportType = .trend
    input.goalDirection = nil
    input.missingData = ["sleep", "restingHeartRate", "heartRateVariability"]
    input.facts = [
      .init(id: "source-f00", metric: "recovery.feeling", value: nil, unit: .none, window: AnalysisFixtures.window, sources: [.manual], quality: [.missing]),
      .init(id: "source-f01", metric: "diet.completeDays", value: 0, unit: .count, window: AnalysisFixtures.window, sources: [.manual]),
    ]
    input.candidates = []
    let request = try OnDeviceReportRequest(input)
    let expectedPrompt = String(decoding: try XCTUnwrap(Data(base64Encoded: "PHxpbV9zdGFydHw+c3lzdGVtClNlbGVjdCB1c2VmdWwgZmFjdHMgYW5kIGFwcHJvdmVkIGFjdGlvbnMgZm9yIGEgZml0bmVzcyByZXBvcnQuIFJldHVybiBvbmx5IEpTT04gd2l0aCBmYWN0SURzIGFuZCBhY3Rpb25JRHMsIGVhY2ggYXQgbW9zdCAzIHVuaXF1ZSBJRHMuIFByaW9yaXRpemUgcGFpbiwgbGltaXRhdGlvbnMsIHBvb3IgcmVjb3ZlcnkgYW5kIG1pc3NpbmcgZXZpZGVuY2UgYmVmb3JlIHJvdXRpbmUgcG9zaXRpdmUgZmFjdHMuIE1hdGNoIHRoZSByZXBvcnQgc2NvcGUuIFVua25vd24gaXMgbm90IHplcm87IHVuY2VydGFpbiBmYWN0cyByZW1haW4gdW5jZXJ0YWluLiBTZWxlY3Qgb25seSBJRHMgZnJvbSB0aGUgc3VwcGxpZWQgbGlzdHMuIEFjdGlvbnMgYXJlIGFscmVhZHkgYXBwcm92ZWQgYnkgY29kZTsgZG8gbm90IGNyZWF0ZSBhY3Rpb25zLCBudW1iZXJzIG9yIGFkdmljZS4gSWYgbm8gcmVsZXZhbnQgaXRlbSBleGlzdHMsIHJldHVybiBhbiBlbXB0eSBhcnJheS4gL25vX3RoaW5rCjx8aW1fZW5kfD4KPHxpbV9zdGFydHw+dXNlcgp7ImFjdGlvbnMiOltdLCJmYWN0cyI6W3siaWQiOiJmMCIsIm1ldHJpYyI6ImRpZXQuY29tcGxldGVEYXlzIiwicXVhbGl0eSI6W10sInVuaXQiOiJjb3VudCIsInZhbHVlIjowfV0sIm1pc3NpbmciOlsic2xlZXAiLCJyZXN0aW5nSGVhcnRSYXRlIiwiaGVhcnRSYXRlVmFyaWFiaWxpdHkiXSwic2NvcGUiOiJ0cmVuZCJ9Cjx8aW1fZW5kfD4KPHxpbV9zdGFydHw+YXNzaXN0YW50Cjx0aGluaz4KCjwvdGhpbms+")), as: UTF8.self)
    let expectedGrammar = String(decoding: try XCTUnwrap(Data(base64Encoded: "cm9vdCA6Oj0gInsiIHdzICJcImZhY3RJRHNcIiIgd3MgIjoiIHdzIGZhY3RzIHdzICIsIiB3cyAiXCJhY3Rpb25JRHNcIiIgd3MgIjoiIHdzIGFjdGlvbnMgd3MgIn0iIHdzCndzIDo6PSBbIFx0XG5ccl0qCmZhY3RzLWlkIDo6PSAiXCJmMFwiIgpmYWN0cyA6Oj0gIlsiIHdzIChmYWN0cy1pZCAod3MgIiwiIHdzIGZhY3RzLWlkICh3cyAiLCIgd3MgZmFjdHMtaWQpPyk/KT8gd3MgIl0iCmFjdGlvbnMgOjo9ICJbIiB3cyAiXSI=")), as: UTF8.self)
    XCTAssertEqual(request.prompt.trimmingCharacters(in: .whitespacesAndNewlines), expectedPrompt)
    XCTAssertEqual(request.grammar.trimmingCharacters(in: .whitespacesAndNewlines), expectedGrammar)
    XCTAssertEqual(request.facts.map(\.metric), ["diet.completeDays"])
  }

  func testEvaluationRetryProjectionPreservesAllRequiredEvidence() throws {
    var input = validRuntimeReportInput()
    input.reportType = .today
    input.goalDirection = nil
    input.missingData = []
    input.facts = (0..<20).map { index in
      MetricFact(id: String(format: "source-f%02d", index),
        metric: "recommendation.alternative.12345678-1234-1234-1234-\(String(format: "%012d", index)).quads",
        value: 33.333333333333336, unit: .score, window: AnalysisFixtures.window, sources: [.manual])
    }
    let reasons = input.facts.prefix(12).map(\.id)
    input.candidates = [.init(actionID: "source-a00", action: .swapTrainingDay, muscleIDs: [], reasonFactIDs: reasons)]
    let initial = try OnDeviceReportRequest(input)
    let retry = try OnDeviceReportRequest(input, maximumFacts: 12)
    XCTAssertEqual(initial.facts.count, 20)
    XCTAssertEqual(retry.facts.count, 12)
    XCTAssertEqual(Set(retry.facts.map(\.id)), Set(reasons))
    XCTAssertEqual(initial.candidates, retry.candidates)
    input.candidates[0].reasonFactIDs.append(input.facts[12].id)
    XCTAssertThrowsError(try OnDeviceReportRequest(input, maximumFacts: 12), "Required evidence cannot be truncated")
  }
}

private actor RetryProbeRuntime: OnDeviceModelRuntime {
  enum Behavior: Sendable { case overflowThenSuccess, alwaysOverflow, decodeFailure }
  struct Invocation: Sendable {
    let prompt: String
    let grammar: String
    let maximumTokens: Int
  }
  private let behavior: Behavior
  private var invocations: [Invocation] = []
  init(_ behavior: Behavior) { self.behavior = behavior }
  func recordedInvocations() -> [Invocation] { invocations }
  func generate(prompt: String, grammar: String, maximumTokens: Int) async throws -> String {
    invocations.append(.init(prompt: prompt, grammar: grammar, maximumTokens: maximumTokens))
    switch behavior {
    case .decodeFailure: throw OnDeviceRuntimeError.decodingFailed
    case .alwaysOverflow: throw OnDeviceRuntimeError.inputTooLong
    case .overflowThenSuccess:
      if invocations.count == 1 { throw OnDeviceRuntimeError.inputTooLong }
      return "{\"factIDs\":[\"f0\"],\"actionIDs\":[\"a0\"]}"
    }
  }
}

extension LlamaReportRuntimeTests {
  private func generatorRetryInput() -> ReportInput {
    var input = validRuntimeReportInput()
    input.reportType = .today
    input.goalDirection = nil
    input.missingData = []
    input.facts = (0..<20).map { index in
      MetricFact(id: String(format: "retry-f%02d", index),
        metric: "recommendation.alternative.12345678-1234-1234-1234-\(String(format: "%012d", index)).quads",
        value: 33, unit: .score, window: AnalysisFixtures.window, sources: [.manual])
    }
    input.candidates = [.init(actionID: "retry-a0", action: .swapTrainingDay, muscleIDs: [],
      reasonFactIDs: [input.facts[0].id])]
    return input
  }

  func testGeneratorRetriesOverflowExactlyOnceWithReducedPromptAndValidatesResult() async throws {
    let input = generatorRetryInput(), now = AnalysisFixtures.asOf
    let runtime = RetryProbeRuntime(.overflowThenSuccess)
    let report = try await OnDeviceReportGenerator(runtime: runtime, clock: { now }).generate(input)
    let calls = await runtime.recordedInvocations()
    XCTAssertEqual(calls.count, 2)
    guard calls.count == 2 else { return }
    XCTAssertEqual(calls[0].prompt, try OnDeviceReportRequest(input).prompt)
    XCTAssertEqual(calls[1].prompt, try OnDeviceReportRequest(input, maximumFacts: 12).prompt)
    XCTAssertLessThan(calls[1].prompt.utf8.count, calls[0].prompt.utf8.count)
    XCTAssertNotEqual(calls[0].grammar, calls[1].grammar)
    XCTAssertTrue(calls.allSatisfy { $0.maximumTokens == 256 })
    XCTAssertEqual(report.observations.first?.evidenceIDs, [input.facts[0].id])
    XCTAssertEqual(report.recommendations.first?.actionID, "retry-a0")
    XCTAssertFalse(report.isLocalFallback)
    XCTAssertNoThrow(try ReportResultValidator.validateOnDevice(report, input: input, now: now))
  }

  func testGeneratorRepeatedOverflowStopsAfterTwoCalls() async throws {
    let input = generatorRetryInput(), now = AnalysisFixtures.asOf
    let runtime = RetryProbeRuntime(.alwaysOverflow)
    do {
      _ = try await OnDeviceReportGenerator(runtime: runtime, clock: { now }).generate(input)
      XCTFail("A second overflow must propagate for rule fallback")
    } catch OnDeviceRuntimeError.inputTooLong {} catch { XCTFail("Unexpected error: \(error)") }
    let calls = await runtime.recordedInvocations()
    XCTAssertEqual(calls.count, 2)
    if calls.count == 2 { XCTAssertLessThan(calls[1].prompt.utf8.count, calls[0].prompt.utf8.count) }
  }

  func testGeneratorDoesNotRetryOtherRuntimeFailures() async throws {
    let input = generatorRetryInput(), now = AnalysisFixtures.asOf
    let runtime = RetryProbeRuntime(.decodeFailure)
    do {
      _ = try await OnDeviceReportGenerator(runtime: runtime, clock: { now }).generate(input)
      XCTFail("Decode failure must propagate without another inference")
    } catch OnDeviceRuntimeError.decodingFailed {} catch { XCTFail("Unexpected error: \(error)") }
    let calls = await runtime.recordedInvocations()
    XCTAssertEqual(calls.count, 1)
  }
}
