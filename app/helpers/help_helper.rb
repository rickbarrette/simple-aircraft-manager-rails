module HelpHelper
  def help_page_url_for(slug, anchor = nil)
    slug == "README" ? help_path(anchor: anchor) : help_page_path(slug, anchor: anchor)
  end

  def guide_html(page, links: true, title: true)
    html = HelpGuide.html(page, title: title, link: (links ? method(:help_page_url_for) : nil))
    tag.div(html.html_safe, class: "markdown guide") # rubocop:disable Rails/OutputSafety -- sanitized in HelpGuide
  end

  # A piece of the guide's Markdown (an intro, one release's notes).
  def guide_markdown(markdown, class: nil)
    html = HelpGuide.render(markdown, link: method(:help_page_url_for))
    tag.div(html.html_safe, class: [ "markdown guide", binding.local_variable_get(:class) ]) # rubocop:disable Rails/OutputSafety -- sanitized in HelpGuide
  end

  # "4 changes · 3 fixes · 2 for administrators"
  def release_summary(release)
    release.counts.map { |key, count| t("help.changelog.counts.#{key}", count: count) }.join(" · ")
  end
end
