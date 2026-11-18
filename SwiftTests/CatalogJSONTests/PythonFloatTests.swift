import CatalogJSON
import Testing

struct PythonFloatTests {
  /// Each pair is a value and Python's `repr` of it.
  @Test(arguments: [
    // The floats the data files hold.
    (0.067, "0.067"), (0.1, "0.1"), (0.2, "0.2"), (0.3, "0.3"), (0.392157, "0.392157"),
    (0.5, "0.5"), (2.3, "2.3"), (3.5, "3.5"), (4.5, "4.5"), (6.5, "6.5"), (8.5, "8.5"),
    (21.5, "21.5"), (23.5, "23.5"), (38.5, "38.5"), (755.2, "755.2"),
    // Integral values keep ".0".
    (1.0, "1.0"), (100.0, "100.0"), (0.0, "0.0"), (-0.0, "-0.0"), (-2.0, "-2.0"),
    // Fixed notation holds from 1e-4 up to below 1e16.
    (0.0001, "0.0001"), (0.00012345, "0.00012345"), (123456789012345.0, "123456789012345.0"),
    (1e15, "1000000000000000.0"), (9999999999999998.0, "9999999999999998.0"),
    (123456789.123, "123456789.123"),
    // Exponent notation has a sign and at least two digits.
    (0.00001, "1e-05"), (1e-07, "1e-07"), (1.5e-10, "1.5e-10"), (Double.leastNonzeroMagnitude, "5e-324"),
    (1e16, "1e+16"), (1.2345e20, "1.2345e+20"), (1e100, "1e+100"),
    (Double.greatestFiniteMagnitude, "1.7976931348623157e+308"), (-1e-07, "-1e-07")
  ])
  func formatsLikePythonRepr(value: Double, expected: String) {
    #expect(PythonFloat.format(value) == expected)
  }

  @Test(arguments: [Double.nan, .infinity, -.infinity])
  func hasNoFormatForNonFiniteValues(value: Double) {
    #expect(PythonFloat.format(value) == nil)
  }
}
