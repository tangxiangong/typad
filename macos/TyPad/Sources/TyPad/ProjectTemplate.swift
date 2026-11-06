enum ProjectTemplate: String, CaseIterable {
    case blank = "Blank Document", report = "Report", letter = "Letter"
    var source: String {
        switch self {
        case .blank: return "= New document\n\n"
        case .report: return "#set page(paper: \"a4\", margin: 25mm)\n#set text(size: 11pt)\n#set heading(numbering: \"1.\")\n#align(center)[#text(size: 22pt, weight: \"bold\")[Report]]\n#outline()\n\n= Introduction\n\nWrite your introduction here.\n\n= Results\n\n= Conclusion\n"
        case .letter: return "#set page(paper: \"a4\", margin: 25mm)\n#set text(size: 11pt)\n#align(right)[Your name \\\nYour address]\n\nDear reader,\n\nWrite your letter here.\n\nSincerely,\n\nYour name\n"
        }
    }
}
