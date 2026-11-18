/// A lookup table that keeps the order its entries were written in, because the page lists them in
/// that order.
struct OrderedTable: Sendable {
  let entries: [(key: String, value: String)]

  init(_ entries: [(String, String)]) {
    self.entries = entries.map { (key: $0.0, value: $0.1) }
  }

  var keys: [String] { entries.map(\.key) }
  var values: [String] { entries.map(\.value) }
  var count: Int { entries.count }

  subscript(key: String) -> String? {
    entries.first { $0.key == key }?.value
  }
}

/// The constant wording the page is built from.
enum PageTables {
  /// The verification statuses, in the order the page lists them.
  static let statuses = ["observed", "documented", "inferred", "conflicting"]

  /// One sentence each, for the page. They say what the README says a status means.
  static let statusExplanations = OrderedTable([
    ("observed", "Seen on a real device, with the firmware it was running recorded."),
    ("documented", "An Insteon document gives it and none of the catalog's sources disagree."),
    ("inferred", "No document states it, so it is read from an example, a similar product or how the product behaves."),
    ("conflicting", "Insteon's documents disagree, and the note says which value the catalog uses.")
  ])

  /// The category names the Insteon Developer's Guide gives.
  static let categoryNames = OrderedTable([
    ("0x00", "Generalized Controllers"),
    ("0x01", "Dimmable Lighting Control"),
    ("0x02", "Switched Lighting Control"),
    ("0x03", "Network Bridges"),
    ("0x04", "Irrigation Control"),
    ("0x05", "Climate Control"),
    ("0x06", "Pool and Spa Control"),
    ("0x07", "Sensors and Actuators"),
    ("0x08", "Home Entertainment"),
    ("0x09", "Energy Management"),
    ("0x0A", "Built-In Appliance Control"),
    ("0x0B", "Plumbing"),
    ("0x0C", "Communication"),
    ("0x0D", "Computer Control"),
    ("0x0E", "Window Coverings"),
    ("0x0F", "Access Control"),
    ("0x10", "Security, Health, Safety"),
    ("0x11", "Surveillance"),
    ("0x12", "Automotive"),
    ("0x13", "Pet Care"),
    ("0x14", "Toys"),
    ("0x15", "Timekeeping"),
    ("0x16", "Holiday")
  ])

  /// What each category holds, for the page's sections.
  static let categoryDescriptions = OrderedTable([
    ("0x00", "Controllers that send commands rather than switch a load of their own, such as remotes, tabletop controllers and range extenders."),
    ("0x01", "Dimmers: wall switches, keypads, plug-in and in-line modules, outlets and bulbs that dim the light they control."),
    ("0x02", "On/off switches: wall switches, keypads, plug-in and in-line modules, outlets and load controllers that switch what they control."),
    ("0x03", "Network bridges that connect a computer, app or network to Insteon, such as modems, Hubs and USB adapters."),
    ("0x04", "Irrigation controllers, such as sprinkler valve controllers."),
    ("0x05", "Climate control: thermostats and thermostat adapters."),
    ("0x06", "Pool and spa controls, such as pump and heater controllers."),
    ("0x07", "Sensors and actuators: modules with inputs that sense contact closures and voltages, and relays that drive other equipment."),
    ("0x08", "Home entertainment controls, such as audio and video equipment."),
    ("0x09", "Energy management: power meters and high-current load controllers."),
    ("0x0E", "Window coverings: modules and motors for drapes, shades and shutters."),
    ("0x0F", "Access control: locks, deadbolts and garage door controls."),
    ("0x10", "Security, health and safety: open/close, motion and leak sensors, and smoke alarm bridges.")
  ])

  /// How the page names each capability kind.
  static let capabilityLabels = OrderedTable([
    ("onOff", "On/off"),
    ("dimmable", "Dimmable"),
    ("modem", "Modem"),
    ("hub", "Hub"),
    ("hubPro", "Hub Pro"),
    ("thermostat", "Thermostat"),
    ("groupEvents", "Group events"),
    ("heartbeat", "Heartbeat")
  ])

  /// One plain sentence for each capability kind, for the page's legend.
  static let capabilityExplanations = OrderedTable([
    ("onOff", "Switches a load on and off."),
    ("dimmable", "Dims a load to a level between off and full."),
    ("modem", "A modem, which connects a computer or app to the Insteon network, such as a PowerLinc Modem, a USB Adapter or the modem inside a Hub."),
    ("hub", "A Hub, whose modem is driven through the Hub's local HTTP interface."),
    ("hubPro", "A Hub Pro, which also has its own HTTP interface for adding and removing devices and updating its software."),
    ("thermostat", "A thermostat, with the mode values it reports."),
    ("groupEvents", "Sends commands to its ALL-Link groups, and the catalog says what each one means, such as opened or closed."),
    ("heartbeat", "Sends a periodic heartbeat to a group, so software can notice a product that has gone quiet.")
  ])

  /// How the page names each engine.
  static let engineLabels = OrderedTable([("i1", "i1"), ("i2", "i2"), ("i2cs", "i2CS")])

  /// What each engine means for software, as the schema describes it.
  static let engineExplanations = OrderedTable([
    ("i1", "An engine that does not support Enter Linking Mode, so a person uses the device's controls to link it."),
    ("i2", "An engine that takes Enter Linking Mode as a standard message."),
    ("i2cs", "An engine that rejects an extended message whose D14 checksum is wrong, and takes Enter Linking Mode as an extended message with a checksum.")
  ])

  /// How each radio is explained, and the profiles that state none.
  static let radioExplanations = OrderedTable([
    ("powerline", "Communicates over the home's power wiring only."),
    ("rf", "Communicates by radio only."),
    ("dual", "Communicates over both the power wiring and radio."),
    ("unstated", "No source the catalog cites states how the product communicates.")
  ])

  static let batteryExplanation = "Runs on batteries and sleeps between messages."

  static let radioLabels = OrderedTable([("powerline", "Powerline"), ("rf", "RF"), ("dual", "Dual-band")])

  static let roleLabels = OrderedTable([
    ("controller", "Controller"),
    ("responder", "Responder"),
    ("both", "Controller and responder")
  ])

  /// The facts a card gives about a command set, in the order it gives them.
  static let commandSetFacts = ["operatingFlags", "extendedSettings", "standardCommands", "extendedCommands", "serialCommands", "readings"]

  /// The names a card gives each list of labels, for the summary that opens it.
  static let listTitles = OrderedTable([
    ("operatingFlags", "Operating flags"),
    ("extendedSettings", "Extended settings"),
    ("readings", "Readings")
  ])

  /// The keys of a command set that describe it rather than the product's behavior.
  static let commandSetDescriptiveKeys: Set<String> = ["id", "name", "description", "notes", "sources"]
}
