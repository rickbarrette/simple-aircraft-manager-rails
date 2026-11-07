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

  # Model names to search for: the owner's list, or the aircraft, engine and
  # propeller models.
  def self.default_terms(aircraft)
    models = [ aircraft.model ] + aircraft.components.in_use.includes(:component_type)
                                         .select { _1.component_type&.name.to_s.match?(/engine|propell?er|\bprop\b/i) }.map(&:model)
    models.compact_blank.map { _1.strip }.uniq
  end

  def terms
    custom = @aircraft.ad_watch_terms.to_s.split(/[,;\n]/).map(&:strip).compact_blank
    custom.any? ? custom : self.class.default_terms(@aircraft)
  end

  # Returns the new AdAlerts.
  def check!
    since = (@aircraft.ad_watch_checked_at || FIRST_LOOKBACK.ago).to_date - 7 # overlap; duplicates are skipped
    known = AirworthinessDirective.pluck(:name).to_set
    created = terms.flat_map { |term| search(term, since).filter_map { record(_1, term, known) } }
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
      publication_date: doc["publication_date"], effective_on: doc["effective_on"], matched_term: term
    )
  end

  def search(term, since)
    query = [
      [ "per_page", "50" ], [ "order", "newest" ],
      [ "conditions[agencies][]", "federal-aviation-administration" ], [ "conditions[type][]", "RULE" ],
      [ "conditions[term]", %("airworthiness directives" "#{term.delete('"')}") ],
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
