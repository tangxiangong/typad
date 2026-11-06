import SwiftUI

struct SymbolInsertion {
    let id = UUID()
    let text: String
}

/// A picker must not apply an old selection to a different source revision.
struct SymbolInsertionTarget {
    let source: String
    let selection: NSRange

    func range(in currentSource: String) -> NSRange? {
        let text = currentSource as NSString
        guard source.utf16.elementsEqual(currentSource.utf16),
              selection.location <= text.length,
              selection.length <= text.length - selection.location else { return nil }
        for boundary in [selection.location, NSMaxRange(selection)] where boundary < text.length {
            if (0xDC00...0xDFFF).contains(text.character(at: boundary)) { return nil }
        }
        return selection
    }
}

struct MathSymbol: Identifiable {
    let glyph: String
    let name: String
    var id: String { name }
    var command: String {
        switch name {
        case "sqrt": return "sqrt(x)"
        case "root.cube": return "root(3, x)"
        default: return name
        }
    }
}

struct MathSymbolCategory: Identifiable {
    let title: String
    let symbols: [MathSymbol]
    var id: String { title }

    private static func category(_ title: String, _ entries: String) -> Self {
        Self(title: title, symbols: entries.unicodeScalars.split(separator: " ").map { scalars in
            let entry = String(String.UnicodeScalarView(scalars))
            let separator = entry.lastIndex(of: ":")!
            return MathSymbol(glyph: String(entry[..<separator]), name: String(entry[entry.index(after: separator)...]))
        })
    }

    // Generated from codex 0.3.0 sym.txt (Typst 0.15.1); see ci/update-math-symbols.py.
    static let all: [Self] = [
        category("Greek Letters", "α:alpha β:beta ϐ:beta.alt χ:chi δ:delta ϝ:digamma ε:epsilon ϵ:epsilon.alt ϶:epsilon.alt.rev η:eta γ:gamma ι:iota ℩:iota.inv κ:kappa ϰ:kappa.alt λ:lambda μ:mu ν:nu ω:omega ο:omicron φ:phi ϕ:phi.alt π:pi ϖ:pi.alt ψ:psi ρ:rho ϱ:rho.alt σ:sigma ς:sigma.alt τ:tau θ:theta ϑ:theta.alt υ:upsilon ξ:xi ζ:zeta Α:Alpha Β:Beta Χ:Chi Δ:Delta Ϝ:Digamma Ε:Epsilon Η:Eta Γ:Gamma Ι:Iota Κ:Kappa Λ:Lambda Μ:Mu Ν:Nu Ω:Omega ℧:Omega.inv Ο:Omicron Φ:Phi Π:Pi Ψ:Psi Ρ:Rho Σ:Sigma Τ:Tau Θ:Theta ϴ:Theta.alt Υ:Upsilon Ξ:Xi Ζ:Zeta"),
        category("Relations", "=:eq ⩮:eq.ast ≛:eq.star ⊜:eq.o ≕:eq.colon ≐:eq.dot ≑:eq.dots ≒:eq.dots.down ≓:eq.dots.up ≝:eq.def ≜:eq.delta ≚:eq.equi ≙:eq.est ⋝:eq.gt ⋜:eq.lt ≞:eq.m ≠:eq.not ⋞:eq.prec ≟:eq.quest ⋟:eq.succ ≡:eq.triple ≢:eq.triple.not ≣:eq.quad >:gt ⧁:gt.o ⋗:gt.dot ⩼:gt.quest ⪆:gt.approx ⪧:gt.arc ⪩:gt.arc.eq ⊳:gt.closed ⊵:gt.closed.eq ⋭:gt.closed.eq.not ⋫:gt.closed.not ≫:gt.double ⪢:gt.double.nested ≥:gt.eq ⩾:gt.eq.slant ⋛:gt.eq.lt ≱:gt.eq.not ≧:gt.equiv ≷:gt.lt ≹:gt.lt.not ⪈:gt.neq ⪊:gt.napprox ≩:gt.nequiv ≯:gt.not ⋧:gt.ntilde ≳:gt.tilde ≵:gt.tilde.not ⋙:gt.triple ⫸:gt.triple.nested <:lt ⧀:lt.o ⋖:lt.dot ⩻:lt.quest ⪅:lt.approx ⪦:lt.arc ⪨:lt.arc.eq ⊲:lt.closed ⊴:lt.closed.eq ⋬:lt.closed.eq.not ⋪:lt.closed.not ≪:lt.double ⪡:lt.double.nested ≤:lt.eq ⩽:lt.eq.slant ⋚:lt.eq.gt ≰:lt.eq.not ≦:lt.equiv ≶:lt.gt ≸:lt.gt.not ⪇:lt.neq ⪉:lt.napprox ≨:lt.nequiv ≮:lt.not ⋦:lt.ntilde ≲:lt.tilde ≴:lt.tilde.not ⋘:lt.triple ⫷:lt.triple.nested ≈:approx ≊:approx.eq ≉:approx.not ⩯:approx.hat ≺:prec ⪷:prec.approx ≼:prec.curly.eq ⋠:prec.curly.eq.not ⪻:prec.double ⪯:prec.eq ⪳:prec.equiv ⪹:prec.napprox ⪱:prec.neq ⪵:prec.nequiv ⊀:prec.not ⋨:prec.ntilde ≾:prec.tilde ≻:succ ⪸:succ.approx ≽:succ.curly.eq ⋡:succ.curly.eq.not ⪼:succ.double ⪰:succ.eq ⪴:succ.equiv ⪺:succ.napprox ⪲:succ.neq ⪶:succ.nequiv ⊁:succ.not ⋩:succ.ntilde ≿:succ.tilde ≡:equiv ≢:equiv.not ⪪:smt ⪬:smt.eq ⪫:lat ⪭:lat.eq ∝:prop ⊶:original ⊷:image ≍:asymp ≭:asymp.not"),
        category("Operators", "+:plus ⊕:plus.o ⨭:plus.o.l ⨮:plus.o.r ⟴:plus.o.arrow ⨁:plus.o.big ∔:plus.dot ⧺:plus.double ±:plus.minus ⊞:plus.square ⨹:plus.triangle ⧻:plus.triple ⨣:plus.hat −:minus ⊖:minus.o ∸:minus.dot ∓:minus.plus ⊟:minus.square ≂:minus.tilde ⨺:minus.triangle ÷:div ⨸:div.o ⦼:div.slanted.o ×:times ⨉:times.big ⊗:times.o ⨴:times.o.l ⨵:times.o.r ⨶:times.o.hat ⨂:times.o.big ⋇:times.div ⋋:times.three.l ⋌:times.three.r ⋉:times.l ⋊:times.r ⊠:times.square ⨻:times.triangle ∶:ratio"),
        category("Calculus", "∞:infinity ⧞:infinity.bar ⧜:infinity.incomplete ⧝:infinity.tie ∞:oo ∂:partial ∇:gradient ∇:nabla ∑:sum ⨋:sum.integral ∏:product ∐:product.co ∫:integral ⨗:integral.arrow.hook ⨑:integral.ccw ∮:integral.cont ∳:integral.cont.ccw ∲:integral.cont.cw ∱:integral.cw ⨍:integral.dash ⨎:integral.dash.double ∬:integral.double ⨌:integral.quad ⨙:integral.inter ⨏:integral.slash ⨖:integral.square ∯:integral.surf ⨘:integral.times ∭:integral.triple ⨚:integral.union ∰:integral.vol ∆:laplace √:sqrt ∛:root.cube d:dif D:Dif"),
        category("Sets & Logic", "∅:emptyset ∅:emptyset.zero ⦳:emptyset.arrow.r ⦴:emptyset.arrow.l ⦱:emptyset.bar ⦲:emptyset.circle ⦰:emptyset.rev ∅:nothing ∅:nothing.zero ⦳:nothing.arrow.r ⦴:nothing.arrow.l ⦱:nothing.bar ⦲:nothing.circle ⦰:nothing.rev ∖:without ∁:complement ∈:in ∉:in.not ∋:in.rev ∌:in.rev.not ∍:in.rev.small ∊:in.small ⊂:subset ⫉:subset.approx ⫏:subset.closed ⫑:subset.closed.eq ⪽:subset.dot ⋐:subset.double ⊆:subset.eq ⫃:subset.eq.dot ⊈:subset.eq.not ⊑:subset.eq.sq ⋢:subset.eq.sq.not ⫅:subset.equiv ⊊:subset.neq ⫋:subset.nequiv ⊄:subset.not ⪿:subset.plus ⊏:subset.sq ⋤:subset.sq.neq ⫇:subset.tilde ⫁:subset.times ⊃:supset ⫊:supset.approx ⫐:supset.closed ⫒:supset.closed.eq ⪾:supset.dot ⋑:supset.double ⊇:supset.eq ⫄:supset.eq.dot ⊉:supset.eq.not ⊒:supset.eq.sq ⋣:supset.eq.sq.not ⫆:supset.equiv ⊋:supset.neq ⫌:supset.nequiv ⊅:supset.not ⫀:supset.plus ⊐:supset.sq ⋥:supset.sq.neq ⫈:supset.tilde ⫂:supset.times ∪:union ∪:union.serif ⊌:union.arrow ⋃:union.big ⊍:union.dot ⨃:union.dot.big ⋓:union.double ⩁:union.minus ⩅:union.or ⊎:union.plus ⨄:union.plus.big ⊔:union.sq ⊔:union.sq.serif ⨆:union.sq.big ⩏:union.sq.double ∩:inter ∩:inter.serif ⩄:inter.and ⋂:inter.big ⩀:inter.dot ⋒:inter.double ⊓:inter.sq ⊓:inter.sq.serif ⨅:inter.sq.big ⩎:inter.sq.double ∀:forall ∃:exists ∄:exists.not ⊤:top ⊥:bot ¬:not ∧:and ⋀:and.big ⋏:and.curly ⟑:and.dot ⩓:and.double ∨:or ⋁:or.big ⋎:or.curly ⟇:or.dot ⩔:or.double ⊕:xor ⨁:xor.big ⊧:models ⊩:forces ⊮:forces.not ∴:therefore ∵:because ∎:qed"),
        category("Arrows", "→:arrow →:arrow.r ⟼:arrow.r.long.bar ↦:arrow.r.bar ⤷:arrow.r.curve ⮎:arrow.r.turn ⇢:arrow.r.dashed ⤑:arrow.r.dotted ⇒:arrow.r.double ⤇:arrow.r.double.bar ⟹:arrow.r.double.long ⟾:arrow.r.double.long.bar ⇏:arrow.r.double.not ⤃:arrow.r.double.struck ➡:arrow.r.filled ↪:arrow.r.hook ⟶:arrow.r.long ⟿:arrow.r.long.squiggly ↬:arrow.r.loop ↛:arrow.r.not ⭆:arrow.r.quad ⇝:arrow.r.squiggly ⇥:arrow.r.stop ⇨:arrow.r.stroked ⇸:arrow.r.struck ⇻:arrow.r.dstruck ↣:arrow.r.tail ⤔:arrow.r.tail.struck ⤕:arrow.r.tail.dstruck ⥲:arrow.r.tilde ⇛:arrow.r.triple ↠:arrow.r.twohead ⤅:arrow.r.twohead.bar ⤀:arrow.r.twohead.struck ⤁:arrow.r.twohead.dstruck ⤖:arrow.r.twohead.tail ⤗:arrow.r.twohead.tail.struck ⤘:arrow.r.twohead.tail.dstruck ⇾:arrow.r.open ↝:arrow.r.wave ←:arrow.l ↤:arrow.l.bar ⤶:arrow.l.curve ⮌:arrow.l.turn ⇠:arrow.l.dashed ⬸:arrow.l.dotted ⇐:arrow.l.double ⤆:arrow.l.double.bar ⟸:arrow.l.double.long ⟽:arrow.l.double.long.bar ⇍:arrow.l.double.not ⤂:arrow.l.double.struck ⬅:arrow.l.filled ↩:arrow.l.hook ⟵:arrow.l.long ⟻:arrow.l.long.bar ⬳:arrow.l.long.squiggly ↫:arrow.l.loop ↚:arrow.l.not ⭅:arrow.l.quad ⇜:arrow.l.squiggly ⇤:arrow.l.stop ⇦:arrow.l.stroked ⇷:arrow.l.struck ⇺:arrow.l.dstruck ↢:arrow.l.tail ⬹:arrow.l.tail.struck ⬺:arrow.l.tail.dstruck ⭉:arrow.l.tilde ⇚:arrow.l.triple ↞:arrow.l.twohead ⬶:arrow.l.twohead.bar ⬴:arrow.l.twohead.struck ⬵:arrow.l.twohead.dstruck ⬻:arrow.l.twohead.tail ⬼:arrow.l.twohead.tail.struck ⬽:arrow.l.twohead.tail.dstruck ⇽:arrow.l.open ↜:arrow.l.wave ↑:arrow.t ↥:arrow.t.bar ⤴:arrow.t.curve ⮍:arrow.t.turn ⇡:arrow.t.dashed ⇑:arrow.t.double ⬆:arrow.t.filled ⟰:arrow.t.quad ⤒:arrow.t.stop ⇧:arrow.t.stroked ⤉:arrow.t.struck ⇞:arrow.t.dstruck ⤊:arrow.t.triple ↟:arrow.t.twohead ↓:arrow.b ↧:arrow.b.bar ⤵:arrow.b.curve ⮏:arrow.b.turn ⇣:arrow.b.dashed ⇓:arrow.b.double ⬇:arrow.b.filled ⟱:arrow.b.quad ⤓:arrow.b.stop ⇩:arrow.b.stroked ⤈:arrow.b.struck ⇟:arrow.b.dstruck ⤋:arrow.b.triple ↡:arrow.b.twohead ↔:arrow.l.r ⇔:arrow.l.r.double ⟺:arrow.l.r.double.long ⇎:arrow.l.r.double.not ⤄:arrow.l.r.double.struck ⬌:arrow.l.r.filled ⟷:arrow.l.r.long ↮:arrow.l.r.not ⬄:arrow.l.r.stroked ⇹:arrow.l.r.struck ⇼:arrow.l.r.dstruck ⇿:arrow.l.r.open ↭:arrow.l.r.wave ↕:arrow.t.b ⇕:arrow.t.b.double ⬍:arrow.t.b.filled ⇳:arrow.t.b.stroked ↗:arrow.tr 🢹:arrow.tr.bar ⇗:arrow.tr.double ⬈:arrow.tr.filled ⤤:arrow.tr.hook ⬀:arrow.tr.stroked ↘:arrow.br 🢺:arrow.br.bar ⇘:arrow.br.double ⬊:arrow.br.filled ⤥:arrow.br.hook ⬂:arrow.br.stroked ↖:arrow.tl 🢸:arrow.tl.bar ⇖:arrow.tl.double ⬉:arrow.tl.filled ⤣:arrow.tl.hook ⬁:arrow.tl.stroked ↙:arrow.bl 🢻:arrow.bl.bar ⇙:arrow.bl.double ⬋:arrow.bl.filled ⤦:arrow.bl.hook ⬃:arrow.bl.stroked ⤡:arrow.tl.br ⤢:arrow.tr.bl ↺:arrow.ccw ↶:arrow.ccw.half ↻:arrow.cw ↷:arrow.cw.half ↯:arrow.zigzag ⇉:arrows ⇉:arrows.rr ⇇:arrows.ll ⇈:arrows.tt ⇊:arrows.bb ⇆:arrows.lr ↹:arrows.lr.stop ⇄:arrows.rl 🣐:arrows.rl.long ⇅:arrows.tb ⇵:arrows.bt ⇶:arrows.rrr ⬱:arrows.lll ⌃:arrowhead ⌃:arrowhead.t ⌄:arrowhead.b ⇀:harpoon ⇀:harpoon.rt ⥛:harpoon.rt.bar ⥓:harpoon.rt.stop ⇁:harpoon.rb ⥟:harpoon.rb.bar ⥗:harpoon.rb.stop ↼:harpoon.lt ⥚:harpoon.lt.bar ⥒:harpoon.lt.stop ↽:harpoon.lb ⥞:harpoon.lb.bar ⥖:harpoon.lb.stop ↿:harpoon.tl ⥠:harpoon.tl.bar ⥘:harpoon.tl.stop ↾:harpoon.tr ⥜:harpoon.tr.bar ⥔:harpoon.tr.stop ⇃:harpoon.bl ⥡:harpoon.bl.bar ⥙:harpoon.bl.stop ⇂:harpoon.br ⥝:harpoon.br.bar ⥕:harpoon.br.stop ⥎:harpoon.lt.rt ⥐:harpoon.lb.rb ⥋:harpoon.lb.rt ⥊:harpoon.lt.rb ⥑:harpoon.tl.bl ⥏:harpoon.tr.br ⥍:harpoon.tl.br ⥌:harpoon.tr.bl ⥤:harpoons ⥤:harpoons.rtrb ⥥:harpoons.blbr ⥯:harpoons.bltr ⥧:harpoons.lbrb ⥢:harpoons.ltlb ⇋:harpoons.ltrb ⥦:harpoons.ltrt ⥩:harpoons.rblb ⇌:harpoons.rtlb ⥨:harpoons.rtlt ⥮:harpoons.tlbr ⥣:harpoons.tltr ⊢:tack ⊢:tack.r ⊬:tack.r.not ⟝:tack.r.long ⊦:tack.r.short ⊨:tack.rr ⊭:tack.rr.not ⫢:tack.rrr ⊣:tack.l ⟞:tack.l.long ⫞:tack.l.short ⫤:tack.ll ⊥:tack.t ⟘:tack.t.big ⫫:tack.tt ⫠:tack.t.short ⊤:tack.b ⟙:tack.b.big ⫪:tack.bb ⫟:tack.b.short ⟛:tack.l.r"),
        category("Delimiters", "(:paren (:paren.l ⟮:paren.l.flat ⦇:paren.l.closed ⦅:paren.l.stroked ):paren.r ⟯:paren.r.flat ⦈:paren.r.closed ⦆:paren.r.stroked ⏜:paren.t ⏝:paren.b {:brace {:brace.l ⦃:brace.l.stroked }:brace.r ⦄:brace.r.stroked ⏞:brace.t ⏟:brace.b [:bracket [:bracket.l ⦍:bracket.l.tick.t ⦏:bracket.l.tick.b ⟦:bracket.l.stroked ]:bracket.r ⦐:bracket.r.tick.t ⦎:bracket.r.tick.b ⟧:bracket.r.stroked ⎴:bracket.t ⎵:bracket.b ❲:shell ❲:shell.l ⟬:shell.l.stroked ⦗:shell.l.filled ❳:shell.r ⟭:shell.r.stroked ⦘:shell.r.filled ⏠:shell.t ⏡:shell.b ⟅:bag ⟅:bag.l ⟆:bag.r ⎰:mustache ⎰:mustache.l ⎱:mustache.r |:bar |:bar.v ‖:bar.v.double ⦀:bar.v.triple ¦:bar.v.broken ⦶:bar.v.o ―:bar.h ⧘:fence ⧘:fence.l ⧚:fence.l.double ⧙:fence.r ⧛:fence.r.double ⦙:fence.dotted ⟨:chevron ⟨:chevron.l ⧼:chevron.l.curly ⦑:chevron.l.dot ⦉:chevron.l.closed ⟪:chevron.l.double ⟩:chevron.r ⧽:chevron.r.curly ⦒:chevron.r.dot ⦊:chevron.r.closed ⟫:chevron.r.double ⌈:ceil ⌈:ceil.l ⌉:ceil.r ⌊:floor ⌊:floor.l ⌋:floor.r ⌜:corner ⌜:corner.l.t ⌞:corner.l.b ⌝:corner.r.t ⌟:corner.r.b"),
        category("Functions & Categories", "↦:mapsto ⟼:mapsto.long ↤:mapsfrom ⟻:mapsfrom.long ∘:compose ⊚:compose.o ∗:convolve ⊛:convolve.o ⊸:multimap ⧟:multimap.double"),
        category("Other Mathematics", "⧾:tiny ⧿:miny ∣:divides ∤:divides.not ⫮:divides.not.rev ⟊:divides.struck ≀:wreath ⌀:diameter ⫴:interleave ⫼:interleave.big ⫵:interleave.struck ⋈:bowtie ⋈:bowtie.stroked ⨝:bowtie.stroked.big ⟕:bowtie.stroked.big.l ⟖:bowtie.stroked.big.r ⟗:bowtie.stroked.big.l.r ⧓:bowtie.filled ⧑:bowtie.filled.l ⧒:bowtie.filled.r °:degree ⨳:smash ⌣:smile ⌢:frown"),
        category("Geometry & Shapes", "∠:angle ⦟:angle.acute ∡:angle.arc ⦛:angle.arc.rev ⍼:angle.azimuth ⦦:angle.obtuse ⦣:angle.rev ∟:angle.right ⯾:angle.right.rev ⊾:angle.right.arc ⦝:angle.right.dot ⦜:angle.right.square ⦞:angle.s ⟀:angle.spatial ∢:angle.spheric ⦠:angle.spheric.rev ⦡:angle.spheric.t ⍼:angzarr ∥:parallel ⫲:parallel.struck ⦷:parallel.o ⋕:parallel.eq ⩨:parallel.equiv ∦:parallel.not ⧣:parallel.slanted.eq ⧤:parallel.slanted.eq.tilde ⧥:parallel.slanted.equiv ⫳:parallel.tilde ⟂:perp ⦹:perp.o •:bullet ∙:bullet.op ⦿:bullet.o ◦:bullet.stroked ⦾:bullet.stroked.o ◘:bullet.hole ⁃:bullet.hyph ‣:bullet.tri ⁌:bullet.l ⁍:bullet.r ○:circle ○:circle.stroked ∘:circle.stroked.tiny ⚬:circle.stroked.small ◯:circle.stroked.big ●:circle.filled ⦁:circle.filled.tiny ∙:circle.filled.small ⬤:circle.filled.big ◌:circle.dotted ⬭:ellipse ⬭:ellipse.stroked.h ⬯:ellipse.stroked.v ⬬:ellipse.filled.h ⬮:ellipse.filled.v △:triangle △:triangle.stroked.t ▽:triangle.stroked.b ▷:triangle.stroked.r ◁:triangle.stroked.l ◺:triangle.stroked.bl ◿:triangle.stroked.br ◸:triangle.stroked.tl ◹:triangle.stroked.tr ▵:triangle.stroked.small.t ▿:triangle.stroked.small.b ▹:triangle.stroked.small.r ◃:triangle.stroked.small.l 🛆:triangle.stroked.rounded ⟁:triangle.stroked.nested ◬:triangle.stroked.dot ▲:triangle.filled.t ▼:triangle.filled.b ▶:triangle.filled.r ◀:triangle.filled.l ◣:triangle.filled.bl ◢:triangle.filled.br ◤:triangle.filled.tl ◥:triangle.filled.tr ▴:triangle.filled.small.t ▾:triangle.filled.small.b ▸:triangle.filled.small.r ◂:triangle.filled.small.l □:square □:square.stroked ▫:square.stroked.tiny ◽:square.stroked.small ◻:square.stroked.medium ⬜:square.stroked.big ⬚:square.stroked.dotted ▢:square.stroked.rounded ■:square.filled ▪:square.filled.tiny ◾:square.filled.small ◼:square.filled.medium ⬛:square.filled.big ▭:rect ▭:rect.stroked.h ▯:rect.stroked.v ▬:rect.filled.h ▮:rect.filled.v ⬠:penta ⬠:penta.stroked ⬟:penta.filled ⬡:hexa ⬡:hexa.stroked ⬢:hexa.filled ◇:diamond ◇:diamond.stroked ⋄:diamond.stroked.small ⬦:diamond.stroked.medium ⟐:diamond.stroked.dot ◆:diamond.filled ⬥:diamond.filled.medium ⬩:diamond.filled.small ◊:lozenge ◊:lozenge.stroked ⬫:lozenge.stroked.small ⬨:lozenge.stroked.medium ⧫:lozenge.filled ⬪:lozenge.filled.small ⬧:lozenge.filled.medium ▱:parallelogram ▱:parallelogram.stroked ▰:parallelogram.filled ⋆:star ⋆:star.op ☆:star.stroked ★:star.filled"),
        category("Punctuation & Accents", "&:amp ⅋:amp.inv ∗:ast ∗:ast.op ⊛:ast.op.o *:ast.basic ⁎:ast.low ⁑:ast.double ⁂:ast.triple ⧆:ast.square @:at \\:backslash ⦸:backslash.o ⧷:backslash.not ℅:co ::colon ₡:colon.currency ∷:colon.double ⁝:colon.tri ⫶:colon.tri.op ≔:colon.eq ⩴:colon.double.eq ,:comma ⸲:comma.inv ⹁:comma.rev †:dagger ‡:dagger.double ⹋:dagger.triple ⸶:dagger.l ⸷:dagger.r ⸸:dagger.inv –:dash –:dash.en —:dash.em ⸺:dash.em.two ⸻:dash.em.three ‒:dash.fig ∹:dash.colon ⊝:dash.o 〜:dash.wave 〰:dash.wave.double _:underscore ⋅:dot ⋅:dot.op .:dot.basic ·:dot.c ⊙:dot.o ⨀:dot.o.big ⊡:dot.square ¨:dot.double ⃛:dot.triple ⃜:dot.quad !:excl ‼:excl.double ¡:excl.inv ⁉:excl.quest ?:quest ⁇:quest.double ⁈:quest.excl ¿:quest.inv ‽:interrobang ⸘:interrobang.inv #:hash ‐:hyph -:hyph.minus ‑:hyph.nobreak ‧:hyph.point ­:hyph.soft №:numero %:percent ‰:permille ‱:permyriad ¶:pilcrow ⁋:pilcrow.rev §:section ;:semi ⸵:semi.inv ⁏:semi.rev /:slash ⊘:slash.o ⫽:slash.double ⫻:slash.triple ⧸:slash.big …:dots ⋯:dots.h.c …:dots.h ⋮:dots.v ⋱:dots.down ⋰:dots.up ∼:tilde ∼:tilde.op ~:tilde.basic ⩪:tilde.dot ≃:tilde.eq ≄:tilde.eq.not ⋍:tilde.eq.rev ≅:tilde.equiv ≇:tilde.equiv.not ≆:tilde.nequiv ≁:tilde.not ∽:tilde.rev ≌:tilde.rev.equiv ≋:tilde.triple ´:acute ˝:acute.double ˘:breve ‸:caret ˇ:caron ^:hat ¨:diaer `:grave ¯:macron \":quote \":quote.double ':quote.single “:quote.l.double ‘:quote.l.single ”:quote.r.double ’:quote.r.single «:quote.chevron.l.double ‹:quote.chevron.l.single »:quote.chevron.r.double ›:quote.chevron.r.single ‟:quote.high.double ‛:quote.high.single „:quote.low.double ‚:quote.low.single ′:prime ‵:prime.rev ″:prime.double ‶:prime.double.rev ‴:prime.triple ‷:prime.triple.rev ⁗:prime.quad"),
        category("Letterlike Symbols", "ш:sha Ш:Sha א:aleph ב:beth ג:gimel ד:daleth 𝔸:AA 𝔹:BB ℂ:CC 𝔻:DD 𝔼:EE 𝔽:FF 𝔾:GG ℍ:HH 𝕀:II 𝕁:JJ 𝕂:KK 𝕃:LL 𝕄:MM ℕ:NN 𝕆:OO ℙ:PP ℚ:QQ ℝ:RR 𝕊:SS 𝕋:TT 𝕌:UU 𝕍:VV 𝕎:WW 𝕏:XX 𝕐:YY ℤ:ZZ Å:angstrom ℓ:ell ℘:pee ħ:planck ℜ:Re ℑ:Im ı:dotless ı:dotless.i ȷ:dotless.j"),
    ]
}

struct MathSymbolPicker: View {
    let insert: (MathSymbol) -> Void
    var complete: (() -> Void)? = nil
    var help: (() -> Void)? = nil
    @State private var category = MathSymbolCategory.all[0].id
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    private var visibleCategories: [MathSymbolCategory] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return MathSymbolCategory.all.compactMap { group in
            if query.isEmpty { return group.id == category ? group : nil }
            let symbols = group.symbols.filter {
                $0.name.localizedCaseInsensitiveContains(query) || $0.glyph.contains(query)
            }
            return symbols.isEmpty ? nil : MathSymbolCategory(title: group.title, symbols: symbols)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Math Symbols", systemImage: "x.squareroot").font(.headline)
                    Spacer()
                    Button("Done") { dismiss() }
                }
                TextField("Search symbols", text: $search).textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Picker("Math Symbols", selection: $category) {
                    ForEach(MathSymbolCategory.all) { group in
                        Text(LocalizedStringKey(group.title)).tag(group.id)
                    }
                }.pickerStyle(.menu)
            }.padding(16)
            #else
            HStack {
                Label("Math Symbols", systemImage: "x.squareroot").font(.headline)
                Spacer()
                TextField("Search symbols", text: $search)
                    .textFieldStyle(.roundedBorder).frame(width: 220)
            }.padding(16)
            #endif
            Divider()
            HStack(spacing: 0) {
                #if os(macOS)
                List(selection: $category) {
                    ForEach(MathSymbolCategory.all) { group in
                        Text(LocalizedStringKey(group.title)).tag(group.id)
                    }
                }.listStyle(.sidebar).frame(width: 158)
                #endif
                ScrollView {
                    if visibleCategories.isEmpty {
                        Text("No matching symbols").foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.top, 48)
                    }
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(visibleCategories) { group in
                            Text(LocalizedStringKey(group.title)).font(.headline)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                                ForEach(group.symbols) { symbol in
                                    Button { insert(symbol) } label: {
                                        VStack(spacing: 6) {
                                            Text(symbol.glyph).font(.system(size: 28, design: .serif))
                                                .frame(height: 34)
                                            Text(symbol.command).font(.system(size: 10, design: .monospaced))
                                                .lineLimit(2).multilineTextAlignment(.center)
                                                .frame(height: 26).foregroundStyle(.secondary)
                                        }.frame(maxWidth: .infinity).padding(.vertical, 8)
                                    }
                                    .buttonStyle(.bordered)
                                    .help(symbol.command + " · " + symbol.glyph)
                                    .accessibilityLabel(symbol.name)
                                    .accessibilityHint("Insert symbol command at selection")
                                }
                            }
                        }
                    }.padding(16)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack {
                Text("Inserts the Typst command at your selection").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let complete { Button("Complete", action: complete).keyboardShortcut(" ", modifiers: .control) }
                if let help { Button("Quick Help", action: help).keyboardShortcut("i", modifiers: [.option, .command]) }
            }.padding(12)
        }
        #if os(macOS)
        .frame(width: 600, height: 430)
        #else
        .frame(idealWidth: 480, idealHeight: 520)
        #endif
    }
}
