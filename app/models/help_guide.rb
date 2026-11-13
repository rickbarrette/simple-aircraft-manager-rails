# The user guide: Markdown files in docs/guide (readable on GitHub too),
# shown in the app under /help. Only the pages listed here can be opened.
class HelpGuide
  DIR = Rails.root.join("docs/guide")
  ORDER = %w[README getting-started profile aircraft flights squawks oil-and-fuel components logbook records
             inspections ads documents major-records sharing administration disclaimer changelog].freeze
  OPTIONS = {
    parse: { smart: true },
    render: { hardbreaks: false, unsafe: false },
    extension: { strikethrough: true, tagfilter: true, table: true, autolink: true, header_ids: "" }
  }.freeze
  TAGS = %w[p br strong em del a ul ol li blockquote code pre h1 h2 h3 h4 hr table thead tbody tr th td].freeze
  ATTRIBUTES = %w[href id align].freeze

  Page = Data.define(:slug, :title, :markdown)

  def self.pages = ORDER.filter_map { find(_1) }

  def self.find(slug)
    return unless ORDER.include?(slug.to_s)
    path = slug.to_s == "changelog" ? Rails.root.join("CHANGELOG.md") : DIR.join("#{slug}.md")
    return unless path.file?
    markdown = path.read
    Page.new(slug: slug.to_s, title: markdown[/\A# (.+)$/, 1] || slug.to_s.titleize, markdown: markdown)
  end

  # Sanitized HTML. Links to other guide pages ("records.md#mistakes") go
  # through `link` (slug, anchor) -> URL, or become plain text when nil.
  def self.html(page, link:, title: true)
    source = title ? page.markdown : page.markdown.sub(/\A# .+\n+/, "")
    html = Commonmarker.to_html(source, options: OPTIONS, plugins: { syntax_highlighter: nil })
    html = Rails::HTML5::SafeListSanitizer.new.sanitize(html, tags: TAGS, attributes: ATTRIBUTES)
    html.gsub(%r{<a href="([a-z-]+|README)\.md(?:#([a-z0-9-]+))?">(.*?)</a>}m) do
      slug, anchor, text = $1, $2, $3
      next text unless link && ORDER.include?(slug)
      %(<a href="#{ERB::Util.h(link.call(slug, anchor))}">#{text}</a>)
    end
  end
end
