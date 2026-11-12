# One search across an aircraft's records: logbook, squawks, notes, ADs,
# documents (names, descriptions and the text read from their pages),
# components, flights and major repairs/alterations.
class SiteSearch
  Result = Data.define(:kind, :title, :snippet, :aircraft, :path)
  LIMIT = 25
  KINDS = { "logbook" => "Logbook", "squawk" => "Squawks", "note" => "Notes", "ad" => "ADs", "document" => "Documents",
            "component" => "Components", "flight" => "Flights", "major" => "Major repairs & alterations" }.freeze

  attr_reader :query

  def initialize(query, aircraft)
    @query = query.to_s.strip.first(100)
    @aircraft = Array(aircraft)
    @ids = @aircraft.map(&:id)
    @by_id = @aircraft.index_by(&:id)
    @urls = Rails.application.routes.url_helpers
  end

  def searchable? = @query.length >= 2

  # { kind => [Result] }, kinds with no matches left out.
  def results
    return {} unless searchable?
    @results ||= {
      "logbook" => find(LogbookEntry.where(aircraft_id: @ids).order(date: :desc), %w[text signoff_person signoff_location]) { |e, s|
        [ "#{e.date} · #{LogbookEntry::LOG_TYPES[e.log_type]} log", s, @urls.aircraft_logbook_entry_path(e.aircraft_id, e) ] },
      "squawk" => find(Squawk.where(aircraft_id: @ids).order(created_at: :desc), %w[issue_reported notes deferral_notes]) { |q, s|
        [ "#{q.issue_reported.truncate(80)}#{' (resolved)' if q.resolved?}", s, @urls.aircraft_squawks_path(q.aircraft_id) ] },
      "note" => find(AircraftNote.where(aircraft_id: @ids).order(created_at: :desc), %w[text]) { |n, s|
        [ "Note, #{n.created_at.to_date}", s, @urls.aircraft_notes_path(n.aircraft_id) ] },
      "ad" => ads,
      "document" => find(Document.where(aircraft_id: @ids).order(:name), %w[name description pages_text]) { |d, s|
        [ d.name, s, @urls.aircraft_document_path(d.aircraft_id, d) ] },
      "component" => components,
      "flight" => find(FlightLog.where(aircraft_id: @ids).order(date: :desc), %w[departure_location destination_location route notes]) { |f, s|
        [ "#{f.date} · #{f.route_summary.presence || 'Flight'}", s, @urls.aircraft_flight_log_path(f.aircraft_id, f) ] },
      "major" => find(MajorRecord.where(aircraft_id: @ids).order(date_performed: :desc), %w[title description stc_number stc_holder notes]) { |m, s|
        [ m.title.to_s, s, @urls.aircraft_major_record_path(m.aircraft_id, m) ] }
    }.reject { _2.empty? }
  end

  def count = results.values.sum(&:size)

  private

  def term = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"

  def find(scope, columns)
    columns = columns.select { scope.klass.column_names.include?(_1) }
    sql = columns.map { "#{scope.klass.connection.quote_column_name(_1)} LIKE :t ESCAPE '\\'" }.join(" OR ")
    scope.where(sql, t: term).limit(LIMIT).map do |record|
      title, snippet, path = yield(record, snippet_for(record, columns))
      Result.new(kind: nil, title: title, snippet: snippet, aircraft: @by_id[record.aircraft_id], path: path)
    end
  end

  # Components, by type name too ("magneto").
  def components
    cols = %w[manufacturer model serial_number install_location notes]
    sql = (cols.map { "components.#{_1}" } + [ "component_types.name" ]).map { "#{_1} LIKE :t ESCAPE '\\'" }.join(" OR ")
    Component.where(aircraft_id: @ids).left_joins(:component_type).includes(:component_type).where(sql, t: term).order(:id).limit(LIMIT).map do |c|
      Result.new(kind: nil, title: "#{c} · #{c.manufacturer} #{c.model}".strip, snippet: snippet_for(c, cols),
                 aircraft: @by_id[c.aircraft_id], path: @urls.aircraft_component_path(c.aircraft_id, c))
    end
  end

  # ADs are shared: those that apply to these aircraft (directly or through a component).
  def ads
    @aircraft.flat_map do |a|
      find_scope = AirworthinessDirective.applicable_to(a).order(:name)
      cols = %w[name short_description required_action docket_number]
      sql = cols.map { "airworthiness_directives.#{_1} LIKE :t ESCAPE '\\'" }.join(" OR ")
      find_scope.where(sql, t: term).limit(LIMIT).map do |ad|
        Result.new(kind: nil, title: "AD #{ad.name} · #{ad.short_description.to_s.truncate(70)}", snippet: snippet_for(ad, cols),
                   aircraft: a, path: @urls.aircraft_airworthiness_directives_path(a))
      end
    end.first(LIMIT)
  end

  # The text around the first match, from whichever field has it.
  def snippet_for(record, columns)
    columns.each do |col|
      text = record[col].to_s.squish
      at = text.downcase.index(@query.downcase) or next
      start = [ at - 60, 0 ].max
      return "#{'…' if start.positive?}#{text[start, @query.length + 140]}#{'…' if start + @query.length + 140 < text.length}"
    end
    nil
  end
end
