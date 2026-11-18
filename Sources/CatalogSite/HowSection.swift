/// The page's closing section: where the catalog's facts come from and how to help.
enum HowSection {
  static var html: String {
    let base = "https://github.com/brandtdaniels/insteon-device-catalog"

    var html = #"<section class="how" aria-labelledby="how-heading">"#
    html += #"<h2 id="how-heading">How this catalog is built and how to help</h2>"#
    html += "<p>Every fact comes from a public Insteon document, cited by its exact title and version in the profile's <code>sources</code>, "
    html += "or from an observation on a real device, which names the firmware it was seen on. "
    html += "A value that no document states, that documents disagree on, or that a device has shown carries a status (inferred, conflicting or observed) and a note that say so. "
    html += "A value with no mark is documented: a public Insteon document gives it.</p>"
    html += "<p>Help is welcome wherever a value is marked inferred or conflicting, and for devices the catalog has no command set for:</p>"
    html += "<ul>"
    html += #"<li>Found a wrong or missing value? <a href="\#(base)/issues">Open an issue</a> that names the product, the value and the document or device that shows it.</li>"#
    html += #"<li>Own a device? A <a href="\#(base)/pulls">pull request</a> can record what it did: the model, the firmware it was running and what you saw. "#
    html += #"<a href="\#(base)/blob/main/README.md#adding-or-changing-a-profile">Adding or changing a profile</a> describes the steps and the checks every change passes.</li>"#
    html += #"<li>Writing software? <a href="\#(base)/blob/main/API.md">API.md</a> describes the files and how to read them.</li>"#
    html += "</ul>"
    html += "</section>"
    return html
  }
}
