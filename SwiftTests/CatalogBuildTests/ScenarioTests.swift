import CatalogTestSupport
import Foundation
import Testing

/// Hand-picked changes to the real data, each of which makes one rule speak. Each expected message is the
/// text the rule prints for the change.
struct ScenarioTests {
  @Test(arguments: Scenarios.all.map(\.name))
  func eachScenarioMakesItsRulesSpeak(name: String) throws {
    let scenario = try #require(Scenarios.all.first { $0.name == name })
    let problems = try ScenarioRunner(repository: CatalogRepository.url).problems(for: scenario)

    for fragment in scenario.expecting {
      #expect(problems.contains { $0.contains(fragment) }, "\(fragment)")
    }
  }

  @Test func everyScenarioHasAUniqueName() {
    #expect(Set(Scenarios.all.map(\.name)).count == Scenarios.all.count)
  }
}
