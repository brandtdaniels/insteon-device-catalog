// A card's full details: everything the catalog states about one product, written from the
// published catalog when the card is opened. InsteonDetails.render needs no document, so the tests
// run it on every profile. A field with no name of its own here is shown under its key.
const InsteonDetails = (() => {
  const repository = "https://github.com/brandtdaniels/insteon-device-catalog";

  const names = {
    command1: "cmd1", command2: "cmd2", bytes: "Bytes", on: "Set with cmd2", off: "Clear with cmd2",
    query: "Query (cmd2)", idempotent: "Safe to send again", default: "Factory default", flagsQuery: "Operating flags query",
    onCommand: "Set by command", offCommand: "Cleared by command", extendedWhen: "Sent extended while", activeWhen: "In use while",
    allGroupsWhen: "Every group while", celsiusWhen: "Celsius while", releasedBy: "Released by", restState: "Rest state",
    pulsesOnEveryCommandWhen: "Pulses on every command while", resetErases: "Reset erases",
    linkingTimeoutSeconds: "Linking mode lasts, seconds", awakeSeconds: "Stays awake, seconds", intervalMinutes: "Interval, minutes",
    productKey: "Product key", commandSet: "Command set", command: "Command", linkData: "ALL-Link record data",
    modeValues: "Mode values", remoteEnterLinkingMode: "Remote Enter Linking Mode", fromHub: "Linking from a Hub",
    keepAwake: "Keep awake", deviceFirst: "Device goes into linking mode first", modemGroup: "Modem group",
    deviceGroup: "Device group", perButton: "Per button", perGroup: "The responder's group", legs: "Links to make",
    operatingFlags: "Operating flags", readings: "Readings", extendedSettings: "Extended settings",
    standardCommands: "Standard commands", extendedCommands: "Extended commands", flagCommands: "Flag commands",
    serialCommands: "Serial commands", directMessages: "Direct messages", groupTypes: "Group types",
    linkingChanges: "Flags linking changes", displayScale: "Display scale", valueTables: "Value tables",
    enumerations: "Enumerations", values: "Values", writes: "Writes", firmware: "Firmware", bitPerGroup: "One bit per group",
    onWhen: "On when", stateHolding: "State holding", armModes: "Arm modes", followUp: "Follow-up value",
    installation: "Installation", linking: "Linking", multiLinking: "Multi-linking", unlinking: "Unlinking",
    waking: "Waking", reset: "Factory reset", removal: "Removal"
  };

  const statuses = { observed: "Observed", documented: "Documented", inferred: "Inferred", conflicting: "Conflicting" };
  const capabilities = {
    onOff: "On/off", dimmable: "Dimmable", modem: "Modem", hub: "Hub", hubPro: "Hub Pro", thermostat: "Thermostat",
    groupEvents: "Group events", heartbeat: "Heartbeat"
  };
  const radios = { powerline: "Powerline", rf: "RF", dual: "Dual-band" };
  const roles = { controller: "Controller", responder: "Responder", both: "Controller and responder" };
  const engines = { i1: "i1", i2: "i2", i2cs: "i2CS" };
  const procedures = ["installation", "linking", "multiLinking", "unlinking", "waking", "reset", "removal"];
  const parts = [
    "operatingFlags", "readings", "extendedSettings", "standardCommands", "extendedCommands", "flagCommands", "serialCommands",
    "directMessages", "groupTypes", "linkingChanges", "displayScale", "valueTables", "enumerations"
  ];

  // The keys a reader looks for first, in order. The rest follow as the catalog writes them,
  // alphabetically.
  const order = [
    "number", "category", "subcategory", "region", "firmware", "productKey", "query", "bit", "on", "off", "command1", "command2",
    "selector", "position", "byte", "bytes", "mask", "value", "label", "name", "description", "action", "control", "command", "count",
    "seconds", "expect", "modem", "modemGroup", "deviceGroup", "role", "type"
  ];
  const place = (key) => (order.includes(key) ? order.indexOf(key) : order.length);
  const inOrder = (keys) => [...keys].sort((left, right) => place(left) - place(right));

  const escapes = { "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#x27;" };
  const escape = (text) => String(text).replace(/[&<>"']/g, (character) => escapes[character]);
  const own = (table, key) => (Object.prototype.hasOwnProperty.call(table, key) ? table[key] : undefined);

  const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
  const isScalar = (value) => value === null || typeof value !== "object";
  const keysOf = (value) => Object.keys(value).sort().join(" ");

  // A key in words: its name above, or its camel case spelled out.
  function name(key) {
    const known = own(names, key);
    if (known) return known;
    const words = key.replace(/([a-z0-9])([A-Z])/g, "$1 $2").toLowerCase();
    return words.charAt(0).toUpperCase() + words.slice(1);
  }

  function scalar(value) {
    if (typeof value === "boolean") return value ? "Yes" : "No";
    if (typeof value === "string" && /^0x[0-9A-F]+$/.test(value)) return "<code>" + value + "</code>";
    return escape(value);
  }

  // A value that reads as a phrase, such as a range or a condition on a flag, or nothing.
  function phrase(value) {
    if (isScalar(value)) return scalar(value);
    if (Array.isArray(value)) {
      if (value.every(isScalar)) return value.length ? value.map(scalar).join(", ") : "None";
      if (value.every((item) => Array.isArray(item) && item.every(isScalar))) return value.map((item) => item.map(scalar).join(" and ")).join(", or ");
      return null;
    }
    const keys = keysOf(value);
    if (keys === "from through") return phrase(value.from) + " through " + phrase(value.through);
    if (keys === "flag set" && typeof value.set === "boolean") return scalar(value.flag) + (value.set ? " is set" : " is clear");
    if ((keys === "only" || keys === "except") && Array.isArray(value[keys])) return keys + " " + phrase(value[keys]);
    return null;
  }

  const facts = (rows) => (rows.length
    ? "<dl class=\"facts\">" + rows.map(([term, html]) => "<div><dt>" + escape(term) + "</dt><dd>" + html + "</dd></div>").join("") + "</dl>"
    : "");

  function mark(verification, subject) {
    if (!isObject(verification)) return "";
    const { status, note, firmware, ...rest } = verification;
    let html = "<p class=\"verification\">";
    if (status !== undefined) {
      html += "<span class=\"status pill status-" + escape(status) + "\">" + escape(own(statuses, status) || status) + "</span> ";
    }
    if (subject) html += "<strong>" + escape(subject) + ":</strong> ";
    if (note !== undefined) html += escape(note);
    if (firmware !== undefined) html += " <span class=\"firmware\">Seen on firmware " + phrase(firmware) + "</span>";
    return html + "</p>" + block(rest);
  }

  // A list whose items are all small and flat, such as a value table, reads best as a table.
  function table(items) {
    const columns = inOrder(new Set(items.flatMap(Object.keys)));
    const head = columns.map((key) => "<th scope=\"col\">" + escape(name(key)) + "</th>").join("");
    const rows = items.map((item) => "<tr>" + columns.map((key) => "<td>" + (key in item ? phrase(item[key]) : "") + "</td>").join("") + "</tr>").join("");
    return "<div class=\"scroll\"><table class=\"values\"><thead><tr>" + head + "</tr></thead><tbody>" + rows + "</tbody></table></div>";
  }

  const isTable = (items) =>
    items.every((item) => isObject(item) && Object.values(item).every((value) => phrase(value) !== null))
    && new Set(items.flatMap(Object.keys)).size <= 4;

  function list(items) {
    if (items.every(isObject) && isTable(items)) return table(items);
    return "<ul class=\"entries\">" + items.map((item) => "<li class=\"entry\">" + (isObject(item) ? block(item) : any(item)) + "</li>").join("") + "</ul>";
  }

  function any(value) {
    const text = phrase(value);
    if (text !== null) return text;
    return Array.isArray(value) ? list(value) : block(value);
  }

  // An object: its title, its sentence, its facts, whatever is nested in it, then how sure it is.
  // `lead` and `trail` put facts the caller has worked out before and after the object's own.
  function block(value, { title, lead = [], trail = [] } = {}) {
    const keys = Object.keys(value);
    const used = new Set();
    let heading = title;
    let html = "";

    if (heading === undefined) {
      const label = ["label", "name"].find((key) => typeof value[key] === "string");
      if (label) {
        used.add(label);
        heading = escape(value[label]);
        if (label === "label" && typeof value.name === "string") {
          used.add("name");
          heading += "</strong> <code>" + escape(value.name) + "</code><strong>";
        }
      }
    }
    if (heading !== undefined) html += "<p class=\"entry-title\"><strong>" + heading + "</strong></p>";

    if (typeof value.description === "string") {
      used.add("description");
      html += "<p class=\"entry-text\">" + escape(value.description) + "</p>";
    }

    const rows = lead.slice();
    const nested = [];
    let marks = "";

    for (const key of inOrder(keys)) {
      if (used.has(key)) continue;
      const item = value[key];
      if (key === "verification" && isObject(item)) marks += mark(item);
      else if (key === "productKeyVerification" && isObject(item)) marks += mark(item, "Product key");
      else if (key === "notes" && Array.isArray(item) && item.every(isScalar)) nested.push([key, notes(item)]);
      else if (phrase(item) !== null) rows.push([name(key), phrase(item)]);
      else nested.push([key, any(item)]);
    }

    html += facts(rows.concat(trail));
    for (const [key, content] of nested) {
      html += "<div class=\"nested\"><p class=\"nested-title\">" + escape(name(key)) + "</p>" + content + "</div>";
    }
    return html + marks;
  }

  const notes = (items) => "<ul class=\"notes\">" + items.map((item) => "<li>" + scalar(item) + "</li>").join("") + "</ul>";

  const identityCode = (entry) => entry.category + "/" + entry.subcategory;

  const entries = (items, write) => "<ul class=\"entries\">" + items.map((item) => "<li class=\"entry\">" + write(item) + "</li>").join("") + "</ul>";

  // Each identity, with the engine and command sets the profile gives it.
  function identities(profile, sets) {
    return entries(profile.identities || [], (identity) => {
      const belongs = (entry) => entry.category === identity.category && entry.subcategory === identity.subcategory;
      const trail = [];
      let marks = "";

      function add(term, subject, entry) {
        const { category, subcategory, verification, firmware, ...rest } = entry;
        const versions = firmware === undefined ? "" : ", firmware " + any(firmware);
        trail.push([term, escape(subject) + versions + block(rest)]);
        marks += mark(verification, term + " " + subject);
      }

      for (const { engine, ...entry } of (profile.engines || []).filter(belongs)) {
        add("Engine", own(engines, engine) || engine, entry);
      }
      for (const { commandSet: id, ...entry } of (profile.commandSets || []).filter(belongs)) {
        add("Command set", sets.has(id) ? sets.get(id).name : id, entry);
      }

      return block(identity, { title: "<code>" + escape(identityCode(identity)) + "</code>", trail }) + marks;
    });
  }

  function hardware(profile) {
    const rows = [
      ["Radio", escape(own(radios, profile.radio) || profile.radio || "Not stated")],
      ["Role", escape(own(roles, profile.role) || profile.role || "Not stated")]
    ];
    if (profile.batteryPowered !== undefined) rows.push(["Battery powered", scalar(profile.batteryPowered)]);

    let html = facts(rows);

    if (profile.capabilities && profile.capabilities.length) {
      html += "<h5>Capabilities</h5>" + entries(profile.capabilities, (capability) => {
        const { kind, ...rest } = capability;
        return block(rest, { title: escape(own(capabilities, kind) || kind) });
      });
    }
    return html;
  }

  function steps(items) {
    return "<ol class=\"steps\">" + items.map((step) => {
      const { text, device, verification, ...rest } = step;
      const rows = [];
      if (device !== undefined) rows.push(["On", device === "other" ? "the other device" : device === "this" ? "this device" : escape(device)]);
      return "<li>" + escape(text === undefined ? "" : text) + block(rest, { lead: rows }) + mark(verification) + "</li>";
    }).join("") + "</ol>";
  }

  function procedure(value, title) {
    const { steps: items, notes: written, alternatives, verification, description, ...rest } = value;
    let html = "<details class=\"list\"><summary>" + escape(title) + "</summary><div class=\"list-body\">";
    if (description !== undefined && description !== title) html += "<p class=\"entry-text\">" + escape(description) + "</p>";
    html += block(rest);
    if (items) html += steps(items);
    if (written) html += notes(written);
    html += mark(verification);
    for (const [index, other] of (alternatives || []).entries()) {
      html += procedure(other, other.description || "Alternative " + (index + 1));
    }
    return html + "</div></details>";
  }

  function setup(lifecycle) {
    const rest = { ...lifecycle };
    let html = "";
    const isProcedure = (value) => isObject(value) && Array.isArray(value.steps);
    const keys = [...procedures, ...Object.keys(rest).filter((key) => !procedures.includes(key))];

    for (const key of keys) {
      if (!isProcedure(rest[key])) continue;
      html += procedure(rest[key], name(key));
      delete rest[key];
    }

    const { fromHub, ...others } = rest;
    html = block(others) + html;
    if (fromHub !== undefined) html += part(name("fromHub"), "", any(fromHub));
    return html;
  }

  const part = (title, attributes, content) =>
    "<details class=\"list\"" + attributes + "><summary>" + escape(title) + "</summary><div class=\"list-body\">" + content + "</div></details>";

  function count(value) {
    if (Array.isArray(value)) return value.length;
    if (isObject(value) && Array.isArray(value.values)) return value.values.length;
    return null;
  }

  function commandSet(id, set, users) {
    if (!set) {
      return "<div class=\"command-set\" data-command-set=\"" + escape(id) + "\"><p>The catalog file holds no command set named "
        + escape(id) + ".</p></div>";
    }

    const { id: ownID, name: title, description, notes: written, sources, ...rest } = set;
    let html = "<div class=\"command-set\" data-command-set=\"" + escape(id) + "\">";
    html += "<h5>" + escape(title) + " <code>" + escape(ownID) + "</code></h5>";
    if (description !== undefined) html += "<p class=\"entry-text\">" + escape(description) + "</p>";
    html += "<p class=\"used-by\">Used by " + users.map((entry) => {
      let text = "<code>" + escape(identityCode(entry)) + "</code>";
      if (entry.firmware !== undefined) text += ", firmware " + any(entry.firmware);
      return text;
    }).join("; ") + "</p>";

    const keys = [...parts, ...Object.keys(rest).filter((key) => !parts.includes(key))];
    for (const key of keys) {
      if (!(key in rest)) continue;
      const total = count(rest[key]);
      html += part(name(key) + (total === null ? "" : " (" + total + ")"), " data-list=\"" + escape(key) + "\"", any(rest[key]));
    }

    if (written) html += part("Notes", " data-list=\"notes\"", notes(written));
    if (sources) html += part("Command set sources", " data-list=\"sources\"", notes(sources));
    return html + "</div>";
  }

  const section = (key, title, content) => (content ? "<section data-part=\"" + key + "\"><h4>" + title + "</h4>" + content + "</section>" : "");

  function render(profile, commandSets) {
    const sets = new Map(commandSets.map((set) => [set.id, set]));
    const {
      model, name: productName, aliases, description, identities: ids, engines: engineEntries, commandSets: setEntries,
      radio, role, batteryPowered, capabilities: kinds, verification, groups, lifecycle, notes: written, sources, ...rest
    } = profile;

    const used = new Map();
    for (const entry of setEntries || []) {
      if (!used.has(entry.commandSet)) used.set(entry.commandSet, []);
      used.get(entry.commandSet).push(entry);
    }

    let html = "<div class=\"full\">";
    // A mark on the profile itself is about everything below it, so it comes first.
    html += mark(verification, "The whole profile");
    html += section("identity", "Identity", identities(profile, sets));
    html += section("hardware", "Hardware", hardware(profile));
    html += section("groups", "ALL-Link groups", groups && groups.length ? entries(groups, (group) => block(group)) : "<p>None listed.</p>");
    html += section("setup", "Setup and linking", lifecycle ? setup(lifecycle) : "<p>The catalog has no setup steps for this device.</p>");
    html += section("software", "Commands and settings", used.size
      ? [...used].map(([id, users]) => commandSet(id, sets.get(id), users)).join("")
      : "<p>The catalog has no command set for this device.</p>");
    html += section("notes", "Notes", written ? notes(written) : "");
    html += section("sources", "Sources", sources ? notes(sources) : "");
    html += section("other", "Other", block(rest));
    html += "<p class=\"data-file\"><a href=\"" + repository + "/blob/main/devices/" + encodeURIComponent(model) + ".json\">"
      + "This profile's data file</a></p>";
    return html + "</div>";
  }

  return { render };
})();

// Fills a card with its full details the first time it is opened. The card keeps its summary when
// the catalog can't be loaded, and tries again the next time it is opened.
if (typeof document !== "undefined") {
  (() => {
    const main = document.querySelector("main[data-catalog]");
    if (!main) return;
    const address = main.dataset.catalog;
    let catalog;

    function load() {
      catalog = catalog || fetch(address).then((response) => {
        if (!response.ok) throw new Error("HTTP " + response.status);
        return response.json();
      }).catch((error) => {
        catalog = undefined;
        throw error;
      });
      return catalog;
    }

    async function fill(card, more) {
      if (more.dataset.state === "loading" || more.dataset.state === "full") return;
      more.dataset.state = "loading";

      let status = more.querySelector(".load-status");
      if (!status) {
        status = document.createElement("p");
        status.className = "load-status";
        status.setAttribute("role", "status");
        more.querySelector("summary").after(status);
      }
      status.textContent = "Loading the full details.";

      try {
        const data = await load();
        const profile = data.devices.find((device) => device.model === card.dataset.model);
        if (!profile) throw new Error("no profile for " + card.dataset.model);
        const holder = document.createElement("template");
        holder.innerHTML = InsteonDetails.render(profile, data.commandSets);
        status.remove();
        more.querySelector(".groups").replaceWith(holder.content);
        more.dataset.state = "full";
      } catch (error) {
        console.error(error);
        status.textContent = "The full details can't be loaded, so this is the summary. Close and open this section to retry.";
        more.dataset.state = "failed";
      }
    }

    // The toggle event doesn't bubble, so it is heard on the way down.
    main.addEventListener("toggle", (event) => {
      const more = event.target;
      if (!more.matches("details.more")) return;
      const card = more.closest(".card");
      card.classList.toggle("open", more.open);
      if (!more.open) return;
      card.scrollIntoView({ block: "nearest" });
      fill(card, more);
    }, true);

    // A browser may restore an open section before this script listens.
    for (const more of main.querySelectorAll("details.more[open]")) {
      const card = more.closest(".card");
      card.classList.add("open");
      fill(card, more);
    }
  })();
}
