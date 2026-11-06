require "csv"
require "open-uri"

# Keeps the airports table in sync with OurAirports
# (https://ourairports.com/data/, public domain), the source AirTrail uses,
# the way AirTrail does (src/lib/utils/data/airports/source.ts):
#
# - On first start the table is empty, so it's populated by downloading the
#   data (AirportUpdateJob, queued at boot).
# - An admin can update it later: new airports are added, changed ones
#   updated, ones no longer in OurAirports removed. Rows keep their ids.
# - Custom airports (added by an admin) are never touched, and a source
#   airport with the same identifier as a custom one is skipped.
#
# Each airport gets AirTrail's code for it (createAirportCode): the
# 4-character GPS code when it doesn't collide with another airport's
# identifier, otherwise the OurAirports identifier.
module AirportData
  SOURCE_URL = "https://davidmegginson.github.io/ourairports-data/airports.csv".freeze
  BATCH = 2_000
  FIELDS = %i[airtrail_code gps_code local_code iata name kind municipality region country latitude longitude elevation_ft].freeze

  module_function

  # Download and sync. Returns { created:, updated:, removed: }.
  def refresh!(url = SOURCE_URL)
    Tempfile.create([ "airports", ".csv" ], binmode: true) do |file|
      URI.parse(url).open(read_timeout: 300, open_timeout: 30) { |remote| IO.copy_stream(remote, file) }
      file.flush
      file.rewind
      sync!(file)
    end
  end

  # Sync from a CSV (IO or path) in OurAirports' format.
  def sync!(source)
    rows = read(source)
    custom = Airport.where(custom: true).pluck(:ident).to_set
    source_idents = rows.to_set { _1["ident"].to_s.strip.upcase }
    now = Time.current

    incoming = rows.filter_map do |r|
      record = build(r, source_idents)
      record unless record.nil? || custom.include?(record[:ident])
    end.index_by { _1[:ident] }

    existing = Airport.where(custom: false).pluck(:id, :ident, *FIELDS).to_h { |id, ident, *values| [ ident, [ id, FIELDS.zip(values).to_h ] ] }

    created = incoming.except(*existing.keys).values
    changed = incoming.slice(*existing.keys).filter_map do |ident, rec|
      id, current = existing[ident]
      rec.slice(*FIELDS).merge(id: id, ident: ident) if normalize(current) != normalize(rec.slice(*FIELDS))
    end
    stale = existing.keys - incoming.keys

    Airport.transaction do
      created.each_slice(BATCH) { |batch| Airport.insert_all(batch.map { _1.merge(created_at: now, updated_at: now) }) }
      changed.each_slice(BATCH) { |batch| Airport.upsert_all(batch.map { _1.merge(created_at: now, updated_at: now) }, unique_by: :id, update_only: FIELDS + [ :updated_at ]) }
      stale.each_slice(BATCH) { |idents| Airport.where(custom: false, ident: idents).delete_all }
    end
    { created: created.size, updated: changed.size, removed: stale.size }
  end

  def build(row, source_idents)
    ident = row["ident"].to_s.strip.upcase
    return nil if ident.empty?
    gps = row["gps_code"].to_s.strip.upcase.presence
    {
      ident: ident,
      airtrail_code: gps && gps.length == 4 && (!source_idents.include?(gps) || gps == ident) ? gps : ident,
      gps_code: gps,
      local_code: row["local_code"].to_s.strip.upcase.presence,
      iata: row["iata_code"].to_s.strip.upcase.presence,
      name: row["name"].to_s.strip,
      kind: row["type"].to_s.presence,
      municipality: row["municipality"].to_s.strip.presence,
      region: row["iso_region"].to_s.presence,
      country: row["iso_country"].to_s.presence,
      latitude: row["latitude_deg"].presence&.to_f,
      longitude: row["longitude_deg"].presence&.to_f,
      elevation_ft: row["elevation_ft"].presence&.to_f&.round
    }
  end

  # Compare like with like (database floats/ints vs freshly parsed values).
  def normalize(attrs)
    attrs.transform_values { _1.is_a?(Float) ? _1.round(6) : _1 }
  end

  def read(source)
    stream = source.respond_to?(:read) && !source.is_a?(Pathname)
    content = stream ? source.read : File.binread(source.to_s)
    CSV.parse(content.force_encoding("UTF-8").delete_prefix("﻿"), headers: true).map(&:to_h)
  end
end
