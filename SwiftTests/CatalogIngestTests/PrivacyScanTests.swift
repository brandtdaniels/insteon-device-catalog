import CatalogIngest
import Testing

/// What each pattern of the scan finds and leaves alone, one text at a time.
struct PrivacyScanTests {
  func shapes(_ text: String, models: Set<String> = [], serial: Bool = false) -> [PrivateShape] {
    PrivacyScan.shapes(in: text, models: models, serial: serial)
  }

  @Test(arguments: ["2F.9A.C1", "2f.9a.c1", "a 2F.9A.C1.", "(2F.9A.C1)", "2F.9A.C1,", "x 12.34.56 y", "2F.9A.C1.D2"])
  func aDottedAddressIsFound(text: String) {
    #expect(shapes(text) == [.address], "\(text)")
  }

  @Test(arguments: ["x2F.9A.C1", "2F.9A.C1x", "2F.9A", "2F.9A.C", "1F.2G.3H"])
  func aDottedAddressNeedsItsBoundaries(text: String) {
    #expect(!shapes(text).contains(.address), "\(text)")
  }

  @Test(arguments: ["2F9AC1", "2f9ac1", "a1b2c3", "FACADE", "ABCDEF", "001122", "(2F9AC1)", "2F9AC1,", "id=2F9AC1"])
  func aBareAddressHasADigitOrIsAllUpperCase(text: String) {
    #expect(shapes(text) == [.address], "\(text)")
  }

  @Test(arguments: ["decade", "facade", "abcdef", "decade1", "a1b2c3d", "2F9AC", "ABCDEFG", "0x001122", "x2F9AC1", "2F9AC1x", "faded", "Decade"])
  func aWordThatLooksLikeHexadecimalIsNotAnAddress(text: String) {
    #expect(!shapes(text).contains(.address), "\(text)")
  }

  @Test func aBareTokenThatIsACatalogModelIsAllowedWhenTheCallerSaysSo() {
    #expect(shapes("Dimmer Plug 2457D2") == [.address])
    #expect(shapes("Dimmer Plug 2457D2", models: ["2457D2"]) == [])
    #expect(shapes("Dimmer Plug 2457d2", models: ["2457D2"]) == [.address])
    #expect(shapes("Dimmer Plug 2457D2 at 2F9AC1", models: ["2457D2"]) == [.address])
    #expect(shapes("Dimmer Plug 2457D2 at 2F.9A.C1", models: ["2457D2"]) == [.address])
  }

  @Test(arguments: ["a4:5e:60:11:22:33", "A4-5E-60-11-22-33", "x a4:5e:60:11:22:33 y"])
  func aMACAddressIsFound(text: String) {
    #expect(shapes(text) == [.mac], "\(text)")
  }

  @Test(arguments: ["a4:5e:60:11:22", "a4:5e-60:11:22:33", "xa4:5e:60:11:22:33"])
  func aMACAddressNeedsItsSeparatorsAndBoundaries(text: String) {
    #expect(!shapes(text).contains(.mac), "\(text)")
  }

  @Test(arguments: ["192.168.7.20", "10.0.0.7", "x 1.2.3.4 y", "999.999.999.999", "1.2.3.4.", "1.2.3.4,", "1.2.3.4.5", "v1.2.3.4a"])
  func anIPv4AddressIsFound(text: String) {
    #expect(shapes(text) == [.ip], "\(text)")
  }

  @Test(arguments: ["1.2.3", "1.2.3.", "a.b.c.d", "12.30"])
  func anIPv4AddressNeedsFourNumbers(text: String) {
    #expect(!shapes(text).contains(.ip), "\(text)")
  }

  @Test(arguments: ["fe80::1:2:3:4", ":::", "::1", "1::", "fe80::", "1:2:3:4", "1:2:3:4:5:6:7:8", "a4:5e-60:11:22:33", "x ::1 y"])
  func anIPv6AddressIsFound(text: String) {
    #expect(shapes(text).contains(.ip), "\(text)")
  }

  @Test(arguments: ["a:b:c", "::", "1:2:3:4:5:6:7:8:9", "12:30", "at 12:30:00 sharp", "x:1:2:3:4", "1:2:3:4:z"])
  func anIPv6AddressNeedsItsShape(text: String) {
    #expect(!shapes(text).contains(.ip), "\(text)")
  }

  @Test func aMACAddressIsNotAlsoReportedAsAnIPv6Address() {
    #expect(shapes("a4:5e:60:11:22:33") == [.mac])
    #expect(shapes("a4:5e:60:11:22:33 and 1.2.3.4") == [.mac, .ip])
  }

  @Test(arguments: ["https://hub.example.test/status", "ftp://x", "www.example", "hub.example.com", "example.local", "x.Home", "a.b.EDU", "mailto://x"])
  func aURLOrHostNameIsFound(text: String) {
    #expect(shapes(text).contains(.url), "\(text)")
  }

  @Test(arguments: ["example", "example.localhost", "file.txt", "I/O Module", "a.commercial", "version 1.2", "mailto:x"])
  func aWordWithADotIsNotAHostName(text: String) {
    #expect(!shapes(text).contains(.url), "\(text)")
  }

  @Test(arguments: ["someone@example.test", "a.b+c@d-e.f.g", "x@y.zz", "caf\u{00E9}@exemple.fr"])
  func anEmailAddressIsFound(text: String) {
    #expect(shapes(text).contains(.email), "\(text)")
  }

  @Test(arguments: ["name@host", "@example.test", "name @example.test", "at the bench"])
  func anAtSignAloneIsNotAnEmailAddress(text: String) {
    #expect(!shapes(text).contains(.email), "\(text)")
  }

  @Test(arguments: ["/Users/someone/notes.txt", "/home/someone/notes", "C:\\Users\\someone", "c:\\x", "\\\\server\\share", "~/notes", "see /etc/hosts now", "(/tmp/x/y)", "=/a/b/", "'/a/b/'", "\"/a/b/\"", "x\r\n/tmp/a/"])
  func aFilePathIsFound(text: String) {
    #expect(shapes(text).contains(.path), "\(text)")
  }

  @Test(arguments: ["a/b/c", "12/34/56", "I/O Module 2450 (I/O Linc)", "/etc", "x/tmp/a/", "C:x", "~x/y"])
  func aSlashAloneIsNotAFilePath(text: String) {
    #expect(!shapes(text).contains(.path), "\(text)")
  }

  @Test func aPathAtTheStartOfTheTextIsFound() {
    #expect(shapes("/home/a/b").contains(.path))
    #expect(shapes("~/notes").contains(.path))
  }

  @Test(arguments: ["SN12345678", "ab12cd34", "ABCDEFGH1", "Label SN12345678 here", "12345678"])
  func aSerialNumberLikeTokenIsFoundOnlyWhenAsked(text: String) {
    #expect(shapes(text, serial: true).contains(.serial), "\(text)")
    #expect(!shapes(text, serial: false).contains(.serial), "\(text)")
  }

  @Test(arguments: ["ab12cd3", "abcdefgh", "0x00001A", "0x12345678", "plain words only"])
  func aTokenWithoutEightCharactersAndADigitIsNotASerialNumber(text: String) {
    #expect(!shapes(text, serial: true).contains(.serial), "\(text)")
  }

  @Test func theShapesComeInAFixedOrderAndEachOnceOnly() {
    let text = "/home/a/b/ a@b.example 1.2.3.4 www.x.y a4:5e:60:11:22:33 2F.9A.C1 2F9AC1 SN12345678"

    #expect(shapes(text, serial: true) == [.address, .mac, .ip, .url, .email, .path, .serial])
  }

  @Test func eachShapeHasTheNameTheRejectionPrints() {
    #expect(PrivateShape.address.description == "an Insteon address")
    #expect(PrivateShape.mac.description == "a MAC address")
    #expect(PrivateShape.ip.description == "an IP address")
    #expect(PrivateShape.url.description == "a URL or host name")
    #expect(PrivateShape.email.description == "an email address")
    #expect(PrivateShape.path.description == "a file path")
    #expect(PrivateShape.serial.description == "a serial number")
  }

  /// Python's `\d`, `\w` and `\s` take characters ICU's do not or the other way round; the scan
  /// follows Python.
  @Test func digitsAndSpacesAreReadAsPythonReadsThem() {
    #expect(shapes("\u{0663}.\u{0663}.\u{0663}.\u{0663}").contains(.ip))
    #expect(shapes("x\u{000B}/tmp/a/").contains(.path))
    #expect(shapes("x\u{001C}/tmp/a/").contains(.path))
    #expect(shapes("x\u{0085}/tmp/a/").contains(.path))
    #expect(shapes("caf\u{00E9}@exemple.fr").contains(.email))
  }
}
