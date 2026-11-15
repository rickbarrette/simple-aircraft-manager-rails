# The release notes (CHANGELOG.md) split into releases, so the app can show
# the running version's notes on their own and fold away older ones. The
# file stays one plain Markdown document (it reads the same on GitHub):
#
#   # What's new
#   intro...
#   ## 2026.11.5
#   ### Changes
#   - ...
#   ### Fixes
#   - ...
class Changelog
  PATH = Rails.root.join("CHANGELOG.md")
  # The section headings counted in a release's one-line summary; items
  # under any other heading (the first release's highlights) count as notes.
  SECTIONS = { "Changes" => :changes, "Fixes" => :fixes, "For administrators" => :administrators }.freeze

  Release = Data.define(:version, :markdown) do
    def year = version.split(".")[0].to_i
    def month = version.split(".")[1].to_i
    def month_start = Date.new(year, month, 1)
    def anchor = "v#{version.tr('.', '-')}"

    # { changes: 4, fixes: 3 }: the top-level items under each heading.
    def counts
      counts = markdown.split(/^### /).drop(1).each_with_object(Hash.new(0)) do |section, tally|
        heading, body = section.split("\n", 2)
        tally[SECTIONS.fetch(heading.strip, :notes)] += body.to_s.scan(/^- /).size
      end
      (SECTIONS.values + [ :notes ]).filter_map { |key| [ key, counts[key] ] if counts[key].positive? }.to_h
    end
  end

  def self.load = new(PATH.file? ? PATH.read : "")

  attr_reader :title, :intro, :releases

  def initialize(markdown)
    head, *parts = markdown.split(/^## /)
    @title = head[/\A# (.+)$/, 1] || "What's new"
    @intro = head.sub(/\A# .+\n+/, "").strip
    @releases = parts.filter_map do |part|
      version, body = part.split("\n", 2)
      version = version.strip
      Release.new(version: version, markdown: body.to_s.strip) if version.match?(/\A\d{4}\.\d{1,2}\.\d+\z/)
    end
  end

  def release(version) = releases.find { _1.version == version }

  # Shown open: the running version and any newer (or the newest, when the
  # running version has no notes, such as in development).
  def open?(release, running:)
    index = releases.index { _1.version == running } || 0
    releases.index(release) <= index
  end
end
