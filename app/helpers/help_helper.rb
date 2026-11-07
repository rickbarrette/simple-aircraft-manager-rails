module HelpHelper
  def help_page_url_for(slug, anchor = nil)
    slug == "README" ? help_path(anchor: anchor) : help_page_path(slug, anchor: anchor)
  end

  def guide_html(page, links: true, title: true)
    html = HelpGuide.html(page, title: title, link: (links ? method(:help_page_url_for) : nil))
    tag.div(html.html_safe, class: "markdown guide") # rubocop:disable Rails/OutputSafety -- sanitized in HelpGuide
  end
end
