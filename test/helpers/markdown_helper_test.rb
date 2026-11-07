require "test_helper"

class MarkdownHelperTest < ActionView::TestCase
  test "renders GitHub-flavored Markdown and keeps single line breaks" do
    html = markdown("**Hangar** code 1234\nGate on the left\n\n- [x] Oil\n- [ ] Tires\n\n| A | B |\n|---|---|\n| 1 | 2 |")
    assert_includes html, "<strong>Hangar</strong> code 1234<br>"
    assert_includes html, '<input type="checkbox" checked="" disabled="">'
    assert_includes html, "<td>1</td>"
    assert_match(/\A<div class="markdown">/, html)
  end

  test "drops raw HTML and script links; links open in a new tab" do
    html = markdown("<script>alert(1)</script>\n\nSee <img src=x onerror=alert(1)> [bad](javascript:alert(1)) https://example.com")
    refute_match(/<script|<img|onerror|javascript:/i, html)
    assert_includes html, '<a target="_blank" rel="noopener nofollow" href="https://example.com">'
  end

  test "excerpts are plain text" do
    assert_equal "Oil leak at the sump Check it", markdown_excerpt("# Oil leak\nat the *sump*\n\n- Check it")
    assert_equal "", markdown_excerpt(nil)
  end
end
