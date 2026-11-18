// tools/inspect-accessibility/main.swift
//
// Prints what VoiceOver can see in a running app: the app's windows and
// menu bar, the element with keyboard focus and what's around it, and any
// shortcut menu that's open on it. Read-only: it never clicks or changes
// anything.
//
// Run it with:  bash tools/inspect-accessibility.sh
// It needs Accessibility permission (System Settings > Privacy & Security
// > Accessibility) for the app you run it from, such as Terminal. Turn the
// permission off again afterwards if you like.
//
// Written 2026-11-14 to find why VO-Down stuck in the log's shortcut menu:
// it showed a hidden, unnamed item macOS had added to the menu.

import AppKit
import ApplicationServices
// Read-only: prints where the open menu is and its tree, right now.
let target = NSRunningApplication.runningApplications(withBundleIdentifier: CommandLine.arguments[1]).first!
let app = AXUIElementCreateApplication(target.processIdentifier)
func attr(_ e: AXUIElement, _ name: String) -> CFTypeRef? { var v: CFTypeRef?; return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil }
func actions(_ e: AXUIElement) -> [String] { var n: CFArray?; AXUIElementCopyActionNames(e, &n); return (n as? [String]) ?? [] }
func describe(_ e: AXUIElement, _ depth: Int, _ maxDepth: Int) {
  let role = attr(e, "AXRole") as? String ?? "?"
  let title = attr(e, "AXTitle") as? String ?? ""
  let value = attr(e, "AXValue").map { "\($0)" } ?? ""
  let enabled = attr(e, "AXEnabled") as? Bool
  let selected = attr(e, "AXSelected") as? Bool
  print(String(repeating: "  ", count: depth) + "\(role) title='\(title)' value='\(value.prefix(30))' enabled=\(enabled.map{"\($0)"} ?? "-") selected=\(selected.map{"\($0)"} ?? "-") actions=\(actions(e))")
  if depth < maxDepth, let kids = attr(e, "AXChildren") as? [AXUIElement] { for k in kids { describe(k, depth + 1, maxDepth) } }
}
print("app children:")
for k in attr(app, "AXChildren") as? [AXUIElement] ?? [] { describe(k, 1, 1) }
if let f = attr(app, "AXFocusedUIElement") { print("focused element:"); describe(f as! AXUIElement, 1, 0)
  if let p = attr(f as! AXUIElement, "AXParent") { print("its parent:"); describe(p as! AXUIElement, 1, 3) } }
let sys = AXUIElementCreateSystemWide()
if let f = attr(sys, "AXFocusedUIElement") { print("system-wide focused:"); describe(f as! AXUIElement, 1, 0) }
print("--- the menu under the table:")
if let f = attr(app, "AXFocusedUIElement"), let kids = attr(f as! AXUIElement, "AXChildren") as? [AXUIElement],
   let menu = kids.first(where: { (attr($0, "AXRole") as? String) == "AXMenu" }) {
  describe(menu, 0, 4)
  var n: CFArray?; AXUIElementCopyAttributeNames(menu, &n); print("menu attributes:", (n as? [String]) ?? [])
  for item in attr(menu, "AXChildren") as? [AXUIElement] ?? [] { var m: CFArray?; AXUIElementCopyAttributeNames(item, &m); print("item attributes:", (m as? [String]) ?? []); break }
} else { print("menu not found (closed?)") }
