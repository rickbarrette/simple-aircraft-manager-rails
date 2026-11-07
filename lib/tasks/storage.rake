namespace :storage do
  desc "Store each distinct uploaded file once (hard links) and drop unused copies"
  task dedupe: :environment do
    service = ActiveStorage::Blob.service
    abort "The #{service.class.name.demodulize} service doesn't deduplicate." unless service.respond_to?(:sweep)
    result = service.sweep
    puts "Linked #{result[:linked]} duplicate files, removed #{result[:removed]} unused copies; " \
         "#{ActiveSupport::NumberHelper.number_to_human_size(result[:saved_bytes])} saved by sharing."
  end
end
