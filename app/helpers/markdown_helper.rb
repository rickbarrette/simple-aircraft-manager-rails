# GitHub-flavored Markdown for notes. Raw HTML in the source is dropped and the
# output is sanitized again, so notes (some shown on public share links) can't
# inject markup. Single line breaks are kept, so plain-text notes written
# before Markdown support look the same as before.
module MarkdownHelper
  OPTIONS = {
    parse: { smart: true },
    render: { hardbreaks: true, unsafe: false, escape: false },
    extension: { strikethrough: true, tagfilter: true, table: true, autolink: true, tasklist: true, header_ids: nil, footnotes: false }
  }.freeze
  TAGS = %w[p br strong em del a ul ol li blockquote code pre h1 h2 h3 h4 h5 h6 hr table thead tbody tr th td input span].freeze
  ATTRIBUTES = %w[href title type checked disabled align class].freeze

  def markdown(text)
    return "".html_safe if text.blank?
    html = Commonmarker.to_html(text.to_s, options: OPTIONS, plugins: { syntax_highlighter: nil })
    html = sanitize(html, tags: TAGS, attributes: ATTRIBUTES)
    # Links open in a new tab (notes often link to manuals and vendors).
    html = html.gsub(/<a href=/, '<a target="_blank" rel="noopener nofollow" href=')
    tag.div(html.html_safe, class: "markdown") # rubocop:disable Rails/OutputSafety -- sanitized above
  end

  # Plain-text excerpt for previews ("**Oil** leak at…" → "Oil leak at…").
  def markdown_excerpt(text, length: 200)
    return "" if text.blank?
    html = Commonmarker.to_html(text.to_s, options: OPTIONS.merge(render: { hardbreaks: false, unsafe: false }), plugins: { syntax_highlighter: nil })
    CGI.unescapeHTML(strip_tags(html.gsub(%r{</(p|li|h\d|tr|blockquote)>}, " "))).squish.truncate(length)
  end
end
