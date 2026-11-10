require "net/http"

# Looks for newly published ADs that may apply to an aircraft. Every AD is
# published in the Federal Register, whose API is public; this searches its
# full text for each of the aircraft's watch terms (by default the aircraft,
# engine and propeller models). Matches are only possibly applicable: the
# owner reviews them on the ADs tab.
class AdWatch
  API = "https://www.federalregister.gov/api/v1/documents.json".freeze
  FIELDS = %w[document_number title publication_date effective_on html_url abstract docket_ids].freeze
  FIRST_LOOKBACK = 2.years

  class Error < StandardError; end

  def initialize(aircraft)
    @aircraft = aircraft
  end

  # A search: what's shown ("Champion Slick 4301"), the words that must all
  # appear in the AD's text, and the installed component it came from.
  Term = Data.define(:label, :words, :component_id) do
    def to_s = label
  end

  ENGINE_OR_PROP = /engine|propell?er|\bprop\b/i

  # The aircraft model; each engine and propeller model (and its family);
  # and every other installed component's make and model, so ADs on
  # appliances (magnetos, ELTs, radios, filters…) are found too.
  def self.default_terms(aircraft)
    terms = []
    terms << Term.new(aircraft.model.strip, [ aircraft.model.strip ], nil) if aircraft.model.present?
    aircraft.components.in_use.includes(:component_type).order(:id).each do |c|
      model = c.model.to_s.strip
      next if model.blank?
      if c.component_type&.name.to_s.match?(ENGINE_OR_PROP)
        [ model, model_family(model) ].compact.each { |m| terms << Term.new(m, [ m ], c.id) }
      else
        label = [ c.manufacturer.to_s.strip, model ].compact_blank.join(" ")
        # Maker + model, and type + model: ADs often name the maker differently
        # (a successor company) but say what the part is ("magneto", "ELT").
        [ c.manufacturer.to_s.strip.split.first, c.component_type&.name.to_s.strip.split.first ].compact_blank.uniq.each do |lead|
          terms << Term.new(label, ([ lead ] + designators(model)).uniq, c.id)
        end
      end
    end
    terms.uniq { _1.words.map(&:downcase) }
  end

  # The engine family ADs often name instead of the exact model, and that also
  # catches a different spelling of the suffix: "O-200A" and "O-200-A" -> "O-200",
  # "IO-550-N" -> "IO-550". Nil when there's no family to add.
  def self.model_family(model)
    family = model.to_s.upcase[/\A([A-Z]{1,5}-\d{3,4})(?=-?[A-Z0-9])/, 1]
    family unless family.nil? || family == model.to_s.upcase
  end

  # The parts of a model name with digits in them ("Slick 4301" -> ["4301"]):
  # brand words in the model field rarely appear in an AD's text.
  def self.designators(model)
    words = model.split
    with_digits = words.grep(/\d/)
    with_digits.any? ? with_digits : words
  end

  # The owner's own list (comma-separated) replaces the defaults.
  def terms
    custom = @aircraft.ad_watch_terms.to_s.split(/[,;\n]/).map(&:strip).compact_blank
    custom.any? ? custom.map { Term.new(_1, [ _1 ], nil) } : self.class.default_terms(@aircraft)
  end

  # Returns the new AdAlerts.
  def check!
    since = (@aircraft.ad_watch_checked_at || FIRST_LOOKBACK.ago).to_date - 7 # overlap; duplicates are skipped
    known = AirworthinessDirective.pluck(:name).to_set
    created = terms.flat_map { |term| search(term.words, since).filter_map { record(_1, term, known) } }
    @aircraft.update_column(:ad_watch_checked_at, Time.current)
    created
  end

  private

  def record(doc, term, known)
    dockets = Array(doc["docket_ids"])
    ad_number = dockets.find { _1.start_with?("AD ") }&.delete_prefix("AD ")
    return if ad_number && known.include?(ad_number) && @aircraft.applicable_ads.exists?(name: ad_number)
    return if @aircraft.ad_alerts.exists?(fr_document_number: doc["document_number"])
    @aircraft.ad_alerts.create!(
      fr_document_number: doc["document_number"], ad_number: ad_number,
      amendment: dockets.find { _1.start_with?("Amendment ") }&.delete_prefix("Amendment "),
      title: doc["title"].to_s.truncate(250), abstract: doc["abstract"], html_url: doc["html_url"],
      publication_date: doc["publication_date"], effective_on: doc["effective_on"], matched_term: term.label,
      component_id: term.component_id
    )
  end

  def search(words, since)
    query = [
      [ "per_page", "50" ], [ "order", "newest" ],
      [ "conditions[agencies][]", "federal-aviation-administration" ], [ "conditions[type][]", "RULE" ],
      [ "conditions[term]", ([ "airworthiness directives" ] + words).map { %("#{_1.delete('"')}") }.join(" ") ],
      [ "conditions[publication_date][gte]", since.iso8601 ]
    ] + FIELDS.map { [ "fields[]", _1 ] }
    uri = URI(API)
    uri.query = URI.encode_www_form(query)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20) do |http|
      http.get(uri.request_uri, "Accept" => "application/json", "User-Agent" => "SimpleAircraftManager")
    end
    raise Error, "the Federal Register returned #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    Array(JSON.parse(response.body)["results"]).select { _1["title"].to_s.start_with?("Airworthiness Directives") }
  rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError, JSON::ParserError => e
    raise Error, "couldn't reach the Federal Register (#{e.class.name.demodulize})"
  end
end
