# Command-line export/import of aircraft archives (.sam.zip), e.g. for backups:
#   bin/rails "sam:export[N12345]"                         → n12345-2026-11-06.sam.zip
#   bin/rails "sam:export[N12345,/backups/n12345.sam.zip]"
#   bin/rails "sam:import[/backups/n12345.sam.zip,owner@example.com]"
#   bin/rails "sam:import[/backups/n12345.sam.zip,owner@example.com,N54321]"   (new tail number)
namespace :sam do
  desc "Export an aircraft to a .sam.zip archive"
  task :export, %i[tail_number path] => :environment do |_, args|
    aircraft = Aircraft.find_by("UPPER(tail_number) = ?", args[:tail_number].to_s.upcase) or abort "No aircraft #{args[:tail_number]}"
    exporter = AircraftArchive::Exporter.new(aircraft)
    path = exporter.write_to(args[:path].presence || exporter.filename)
    puts "Wrote #{path} (#{ActiveSupport::NumberHelper.number_to_human_size(File.size(path))})"
    warn "#{exporter.missing} attached file(s) were missing from storage and left out." if exporter.missing.positive?
  end

  desc "Import a .sam.zip archive as a new aircraft owned by the given user"
  task :import, %i[path owner_email tail_number] => :environment do |_, args|
    owner = User.find_by(email_address: args[:owner_email].to_s.strip.downcase) or abort "No user #{args[:owner_email]}"
    preview = AircraftArchive::Importer.check(args[:path])
    tail = args[:tail_number].presence&.upcase || preview.tail_number
    abort "An aircraft #{tail} already exists; pass a different tail number." if Aircraft.where("UPPER(tail_number) = ?", tail.upcase).exists?
    result = AircraftArchive::Importer.new(args[:path], owner: owner, tail_number: tail).run
    puts "Imported #{result[:aircraft].tail_number}: #{result[:counts].map { |k, n| "#{n} #{k.tr('_', ' ')}" }.join(', ')}"
    result[:warnings].each { warn "  note: #{_1}" }
  rescue AircraftArchive::Error => e
    abort "Can't import: #{e.message}"
  end
end
