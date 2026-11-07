# Aircraft archives (.sam.zip): a whole aircraft's records and files in one ZIP,
# in the format of the original Simple Aircraft Manager (manifest schema v2), so
# archives move both ways between this app and the original.
#
#   manifest.json        all records, with archive-local IDs linking them
#   attachments/…        pictures, document pages, squawk files, track logs…
#
# Records carry a few extra keys for data only this app has (all squawk
# attachments, engine monitor files, oil report PDFs and lab averages, newer AD
# fields). The original ignores keys it doesn't know inside records, but rejects
# unknown top-level keys, so none are added there.
module AircraftArchive
  class Error < StandardError; end

  SCHEMA_VERSION = 2
  TOP_LEVEL_KEYS = %w[
    schema_version exported_at source_instance aircraft component_types components document_collections
    documents document_images logbook_entries squawks inspection_types inspection_records ads ad_compliances
    consumable_records major_records notes oil_analysis_reports flight_logs features weight_balance_records
  ].freeze
  # Not in archives from the original app (nor flight_logs before schema v2).
  OPTIONAL_KEYS = %w[features weight_balance_records].freeze

  MANIFEST_MAX_BYTES = 50.megabytes
  FILE_MAX_BYTES = 1.gigabyte # the most Admin → Settings allows for uploads
  ARCHIVE_MAX_BYTES = 10.gigabytes # uncompressed
  MAX_RATIO = 100                  # compression ratio above this looks like a zip bomb

  # Leading bytes per extension; text formats have none to check.
  MAGIC = {
    "jpg" => [ "\xFF\xD8\xFF".b ], "jpeg" => [ "\xFF\xD8\xFF".b ], "png" => [ "\x89PNG\r\n\x1A\n".b ],
    "gif" => [ "GIF8".b ], "webp" => [ "RIFF".b ], "bmp" => [ "BM".b ], "tif" => [ "II*\x00".b, "MM\x00*".b ],
    "tiff" => [ "II*\x00".b, "MM\x00*".b ], "pdf" => [ "%PDF-".b ]
  }.freeze
  TEXT_EXTENSIONS = %w[txt csv gpx kml xml].freeze
  EXTENSIONS = (MAGIC.keys + TEXT_EXTENSIONS).freeze

  def self.extension(path) = File.extname(path.to_s).delete(".").downcase

  def self.content_matches?(data, ext)
    return EXTENSIONS.include?(ext) unless MAGIC.key?(ext)
    MAGIC[ext].any? { data.byteslice(0, _1.bytesize) == _1 }
  end
end
