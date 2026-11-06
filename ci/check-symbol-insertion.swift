import Foundation

@main
struct SymbolInsertionChecks {
    static func main() {
        let source = "中文😀 $ alpha + beta $"
        let selection = (source as NSString).range(of: "alpha")
        let target = SymbolInsertionTarget(source: source, selection: selection)
        precondition(target.range(in: source) == selection)
        let inserted = (source as NSString).replacingCharacters(in: target.range(in: source)!, with: "arrow.r")
        precondition(inserted == "中文😀 $ arrow.r + beta $")
        precondition(target.range(in: "前缀" + source) == nil)
        precondition(target.range(in: source.replacingOccurrences(of: "beta", with: "zeta")) == nil)
        let caret = SymbolInsertionTarget(source: source, selection: NSRange(location: 4, length: 0))
        precondition(caret.range(in: source) != nil)
        let surrogate = SymbolInsertionTarget(source: source, selection: NSRange(location: 3, length: 0))
        precondition(surrogate.range(in: source) == nil)
        let invalid = SymbolInsertionTarget(source: source, selection: NSRange(location: NSNotFound, length: 0))
        precondition(invalid.range(in: source) == nil)
        let empty = SymbolInsertionTarget(source: "", selection: NSRange(location: 0, length: 0))
        precondition(empty.range(in: "") != nil)
        let symbols = MathSymbolCategory.all.flatMap(\.symbols)
        print("Catalog count: \(symbols.count)")
        precondition(symbols.count == 1024)
        precondition(symbols.first { $0.name == "alpha" }?.command == "alpha")
        precondition(symbols.first { $0.name == "arrow.r" }?.command == "arrow.r")
        precondition(symbols.allSatisfy { !$0.command.contains("#") && !$0.command.contains(";") })
        print("PASS: Unicode selections, replacements, stale source rejection and formula commands")
    }
}
