import CatalogSweep
import Foundation
import Testing

/// The sweep's hand-picked scenarios, run on the Swift rules alone. Each expected message is the
/// text the Python build printed for the same change when the sweep compared them.
struct ScenarioTests {
  @Test(arguments: Scenarios.all.map(\.name))
  func eachScenarioMakesItsRulesSpeak(name: String) throws {
    let scenario = try #require(Scenarios.all.first { $0.name == name })
    let problems = try Sweep(repository: SweepTests.repository).swiftProblems(for: scenario)

    for fragment in scenario.expecting {
      #expect(problems.contains { $0.contains(fragment) }, "\(fragment)")
    }
  }

  @Test func everyScenarioHasAUniqueName() {
    #expect(Set(Scenarios.all.map(\.name)).count == Scenarios.all.count)
  }
}
