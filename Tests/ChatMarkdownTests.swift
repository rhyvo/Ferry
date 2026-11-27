import Foundation

func runChatMarkdownTests() {
    typealias B = ChatMarkdown.Block
    check(ChatMarkdown.blocks("### Why\n* **A:** one\n  * nested\n1. first\n---\nDone.")
          == [B.heading(level: 3, text: "Why"), .bullet("**A:** one", depth: 0), .bullet("nested", depth: 1), .numbered(1, "first", depth: 0), .rule, .paragraph("Done.")],
          "blocks: headings, lists, rule, paragraph")
    check(ChatMarkdown.blocks("```swift\nlet x = 1\n```") == [B.code("let x = 1")], "blocks: fenced code drops the language")
    check(ChatMarkdown.blocks("```\na\nb") == [B.code("a\nb")], "blocks: unclosed fence runs to the end")
    check(ChatMarkdown.blocks("Hello there") == [B.paragraph("Hello there")], "blocks: plain text")
    check(ChatMarkdown.blocks("").isEmpty, "blocks: empty")
    check(ChatMarkdown.blocks("#") == [B.paragraph("#")], "blocks: lone # is text")
    check(ChatMarkdown.blocks("**unclosed") == [B.paragraph("**unclosed")], "blocks: unclosed bold is text")
    check(ChatMarkdown.blocks("a\nb\n\nc") == [B.paragraph("a\nb"), .paragraph("c")], "blocks: paragraph join")
    check(ChatMarkdown.plainMath("$2^{32}$ bytes") == "2³² bytes", "math: superscript with text")
    check(ChatMarkdown.plainMath("$2^{64}$") == "2⁶⁴", "math: 2^64")
    check(ChatMarkdown.plainMath("$x_1$") == "x₁", "math: subscript")
    check(ChatMarkdown.plainMath("$$a+b$$") == "a+b", "math: display delimiters stripped")
    check(ChatMarkdown.plainMath("costs $5 and $6") == "costs $5 and $6", "math: dollar amounts unchanged")
    check(ChatMarkdown.plainMath("costs $5 and $x^2$") == "costs $5 and x²", "math: amount then math")
    check(ChatMarkdown.plainMath("$5 for a_b and $6") == "$5 for a_b and $6", "math: amounts around snake_case unchanged")
    check(ChatMarkdown.plainMath("`$A_B` and `$C_D`") == "`$A_B` and `$C_D`", "math: inline code untouched")
    check(ChatMarkdown.blocks("```winecfg```\nafter") == [B.paragraph("```winecfg```\nafter")], "blocks: one-line fence is not a fence")
    check(ChatMarkdown.blocks("```\na\n```swift\nb\n```\nend") == [B.code("a\n```swift\nb"), .paragraph("end")], "blocks: ```lang inside code does not close it")
    check(ChatMarkdown.plainMath("$WINEPREFIX/drive_c/users/$USER") == "$WINEPREFIX/drive_c/users/$USER", "math: shell variables keep their dollars")
    check(ChatMarkdown.plainMath("$\\frac{a}{b}$") == "\\frac{a}{b}", "math: unknown TeX loses only its dollars")
    check(ChatMarkdown.plainMath("$2^{32}$ and $2^{64}$") == "2³² and 2⁶⁴", "math: two expressions on a line")
}
